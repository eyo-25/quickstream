import AppKit

/// 앱 진입점. 단일 인스턴스: 이미 실행 중이면 명령(오버레이/설정)만 전달하고 끝낸다.
enum LaunchCommand: String {
    case show, settings

    /// 인자에서 읽는다. `--settings` 가 있으면 설정 창, `--show` 가 있으면 오버레이, 없으면 nil.
    static func from(arguments: [String]) -> LaunchCommand? {
        if arguments.contains("--settings") { return .settings }
        if arguments.contains("--show") { return .show }
        return nil
    }

    static var notificationName: Notification.Name { Notification.Name("\(AppInfo.bundleId).command") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var commandObserver: NSObjectProtocol?
    /// `controller.start()` 가 끝났는가. 그 전에 온 명령은 보류한다(메뉴·창이 아직 없다).
    private var started = false
    private var pendingCommands: [LaunchCommand] = []

    override init() {
        super.init()
        // 두 번째 실행이 보내는 명령(`QuickStream --show`, `--settings`). 첫 인스턴스가 초기화 중이어도 놓치지 않도록
        // 앱 시작 알림(applicationDidFinishLaunching)이 아니라 델리게이트 생성 시점에 등록한다.
        commandObserver = DistributedNotificationCenter.default().addObserver(forName: LaunchCommand.notificationName, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            if info?["command"] as? String == "key", let code = info?["keyCode"] as? Int {
                self?.controller.injectTestKey(keyCode: UInt16(code), down: info?["phase"] as? String != "up", shift: info?["shift"] as? Bool ?? false)
                return
            }
            self?.handle(LaunchCommand(rawValue: info?["command"] as? String ?? ""))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        started = true
        let pending = pendingCommands
        pendingCommands = []
        for command in pending { handle(command) }
        handle(LaunchCommand.from(arguments: CommandLine.arguments))
    }

    /// `start()` 이후에만 실행한다. 그 전이면 보류했다가 시작이 끝나면 순서대로 처리한다.
    private func handle(_ command: LaunchCommand?) {
        guard let command else { return }
        guard started else {
            pendingCommands.append(command)
            return
        }
        switch command {
        case .show: controller.showOverlay()
        case .settings: controller.openSettings()
        }
    }

    /// Finder/Spotlight 에서 이미 실행 중인 앱을 다시 열면 설정 창을 보여 준다(메뉴바 앱은 Dock 아이콘이 없어 눌러 볼 곳이 없다)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.openSettings()
        return false
    }

    /// ⌘Q·메뉴 종료 때 설정 창의 저장하지 않은 변경을 확인한다(창 닫기 확인과 같은 '적용/닫기/취소').
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.shouldTerminate() ? .terminateNow : .terminateCancel
    }
}

// 격리 실행(--support-dir=)은 사용자 인스턴스와 별개로 뜰 수 있게 단일 인스턴스 검사를 건너뛴다
if AppInfo.supportDirectoryOverride == nil {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleId).filter { $0.processIdentifier != getpid() }
    if !others.isEmpty {
        let command = LaunchCommand.from(arguments: CommandLine.arguments) ?? .show
        DistributedNotificationCenter.default().postNotificationName(LaunchCommand.notificationName, object: nil, userInfo: ["command": command.rawValue], deliverImmediately: true)
        exit(0)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
