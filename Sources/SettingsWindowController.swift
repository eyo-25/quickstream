import AppKit
import SwiftUI

/// 설정 창(싱글턴처럼 쓴다: 이미 열려 있으면 포커스만 옮긴다).
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(store: SettingsStoring,
         catalog: AppCatalog,
         save: @escaping (Settings) -> ActionResult,
         checkForUpdates: @escaping () -> Void,
         versionText: @escaping () -> String,
         onRecordingChange: @escaping (Bool) -> Void) {
        model = SettingsModel(store: store, catalog: catalog, save: save, checkForUpdates: checkForUpdates, versionText: versionText, onRecordingChange: onRecordingChange)
        let host = NSHostingController(rootView: SettingsRootView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "퀵스트림 설정"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // 기본 높이: 한 화면에 더 많이 보이도록 높이되(680 → 860), 작은 화면에서는 보이는 영역(제목 표시줄·여백 포함)에 맞춰 줄인다. 최소 높이 아래로는 줄이지 않는다.
        let contentHeight = min(860, max(560, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        window.setContentSize(NSSize(width: 960, height: contentHeight))
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.appearance = NSAppearance(named: .darkAqua)
        // 시스템의 확대 팝인/축소 연출을 끈다(열 때·닫을 때 즉시 나타나고 사라진다)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        // 저장이 끝나면 창을 닫는다. 버튼 동작이 끝난 뒤에 닫도록 한 박자 미룬다(SwiftUI 가 동작 중인 뷰를 내리지 않게).
        // 저장 직후엔 isDirty 가 false 라 닫기 확인 창은 뜨지 않는다. 그 한 박자 사이에 다시 편집했다면 확인 없이 버려지지 않게 닫지 않는다.
        model.onSaved = { [weak self] in DispatchQueue.main.async { if self?.model.isDirty == false { self?.window?.close() } } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 는 쓰지 않는다") }

    /// 이미 보이면 앞으로(최소화 복원), 닫혀 있었다면 디스크 기준으로 편집을 새로 시작해 연다.
    func open() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        } else if !window.isVisible {
            // 열릴 때 값이 바뀌며 생기는 색 전환·패널 슬라이드·배너 전환이 보이지 않게, 애니메이션을 끈 채로 최종 상태로 만든다
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.resetFromStore() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        endRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        endRecording()
    }

    /// 녹화 중 닫기/포커스 이탈이면 버튼의 녹화 표시도 끝내고(재오픈 때 녹화 상태로 남지 않게) 전역 단축키를 되살린다.
    /// AppKit 은 창이 닫히거나 키 창을 잃을 때 resignFirstResponder 를 부르지 않으므로 직접 끝낸다. 모델 호출은 중복 방지용 보루다.
    /// 녹화 중이 아닐 때는 입력 포커스를 지우지 않는다: 오버레이를 닫고 설정 창으로 돌아왔을 때 입력 중이던 필드로 키가 가야 한다.
    private func endRecording() {
        // 단축키 녹화 버튼이든 슬롯·닫기 키 녹화 버튼이든 녹화 중이면 입력 포커스를 지워 버튼의 녹화 표시를 끝낸다
        if model.isRecordingShortcut || window?.firstResponder is KeyRecorder.RecorderButton { window?.makeFirstResponder(nil) }
        model.setShortcutRecording(false)
    }

    private enum UnsavedChoice { case apply, discard, cancel }

    /// 저장하지 않은 변경이 있을 때 묻는 '적용' / '닫기'(버리기) / '취소' 확인창.
    private func askUnsaved(applyHint: String) -> UnsavedChoice {
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 변경 사항이 있습니다."
        alert.informativeText = "\(applyHint) 닫기를 누르면 변경 사항이 사라집니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "적용") // 기본(Enter)
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: "취소").keyEquivalent = "\u{1b}" // Esc
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .apply
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// 창을 닫으려 할 때: 변경이 있으면 위 확인창을 띄운다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        switch askUnsaved(applyHint: "적용하면 저장하고 닫습니다.") {
        case .apply:
            // 저장이 성공하면 `onSaved` 가 창을 닫는다. 검증에 막히거나 저장이 실패하면 창이 열려 있어 사유를 볼 수 있다.
            model.save()
            return false
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    /// 앱을 종료하기 직전(⌘Q·메뉴 종료): 설정 창이 열려 있고 저장하지 않은 변경이 있으면 같은 확인창을 띄운다. 종료해도 되면 true.
    /// 창이 이미 닫혀 있으면 남아 있는 초안은 버려진 것이므로 묻지 않는다. 최소화된 창은 `isVisible` 이 false 지만 아직 열려 있는 편집이다.
    func confirmTermination() -> Bool {
        guard window?.isVisible == true || window?.isMiniaturized == true, model.isDirty else { return true }
        // 최소화돼 있으면 먼저 펼친다: 확인창이 무엇에 대한 것인지 보이고, 적용이 검증에 막혔을 때 사유가 창에 보이게 한다.
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        switch askUnsaved(applyHint: "적용하면 저장하고 종료합니다.") {
        case .apply:
            model.save()
            return !model.isDirty // 검증·저장에 실패하면 종료하지 않고 창에서 사유를 보게 한다
        case .discard:
            return true
        case .cancel:
            return false
        }
    }
}
