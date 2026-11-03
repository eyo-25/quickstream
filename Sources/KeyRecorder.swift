import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 키 이벤트 하나를 슬롯 키 녹화 결과로 해석한다(AppKit 과 분리해 단위 테스트한다).
enum KeyRecording {
    enum Outcome: Equatable {
        /// Esc: 녹화 취소
        case cancel
        /// Delete: 지정을 지우고 기본으로 되돌린다
        case clear
        /// 확정된 키(영문자·숫자 한 글자, 소문자)
        case key(String)
        /// 수정키만 눌림: 계속 기다린다
        case ignore
        /// 영문자·숫자가 아니거나 ⌘⌃⌥ 가 함께 눌린 키: 안내를 보이고 계속 기다린다
        case unsupported
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
    ]

    static func interpret(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Outcome {
        let code = Int(keyCode)
        if code == kVK_Escape { return .cancel }
        if code == kVK_Delete || code == kVK_ForwardDelete { return .clear }
        if modifierKeyCodes.contains(code) { return .ignore }
        // 오버레이는 ⌘⌃⌥ 와 함께 눌린 키를 처리하지 않는다(앱 단축키·전역 호출 키와 충돌 방지)
        if !modifierFlags.intersection([.command, .control, .option]).isEmpty { return .unsupported }
        if let key = SlotKey.character(forKeyCode: keyCode) { return .key(key) }
        return .unsupported
    }
}

/// 클릭하고 키 하나(영문자·숫자)를 누르면 그 키를 돌려주는 버튼. Delete 는 기본으로 되돌리고 Esc 는 취소한다.
/// `validate` 가 이유를 돌려주면(다른 곳에서 쓰는 키) 그 안내를 보이고 계속 기다린다.
struct KeyRecorder: NSViewRepresentable {
    /// 버튼에 보일 글자(녹화 중이 아닐 때)
    var display: String
    var accent: NSColor
    var accessibilityLabel: String
    var validate: (String) -> String?
    /// 확정된 키(소문자). nil 이면 기본으로 되돌림.
    var onChange: (String?) -> Void
    var onHint: (String?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton()
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.display = display
        button.accent = accent
        button.validate = validate
        button.onChange = onChange
        button.onHint = onHint
        button.setAccessibilityLabel(accessibilityLabel)
    }

    /// 녹화 중에 뷰가 사라져도(창 닫기, 화면 전환) 녹화 상태가 남지 않게 한다
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.endRecording()
    }

    final class RecorderButton: NSButton {
        var display = "" { didSet { refreshTitle() } }
        var validate: (String) -> String? = { _ in nil }
        var onChange: (String?) -> Void = { _ in }
        var onHint: (String?) -> Void = { _ in }
        /// 녹화 중 테두리 색(설정 창의 포커스 색을 따른다)
        var accent = NSColor(srgbRed: 0.302, green: 0.639, blue: 1.0, alpha: 1)
        private var recording = false {
            didSet {
                refreshTitle()
                updatePulse()
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
        override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 30) }

        private func refreshTitle() {
            title = recording ? "키를 누르세요…" : display
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
            switch KeyRecording.interpret(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
            case .cancel:
                recording = false
                hint(nil)
            case .clear:
                recording = false
                hint(nil)
                let change = onChange
                DispatchQueue.main.async { change(nil) }
            case let .key(key):
                if let reason = validate(key) {
                    hint(reason) // 쓸 수 없는 키: 안내를 보이고 계속 기다린다
                } else {
                    recording = false
                    hint(nil)
                    let change = onChange
                    DispatchQueue.main.async { change(key) }
                }
            case .ignore:
                break
            case .unsupported:
                hint("영문자 또는 숫자 키 하나만 쓸 수 있습니다(⌘ ⌃ ⌥ 와 함께는 안 됩니다)")
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
