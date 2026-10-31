import AppKit
import Carbon.HIToolbox

/// Electron 가속키 문자열("Alt+Q", "Command+Shift+Space") ↔ 키코드/수정키. 설정 파일 호환을 위해 문자열 형식을 유지한다.
/// 설정 창의 단축키 녹화(이벤트 → 문자열)와 전역 단축키 등록(문자열 → Carbon)이 같은 표를 쓴다.
enum Accelerator {
    struct Parsed: Equatable {
        var keyCode: UInt32
        /// Carbon 수정키 마스크(cmdKey/shiftKey/optionKey/controlKey)
        var carbonModifiers: UInt32
    }

    /// 물리 키 이름 ↔ 가상 키코드. 한글 입력 상태에서도 같도록 문자가 아니라 키코드로 판단한다.
    private static let keyTable: [(name: String, code: Int)] = {
        var t: [(String, Int)] = [
            ("A", kVK_ANSI_A), ("B", kVK_ANSI_B), ("C", kVK_ANSI_C), ("D", kVK_ANSI_D), ("E", kVK_ANSI_E), ("F", kVK_ANSI_F),
            ("G", kVK_ANSI_G), ("H", kVK_ANSI_H), ("I", kVK_ANSI_I), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K), ("L", kVK_ANSI_L),
            ("M", kVK_ANSI_M), ("N", kVK_ANSI_N), ("O", kVK_ANSI_O), ("P", kVK_ANSI_P), ("Q", kVK_ANSI_Q), ("R", kVK_ANSI_R),
            ("S", kVK_ANSI_S), ("T", kVK_ANSI_T), ("U", kVK_ANSI_U), ("V", kVK_ANSI_V), ("W", kVK_ANSI_W), ("X", kVK_ANSI_X),
            ("Y", kVK_ANSI_Y), ("Z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            ("Space", kVK_Space), ("Enter", kVK_Return), ("Tab", kVK_Tab), ("Backspace", kVK_Delete), ("Delete", kVK_ForwardDelete),
            ("Up", kVK_UpArrow), ("Down", kVK_DownArrow), ("Left", kVK_LeftArrow), ("Right", kVK_RightArrow),
            ("Home", kVK_Home), ("End", kVK_End), ("PageUp", kVK_PageUp), ("PageDown", kVK_PageDown),
            // Mac 키보드의 Help 키(0x72)가 Insert 자리다. Electron 녹화기가 만드는 이름이라 받아 준다.
            ("Insert", kVK_Help),
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket), ("]", kVK_ANSI_RightBracket),
            (";", kVK_ANSI_Semicolon), ("'", kVK_ANSI_Quote), (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash), ("\\", kVK_ANSI_Backslash), ("`", kVK_ANSI_Grave),
            ("num0", kVK_ANSI_Keypad0), ("num1", kVK_ANSI_Keypad1), ("num2", kVK_ANSI_Keypad2), ("num3", kVK_ANSI_Keypad3),
            ("num4", kVK_ANSI_Keypad4), ("num5", kVK_ANSI_Keypad5), ("num6", kVK_ANSI_Keypad6), ("num7", kVK_ANSI_Keypad7),
            ("num8", kVK_ANSI_Keypad8), ("num9", kVK_ANSI_Keypad9),
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fKeys.enumerated() { t.append(("F\(i + 1)", code)) }
        return t.map { (name: $0.0, code: $0.1) }
    }()

    private static let codeByName: [String: Int] = Dictionary(uniqueKeysWithValues: keyTable.map { ($0.name.lowercased(), $0.code) })
    private static let nameByCode: [Int: String] = Dictionary(uniqueKeysWithValues: keyTable.map { ($0.code, $0.name) })

    /// Electron 이 허용하지만 Carbon 가상 키코드가 없어 macOS 에서 등록할 수 없는 키(F21~F24).
    /// 설정 파일에 있어도 파일 전체를 버리지 않고(검증 통과), 등록 단계에서 경고로 처리한다.
    private static let unregistrableKeys: Set<String> = ["f21", "f22", "f23", "f24"]

    private static let modifierNames: [String: UInt32] = [
        "command": UInt32(cmdKey), "cmd": UInt32(cmdKey), "super": UInt32(cmdKey),
        // macOS 에서 CommandOrControl/CmdOrCtrl 은 ⌘, Meta 도 ⌘ 이다
        "commandorcontrol": UInt32(cmdKey), "cmdorctrl": UInt32(cmdKey), "meta": UInt32(cmdKey),
        "control": UInt32(controlKey), "ctrl": UInt32(controlKey),
        "alt": UInt32(optionKey), "option": UInt32(optionKey),
        "shift": UInt32(shiftKey),
    ]

    private struct Scanned {
        var modifiers: UInt32
        /// 정규 표기의 키 이름
        var keyName: String
        /// Carbon 키코드. F21~F24 처럼 이름만 알려진 키는 nil
        var keyCode: Int?
    }

    /// 문자열을 수정키 + 키 하나로 나눈다. 알 수 없는 이름·키 중복·빈 조각·키 없음·수정키 없음이면 nil.
    private static func scan(_ accelerator: String) -> Scanned? {
        var modifiers: UInt32 = 0
        var key: (name: String, code: Int?)?
        for rawPart in accelerator.split(separator: "+", omittingEmptySubsequences: false) {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            let lower = part.lowercased()
            if part.isEmpty {
                // "Command++" 처럼 + 키 자체는 지원하지 않는다
                return nil
            }
            if let m = modifierNames[lower] {
                modifiers |= m
            } else if key == nil, let code = codeByName[lower] {
                key = (nameByCode[code] ?? part, code)
            } else if key == nil, unregistrableKeys.contains(lower) {
                key = (part.uppercased(), nil)
            } else {
                return nil
            }
        }
        guard let key, modifiers != 0 else { return nil }
        return Scanned(modifiers: modifiers, keyName: key.name, keyCode: key.code)
    }

    /// 형식이 올바른가(등록 가능 여부와 별개). Electron 이 만든 설정 파일을 통째로 거부하지 않으려고 검증은 이쪽을 쓴다.
    static func isWellFormed(_ accelerator: String) -> Bool { scan(accelerator) != nil }

    /// 가속키 문자열을 해석한다. 키가 없거나 알 수 없는 이름/수정키가 있으면 nil. 수정키가 하나도 없어도 nil(전역 단축키가 일반 입력을 가로채지 않게).
    /// Carbon 키코드가 없는 키(F21~F24)도 nil — 등록할 수 없기 때문이다.
    static func parse(_ accelerator: String) -> Parsed? {
        guard let s = scan(accelerator), let code = s.keyCode else { return nil }
        return Parsed(keyCode: UInt32(code), carbonModifiers: s.modifiers)
    }

    /// 키 입력 → 가속키 문자열. 수정키가 없거나 지원하지 않는 키(수정키만 누름 포함)면 nil.
    /// 출력 순서는 Command, Control, Alt, Shift (기존 설정 파일과 같다).
    static func string(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> String? {
        guard let key = nameByCode[Int(keyCode)] else { return nil }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("Command") }
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        guard !parts.isEmpty else { return nil }
        return (parts + [key]).joined(separator: "+")
    }

    /// 화면 표시용: ⌃⌥⇧⌘ 기호 + 키. 해석할 수 없으면 원문을 그대로 돌려준다.
    static func display(_ accelerator: String) -> String {
        guard let s = scan(accelerator) else { return accelerator }
        let key = s.keyName
        var out = ""
        if s.modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if s.modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if s.modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if s.modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        let shown: String
        switch key {
        case "Space": shown = "Space"
        case "Enter": shown = "↩"
        case "Tab": shown = "⇥"
        case "Backspace": shown = "⌫"
        case "Delete": shown = "⌦"
        case "Up": shown = "↑"
        case "Down": shown = "↓"
        case "Left": shown = "←"
        case "Right": shown = "→"
        default: shown = key
        }
        return out + shown
    }
}
