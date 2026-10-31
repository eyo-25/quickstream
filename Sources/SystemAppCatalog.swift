import AppKit

/// NSWorkspace 기반 AppCatalog. Electron 판 `native/QuickStreamBridge.swift` 의 동작을 그대로 옮겼다.
final class SystemAppCatalog: AppCatalog, @unchecked Sendable {
    var onAppActivated: ((RunningApp) -> Void)?

    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private let lock = NSLock()
    private var iconCache: [String: Data] = [:]
    /// 오래 안 쓴 순서(앞이 가장 오래됨). 상한을 넘으면 앞에서부터 버린다.
    private var iconOrder: [String] = []
    private static let iconCacheLimit = 256
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let ref = self.describe(app) else { return }
            self.onAppActivated?(ref)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    // MARK: - 실행 중 앱

    /// 일반(Dock 에 보이는) 앱만. 백그라운드 유틸·자기 자신·종료된 앱은 제외
    private func describe(_ app: NSRunningApplication) -> RunningApp? {
        guard app.activationPolicy == .regular, !app.isTerminated,
              app.processIdentifier != ownPid, let bundleId = app.bundleIdentifier else { return nil }
        return RunningApp(
            bundleId: bundleId, pid: app.processIdentifier, name: app.localizedName ?? bundleId,
            appPath: app.bundleURL?.path, launchedAt: app.launchDate)
    }

    func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap(describe)
    }

    func frontmostApp() -> RunningApp? {
        NSWorkspace.shared.frontmostApplication.flatMap(describe)
    }

    // MARK: - 실행/전환

    func activate(bundleId: String, pid: Int32?) async -> ActionResult {
        var target: NSRunningApplication?
        if let pid, let byPid = NSRunningApplication(processIdentifier: pid), byPid.bundleIdentifier == bundleId {
            target = byPid
        }
        if target == nil {
            target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first { !$0.isTerminated }
        }
        guard let app = target, !app.isTerminated, let url = app.bundleURL else {
            return .failure("실행 중이 아닙니다: \(bundleId)")
        }
        app.unhide()
        return await openApplication(at: url)
    }

    /// `activate`/`open` 은 NSWorkspace.openApplication 을 거쳐 이미 떠 있는 앱에 reopen 이벤트를 보낸다.
    /// 창을 닫아 두고 상주하는 앱(카카오톡 등)은 그 이벤트에 메인 창을 새로 띄우므로, 단순 포커스 복원에는 쓰지 않는다.
    /// 대신 macOS 14 협력 활성화(yieldActivation + activate)로 reopen 없이 앞으로 가져온다.
    func refocus(bundleId: String, pid: Int32?) -> Bool {
        var target: NSRunningApplication?
        if let pid, let byPid = NSRunningApplication(processIdentifier: pid), byPid.bundleIdentifier == bundleId {
            target = byPid
        }
        if target == nil {
            target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first { !$0.isTerminated }
        }
        // 종료된 앱은 되살리지 않는다(복원 실패로 앱이 새로 실행되면 안 된다)
        guard let app = target, !app.isTerminated else { return false }
        app.unhide()
        NSApplication.shared.yieldActivation(to: app)
        return app.activate()
    }

    func open(bundleId: String?, appPath: String?) async -> ActionResult {
        if let appPath {
            guard appPath.hasSuffix(".app"), FileManager.default.fileExists(atPath: appPath) else {
                return .failure("앱을 찾을 수 없습니다: \(appPath)")
            }
            return await openApplication(at: URL(fileURLWithPath: appPath))
        }
        if let bundleId {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                return .failure("설치된 앱을 찾을 수 없습니다: \(bundleId)")
            }
            return await openApplication(at: url)
        }
        return .failure("bundleId 또는 appPath 가 필요합니다")
    }

    /// 협력적 `activate()` 는 호출 앱이 활성 상태여야 해서, 시스템이 처리하는 openApplication 을 쓴다.
    private func openApplication(at url: URL) async -> ActionResult {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - 설치된 앱

    /// 호출할 때마다 새로 훑는다(설정 창을 열 때마다 최신 설치 목록을 보이려고). 디스크 읽기는 백그라운드 큐에서 한다.
    func installedApps() async -> [InstalledApp] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[InstalledApp], Never>) in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: Self.scanInstalledApps()) }
        }
    }

    /// 사용자 언어에 맞는 앱 이름. `FileManager.displayName` 은 최신 앱이 쓰는 InfoPlist.loctable
    /// (언어별 딕셔너리 한 파일)을 해석하지 못해 영문 파일명으로 떨어지므로, loctable → InfoPlist.strings 순으로 직접 읽는다.
    static func localizedAppName(_ bundle: Bundle, fallback: String) -> String {
        let candidates = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages)

        func name(in strings: [String: Any]?) -> String? {
            guard let strings else { return nil }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = strings[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }

        if let url = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
           let table = NSDictionary(contentsOf: url) as? [String: Any] {
            for language in candidates {
                if let found = name(in: table[language] as? [String: Any]) { return found }
            }
        }
        for language in candidates {
            if let url = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: language),
               let found = name(in: NSDictionary(contentsOf: url) as? [String: Any]) {
                return found
            }
        }
        return fallback
    }

    /// 디스크를 훑으므로 메인 스레드가 아닌 곳에서 부른다. 루트는 테스트에서 바꿀 수 있다.
    static func scanInstalledApps(
        roots: [String] = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"],
        extraApps: [String] = ["/System/Library/CoreServices/Finder.app"]
    ) -> [InstalledApp] {
        let fileManager = FileManager.default

        func entries(in directory: String) -> [URL] {
            (try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        }

        var found: [InstalledApp] = []
        var seen = Set<String>()
        func consider(_ url: URL) {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier, seen.insert(bundleId).inserted else { return }
            var fallback = fileManager.displayName(atPath: url.path)
            if fallback.hasSuffix(".app") { fallback = String(fallback.dropLast(4)) }
            let name = localizedAppName(bundle, fallback: fallback)
            // 지역화된 이름과 파일 이름(보통 영문)이 다르면 검색에 쓰도록 함께 보관한다("계산기" / "Calculator")
            let fileName = url.deletingPathExtension().lastPathComponent
            found.append(InstalledApp(bundleId: bundleId, name: name, altName: fileName != name ? fileName : nil, appPath: url.path))
        }

        for root in roots {
            for entry in entries(in: root) {
                if entry.pathExtension == "app" {
                    consider(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // 1단계 하위 폴더(예: Utilities)까지만 본다
                    for child in entries(in: entry.path) where child.pathExtension == "app" { consider(child) }
                }
            }
        }
        // Finder 는 앱 폴더가 아니라 CoreServices 에 있어 따로 넣는다(고정 슬롯 후보로 가장 흔하다)
        for path in extraApps { consider(URL(fileURLWithPath: path)) }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 아이콘

    func iconPNG(for target: IconTarget, pixels: Int) -> Data? {
        let size = min(max(pixels, 1), 256)
        let path: String?
        switch target {
        case let .appPath(appPath):
            // open 과 같은 규칙: .app 접미사 + 존재 확인
            path = appPath.hasSuffix(".app") && FileManager.default.fileExists(atPath: appPath) ? appPath : nil
        case let .bundleId(bundleId):
            path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.path
        }
        guard let path else { return nil }

        let key = "\(path)@\(size)"
        if let hit = lock.withLock({ () -> Data? in
            guard let data = iconCache[key] else { return nil }
            iconOrder.removeAll { $0 == key }
            iconOrder.append(key)
            return data
        }) { return hit }

        guard let png = Self.renderIcon(path: path, pixels: size) else { return nil }
        lock.withLock {
            iconCache[key] = png
            iconOrder.removeAll { $0 == key }
            iconOrder.append(key)
            while iconOrder.count > Self.iconCacheLimit { iconCache[iconOrder.removeFirst()] = nil }
        }
        return png
    }

    /// NSImage 를 바로 PNG 로 바꾸면 해상도 표현(@1x/@2x)이 섞여 크기가 들쭉날쭉해서, 비트맵에 그려 크기를 고정한다.
    private static func renderIcon(path: String, pixels: Int) -> Data? {
        let image = NSWorkspace.shared.icon(forFile: path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
