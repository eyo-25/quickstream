import AppKit

enum UpdateStatus: Equatable {
    case unknown, checking, upToDate
    case available(version: String, url: URL)
    case updating
    case failed(String)
    case stalled
}

// MARK: - 프로세스 실행 (주입 가능)

enum ProcessOutcome: Equatable {
    case exited(Int32)
    case timedOut
    case launchFailed(String)
}

protocol ProcessRunning {
    /// 끝날 때까지 기다린다. timeout 을 넘기면 프로세스를 종료하고 .timedOut. output 이 nil 이면 출력을 버린다.
    func run(_ executable: String, _ arguments: [String], environment: [String: String], output: FileHandle?, timeout: TimeInterval?) async -> ProcessOutcome
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false
    private var resumed = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    func terminateIfRunning(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        if process.isRunning { timedOut = true; process.terminate() }
    }
    /// 종료 핸들러와 강제 종료 타이머 중 먼저 온 쪽만 true. continuation 을 한 번만 재개하기 위한 장치.
    func claimResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

final class SystemProcessRunner: ProcessRunning {
    /// SIGTERM 을 무시하는 프로세스를 SIGKILL 로 끝내기 전의 유예
    let killGrace: TimeInterval

    init(killGrace: TimeInterval = 5) { self.killGrace = killGrace }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], output: FileHandle?, timeout: TimeInterval?) async -> ProcessOutcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output ?? FileHandle.nullDevice
            let grace = killGrace
            process.standardError = output ?? FileHandle.nullDevice

            let flag = TimeoutFlag()
            process.terminationHandler = { finished in
                guard flag.claimResume() else { return }
                continuation.resume(returning: flag.value ? .timedOut : .exited(finished.terminationStatus))
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: .launchFailed(error.localizedDescription))
                return
            }
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + max(timeout, 0)) {
                    // 끝난 뒤에 도착한 타이머가 종료 사유를 바꾸지 않도록 실행 중일 때만 표시한다
                    flag.terminateIfRunning(process)
                    guard flag.value else { return }
                    // SIGTERM 을 무시하면 종료 핸들러가 영영 불리지 않아 상태가 .updating 에 고정되므로, 유예 뒤 SIGKILL 하고 종료 확인을 기다리지 않는다.
                    // 하위 프로세스(brew 가 띄운 git/curl)까지 정리하려면 프로세스 그룹이 필요하지만 Process 는 새 그룹을 만들지 못해 생략한다.
                    DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
                        guard flag.claimResume() else { return }
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        continuation.resume(returning: .timedOut)
                    }
                }
            }
        }
    }
}

// MARK: - Homebrew 업데이트

enum UpdateOutcome: Equatable {
    case finished
    case failed(String)
    case stalled
    case alreadyRunning
    /// brew 설치가 아니라서 업그레이드 대신 릴리스 페이지를 열었다
    case openedReleasePage
}

/// 동시에 하나만 돌리기 위한 잠금 파일. 내용은 "pid 시작시각". 주인 프로세스가 죽었거나 제한 시간을 넘긴 잠금은 깨진 것으로 보고 가져온다.
struct UpdateLock {
    var url: URL
    var maxAge: TimeInterval
    var now: () -> Date
    var isProcessAlive: (Int32) -> Bool
    var pid: Int32

    func acquire() -> Bool {
        for _ in 0..<2 {
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd >= 0 {
                let line = "\(pid) \(Int(now().timeIntervalSince1970))\n"
                _ = line.withCString { write(fd, $0, strlen($0)) }
                close(fd)
                return true
            }
            guard errno == EEXIST else { return false }
            if isHeld() { return false }
            try? FileManager.default.removeItem(at: url)
        }
        return false
    }

    func release() { try? FileManager.default.removeItem(at: url) }

    private func isHeld() -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard fields.count >= 2, let owner = Int32(fields[0]), let started = TimeInterval(fields[1]) else { return false }
        return isProcessAlive(owner) && now().timeIntervalSince1970 - started <= maxAge
    }
}

struct BrewUpdater {
    var runner: ProcessRunning
    var cask: String
    var supportDirectory: URL
    var brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    var isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    /// brew update + upgrade 전체에 주는 시간. 이 안에 끝나지 않으면 "끝나지 않았습니다" 로 보고 다시 시도할 수 있게 한다.
    var timeout: TimeInterval = 11 * 60
    var now: () -> Date = { Date() }
    var isProcessAlive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    var pid: Int32 = ProcessInfo.processInfo.processIdentifier

    var caskToken: String { cask.split(separator: "/").last.map(String.init) ?? cask }
    var logURL: URL { supportDirectory.appendingPathComponent("update.log") }
    var lockURL: URL { supportDirectory.appendingPathComponent("update.lock") }

    /// 앱은 Finder/로그인 항목으로 떠서 PATH 가 짧으므로 brew 위치를 직접 찾는다
    func brewPath() -> String? { brewCandidates.first(where: isExecutable) }

    private func environment(brew: String) -> [String: String] {
        let dir = (brew as NSString).deletingLastPathComponent
        // update 는 따로 돌리므로 upgrade 가 또 자동 업데이트를 하지 않게 한다
        return ["PATH": "\(dir):/usr/bin:/bin:/usr/sbin:/sbin", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
    }

    /// Caskroom 으로 이어지는 번들이거나 brew 가 이 cask 를 설치된 것으로 알면 brew 설치
    func isBrewInstall(bundleURL: URL) async -> Bool {
        if bundleURL.resolvingSymlinksInPath().path.contains("/Caskroom/") { return true }
        guard let brew = brewPath() else { return false }
        let outcome = await runner.run(brew, ["list", "--cask", caskToken], environment: environment(brew: brew), output: nil, timeout: 30)
        return outcome == .exited(0)
    }

    func upgrade() async -> UpdateOutcome {
        guard let brew = brewPath() else { return .failed("Homebrew(brew)를 찾지 못했습니다") }
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let lock = UpdateLock(url: lockURL, maxAge: timeout, now: now, isProcessAlive: isProcessAlive, pid: pid)
        guard lock.acquire() else { return .alreadyRunning }
        defer { lock.release() }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        defer { try? log?.close() }
        func note(_ text: String) { try? log?.write(contentsOf: Data((text + "\n").utf8)) }

        let env = environment(brew: brew)
        let start = now()
        let steps = [["update"], ["upgrade", "--cask", cask]]
        for arguments in steps {
            let remaining = timeout - now().timeIntervalSince(start)
            let command = "brew " + arguments.joined(separator: " ")
            note("$ \(command)")
            guard remaining > 0 else { note("제한 시간을 넘겼습니다"); return .stalled }
            switch await runner.run(brew, arguments, environment: env, output: log, timeout: remaining) {
            case .exited(0): continue
            case .exited(let code):
                note("\(command) 이(가) 코드 \(code) 로 끝났습니다")
                return .failed("\(command) 실패(코드 \(code))")
            case .timedOut:
                note("\(command) 이(가) 제한 시간 안에 끝나지 않아 중단했습니다")
                return .stalled
            case .launchFailed(let reason):
                note("\(command) 을(를) 실행하지 못했습니다: \(reason)")
                return .failed("brew 를 실행하지 못했습니다: \(reason)")
            }
        }
        return .finished
    }

    /// 번들의 Contents/Info.plist 에서 CFBundleShortVersionString 을 읽는다. 읽을 수 없으면 nil.
    static func installedVersion(bundleURL: URL) -> Version? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist), let text = info["CFBundleShortVersionString"] as? String else { return nil }
        return Version(text)
    }

    /// 업그레이드가 끝난 뒤 현재 프로세스가 사라지길 기다렸다가 같은 경로의 앱을 다시 연다
    static func relaunchScript(pid: Int32, appPath: String) -> [String] {
        ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"", "sh", String(pid), appPath]
    }
}

// MARK: - 컨트롤러

final class UpdateController {
    static let lastCheckKey = "QSLastUpdateCheck"
    static let latestVersionKey = "QSLatestKnownVersion"
    static let latestURLKey = "QSLatestKnownURL"
    static let notifiedVersionKey = "QSUpdateNotifiedVersion"

    enum CheckOutcome: Equatable {
        case skipped
        case done(UpdateStatus)
        case failed(String)
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let updater: BrewUpdater
    private let bundleURL: URL
    private let currentVersion: String
    /// 업그레이드 뒤 번들 경로에 실제로 설치된 버전을 읽는다(테스트에서 교체)
    private let installedVersion: (URL) -> Version?
    private let now: () -> Date
    private let state = NSLock()
    private var _status: UpdateStatus = .unknown
    private var _lastFailure: String?
    private var isBusy = false

    var onStatusChange: ((UpdateStatus) -> Void)?

    /// runner/now 등은 테스트용 주입점. 앱에서는 기본값을 쓴다.
    init(session: URLSession = .shared, defaults: UserDefaults = .standard,
         runner: ProcessRunning = SystemProcessRunner(), updater customUpdater: BrewUpdater? = nil,
         bundleURL: URL = Bundle.main.bundleURL, currentVersion: String = AppInfo.version,
         installedVersion: @escaping (URL) -> Version? = BrewUpdater.installedVersion,
         now: @escaping () -> Date = { Date() }) {
        self.session = session
        self.defaults = defaults
        self.bundleURL = bundleURL
        self.currentVersion = currentVersion
        self.installedVersion = installedVersion
        self.now = now
        self.updater = customUpdater ?? BrewUpdater(runner: runner, cask: AppInfo.cask, supportDirectory: AppInfo.supportDirectory, now: now)
    }

    private(set) var status: UpdateStatus {
        get { state.lock(); defer { state.unlock() }; return _status }
        set {
            state.lock()
            let changed = _status != newValue
            _status = newValue
            state.unlock()
            // 콜백은 UI 갱신용이라 항상 메인에서 부른다
            if changed { DispatchQueue.main.async { [weak self] in self?.onStatusChange?(newValue) } }
        }
    }

    /// 마지막 업데이트 시도의 실패 사유. 상태가 '업데이트 가능'으로 남아 있어도 왜 실패했는지 보여 주려고 따로 둔다.
    /// 항상 상태 전환(updating ↔ available)과 함께 바뀌므로 알림 콜백은 상태 쪽이 대신 부른다.
    var lastFailure: String? { state.lock(); defer { state.unlock() }; return _lastFailure }

    private func setFailure(_ message: String?) {
        state.lock(); _lastFailure = message; state.unlock()
    }

    var statusText: String {
        switch status {
        case .unknown: return currentVersion
        case .checking: return "\(currentVersion) · 확인 중…"
        case .upToDate: return "\(currentVersion) · 최신 버전입니다"
        case .available(let version, _):
            if let failure = lastFailure { return "\(version) 업데이트 가능 · 마지막 업데이트 실패: \(failure)" }
            return "\(version) 업데이트 가능"
        case .updating: return "\(currentVersion) · 업데이트 중…"
        case .failed(let message): return "\(currentVersion) · \(message)"
        case .stalled: return "\(currentVersion) · 업데이트가 끝나지 않았습니다"
        }
    }

    // MARK: 확인

    func checkInBackground() {
        Task {
            _ = await check(force: false)
            if case .available(let version, _) = status, defaults.string(forKey: Self.notifiedVersionKey) != version {
                defaults.set(version, forKey: Self.notifiedVersionKey)
                await MainActor.run { self.offerUpdate(version: version) }
            }
        }
    }

    func checkNow() {
        Task {
            switch status {
            case .updating:
                await MainActor.run { self.inform("업데이트를 진행 중입니다", "끝나면 퀵스트림이 자동으로 다시 시작됩니다.") }
                return
            case .stalled:
                await MainActor.run { self.offerRetry() }
                return
            default: break
            }
            switch await check(force: true) {
            case .done(.available(let version, _)):
                defaults.set(version, forKey: Self.notifiedVersionKey)
                await MainActor.run { self.offerUpdate(version: version) }
            case .done:
                await MainActor.run { self.inform("최신 버전입니다", "퀵스트림 \(self.currentVersion) 은(는) 현재 가장 새로운 버전입니다.") }
            case .failed(let message):
                await MainActor.run { self.inform("업데이트를 확인하지 못했습니다", message) }
            case .skipped: break
            }
        }
    }

    /// 네트워크 확인 본체. 백그라운드(force=false)는 6시간 안에 다시 오면 저장된 결과만 반영하고, 실패해도 상태를 어지럽히지 않는다.
    func check(force: Bool) async -> CheckOutcome {
        guard let current = Version(currentVersion) else { return .failed("현재 버전(\(currentVersion))을 읽을 수 없습니다") }
        guard beginWork() else { return .skipped }
        defer { endWork() }

        if !force, !UpdateThrottle.shouldCheck(last: lastCheck, now: now()) {
            if case .unknown = status, let cached = cachedRelease() { status = Self.status(for: cached, current: current) }
            return .skipped
        }
        let previous = status
        status = .checking
        do {
            let release = try await fetchLatest()
            defaults.set(now().timeIntervalSince1970, forKey: Self.lastCheckKey)
            defaults.set(release.version.description, forKey: Self.latestVersionKey)
            defaults.set(release.url.absoluteString, forKey: Self.latestURLKey)
            let result = Self.status(for: release, current: current)
            // 같은 업데이트 가능 상태가 이어질 때만 마지막 업데이트 실패 사유를 남긴다
            if result != previous { setFailure(nil) }
            status = result
            return .done(result)
        } catch {
            if force {
                status = .failed("업데이트 확인 실패")
            } else {
                // 오프라인 재시작처럼 이전 상태가 없을 때는 저장된 최신 버전으로 복원한다(현재보다 높을 때만: 낡은 캐시가 '업데이트 있음'으로 남지 않게)
                let restored: UpdateStatus = previous == .checking ? .unknown : previous
                if restored == .unknown, let cached = cachedRelease(), cached.version > current {
                    status = Self.status(for: cached, current: current)
                } else {
                    status = restored
                }
            }
            return .failed((error as? CheckError)?.message ?? error.localizedDescription)
        }
    }

    static func status(for release: ReleaseInfo, current: Version) -> UpdateStatus {
        release.version > current ? .available(version: release.version.description, url: release.url) : .upToDate
    }

    private var lastCheck: Date? {
        defaults.object(forKey: Self.lastCheckKey) is Double ? Date(timeIntervalSince1970: defaults.double(forKey: Self.lastCheckKey)) : nil
    }

    private func cachedRelease() -> ReleaseInfo? {
        guard let v = defaults.string(forKey: Self.latestVersionKey), let version = Version(v),
              let u = defaults.string(forKey: Self.latestURLKey), let url = URL(string: u) else { return nil }
        return ReleaseInfo(version: version, url: url)
    }

    private struct CheckError: Error { var message: String }

    private func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: AppInfo.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuickStream/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CheckError(message: "응답을 읽을 수 없습니다") }
        switch http.statusCode {
        case 200: break
        case 404: throw CheckError(message: "공개된 릴리스를 찾지 못했습니다")
        case 403, 429: throw CheckError(message: "GitHub 요청 한도를 넘었습니다. 잠시 뒤 다시 시도하세요")
        default: throw CheckError(message: "GitHub 응답 오류(\(http.statusCode))")
        }
        guard let release = ReleaseInfo.parseLatest(data) else { throw CheckError(message: "릴리스 정보를 읽을 수 없습니다") }
        return release
    }

    // MARK: 업데이트

    func startUpdate() {
        Task {
            switch await performUpdate() {
            case .finished:
                await MainActor.run { self.relaunch() }
            case .failed(let message):
                await MainActor.run { self.inform("업데이트하지 못했습니다", "\(message)\n로그: \(self.updater.logURL.path)") }
            case .stalled:
                await MainActor.run { self.offerRetry() }
            case .alreadyRunning:
                await MainActor.run { self.inform("업데이트를 진행 중입니다", "다른 업데이트나 확인이 이미 실행 중입니다.") }
            case .openedReleasePage: break
            }
        }
    }

    /// brew 설치: brew update → brew upgrade. 상태를 .updating 으로 두고 결과에 맞게 되돌린다. 소스 빌드는 릴리스 페이지를 연다.
    func performUpdate() async -> UpdateOutcome {
        guard beginWork() else { return .alreadyRunning }
        defer { endWork() }
        let before = status
        guard await updater.isBrewInstall(bundleURL: bundleURL) else {
            // 소스 빌드는 자동으로 바꿀 수 없으므로 릴리스 페이지에서 직접 받게 한다
            var page = AppInfo.releasesURL
            if case .available(_, let url) = before { page = url }
            NSWorkspace.shared.open(page)
            return .openedReleasePage
        }
        setFailure(nil)
        status = .updating
        var outcome = await updater.upgrade()
        // brew upgrade 는 올릴 버전이 없어도(tap 에 새 버전이 없거나 update 가 tap 을 못 받음) 0 으로 끝나므로, 설치된 앱의 버전이 실제로 올랐는지 확인한다.
        // 설치된 버전을 못 읽으면(경로 이동·권한) brew 의 성공을 믿는다: 실제로 성공했는데 실패로 보이는 것보다, 최악의 경우 같은 앱을 한 번 다시 여는 쪽이 덜 해롭다.
        if outcome == .finished, let installed = installedVersion(bundleURL), let current = Version(currentVersion), installed <= current {
            outcome = .failed("brew 가 새 버전을 설치하지 않았습니다(설치된 버전 \(installed)). tap 이 아직 새 버전을 받지 못했을 수 있습니다")
        }
        switch outcome {
        case .finished: break
        case .failed(let message):
            // 실패해도 '업데이트 가능' 정보는 잃지 않는다: 메뉴의 '새 버전 X 업데이트…' 가 남아 곧바로 재시도할 수 있어야 한다.
            // 사유는 상태와 따로 보관한다. 상태 전환이 콜백을 부르므로 사유를 먼저 조용히 넣는다.
            if let available = availableStatus(before: before) {
                setFailure(message)
                status = available
            } else {
                status = .failed(message)
            }
        case .stalled: status = .stalled
        case .alreadyRunning, .openedReleasePage: status = before
        }
        return outcome
    }

    /// 업데이트 시작 전 상태가 '업데이트 가능'이었거나, 저장된 최신 버전이 현재보다 높으면 그 상태. (stalled 에서 재시도한 경우도 포함)
    private func availableStatus(before: UpdateStatus) -> UpdateStatus? {
        if case .available = before { return before }
        guard let current = Version(currentVersion), let cached = cachedRelease(), cached.version > current else { return nil }
        return Self.status(for: cached, current: current)
    }

    /// 재시작하려고 앱을 끝내도 되는지 묻는다(저장하지 않은 설정이 있으면 확인창). 기본은 항상 허용.
    /// 재실행 도우미는 앱이 사라질 때까지 무한정 기다리므로, 사용자가 취소할 수 있는 확인은 도우미를 띄우기 **전에** 끝낸다.
    var confirmQuit: () -> Bool = { true }

    /// 새 버전으로 교체된 같은 경로의 앱을 현재 프로세스가 끝난 뒤 다시 연다
    private func relaunch() {
        guard confirmQuit() else {
            status = .failed("새 버전이 설치되었습니다. 설정을 정리한 뒤 퀵스트림을 종료하고 다시 실행해 주세요")
            return
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = BrewUpdater.relaunchScript(pid: ProcessInfo.processInfo.processIdentifier, appPath: bundleURL.path)
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: 동시 실행 방지(프로세스 안)

    private func beginWork() -> Bool {
        state.lock(); defer { state.unlock() }
        if isBusy { return false }
        isBusy = true
        return true
    }

    private func endWork() {
        state.lock(); isBusy = false; state.unlock()
    }

    // MARK: 알림창

    @MainActor private func offerUpdate(version: String) {
        let alert = NSAlert()
        alert.messageText = "새 버전 \(version) 이(가) 있습니다"
        alert.informativeText = "현재 버전은 \(currentVersion) 입니다. 지금 업데이트할까요?"
        alert.addButton(withTitle: "업데이트")
        alert.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { startUpdate() }
    }

    @MainActor private func offerRetry() {
        let alert = NSAlert()
        alert.messageText = "업데이트가 끝나지 않았습니다"
        alert.informativeText = "11분 안에 끝나지 않아 중단했습니다. 로그: \(updater.logURL.path)"
        alert.addButton(withTitle: "다시 시도")
        alert.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { startUpdate() }
    }

    @MainActor private func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
