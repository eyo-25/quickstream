import AppKit
import UserNotifications

/// 앱 전체를 엮는다: 메뉴바 아이콘, 전역 단축키, 오버레이 표시 흐름, 설정 적용 파이프라인, 업데이트.
/// Electron 판 main/index.ts 의 수명주기를 그대로 옮겼다(표시 경쟁 취소, 이전 앱 복귀, 단축키·로그인 항목·파일 저장의 롤백).
final class AppController: NSObject, NSMenuDelegate {
    let store: SettingsStore
    private let catalog = SystemAppCatalog()
    private let deck: Deck
    private let overlay = OverlayController()
    private let shortcut = GlobalShortcut()
    private let loginItem = SystemLoginItem()
    let updater = UpdateController()

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var updateTimer: Timer?

    /// 오버레이를 열기 직전에 앞에 있던 앱(Esc 로 닫으면 포커스를 돌려준다)
    private var previousApp: RunningApp?
    /// 업데이트 재시작이 이미 종료를 승인받았나(같은 확인을 두 번 띄우지 않는다)
    private var quitApproved = false
    /// 오버레이를 열 때 퀵스트림 자신의 설정 창이 앞(키 창)에 있었나. 자기 자신은 `previousApp` 에서 제외되므로 따로 기억해,
    /// 닫을 때 다른 앱이 아니라 설정 창으로 정확히 돌아가게 한다(안 그러면 설정 창이 다른 앱 창 뒤로 밀려 같이 닫힌 것처럼 보인다).
    private var settingsWasFront = false
    /// 표시 준비 중 닫기/재호출이 오면 늦게 끝난 표시를 버리기 위한 세대 번호
    private var showGeneration = 0
    private var showing = false

    /// 메뉴 상단 상태 줄(경고/오류). 키 → 메시지
    private var statuses: [String: String] = [:]
    /// 설정 창이 단축키를 녹화하는 중인가(전역 단축키가 풀려 있다)
    private var shortcutRecording = false

    /// 번들(.app)로 실행 중인가. 로그인 항목·알림은 번들에서만 의미가 있다.
    private let isBundled = Bundle.main.bundleURL.pathExtension == "app"

    override init() {
        store = SettingsStore()
        deck = Deck(store: store, catalog: catalog)
        super.init()
    }

    // MARK: - 시작

    func start() {
        installMainMenu()
        installStatusItem()

        overlay.onRun = { [weak self] tabId, index in self?.run(tabId: tabId, slotIndex: index) }
        overlay.onClose = { [weak self] restore in self?.hideOverlay(restorePrevious: restore) }
        overlay.onResignKey = { [weak self] in self?.overlayLostFocus() }
        overlay.hidesOnResign = !CommandLine.arguments.contains("--keep-open")

        applyStoredSettings()
        // 처음 보는 앱이 첫 표시에서 약어로 나오지 않게, 설정에 있는 앱의 아이콘을 미리 받아 둔다
        deck.prewarm()

        // 메뉴와 열려 있는 정보 화면이 함께 갱신된다(정보 화면은 body 에서 상태 문구를 읽으므로 변경을 알려 줘야 다시 그린다).
        updater.onStatusChange = { [weak self] _ in
            self?.refreshStatusMenu()
            self?.settingsWindow?.model.objectWillChange.send()
        }
        // 업데이트 재시작은 도우미를 띄우기 전에 저장하지 않은 설정을 확인한다. 승인되면 이어지는 종료에서 같은 확인을 다시 하지 않는다.
        updater.confirmQuit = { [weak self] in
            guard let self else { return true }
            quitApproved = shouldTerminate()
            return quitApproved
        }
        updater.checkInBackground()
        // 1시간마다 깨운다. 실제 요청 간격은 UpdateController 의 스로틀(6시간)이 제한한다. 타이머를 스로틀과 같은 주기로 두면
        // 첫 발화가 항상 스로틀에 걸려 사실상 12시간마다 확인되기 때문이다.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.updater.checkInBackground() }
    }

    /// 시험 전용 키 주입(`--keep-open` 실행에서만). 일반 실행에서는 다른 프로세스가 키를 넣을 수 없다.
    func injectTestKey(keyCode: UInt16, down: Bool, shift: Bool) {
        guard CommandLine.arguments.contains("--keep-open") else { return }
        overlay.sendTestKey(keyCode: keyCode, down: down, shift: shift)
    }

    /// 디스크의 설정을 읽어 단축키·로그인 항목을 맞춘다(시작 시, '설정 다시 불러오기').
    func applyStoredSettings() {
        let settings = store.reload()
        setStatus("config", store.warning)

        // 녹화 중이면 등록하지 않는다(녹화가 끝날 때 store.current 로 등록된다)
        if !shortcutRecording { registerStoredShortcut() }

        // 설정 파일이 깨져 기본값으로 대체된 상태에서는 건드리지 않는다. 쉼표 하나 틀렸다고 켜 둔 로그인 항목이 꺼지면 안 된다.
        if isBundled, store.warning == nil {
            switch applyLoginItem(loginItem, wanted: settings.launchAtLogin) {
            case .success: setStatus("loginItem", nil)
            case let .failure(message): setStatus("loginItem", message)
            }
        }
    }

    /// 설정 창의 단축키 녹화 중에는 전역 단축키를 풀어 둔다. 등록돼 있으면 현재 조합을 누르는 순간 Carbon 이 가로채
    /// 오버레이가 뜨고 설정 창의 키 포커스를 빼앗아 녹화가 취소된다. 카운터 없이 bool 하나로 중복 호출을 걸러 낸다.
    private func setShortcutRecording(_ recording: Bool) {
        guard recording != shortcutRecording else { return }
        shortcutRecording = recording
        if recording {
            shortcut.unregister()
        } else {
            registerStoredShortcut()
        }
    }

    private func registerStoredShortcut() {
        let result = shortcut.register(store.current.shortcut) { [weak self] in self?.toggleOverlay() }
        setStatus("shortcut", result.ok ? nil : (result.error ?? "단축키를 등록하지 못했습니다"))
    }

    // MARK: - 오버레이

    func toggleOverlay() {
        // 표시 도중(아직 안 보임)에 다시 누르면 취소(닫기)로 취급한다
        if showing || overlay.isVisible { hideOverlay(restorePrevious: true) } else { showOverlay() }
    }

    func showOverlay() {
        showGeneration += 1
        let generation = showGeneration
        showing = true
        // 오버레이가 앱을 활성화하기 전에 앞에 있던 앱을 잡는다. 이미 보이는 오버레이를 다시 열면 자기 자신이 앞이라 nil → 이전 기록을 유지한다.
        let frontmost = catalog.frontmostApp()
        let settingsFront = NSApp.isActive && settingsWindow?.window?.isKeyWindow == true
        Task { @MainActor [self] in
            let state = await deck.buildState()
            guard generation == showGeneration else { return } // 그 사이 닫기/재호출이 있었다
            if frontmost != nil || !overlay.isVisible {
                previousApp = frontmost
                settingsWasFront = settingsFront
            }
            overlay.show(state)
            showing = false
        }
    }

    func hideOverlay(restorePrevious: Bool) {
        showGeneration += 1 // 진행 중인 표시가 있으면 취소
        showing = false
        guard overlay.isVisible else { return }
        overlay.hide()
        if restorePrevious { restorePreviousApp() }
    }

    /// 다른 앱으로 포커스가 넘어가 오버레이가 스스로 숨었다: 포커스는 건드리지 않는다
    private func overlayLostFocus() {
        showGeneration += 1
        showing = false
    }

    private func restorePreviousApp() {
        // 설정 창이 앞에 있는 채로 오버레이를 열었다면 그 창으로 정확히 돌아간다(다른 앱으로 가지 않는다).
        if settingsWasFront, let window = settingsWindow?.window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // 복원은 reopen 을 보내지 않는 refocus 로 한다(activate 는 창 닫힌 앱의 창을 다시 띄운다).
        guard !FocusRestore.restore(previousApp, catalog: catalog) else { return }
        // 이전 앱이 없거나 종료됐거나 앞으로 못 가져온 경우: 퀵스트림이 창 없이 활성 상태로 남아 키 입력이 갈 곳을 잃으므로 포커스를 시스템에 돌려준다.
        // 단, 설정 창이 보이면 그 창이 뒤로 밀리지 않게 그대로 둔다. (`NSApp.windows` 전체를 보면 메뉴바 상태 아이템 창이 항상 보여 이 분기가 죽은 코드가 된다.)
        let settingsVisible = settingsWindow?.window?.isVisible == true
        if !settingsVisible { NSApp.deactivate() }
    }

    private func run(tabId: String, slotIndex: Int) {
        let action = deck.action(tabId: tabId, slotIndex: slotIndex)
        hideOverlay(restorePrevious: false) // 오버레이를 먼저 숨긴 뒤 대상 앱을 활성화한다
        Task { @MainActor [self] in
            let result = await deck.execute(tabId: tabId, slotIndex: slotIndex)
            if result.ok {
                setStatus("lastError", nil)
            } else {
                reportError("실행 실패: \(result.error ?? "알 수 없는 오류")")
            }
            // 어떤 앱도 전면으로 가져오지 않은 경우(클립보드 복사, 실패)에는 원래 작업 앱으로 돌려준다.
            // 실행이 오래 걸리는 사이 사용자가 오버레이를 다시 열었다면(또는 여는 중이면) 늦은 복원이 새 오버레이의 키를 빼앗지 않게 건너뛴다.
            if (!result.ok || !(action?.activatesApp ?? false)) && !overlay.isVisible && !showing { restorePreviousApp() }
        }
    }

    // MARK: - 설정 창

    @objc func openSettings() {
        hideOverlay(restorePrevious: false) // 오버레이가 설정 창 위에 떠 있지 않게 한다
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                store: store,
                catalog: catalog,
                save: { [weak self] in self?.applySettings($0) ?? .failure("앱이 종료 중입니다") },
                checkForUpdates: { [weak self] in self?.updater.checkNow() },
                versionText: { [weak self] in self?.updater.statusText ?? AppInfo.version },
                onRecordingChange: { [weak self] in self?.setShortcutRecording($0) }
            )
        }
        settingsWindow?.open()
    }

    /// 종료해도 되는가: 설정 창에 저장하지 않은 변경이 있으면 확인한다. 이미 승인된 종료(업데이트 재시작)는 다시 묻지 않는다.
    func shouldTerminate() -> Bool { quitApproved || (settingsWindow?.confirmTermination() ?? true) }

    /// 검증 → 단축키 교체 시험 → 로그인 항목 → 파일 저장 → 적용. 어느 단계든 실패하면 앞 단계를 되돌려 파일·단축키·로그인 항목이 이전 상태 그대로다.
    private func applySettings(_ next: Settings) -> ActionResult {
        // 녹화 중에 마우스로 저장을 눌러도(버튼이 첫 응답자를 가져가지 않을 수 있다) swap 이 등록해 버린 단축키를 다시 푼다.
        // 롤백 경로도 이 함수 안에서 끝나므로 어느 반환 경로든 녹화 중이면 해제된 채 나간다. 등록 가능 여부 검사는 swap 이 이미 마쳤다.
        defer { if shortcutRecording { shortcut.unregister() } }
        if let first = SettingsValidator.validate(next).first { return .failure(first.text) }
        let current = store.current

        var rollbackShortcut: (() -> Void)?
        if next.shortcut != current.shortcut {
            guard let rollback = GlobalShortcut.swap(registry: shortcut, previous: current.shortcut, next: next.shortcut, handler: { [weak self] in self?.toggleOverlay() }) else {
                return .failure("단축키 \(Accelerator.display(next.shortcut)) 을(를) 등록할 수 없습니다. 다른 앱이 쓰고 있거나 형식이 올바르지 않습니다.")
            }
            rollbackShortcut = rollback
        }

        // 이번 저장에서 토글했을 때만 시도한다: 토글하지 않은 저장이, 시스템 설정에서 사용자가 직접 끈 항목을 되살리려다
        // 거부되어 통째로 실패하면 안 된다.
        var rollbackLogin: (() -> Void)?
        if isBundled, next.launchAtLogin != current.launchAtLogin {
            switch applyLoginItem(loginItem, wanted: next.launchAtLogin) {
            case let .failure(message):
                rollbackShortcut?()
                return .failure(message)
            case let .success(rollback): rollbackLogin = rollback
            }
        }

        let saved = store.save(next)
        if !saved.ok {
            rollbackShortcut?()
            rollbackLogin?()
            return saved
        }
        setStatus("config", nil) // 이제 디스크 파일은 유효하다
        if rollbackShortcut != nil { setStatus("shortcut", nil) }
        if rollbackLogin != nil { setStatus("loginItem", nil) }
        return .success
    }

    // MARK: - 상태 줄 · 알림

    private func setStatus(_ key: String, _ message: String?) {
        if let message { statuses[key] = message } else { statuses.removeValue(forKey: key) }
        refreshStatusMenu()
    }

    private func reportError(_ message: String) {
        FileHandle.standardError.write(Data("[\(AppInfo.displayName)] \(message)\n".utf8))
        setStatus("lastError", message)
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = AppInfo.displayName
            content.body = message
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - 메뉴바

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage()
        item.button?.toolTip = AppInfo.displayName
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        rebuild(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild(menu) }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcutText = Accelerator.display(store.current.shortcut)

        menu.addItem(item("\(AppInfo.displayName) 열기 (\(shortcutText))", #selector(openOverlayFromMenu)))

        let lines = statuses.keys.sorted().compactMap { statuses[$0]?.split(separator: "\n").first.map(String.init) }
        if !lines.isEmpty {
            menu.addItem(.separator())
            for line in lines {
                let status = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                status.isEnabled = false
                menu.addItem(status)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("설정…", #selector(openSettings), key: ","))
        if case let .available(version, _) = updater.status {
            menu.addItem(item("새 버전 \(version) 업데이트…", #selector(startUpdate)))
            // 직전 업데이트가 실패했어도 항목은 남겨 재시도할 수 있게 하고, 사유는 보조 줄로 보여 준다
            if let failure = updater.lastFailure {
                let note = NSMenuItem(title: "마지막 업데이트 실패: \(failure)", action: nil, keyEquivalent: "")
                note.isEnabled = false
                menu.addItem(note)
            }
        } else {
            menu.addItem(item("업데이트 확인…", #selector(checkForUpdates)))
        }
        menu.addItem(item("JSON 파일 열기", #selector(openSettingsFile)))
        menu.addItem(item("설정 다시 불러오기", #selector(reloadSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "\(AppInfo.displayName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openOverlayFromMenu() { showOverlay() }
    @objc private func checkForUpdates() { updater.checkNow() }
    @objc private func startUpdate() { updater.startUpdate() }
    @objc private func openSettingsFile() { NSWorkspace.shared.open(store.fileURL) }
    @objc private func reloadSettings() { applyStoredSettings() }

    /// 링 모양(바깥 8점 + 가운데 점)의 템플릿 이미지. 메뉴바 밝기에 맞춰 시스템이 색을 입힌다.
    private static func statusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let ring: CGFloat = 6.4
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let dot = NSRect(x: center.x + sin(angle) * ring - 1.3, y: center.y + cos(angle) * ring - 1.3, width: 2.6, height: 2.6)
                NSBezierPath(ovalIn: dot).fill()
            }
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - 앱 메뉴 (메뉴바에는 안 보이지만 ⌘C/⌘V/⌘W/⌘Q 같은 단축키가 설정 창에서 동작하려면 필요하다)

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppInfo.displayName)
        appMenu.addItem(item("설정…", #selector(openSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "\(AppInfo.displayName) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "\(AppInfo.displayName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(NSMenuItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(NSMenuItem(title: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
