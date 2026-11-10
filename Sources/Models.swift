import Foundation

// 설정 파일(settings.json) 모델. 기존 Electron 판(schemaVersion 4)과 JSON 형태가 같아서 그대로 읽고 쓴다.
// 알 수 없는 키는 무시한다(옛 설정의 matchApps 등). 필드가 없으면 기본값으로 채운다.

enum Limits {
    static let slots = 8
    static let maxTabs = 8
    static let maxMacroSteps = 16
    static let schemaVersion = 4
    static let alphaRange: ClosedRange<Double> = 0.4...0.95
    static let radiusRange: ClosedRange<Int> = 24...56
    /// 오버레이 바깥(링) 반지름과 중앙 원 반지름(pt).
    /// 검증은 각 키의 독립 범위만 본다(`centerAbsoluteRange`): 두 값의 조합이 어긋났다는 이유로 설정 파일 전체를 버리면 슬롯·탭이 모두 사라지기 때문이다.
    /// 조각이 너무 얇아지는 조합은 그리는 쪽(`centerRange(ring:)`)과 설정 슬라이더가 보정한다.
    static let ringRange: ClosedRange<Int> = 160...320
    static let centerMin = 40
    static let minWedgeThickness = 72
    static let centerAbsoluteRange: ClosedRange<Int> = centerMin...(ringRange.upperBound - minWedgeThickness)
    static func centerRange(ring: Int) -> ClosedRange<Int> { centerMin...max(centerMin, ring - minWedgeThickness) }
    /// 중앙 원 테두리 굵기(pt). 독립 범위만 검증한다.
    static let centerBorderRange: ClosedRange<Int> = 1...12
    /// 중앙 원 안 이름 글자 크기(pt). 0 은 '자동'(원 크기에 맞춤)이라 이 범위 밖의 특별한 값이다.
    static let centerNameSizeRange: ClosedRange<Int> = 10...32
}

/// 설정 파일의 탭 `type`. 설정 창에서는 더 이상 구분하지 않지만(모든 탭이 같은 '탭'), 예전 버전·Electron 판과 파일을 주고받도록 값은 그대로 읽고 쓴다.
enum TabKind: String, Codable, Equatable {
    case pinnedApps = "pinned-apps"
    case custom

    /// 오버레이 허브 상단 캡션
    var caption: String {
        switch self {
        case .pinnedApps: return "PINNED"
        case .custom: return "CUSTOM"
        }
    }
}

/// 슬롯이 실행하는 동작. JSON 은 `{ "type": "launch_app", ... }` 형태.
indirect enum Action: Codable, Equatable {
    case activateApp(bundleId: String, pid: Int32?)
    case launchApp(bundleId: String?, appPath: String?)
    case openURL(String)
    case clipboardText(String)
    case macroSequence(stopOnError: Bool, steps: [Action])

    private enum Keys: String, CodingKey {
        case type, bundleId, pid, appPath, url, text, stopOnError, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "activate_app":
            self = .activateApp(bundleId: try c.decode(String.self, forKey: .bundleId), pid: try c.decodeIfPresent(Int32.self, forKey: .pid))
        case "launch_app":
            self = .launchApp(bundleId: try c.decodeIfPresent(String.self, forKey: .bundleId), appPath: try c.decodeIfPresent(String.self, forKey: .appPath))
        case "open_url":
            self = .openURL(try c.decode(String.self, forKey: .url))
        case "clipboard_text":
            self = .clipboardText(try c.decode(String.self, forKey: .text))
        case "macro_sequence":
            self = .macroSequence(
                stopOnError: try c.decodeIfPresent(Bool.self, forKey: .stopOnError) ?? true,
                steps: try c.decode([Action].self, forKey: .steps))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "지원하지 않는 액션 종류: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .activateApp(bundleId, pid):
            try c.encode("activate_app", forKey: .type)
            try c.encode(bundleId, forKey: .bundleId)
            try c.encodeIfPresent(pid, forKey: .pid)
        case let .launchApp(bundleId, appPath):
            try c.encode("launch_app", forKey: .type)
            try c.encodeIfPresent(bundleId, forKey: .bundleId)
            try c.encodeIfPresent(appPath, forKey: .appPath)
        case let .openURL(url):
            try c.encode("open_url", forKey: .type)
            try c.encode(url, forKey: .url)
        case let .clipboardText(text):
            try c.encode("clipboard_text", forKey: .type)
            try c.encode(text, forKey: .text)
        case let .macroSequence(stopOnError, steps):
            try c.encode("macro_sequence", forKey: .type)
            try c.encode(stopOnError, forKey: .stopOnError)
            try c.encode(steps, forKey: .steps)
        }
    }

    /// 허브에 표시하는 동사
    var verb: String {
        switch self {
        case .activateApp: return "SWITCH"
        case .launchApp: return "LAUNCH"
        case .openURL: return "OPEN"
        case .clipboardText: return "COPY"
        case .macroSequence: return "RUN"
        }
    }

    /// 실행한 뒤 어떤 앱이 스스로 앞으로 오는가. 아니면(클립보드 복사 등) 호출 측이 이전 앱으로 포커스를 돌려줘야 한다.
    var activatesApp: Bool {
        switch self {
        case .activateApp, .launchApp, .openURL: return true
        case .clipboardText: return false
        case let .macroSequence(_, steps): return steps.contains { $0.activatesApp }
        }
    }
}

struct Slot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// 타일 약어(1~3자). 없으면 이름에서 자동 생성
    var label: String?
    var action: Action
    /// 기본 칸 번호 키(숫자 1~8) 말고 이 슬롯을 하나 더 실행하는 키(영문자·숫자 한 글자, 소문자). 없으면 추가 키 없음. 숫자 1~8 은 쓸 수 없다.
    var key: String?
    /// 이 슬롯을 고르는 방향키 조합. 없으면 링 위치의 방향, `off` 면 방향키로 고르지 않는다.
    var direction: SlotDirection?
}

extension Slot {
    private enum DecodeKeys: String, CodingKey { case id, name, label, action, key, direction }

    /// 키·방향은 손으로 고친 값이 틀려도 파일 전체를 버리지 않는다: 읽을 수 없으면 지정 없음(기본 배정)으로 읽고, 대문자 키는 소문자로 읽는다.
    /// 추가 키가 숫자 1~8 이면(키가 칸 번호 키를 대신하던 이전 빌드가 저장한 값) 지정 없음으로 읽는다: 숫자 1~8 은 늘 칸 번호 키다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            label: try c.decodeIfPresent(String.self, forKey: .label),
            action: try c.decode(Action.self, forKey: .action),
            key: ((try? c.decodeIfPresent(String.self, forKey: .key)) ?? nil).flatMap(SlotKey.normalize).flatMap { SlotKey.isPositionDigit($0) ? nil : $0 },
            direction: (try? c.decodeIfPresent(SlotDirection.self, forKey: .direction)) ?? nil)
    }
}

struct Tab: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var type: TabKind
    /// 슬롯. 배열 인덱스 = 링 위치(12시부터 시계 방향, 0~7)이고 `nil` 은 빈 칸이라 중간이 비어 있어도 된다. 저장할 때 끝의 빈 칸은 뺀다.
    var slots: [Slot?]

    init(id: String, name: String, type: TabKind, slots: [Slot?] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.slots = slots
    }

    private enum Keys: String, CodingKey { case id, name, type, slots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(TabKind.self, forKey: .type)
        slots = try c.decodeIfPresent([Slot?].self, forKey: .slots) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        // 끝의 빈 칸은 저장하지 않는다(`[슬롯, null, null, 슬롯]` 처럼 중간 빈 칸만 `null` 로 남는다)
        try c.encode(Array(slots.reversed().drop { $0 == nil }.reversed()), forKey: .slots)
    }
}

/// 오버레이 모양. `pie` 는 반투명 부채꼴 8조각, `orbit` 는 유리 타일이 고리를 이루고 가운데에 현재 선택 정보만 있는 처음 디자인.
/// 알 수 없는 값이 들어와도 파일 전체를 버리지 않도록 디코드는 `pie` 로 되돌린다.
enum OverlayTheme: String, Codable, CaseIterable, Equatable {
    case pie
    case orbit
}

/// 파이 테마에서 선택된 앱 이름을 어디에 띄울지. 오비트는 항상 가운데 원판에 이름이 있어 이 설정과 무관하다.
/// 알 수 없는 값이 들어와도 파일 전체를 버리지 않도록 디코드는 `top` 으로 되돌린다.
enum OverlayNamePlacement: String, Codable, CaseIterable, Equatable {
    /// 링 위쪽(기본)
    case top
    /// 가운데 원 안
    case center
    /// 표시하지 않음
    case hidden
}

/// 중앙 원 안 이름 글자 굵기. 알 수 없는 값이면 `medium`(파일 전체를 버리지 않는다).
enum NameWeight: String, Codable, CaseIterable, Equatable {
    case light, regular, medium, semibold, bold

    var displayName: String {
        switch self {
        case .light: return "얇게"
        case .regular: return "보통"
        case .medium: return "중간"
        case .semibold: return "굵게"
        case .bold: return "아주 굵게"
        }
    }
}

/// 본체(기본 바탕) 색 테마: 면·글자·테두리·유리 질감만 정한다. **포커스(선택) 색은 포함하지 않는다.**
/// 알 수 없는 값이 들어와도 파일 전체를 버리지 않도록 디코드는 `darkGray` 로 되돌린다.
enum OverlayBody: String, Codable, CaseIterable, Equatable {
    /// 기본: 어두운 회색 면, 흰 글씨 (지금까지의 기본 모양)
    case darkGray = "dark-gray"
    /// 어두운 유리: 더 투명하고 광택 있는 어두운 면
    case darkGlass = "dark-glass"
    /// 클리어 글라스: 바탕화면이 비치는 반투명 유리에 사용자가 고른 틴트 색(`glassTintHex`)을 입힌다. 불투명 바닥판을 쓰지 않는다.
    case clearGlass = "clear-glass"
}

/// 포커스(선택) 표현 방식. flat = 강조색으로 면을 채움, neon = 면은 투명하게 두고 밝은 가장자리와 번짐으로 빛남.
/// 알 수 없는 값이면 기본(`neon`).
enum FocusStyle: String, Codable, CaseIterable, Equatable {
    case flat
    case neon
}

/// 포커스 색 프리셋 한 가지(이름 + 색)
struct FocusPreset: Equatable {
    let id: String
    let label: String
    let hex: String
}

/// 포커스 색: 팔레트(프리셋)를 제공하고, 사용자가 임의의 색(`#RRGGBB`)을 직접 골라 쓸 수도 있다.
enum FocusColors {
    /// 기본 포커스 색(민트 프리셋)
    static let defaultHex = "#19F9D8"

    /// 널리 쓰는 에디터 팔레트(TablePeek 의 테마 목록 참고)의 강조색을 이름 붙여 모았다.
    static let presets: [FocusPreset] = [
        FocusPreset(id: "yellow", label: "노랑", hex: "#FAE32E"),
        FocusPreset(id: "mauve", label: "연보라", hex: "#CBA6F7"),
        FocusPreset(id: "purple", label: "보라", hex: "#BD93F9"),
        FocusPreset(id: "blue", label: "파랑", hex: "#7AA2F7"),
        FocusPreset(id: "cyan", label: "청록", hex: "#88C0D0"),
        FocusPreset(id: "rose", label: "장미", hex: "#EBBCBA"),
        FocusPreset(id: "sage", label: "세이지", hex: "#83A598"),
        FocusPreset(id: "azure", label: "하늘", hex: "#268BD2"),
        FocusPreset(id: "violet", label: "라벤더", hex: "#A277FF"),
        FocusPreset(id: "pink", label: "핑크", hex: "#FF7EDB"),
        FocusPreset(id: "mint", label: "민트", hex: "#19F9D8"),
        FocusPreset(id: "gold", label: "골드", hex: "#FAD000"),
        FocusPreset(id: "coral", label: "코랄", hex: "#E95378"),
        FocusPreset(id: "white", label: "하양", hex: "#FFFFFF"),
    ]

    /// `#RRGGBB` / `RRGGBB` / `#RGB`(대소문자 무시)를 `#RRGGBB` 대문자로 정규화한다. 해석할 수 없으면 nil.
    static func normalized(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 else { return nil }
        return "#" + s.uppercased()
    }

    /// 정규화된 `#RRGGBB` 를 0…1 의 (r, g, b) 로. 해석할 수 없으면 nil.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let n = normalized(hex), let value = UInt32(n.dropFirst(), radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// 글라스 틴트 색 프리셋 한 가지(이름 + 색)
struct GlassTintPreset: Equatable {
    let id: String
    let label: String
    let hex: String
}

/// 클리어 글라스 본체에 입히는 틴트 색: 프리셋과 임의 `#RRGGBB`. 정규화·해석은 `FocusColors` 와 같은 규칙을 쓴다.
enum GlassTints {
    /// 기본 틴트(맑은 하늘색)
    static let defaultHex = "#6FB1FF"

    static let presets: [GlassTintPreset] = [
        GlassTintPreset(id: "sky", label: "하늘", hex: "#6FB1FF"),
        GlassTintPreset(id: "pink", label: "분홍", hex: "#FF8FC7"),
        GlassTintPreset(id: "mint", label: "민트", hex: "#5FE3C0"),
        GlassTintPreset(id: "violet", label: "보라", hex: "#B28CFF"),
        GlassTintPreset(id: "amber", label: "호박", hex: "#FFC266"),
        GlassTintPreset(id: "coral", label: "코랄", hex: "#FF8A80"),
        GlassTintPreset(id: "lime", label: "라임", hex: "#B8F26B"),
        GlassTintPreset(id: "clear", label: "투명", hex: "#E8EEF5"),
    ]

    static func normalized(_ text: String) -> String? { FocusColors.normalized(text) }
}

/// 한 테마가 따로 가지는 크기 값(pt). 파이와 오비트는 서로 연동되지 않고 각자 값을 가진다.
struct ThemeSizes: Codable, Equatable {
    /// 링 바깥 반지름
    var ring: Int
    /// 중앙 원 반지름
    var center: Int
    /// 중앙 원 테두리 굵기
    var border: Int
}

extension OverlayTheme {
    /// 이 테마의 기본 크기(처음 값, 초기화 값)
    var defaultSizes: ThemeSizes {
        switch self {
        case .pie: return ThemeSizes(ring: 250, center: 112, border: 4)
        case .orbit: return ThemeSizes(ring: 258, center: 78, border: 4)
        }
    }
}

struct OverlaySettings: Codable, Equatable {
    /// 패널 배경 투명도(알파). 글자·아이콘은 흐려지지 않는다. 기본은 허용 범위의 하한.
    var alpha: Double = 0.4
    var radius: Int = 28
    var slotCount: Int = Limits.slots
    var showIcons: Bool = true
    /// 오버레이 테마(모양). 기본은 오비트.
    var theme: OverlayTheme = .orbit
    /// 파이 테마의 크기
    var pieSizes: ThemeSizes = OverlayTheme.pie.defaultSizes
    /// 오비트 테마의 크기. 파이와 연동되지 않는다.
    var orbitSizes: ThemeSizes = OverlayTheme.orbit.defaultSizes
    /// 본체 색 테마(다크 그레이 / 다크 글라스 / 클리어 글라스). 포커스 색을 포함하지 않는다. 기본은 다크 글라스.
    var bodyTheme: OverlayBody = .darkGlass
    /// 포커스 표현 방식(플랫 / 네온). 기본은 네온.
    var focusStyle: FocusStyle = .neon
    /// 포커스 색 `#RRGGBB`(프리셋이든 사용자 지정이든 같다)
    var focusHex: String = FocusColors.defaultHex
    /// 파이 테마의 선택된 앱 이름 표시 위치(위 / 가운데 원 / 숨김). 기본은 가운데 원.
    var namePlacement: OverlayNamePlacement = .center
    /// 조각의 1~8 숫자(오비트는 번호 배지) 표시 여부. 숫자 키 단축키 자체는 이 설정과 무관하게 동작한다.
    var showNumbers: Bool = true
    /// 오비트 타일 아래의 앱 이름 라벨 표시 여부(항상 타일 아래에 나온다)
    var showTileLabels: Bool = true
    /// 앱 박스(조각·타일)와 중앙 원 **뒤에 불투명한 바닥판**을 깔지 여부. 켜면 바탕화면이 비치지 않고, `alpha` 는 그 위에 얹히는 면 색의 농도만 조절한다.
    var solidBacking: Bool = true
    /// 중앙 원 안 이름(오비트 중앙, 파이 `center`)의 글자 굵기
    var centerNameWeight: NameWeight = .regular
    /// 중앙 원 안 이름의 글자 크기(pt). 0 이면 자동(원 크기에 맞춤), 아니면 `Limits.centerNameSizeRange` 안.
    var centerNameSize: Int = 0
    /// 클리어 글라스 본체의 틴트 색 `#RRGGBB`(다른 본체에서는 쓰이지 않지만 저장은 해 둔다)
    var glassTintHex: String = GlassTints.defaultHex
    /// 포커스 색의 불빛(번짐·글로우·중앙 원 빛·포커스 변경 반짝임) 표시 여부. 끄면 면 틴트와 가는 테두리선만 남는다.
    var focusGlow: Bool = true

    init() {}

    /// 현재 테마의 크기. 편집·렌더링은 이것(또는 아래 `ringSize` 등)을 읽고 쓴다.
    var sizes: ThemeSizes {
        get { theme == .pie ? pieSizes : orbitSizes }
        set { if theme == .pie { pieSizes = newValue } else { orbitSizes = newValue } }
    }
    /// 현재 테마의 링 바깥 반지름(pt)
    var ringSize: Int {
        get { sizes.ring }
        set { sizes.ring = newValue }
    }
    /// 현재 테마의 중앙 원 반지름(pt)
    var centerSize: Int {
        get { sizes.center }
        set { sizes.center = newValue }
    }
    /// 현재 테마의 중앙 원 테두리 굵기(pt)
    var centerBorder: Int {
        get { sizes.border }
        set { sizes.border = newValue }
    }

    private enum Keys: String, CodingKey {
        case alpha, radius, slotCount, showIcons, theme, pieSizes, orbitSizes, bodyTheme, focusStyle, focusHex
        case namePlacement, showNumbers, showTileLabels, solidBacking, centerNameWeight, centerNameSize, glassTintHex, focusGlow
        /// 크기가 테마별로 갈라지기 전의 키. 읽기만 한다(현재 테마의 크기로 가져온다).
        case ringSize, centerSize, centerBorder
    }

    init(from decoder: Decoder) throws {
        // 기본값은 선언부 한 곳에서만 정한다: 먼저 기본값으로 채운 뒤, 읽을 수 있는 키만 덮어쓴다(누락·잘못된 값 = 기본값).
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        if let v = try c.decodeIfPresent(Double.self, forKey: .alpha) { alpha = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .radius) { radius = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .slotCount) { slotCount = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .showIcons) { showIcons = v }
        let decodedTheme = (try? c.decodeIfPresent(OverlayTheme.self, forKey: .theme)) ?? nil
        if let decodedTheme { theme = decodedTheme }

        // 크기: 새 키(테마별)를 우선하고, 없으면 예전 단일 키를 '지금 테마'의 크기로 가져온다. 다른 테마는 기본값.
        // (`theme` 키가 없을 때의 기본 테마(오비트)와, 아래 레거시 이관 대상 테마(파이)는 별개다.)
        let storedPie = (try? c.decodeIfPresent(ThemeSizes.self, forKey: .pieSizes)) ?? nil
        let storedOrbit = (try? c.decodeIfPresent(ThemeSizes.self, forKey: .orbitSizes)) ?? nil
        if let storedPie { pieSizes = storedPie }
        if let storedOrbit { orbitSizes = storedOrbit }
        // 예전 키도 타입 오류 하나로 파일 전체가 버려지지 않게 레니언트하게 읽는다(잘못된 값은 없는 것으로 취급).
        let legacyRing = (try? c.decodeIfPresent(Int.self, forKey: .ringSize)) ?? nil
        let legacyCenter = (try? c.decodeIfPresent(Int.self, forKey: .centerSize)) ?? nil
        let legacyBorder = (try? c.decodeIfPresent(Int.self, forKey: .centerBorder)) ?? nil
        // `theme` 키가 **없던** 시절(단일 크기 키 시대)의 설정은 파이였다. 그때의 크기는 파이 것으로 가져온다.
        // 키는 있는데 값을 읽을 수 없으면(오타·null) 위에서 정한 기본 테마가 그대로 현재 테마이므로 그 테마의 크기로 가져온다.
        let legacyTheme = c.contains(.theme) ? theme : .pie
        if legacyRing != nil || legacyCenter != nil || legacyBorder != nil, (legacyTheme == .pie ? storedPie : storedOrbit) == nil {
            var legacy = legacyTheme.defaultSizes
            if let legacyRing { legacy.ring = legacyRing }
            if let legacyCenter { legacy.center = legacyCenter }
            if let legacyBorder { legacy.border = legacyBorder }
            if legacyTheme == .pie { pieSizes = legacy } else { orbitSizes = legacy }
        }

        if let v = (try? c.decodeIfPresent(OverlayBody.self, forKey: .bodyTheme)) ?? nil { bodyTheme = v }
        if let v = (try? c.decodeIfPresent(FocusStyle.self, forKey: .focusStyle)) ?? nil { focusStyle = v }
        // 해석할 수 없는 색은 기본 색으로 둔다. 파일 전체를 버리지 않는다.
        if let v = ((try? c.decodeIfPresent(String.self, forKey: .focusHex)) ?? nil).flatMap(FocusColors.normalized) { focusHex = v }
        if let v = (try? c.decodeIfPresent(OverlayNamePlacement.self, forKey: .namePlacement)) ?? nil { namePlacement = v }
        if let v = (try? c.decodeIfPresent(Bool.self, forKey: .showNumbers)) ?? nil { showNumbers = v }
        if let v = (try? c.decodeIfPresent(Bool.self, forKey: .showTileLabels)) ?? nil { showTileLabels = v }
        if let v = (try? c.decodeIfPresent(Bool.self, forKey: .solidBacking)) ?? nil { solidBacking = v }
        if let v = (try? c.decodeIfPresent(NameWeight.self, forKey: .centerNameWeight)) ?? nil { centerNameWeight = v }
        // 손으로 고친 값이 범위를 벗어나도 파일 전체를 버리지 않고 범위 안으로 되돌린다(0 은 자동).
        if let raw = (try? c.decodeIfPresent(Int.self, forKey: .centerNameSize)) ?? nil {
            centerNameSize = raw <= 0 ? 0 : min(max(raw, Limits.centerNameSizeRange.lowerBound), Limits.centerNameSizeRange.upperBound)
        }
        // 해석할 수 없는 틴트 색은 기본 틴트로 둔다. 파일 전체를 버리지 않는다.
        if let v = ((try? c.decodeIfPresent(String.self, forKey: .glassTintHex)) ?? nil).flatMap(GlassTints.normalized) { glassTintHex = v }
        if let v = (try? c.decodeIfPresent(Bool.self, forKey: .focusGlow)) ?? nil { focusGlow = v }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(alpha, forKey: .alpha)
        try c.encode(radius, forKey: .radius)
        try c.encode(slotCount, forKey: .slotCount)
        try c.encode(showIcons, forKey: .showIcons)
        try c.encode(theme, forKey: .theme)
        try c.encode(pieSizes, forKey: .pieSizes)
        try c.encode(orbitSizes, forKey: .orbitSizes)
        try c.encode(bodyTheme, forKey: .bodyTheme)
        try c.encode(focusStyle, forKey: .focusStyle)
        try c.encode(focusHex, forKey: .focusHex)
        try c.encode(namePlacement, forKey: .namePlacement)
        try c.encode(showNumbers, forKey: .showNumbers)
        try c.encode(showTileLabels, forKey: .showTileLabels)
        try c.encode(solidBacking, forKey: .solidBacking)
        try c.encode(centerNameWeight, forKey: .centerNameWeight)
        try c.encode(centerNameSize, forKey: .centerNameSize)
        try c.encode(glassTintHex, forKey: .glassTintHex)
        try c.encode(focusGlow, forKey: .focusGlow)
    }
}

struct Settings: Codable, Equatable {
    var schemaVersion: Int = Limits.schemaVersion
    var platform: String = "darwin"
    /// Electron 가속키 문자열("Alt+Q", "Command+Shift+Space"). Accelerator 가 해석한다.
    var shortcut: String = "Alt+Q"
    var launchAtLogin: Bool = false
    /// 오버레이를 닫는 키(영문자·숫자 한 글자, 소문자). Esc 는 늘 닫는다. 기본 Q.
    var closeKey: String = "q"
    var overlay = OverlaySettings()
    var tabs: [Tab] = []

    init() {}

    private enum Keys: String, CodingKey { case schemaVersion, platform, shortcut, launchAtLogin, closeKey, overlay, tabs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Limits.schemaVersion
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "darwin"
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut) ?? "Alt+Q"
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        // 닫기 키도 손으로 고친 값이 틀려도 파일 전체를 버리지 않는다: 읽을 수 없으면 기본 Q, 대문자는 소문자로 읽는다
        closeKey = ((try? c.decodeIfPresent(String.self, forKey: .closeKey)) ?? nil).flatMap(SlotKey.normalize) ?? "q"
        overlay = try c.decodeIfPresent(OverlaySettings.self, forKey: .overlay) ?? OverlaySettings()
        // 예전 버전이 만든 `recent-apps` 탭은 없어졌으므로 읽을 때 버린다. 그것만 있던 파일은 기본 탭으로 되돌려 탭이 항상 하나 이상 있게 한다.
        let stored = try c.decode([StoredTab].self, forKey: .tabs)
        let kept = stored.compactMap(\.tab)
        tabs = kept.isEmpty && !stored.isEmpty ? Settings.defaults.tabs : kept
        // 닫기 키가 슬롯이 있는 칸의 번호 키(숫자 1~8)와 같으면(그 칸이 번호 키를 대신하던 이전 빌드가 저장한 값) 기본 Q 로 읽는다. 안 그러면 검증에 걸려 파일 전체가 기본값으로 바뀐다.
        // 그때 Q 를 추가 키로 쓰던 슬롯이 있으면(닫기 키가 Q 가 아니라서 합법이던 값) 그 추가 키는 지정 없음으로 읽는다.
        if let position = (0..<Limits.slots).first(where: { SlotKey.defaultKey(position: $0) == closeKey }),
           tabs.contains(where: { $0.slots.indices.contains(position) && $0.slots[position] != nil }) {
            closeKey = "q"
            for t in tabs.indices {
                for p in tabs[t].slots.indices where tabs[t].slots[p]?.key == "q" { tabs[t].slots[p]?.key = nil }
            }
        }
    }

    /// 첫 실행 기본값: 비어 있는 탭 하나. 탭은 항상 하나 이상 있어야 한다.
    static var defaults: Settings {
        var s = Settings()
        s.tabs = [Tab(id: "pinned", name: "탭 1", type: .pinnedApps, slots: [])]
        return s
    }
}

/// 저장 파일의 탭 한 칸. 없어진 `recent-apps` 종류는 nil 로 읽고, 그 밖의 오류는 그대로 던져 파일 전체를 실패시킨다.
private struct StoredTab: Decodable {
    let tab: Tab?

    private enum Keys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .type)
        tab = kind == "recent-apps" ? nil : try Tab(from: decoder)
    }
}
