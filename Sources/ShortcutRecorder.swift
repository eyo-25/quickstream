import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 키 이벤트 하나를 녹화 결과로 해석한다(AppKit 과 분리해 단위 테스트한다).
enum ShortcutRecording {
    enum Outcome: Equatable {
        /// Esc: 녹화 취소
        case cancel
        /// 확정된 가속키 문자열
        case accelerator(String)
        /// 수정키만 눌림: 계속 기다린다
        case ignore
        /// 일반 키인데 수정키가 없거나 지원하지 않는 키: 안내를 보이고 계속 기다린다
        case needsModifier
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
    ]

    static func interpret(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Outcome {
        if Int(keyCode) == kVK_Escape { return .cancel }
        if modifierKeyCodes.contains(Int(keyCode)) { return .ignore }
        if let accel = Accelerator.string(keyCode: keyCode, modifierFlags: modifierFlags) { return .accelerator(accel) }
        return .needsModifier
    }
}

/// 클릭하고 키 조합을 누르면 가속키 문자열을 돌려주는 버튼. 녹화 중에는 ⌘ 조합도 시스템 메뉴가 아니라 여기로 온다.
struct ShortcutRecorder: NSViewRepresentable {
    var value: String
    var accent: NSColor
    var onChange: (String) -> Void
    var onHint: (String?) -> Void
    var onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.setAccessibilityLabel("단축키 녹화. 클릭한 뒤 원하는 키 조합을 누르세요")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = value
        button.onChange = onChange
        button.onHint = onHint
        button.onRecordingChange = onRecordingChange
        button.accent = accent
    }

    /// 녹화 중에 뷰가 사라져도(창 닫기, 화면 전환) 전역 단축키가 풀린 채로 남지 않게 한다
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.endRecording()
    }

    final class RecorderButton: NSButton {
        var shortcut = "" { didSet { refreshTitle() } }
        var onChange: (String) -> Void = { _ in }
        var onHint: (String?) -> Void = { _ in }
        /// 녹화 중 테두리 색(설정 창의 포커스 색을 따른다)
        var accent = NSColor(srgbRed: 0.302, green: 0.639, blue: 1.0, alpha: 1)
        /// 녹화 시작/종료를 동기로 알린다. 시작 알림이 키 입력보다 먼저 전역 단축키를 풀어야 하므로 비동기로 미루지 않는다.
        var onRecordingChange: (Bool) -> Void = { _ in }
        private var recording = false {
            didSet {
                refreshTitle()
                updatePulse()
                if recording != oldValue { onRecordingChange(recording) }
            }
        }

        func endRecording() { recording = false }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            controlSize = .large
            target = self
            action = #selector(beginRecording)
            setButtonType(.momentaryPushIn)
            wantsLayer = true
            layer?.cornerRadius = 8
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) 는 쓰지 않는다") }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 30) }

        private func refreshTitle() {
            title = recording ? "키 조합을 누르세요…" : (shortcut.isEmpty ? "(없음)" : Accelerator.display(shortcut))
        }

        /// 녹화 중에는 강조색 테두리가 맥박처럼 숨 쉰다. 동작 줄이기이면 움직임 없이 굵은 테두리만 둔다.
        private func updatePulse() {
            guard let layer else { return }
            let key = "recordingPulse"
            layer.removeAnimation(forKey: key)
            guard recording else {
                layer.borderWidth = 0
                return
            }
            let accent = self.accent
            layer.borderWidth = 2
            layer.borderColor = accent.cgColor
            guard !Motion.reduced else { return }
            let pulse = CABasicAnimation(keyPath: "borderColor")
            pulse.fromValue = accent.withAlphaComponent(0.25).cgColor
            pulse.toValue = accent.cgColor
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: key)
        }

        @objc private func beginRecording() {
            recording = true
            window?.makeFirstResponder(self)
            hint(nil)
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            hint(nil)
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            switch ShortcutRecording.interpret(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
            case .cancel:
                recording = false
                hint(nil)
            case let .accelerator(accel):
                recording = false
                hint(nil)
                let change = onChange
                DispatchQueue.main.async { change(accel) }
            case .ignore:
                break
            case .needsModifier:
                hint("⌘ ⌃ ⌥ ⇧ 중 하나 이상과 함께 누르세요")
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        /// SwiftUI 상태 갱신 중에 호출될 수 있으므로 다음 런루프에서 알린다
        private func hint(_ text: String?) {
            let notify = onHint
            DispatchQueue.main.async { notify(text) }
        }
    }
}
