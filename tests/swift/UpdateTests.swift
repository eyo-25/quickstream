import Foundation

// 업데이트 영역 테스트: 버전 규칙, 릴리스 JSON, 확인 스로틀, brew 감지·명령 순서, 잠금, 시간 초과.
// 네트워크는 URLProtocol 스텁, 프로세스는 가짜 ProcessRunning 으로 대체하고 파일은 임시 폴더에만 쓴다.

private final class FakeRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable { var executable: String; var arguments: [String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _envs: [[String: String]] = []
    private var _timeouts: [TimeInterval?] = []
    var handler: (Call) async -> ProcessOutcome = { _ in .exited(0) }
    var calls: [Call] { lock.withLock { _calls } }
    var environments: [[String: String]] { lock.withLock { _envs } }
    var timeouts: [TimeInterval?] { lock.withLock { _timeouts } }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], output: FileHandle?, timeout: TimeInterval?) async -> ProcessOutcome {
        let call = Call(executable: executable, arguments: arguments)
        lock.withLock { _calls.append(call); _envs.append(environment); _timeouts.append(timeout) }
        return await handler(call)
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var response: (status: Int, body: Data) = (200, Data())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.requests += 1
        let r = HTTPURLResponse(url: request.url!, statusCode: StubProtocol.response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubProtocol.response.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func releaseJSON(tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
    Data("""
    {"tag_name":"\(tag)","html_url":"https://github.com/eyo-25/quickstream/releases/tag/\(tag)","draft":\(draft),"prerelease":\(prerelease)}
    """.utf8)
}

private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qs-update-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeDefaults() -> (UserDefaults, String) {
    let name = "qs-update-tests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

func runUpdateTests() {
    let temp = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }

    section("Update/Version")
    check(Version("0.9.10")! < Version("0.10.0")!, "0.9.10 < 0.10.0 (숫자 비교, 문자열 비교 아님)")
    check(Version("1.0.0")! > Version("0.99.99")!, "major 가 우선")
    checkEqual(Version("v0.2.0"), Version("0.2.0"), "v 접두사 허용")
    checkEqual(Version("V1.2.3")?.description, "1.2.3", "대문자 V 접두사")
    checkEqual(Version(" 1.2.3\n")?.description, "1.2.3", "앞뒤 공백 제거")
    for bad in ["", "v", "1.2", "1.2.3.4", "1.2.x", "a.b.c", "1..3", "1.2.3-beta", "-1.2.3", "1.2.+3", "١.٢.٣", "1234567890.0.0"] {
        check(Version(bad) == nil, "비정상 문자열은 nil: \(bad)")
    }
    checkEqual(Version("01.002.0")?.description, "1.2.0", "앞자리 0 은 숫자로 읽는다")

    section("Update/ReleaseJSON")
    checkEqual(ReleaseInfo.parseLatest(releaseJSON(tag: "v0.2.0"))?.version.description, "0.2.0", "정상 릴리스")
    checkEqual(ReleaseInfo.parseLatest(releaseJSON(tag: "v0.2.0"))?.url.absoluteString, "https://github.com/eyo-25/quickstream/releases/tag/v0.2.0", "릴리스 URL")
    check(ReleaseInfo.parseLatest(releaseJSON(tag: "v0.2.0", draft: true)) == nil, "draft 무시")
    check(ReleaseInfo.parseLatest(releaseJSON(tag: "v0.2.0", prerelease: true)) == nil, "prerelease 무시")
    check(ReleaseInfo.parseLatest(releaseJSON(tag: "nightly")) == nil, "버전이 아닌 태그")
    check(ReleaseInfo.parseLatest(Data("{}".utf8)) == nil, "필드 없음")
    check(ReleaseInfo.parseLatest(Data("not json".utf8)) == nil, "JSON 아님")
    check(ReleaseInfo.parseLatest(Data(#"{"tag_name":"v1.0.0","html_url":"http://example.com/x"}"#.utf8)) == nil, "https 아닌 URL 거부")
    checkEqual(ReleaseInfo.parseLatest(Data(#"{"tag_name":"v1.0.0","html_url":"https://github.com/a/b/releases/tag/v1.0.0"}"#.utf8))?.version.description, "1.0.0", "draft/prerelease 키가 없어도 정상")

    section("Update/Throttle")
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    check(UpdateThrottle.shouldCheck(last: nil, now: t0), "기록이 없으면 확인")
    check(!UpdateThrottle.shouldCheck(last: t0, now: t0.addingTimeInterval(6 * 3600 - 1)), "6시간 직전은 건너뜀")
    check(UpdateThrottle.shouldCheck(last: t0, now: t0.addingTimeInterval(6 * 3600)), "정확히 6시간이면 확인")
    check(UpdateThrottle.shouldCheck(last: t0, now: t0.addingTimeInterval(-60)), "시계가 과거로 가면 확인")

    section("Update/BrewDetection")
    let brew = temp.appendingPathComponent("bin/brew").path
    @Sendable func makeUpdater(fake: FakeRunner, support: URL, brews: [String]? = nil, timeout: TimeInterval = 660, now: @escaping () -> Date = { Date() }, alive: @escaping (Int32) -> Bool = { _ in false }) -> BrewUpdater {
        var u = BrewUpdater(runner: fake, cask: "eyo-25/tap/quickstream", supportDirectory: support)
        u.brewCandidates = brews ?? [brew]
        u.isExecutable = { $0 == brew || $0 == "/usr/local/bin/brew" }
        u.timeout = timeout
        u.now = now
        u.isProcessAlive = alive
        u.pid = 4242
        return u
    }
    let caskroomApp = temp.appendingPathComponent("Caskroom/quickstream/0.1.0/QuickStream.app")
    try? FileManager.default.createDirectory(at: caskroomApp, withIntermediateDirectories: true)
    let linked = temp.appendingPathComponent("Applications/QuickStream.app")
    try? FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.createSymbolicLink(at: linked, withDestinationURL: caskroomApp)
    let sourceApp = temp.appendingPathComponent("Home/Applications/QuickStream.app")

    runAsync {
        let fake = FakeRunner()
        let updater = makeUpdater(fake: fake, support: temp.appendingPathComponent("s1"))
        let viaLink = await updater.isBrewInstall(bundleURL: linked)
        check(viaLink, "Caskroom 심볼릭 링크면 brew 설치")
        check(fake.calls.isEmpty, "링크로 판정되면 brew 를 부르지 않는다")

        fake.handler = { _ in .exited(0) }
        let listed = await updater.isBrewInstall(bundleURL: sourceApp)
        check(listed, "brew list --cask 성공이면 brew 설치")
        checkEqual(fake.calls.last, FakeRunner.Call(executable: brew, arguments: ["list", "--cask", "quickstream"]), "list 는 cask 토큰만 쓴다")
        check(fake.environments.last?["PATH"]?.hasPrefix(temp.appendingPathComponent("bin").path + ":/usr/bin") == true, "짧은 PATH 를 brew 폴더로 보강")

        fake.handler = { _ in .exited(1) }
        let notListed = await updater.isBrewInstall(bundleURL: sourceApp)
        check(!notListed, "brew 가 모르는 cask 면 소스 빌드")
        fake.handler = { _ in .timedOut }
        let hung = await updater.isBrewInstall(bundleURL: sourceApp)
        check(!hung, "brew list 가 멈추면 소스 빌드로 본다")

        let noBrew = makeUpdater(fake: fake, support: temp.appendingPathComponent("s1"), brews: ["/nonexistent/brew"])
        let before = fake.calls.count
        let detected = await noBrew.isBrewInstall(bundleURL: sourceApp)
        check(!detected, "brew 가 없으면 소스 빌드")
        checkEqual(fake.calls.count, before, "brew 가 없으면 프로세스를 띄우지 않는다")
        check(noBrew.brewPath() == nil, "brew 위치 없음")

        var order = makeUpdater(fake: fake, support: temp.appendingPathComponent("s1"))
        order.brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        checkEqual(order.brewPath(), "/usr/local/bin/brew", "Apple Silicon 경로가 없으면 Intel 경로")
        order.isExecutable = { _ in true }
        checkEqual(order.brewPath(), "/opt/homebrew/bin/brew", "둘 다 있으면 /opt/homebrew 가 먼저")
    }

    section("Update/Upgrade")
    runAsync {
        let support = temp.appendingPathComponent("s2")
        let fake = FakeRunner()
        let updater = makeUpdater(fake: fake, support: support)
        let outcome = await updater.upgrade()
        checkEqual(outcome, .finished, "둘 다 성공하면 finished")
        checkEqual(fake.calls.map(\.arguments), [["update"], ["upgrade", "--cask", "eyo-25/tap/quickstream"]], "update → upgrade 순서, 전체 cask 이름")
        check(fake.calls.allSatisfy { $0.executable == brew }, "찾은 brew 로 실행")
        check(fake.environments.allSatisfy { $0["HOMEBREW_NO_AUTO_UPDATE"] == "1" }, "upgrade 가 자동 update 를 또 하지 않게 한다")
        check(!FileManager.default.fileExists(atPath: updater.lockURL.path), "끝나면 잠금 해제")
        let log = (try? String(contentsOf: updater.logURL, encoding: .utf8)) ?? ""
        check(log.contains("$ brew update") && log.contains("$ brew upgrade --cask eyo-25/tap/quickstream"), "로그에 실행한 명령이 남는다")

        // 실패하면 이후 단계를 실행하지 않고 사유를 로그에 남긴다
        let failing = FakeRunner()
        failing.handler = { $0.arguments == ["update"] ? .exited(1) : .exited(0) }
        let failed = await makeUpdater(fake: failing, support: support).upgrade()
        check({ if case .failed(let m) = failed { return m.contains("brew update") }; return false }(), "update 실패는 failed")
        checkEqual(failing.calls.map(\.arguments), [["update"]], "update 가 실패하면 upgrade 는 실행하지 않는다")
        let failLog = (try? String(contentsOf: updater.logURL, encoding: .utf8)) ?? ""
        check(failLog.contains("코드 1"), "실패 코드가 로그에 남는다")
        check(!FileManager.default.fileExists(atPath: updater.lockURL.path), "실패해도 잠금 해제")
        check(!failLog.contains("upgrade"), "실패한 실행의 로그는 이전 실행 내용을 덮어쓴다")

        let upgradeFails = FakeRunner()
        upgradeFails.handler = { $0.arguments.first == "upgrade" ? .exited(2) : .exited(0) }
        let secondFailed = await makeUpdater(fake: upgradeFails, support: support).upgrade()
        check({ if case .failed(let m) = secondFailed { return m.contains("upgrade") }; return false }(), "upgrade 실패는 failed")

        let launchFail = FakeRunner()
        launchFail.handler = { _ in .launchFailed("nope") }
        let lf = await makeUpdater(fake: launchFail, support: support).upgrade()
        check({ if case .failed(let m) = lf { return m.contains("nope") }; return false }(), "실행 실패 사유 전달")

        let none = await makeUpdater(fake: fake, support: support, brews: ["/nonexistent/brew"]).upgrade()
        check({ if case .failed = none { return true }; return false }(), "brew 가 없으면 failed")
    }

    section("Update/Lock")
    runAsync {
        let support = temp.appendingPathComponent("s3")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let lockPath = support.appendingPathComponent("update.lock")
        let now = Date(timeIntervalSince1970: 2_000_000)

        // 살아 있는 주인이 최근에 잡은 잠금은 존중한다
        try? "999 \(Int(now.timeIntervalSince1970) - 60)\n".write(to: lockPath, atomically: true, encoding: .utf8)
        let held = FakeRunner()
        let busy = await makeUpdater(fake: held, support: support, now: { now }, alive: { $0 == 999 }).upgrade()
        checkEqual(busy, .alreadyRunning, "살아 있는 주인이 있으면 실행하지 않는다")
        check(held.calls.isEmpty, "중복 실행은 brew 를 띄우지 않는다")
        check(FileManager.default.fileExists(atPath: lockPath.path), "남의 잠금은 지우지 않는다")

        // 주인이 죽은 잠금은 가져온다
        let takeover = FakeRunner()
        let afterDead = await makeUpdater(fake: takeover, support: support, now: { now }, alive: { _ in false }).upgrade()
        checkEqual(afterDead, .finished, "주인이 죽은 잠금은 이어받는다")

        // 제한 시간을 넘긴 잠금은 주인이 살아 있어도 깨진 것으로 본다
        try? "999 \(Int(now.timeIntervalSince1970) - 661)\n".write(to: lockPath, atomically: true, encoding: .utf8)
        let overdue = await makeUpdater(fake: FakeRunner(), support: support, now: { now }, alive: { _ in true }).upgrade()
        checkEqual(overdue, .finished, "11분 넘은 잠금은 이어받는다")

        // 읽을 수 없는 잠금도 막지 않는다
        try? "garbage".write(to: lockPath, atomically: true, encoding: .utf8)
        let garbage = await makeUpdater(fake: FakeRunner(), support: support, now: { now }, alive: { _ in true }).upgrade()
        checkEqual(garbage, .finished, "깨진 잠금 파일은 무시")

        // 실행 도중 같은 곳에서 또 시작하면 막힌다(앱 두 개·재시도 연타)
        let reentrant = FakeRunner()
        let inner = makeUpdater(fake: reentrant, support: support, now: { now }, alive: { _ in true })
        nonisolated(unsafe) var innerOutcome: UpdateOutcome?
        reentrant.handler = { call in
            if call.arguments == ["update"] { innerOutcome = await inner.upgrade() }
            return .exited(0)
        }
        let outer = await inner.upgrade()
        checkEqual(outer, .finished, "바깥 실행은 정상 종료")
        checkEqual(innerOutcome, .alreadyRunning, "실행 중 두 번째 실행은 거절")
        checkEqual(reentrant.calls.count, 2, "brew 는 한 벌(update, upgrade)만 실행")
    }

    section("Update/Stalled")
    runAsync {
        let support = temp.appendingPathComponent("s4")
        let fake = FakeRunner()
        fake.handler = { $0.arguments == ["update"] ? .exited(0) : .timedOut }
        let updater = makeUpdater(fake: fake, support: support)
        let awaited1 = await updater.upgrade()
        checkEqual(awaited1, .stalled, "upgrade 시간 초과는 stalled")
        check(!FileManager.default.fileExists(atPath: updater.lockURL.path), "stalled 뒤 잠금 해제(다시 시도 가능)")
        let log = (try? String(contentsOf: updater.logURL, encoding: .utf8)) ?? ""
        check(log.contains("제한 시간"), "시간 초과가 로그에 남는다")
        let awaited2 = await makeUpdater(fake: FakeRunner(), support: support).upgrade()
        checkEqual(awaited2, .finished, "stalled 뒤 다시 시도하면 진행")

        // 시간은 update+upgrade 전체에 대한 한 예산이다
        nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 3_000_000)
        let budget = FakeRunner()
        budget.handler = { _ in clock = clock.addingTimeInterval(400); return .exited(0) }
        _ = await makeUpdater(fake: budget, support: support, timeout: 660, now: { clock }).upgrade()
        checkEqual(budget.timeouts.count, 2, "두 단계 모두 실행")
        checkEqual(budget.timeouts[0], 660, "첫 단계는 전체 예산")
        checkEqual(budget.timeouts[1], 260, "둘째 단계는 남은 시간만")

        // 첫 단계에서 예산을 다 쓰면 둘째 단계는 시작하지 않는다
        clock = Date(timeIntervalSince1970: 3_000_000)
        let spent = FakeRunner()
        spent.handler = { _ in clock = clock.addingTimeInterval(700); return .exited(0) }
        let awaited3 = await makeUpdater(fake: spent, support: support, timeout: 660, now: { clock }).upgrade()
        checkEqual(awaited3, .stalled, "예산 소진은 stalled")
        checkEqual(spent.calls.count, 1, "예산을 넘기면 upgrade 를 시작하지 않는다")
    }

    section("Update/SystemRunner")
    runAsync {
        let runner = SystemProcessRunner()
        let awaited4 = await runner.run("/bin/sh", ["-c", "exit 3"], environment: [:], output: nil, timeout: 20)
        checkEqual(awaited4, .exited(3), "종료 코드 전달")
        let awaited5 = await runner.run("/bin/sh", ["-c", "exit 0"], environment: ["QS_X": "1"], output: nil, timeout: 20)
        checkEqual(awaited5, .exited(0), "정상 종료")
        let awaited6 = await runner.run("/bin/sleep", ["30"], environment: [:], output: nil, timeout: 0.3)
        checkEqual(awaited6, .timedOut, "제한 시간이 지나면 종료하고 timedOut")
        if case .launchFailed = await runner.run("/nonexistent/binary", [], environment: [:], output: nil, timeout: 5) {} else { check(false, "없는 실행 파일은 launchFailed") }
        let out = temp.appendingPathComponent("runner-out.txt")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: out) {
            _ = await runner.run("/bin/sh", ["-c", "echo \"$QS_X\"; echo err >&2"], environment: ["QS_X": "hello"], output: handle, timeout: 20)
            try? handle.close()
        }
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        check(text.contains("hello") && text.contains("err"), "stdout/stderr 가 로그 핸들로 들어가고 환경변수가 전달된다")
    }

    section("Update/Relaunch")
    let script = BrewUpdater.relaunchScript(pid: 77, appPath: "/Applications/Quick Stream.app")
    checkEqual(Array(script.suffix(2)), ["77", "/Applications/Quick Stream.app"], "경로는 인자로 전달(공백·인용 안전)")
    check(script[1].contains("/usr/bin/open \"$2\""), "경로를 셸 문자열에 끼워 넣지 않는다")

    section("Update/Controller")
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    let session = URLSession(configuration: config)
    runAsync {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 5_000_000)
        let controller = UpdateController(session: session, defaults: defaults, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0", now: { clock })
        checkEqual(controller.status, .unknown, "처음엔 unknown")
        checkEqual(controller.statusText, "0.1.0", "unknown 문구")

        StubProtocol.requests = 0
        StubProtocol.response = (200, releaseJSON(tag: "v0.1.0"))
        let awaited7 = await controller.check(force: false)
        checkEqual(awaited7, .done(.upToDate), "같은 버전이면 최신")
        checkEqual(controller.statusText, "0.1.0 · 최신 버전입니다", "최신 문구")
        checkEqual(StubProtocol.requests, 1, "요청 1회")

        StubProtocol.response = (200, releaseJSON(tag: "v0.2.0"))
        clock = clock.addingTimeInterval(6 * 3600 - 1)
        let awaited8 = await controller.check(force: false)
        checkEqual(awaited8, .skipped, "6시간 안에는 요청하지 않는다")
        checkEqual(StubProtocol.requests, 1, "스로틀된 확인은 네트워크를 쓰지 않는다")
        checkEqual(controller.status, .upToDate, "스로틀 중에는 이전 상태 유지")

        let awaited9 = await controller.check(force: true)
        checkEqual(awaited9, .done(.available(version: "0.2.0", url: URL(string: "https://github.com/eyo-25/quickstream/releases/tag/v0.2.0")!)), "사용자 요청은 스로틀을 무시")
        checkEqual(controller.statusText, "0.2.0 업데이트 가능", "업데이트 가능 문구")

        // 새 인스턴스(앱 재시작)는 스로틀 중이어도 저장된 결과로 상태를 채운다
        let restarted = UpdateController(session: session, defaults: defaults, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0", now: { clock })
        let requestsBefore = StubProtocol.requests
        let awaited10 = await restarted.check(force: false)
        checkEqual(awaited10, .skipped, "재시작 직후에도 스로틀")
        checkEqual(StubProtocol.requests, requestsBefore, "재시작 후 스로틀 중에는 요청 없음")
        check({ if case .available(let v, _) = restarted.status { return v == "0.2.0" }; return false }(), "저장된 최신 버전으로 상태 복원")

        clock = clock.addingTimeInterval(6 * 3600)
        StubProtocol.response = (200, releaseJSON(tag: "v0.2.0", prerelease: true))
        let ignored = await controller.check(force: false)
        check({ if case .failed = ignored { return true }; return false }(), "prerelease 응답은 업데이트로 보지 않는다")
        check({ if case .available = controller.status { return true }; return false }(), "조용한 확인 실패는 이전 상태를 유지")

        StubProtocol.response = (403, Data())
        let limited = await controller.check(force: true)
        check({ if case .failed(let m) = limited { return m.contains("한도") }; return false }(), "403 은 요청 한도 안내")
        check({ if case .failed = controller.status { return true }; return false }(), "사용자 요청 실패는 failed 상태")

        // 현재 버전이 더 높으면(개발 빌드) 업데이트가 아니다
        let (d2, s2) = makeDefaults()
        defer { d2.removePersistentDomain(forName: s2) }
        let newer = UpdateController(session: session, defaults: d2, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "9.0.0", now: { clock })
        StubProtocol.response = (200, releaseJSON(tag: "v0.2.0"))
        let awaited11 = await newer.check(force: true)
        checkEqual(awaited11, .done(.upToDate), "현재가 더 높으면 최신으로 본다")
    }

    section("Update/ControllerUpgrade")
    runAsync {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let support = temp.appendingPathComponent("s5")
        let fake = FakeRunner()
        let updater = makeUpdater(fake: fake, support: support)
        let controller = UpdateController(session: session, defaults: defaults, updater: updater, bundleURL: linked, currentVersion: "0.1.0")

        let awaited12 = await controller.performUpdate()
        checkEqual(awaited12, .finished, "brew 설치는 업그레이드 실행")
        checkEqual(controller.status, .updating, "성공하면 재시작 전까지 updating")
        checkEqual(controller.statusText, "0.1.0 · 업데이트 중…", "updating 문구")
        checkEqual(fake.calls.map(\.arguments), [["update"], ["upgrade", "--cask", "eyo-25/tap/quickstream"]], "컨트롤러도 update → upgrade")

        let (d2, s2) = makeDefaults()
        defer { d2.removePersistentDomain(forName: s2) }
        let failing = FakeRunner()
        failing.handler = { _ in .exited(1) }
        let c2 = UpdateController(session: session, defaults: d2, updater: makeUpdater(fake: failing, support: support), bundleURL: linked, currentVersion: "0.1.0")
        _ = await c2.performUpdate()
        check({ if case .failed = c2.status { return true }; return false }(), "실패는 failed 상태")

        let (d3, s3) = makeDefaults()
        defer { d3.removePersistentDomain(forName: s3) }
        let hung = FakeRunner()
        hung.handler = { _ in .timedOut }
        let c3 = UpdateController(session: session, defaults: d3, updater: makeUpdater(fake: hung, support: support), bundleURL: linked, currentVersion: "0.1.0")
        let awaited13 = await c3.performUpdate()
        checkEqual(awaited13, .stalled, "시간 초과")
        checkEqual(c3.status, .stalled, "stalled 상태")
        check(c3.statusText.contains("끝나지 않았습니다"), "stalled 문구")
        // 다시 시도 가능: 잠금이 풀려 있어 새로 시작된다
        hung.handler = { _ in .exited(0) }
        let awaited14 = await c3.performUpdate()
        checkEqual(awaited14, .finished, "stalled 뒤 재시도")
    }

    section("Update/OfflineRestartRestoresCache")
    runAsync {
        // 스로틀이 풀린 시점의 재시작 + 네트워크 실패: 저장된 최신 버전이 현재보다 높을 때만 '업데이트 가능'을 복원한다
        func seeded(_ version: String) -> (UserDefaults, String) {
            let (d, s) = makeDefaults()
            d.set(version, forKey: UpdateController.latestVersionKey)
            d.set("https://github.com/eyo-25/quickstream/releases/tag/v\(version)", forKey: UpdateController.latestURLKey)
            return (d, s)
        }
        let (d1, s1) = seeded("0.2.0")
        defer { d1.removePersistentDomain(forName: s1) }
        let offline = UpdateController(session: session, defaults: d1, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0")
        StubProtocol.response = (500, Data())
        let outcome = await offline.check(force: false)
        check({ if case .failed = outcome { return true }; return false }(), "실패 메시지는 그대로 돌려준다")
        check({ if case .available(let v, _) = offline.status { return v == "0.2.0" }; return false }(), "캐시된 더 높은 버전으로 '업데이트 가능' 복원")

        let (d2, s2) = seeded("0.1.0")
        defer { d2.removePersistentDomain(forName: s2) }
        let stale = UpdateController(session: session, defaults: d2, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0")
        _ = await stale.check(force: false)
        checkEqual(stale.status, .unknown, "캐시 버전이 현재와 같으면 복원하지 않는다")

        let (d3, s3) = seeded("0.0.9")
        defer { d3.removePersistentDomain(forName: s3) }
        let older = UpdateController(session: session, defaults: d3, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0")
        _ = await older.check(force: false)
        checkEqual(older.status, .unknown, "캐시 버전이 현재보다 낮으면 복원하지 않는다")

        let (d4, s4) = makeDefaults()
        defer { d4.removePersistentDomain(forName: s4) }
        let empty = UpdateController(session: session, defaults: d4, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.1.0")
        _ = await empty.check(force: false)
        checkEqual(empty.status, .unknown, "캐시가 없으면 unknown 유지")
    }

    section("Update/FailureKeepsRetryable")
    runAsync {
        // 업데이트가 실패해도 '업데이트 가능'을 잃지 않고, 사유는 따로 보여 주며, 다시 시도할 수 있다
        nonisolated(unsafe) var installed: Version? = nil
        let support = temp.appendingPathComponent("s7")
        let url = URL(string: "https://github.com/eyo-25/quickstream/releases/tag/v0.2.0")!
        func makeAvailable(_ fake: FakeRunner) async -> (UpdateController, UserDefaults, String) {
            let (d, s) = makeDefaults()
            let c = UpdateController(session: session, defaults: d, updater: makeUpdater(fake: fake, support: support), bundleURL: linked,
                                     currentVersion: "0.1.0", installedVersion: { _ in installed })
            StubProtocol.response = (200, releaseJSON(tag: "v0.2.0"))
            _ = await c.check(force: true)
            return (c, d, s)
        }

        // brew 비정상 종료
        let failing = FakeRunner()
        failing.handler = { _ in .exited(1) }
        let (c1, d1, s1) = await makeAvailable(failing)
        defer { d1.removePersistentDomain(forName: s1) }
        let out1 = await c1.performUpdate()
        check({ if case .failed = out1 { return true }; return false }(), "brew 실패는 failed 결과")
        checkEqual(c1.status, .available(version: "0.2.0", url: url), "실패 뒤에도 업데이트 가능 상태 유지")
        check(c1.lastFailure?.contains("brew update") == true, "실패 사유를 따로 보관: \(String(describing: c1.lastFailure))")
        check(c1.statusText.contains("0.2.0 업데이트 가능") && c1.statusText.contains("마지막 업데이트 실패"), "상태 문구에 가능 + 실패 사유: \(c1.statusText)")

        // 재시도 성공: brew 가 이번엔 성공하고 설치된 버전도 올랐다
        failing.handler = { _ in .exited(0) }
        installed = Version("0.2.0")
        let out2 = await c1.performUpdate()
        checkEqual(out2, .finished, "실패 뒤 재시도가 성공")
        checkEqual(c1.status, .updating, "성공하면 재시작 전까지 updating")
        check(c1.lastFailure == nil, "재시도를 시작하면 이전 실패 사유를 지운다")
        // 재시작된(0.2.0) 앱의 확인은 최신 버전
        let (dr, sr) = makeDefaults()
        defer { dr.removePersistentDomain(forName: sr) }
        let relaunched = UpdateController(session: session, defaults: dr, runner: FakeRunner(), bundleURL: sourceApp, currentVersion: "0.2.0")
        StubProtocol.response = (200, releaseJSON(tag: "v0.2.0"))
        let relaunchedOutcome = await relaunched.check(force: true)
        checkEqual(relaunchedOutcome, .done(.upToDate), "재시작 뒤에는 upToDate")

        // tap 이 새 버전을 못 받음: brew 는 0 으로 끝났지만 설치된 버전이 그대로
        installed = Version("0.1.0")
        let ok = FakeRunner()
        let (c2, d2, s2) = await makeAvailable(ok)
        defer { d2.removePersistentDomain(forName: s2) }
        let out3 = await c2.performUpdate()
        check({ if case .failed(let m) = out3 { return m.contains("새 버전을 설치하지 않았습니다") }; return false }(), "설치 버전 미상승은 failed")
        checkEqual(c2.status, .available(version: "0.2.0", url: url), "미상승 실패 뒤에도 업데이트 가능 상태 유지")
        check(c2.lastFailure?.contains("tap") == true, "tap 안내 사유 유지")
        // 같은 상태를 다시 확인해도 사유는 남고, 다시 시도하면 지워진다
        StubProtocol.response = (200, releaseJSON(tag: "v0.2.0"))
        _ = await c2.check(force: true)
        check(c2.lastFailure != nil, "같은 업데이트 가능 상태의 재확인은 실패 사유를 지우지 않는다")
        installed = Version("0.2.0")
        let out4 = await c2.performUpdate()
        checkEqual(out4, .finished, "tap 이 따라잡은 뒤 재시도 성공")
        check(c2.lastFailure == nil, "성공 시 사유 없음")

        // 알려진 업데이트가 없던 상태의 실패는 기존처럼 failed
        let (d3, s3) = makeDefaults()
        defer { d3.removePersistentDomain(forName: s3) }
        let bare = UpdateController(session: session, defaults: d3, updater: makeUpdater(fake: failing, support: support), bundleURL: linked,
                                    currentVersion: "0.1.0", installedVersion: { _ in Version("0.1.0") })
        _ = await bare.performUpdate()
        check({ if case .failed = bare.status { return true }; return false }(), "알려진 업데이트가 없으면 failed 상태")
    }

    section("Update/UpgradeMustInstallNewerVersion")
    runAsync {
        // brew upgrade 가 올릴 게 없어도 0 으로 끝난다: 설치된 앱 버전이 안 올랐으면 재실행하지 말고 실패로 본다
        func writePlist(_ version: String) {
            let dir = linked.appendingPathComponent("Contents")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            (["CFBundleShortVersionString": version] as NSDictionary).write(to: dir.appendingPathComponent("Info.plist"), atomically: true)
        }
        let support = temp.appendingPathComponent("s6")

        writePlist("0.1.0")
        let (d1, s1) = makeDefaults()
        defer { d1.removePersistentDomain(forName: s1) }
        let noop = UpdateController(session: session, defaults: d1, updater: makeUpdater(fake: FakeRunner(), support: support), bundleURL: linked, currentVersion: "0.1.0")
        let outcome1 = await noop.performUpdate()
        check({ if case .failed(let m) = outcome1 { return m.contains("새 버전을 설치하지 않았습니다") }; return false }(), "버전이 그대로면 실패: \(outcome1)")
        check({ if case .failed = noop.status { return true }; return false }(), "실패 상태로 표시")

        writePlist("0.2.0")
        let (d2, s2) = makeDefaults()
        defer { d2.removePersistentDomain(forName: s2) }
        let upgraded = UpdateController(session: session, defaults: d2, updater: makeUpdater(fake: FakeRunner(), support: support), bundleURL: linked, currentVersion: "0.1.0")
        let outcome2 = await upgraded.performUpdate()
        checkEqual(outcome2, .finished, "설치된 버전이 더 높으면 성공")

        writePlist("0.0.9")
        let (d3, s3) = makeDefaults()
        defer { d3.removePersistentDomain(forName: s3) }
        let older = UpdateController(session: session, defaults: d3, updater: makeUpdater(fake: FakeRunner(), support: support), bundleURL: linked, currentVersion: "0.1.0")
        let outcome3 = await older.performUpdate()
        check({ if case .failed = outcome3 { return true }; return false }(), "더 낮은 버전도 성공이 아니다")
    }

    section("Update/SigkillAfterGrace")
    runAsync {
        // SIGTERM 을 무시하는 프로세스: 유예 뒤 SIGKILL 로 끝내 .timedOut 을 돌려줘야 한다(핸들러가 영영 안 불리면 여기서 멈춘다)
        let runner = SystemProcessRunner(killGrace: 0.2)
        let started = Date()
        let result = await runner.run("/bin/sh", ["-c", "trap '' TERM; while :; do sleep 0.1; done"], environment: [:], output: nil, timeout: 0.3)
        checkEqual(result, .timedOut, "SIGTERM 무시 프로세스도 시간 초과로 끝난다")
        check(Date().timeIntervalSince(started) < 5, "무한정 기다리지 않는다")
    }
}
