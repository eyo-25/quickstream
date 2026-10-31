import SwiftUI

/// 0…1 sRGB 색 한 점. 설정 창 색 도출과 대비 계산을 UI 없이 검사할 수 있게 값 타입으로 둔다.
struct SettingsRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// `#RRGGBB` → SettingsRGB. 해석할 수 없으면 nil.
    init?(hex: String) {
        guard let c = FocusColors.rgb(hex) else { return nil }
        self.init(c.r, c.g, c.b)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    /// 흰색 쪽으로 t(0…1)만큼 섞는다
    func lightened(_ t: Double) -> SettingsRGB {
        SettingsRGB(r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t)
    }

    /// `other` 쪽으로 t(0…1)만큼 섞는다
    func mixed(with other: SettingsRGB, _ t: Double) -> SettingsRGB {
        SettingsRGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    /// 휘도가 `target` 이 되도록 색상은 두고 명도만 맞춘다: 더 밝으면 검정 쪽으로, 더 어두우면 흰색 쪽으로 1% 단위로 섞는다.
    /// 아주 어두운 틴트(`#000080` 등)도 면 사이 단차가 생기게 하려고 양방향으로 맞춘다.
    func scaled(toLuminance target: Double) -> SettingsRGB {
        let target = min(max(target, 0), 1)
        let up = ContrastMath.luminance(self) < target
        for step in 0...100 {
            let c = up ? lightened(Double(step) / 100) : mixed(with: .black, Double(step) / 100)
            if up ? ContrastMath.luminance(c) >= target : ContrastMath.luminance(c) <= target { return c }
        }
        return up ? .white : .black
    }

    static let white = SettingsRGB(1, 1, 1)
    static let black = SettingsRGB(0, 0, 0)
}

/// WCAG 2.x 대비 계산(순수 함수). 임의의 포커스 색에서도 설정 창 글자가 읽히게 하는 근거다.
enum ContrastMath {
    /// 글자 대비 기준(WCAG AA 일반 텍스트)
    static let minimumText = 4.5

    static func luminance(_ c: SettingsRGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    static func ratio(_ a: SettingsRGB, _ b: SettingsRGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 강조색 면 위에 올릴 글자색: 흰색/검정 중 대비가 높은 쪽(어느 면이든 4.5 이상이 보장된다).
    static func onAccent(_ accent: SettingsRGB) -> SettingsRGB {
        ratio(accent, .white) >= ratio(accent, .black) ? .white : .black
    }

    /// 주 버튼 호버 때 면에 얹는 색의 비율
    static let hoverMix = 0.08

    /// 강조색 면 호버 때 얹는 층의 색: 글자색 반대 방향(흰 글자면 검정, 검정 글자면 흰색).
    /// 글자와 같은 방향으로 섞으면 중간 명도에서 대비가 4.5 아래로 내려간다. 뷰와 테스트가 같은 함수를 읽는다.
    static func hoverTint(_ accent: SettingsRGB) -> SettingsRGB {
        onAccent(accent) == .white ? .black : .white
    }

    /// 강조색 면 호버 때의 면 색(`hoverTint` 를 `hoverMix` 만큼 섞은 것)
    static func hoverFace(_ accent: SettingsRGB) -> SettingsRGB {
        accent.mixed(with: hoverTint(accent), hoverMix)
    }

    /// 강조색을 글자·선·아이콘 자체에 쓸 때의 색: `surface` 위 대비가 `minimum` 미만이면 흰색 쪽으로 밝혀 맞춘다.
    /// 본체 면은 모두 어두워서 밝히는 방향만 있으면 충분하다(흰색은 어떤 어두운 면에서도 기준을 넘는다).
    static func legible(_ accent: SettingsRGB, on surface: SettingsRGB, minimum: Double = minimumText) -> SettingsRGB {
        var t = 0.0
        var color = accent
        while ratio(color, surface) < minimum && t < 1 {
            t = min(1, t + 0.04)
            color = accent.lightened(t)
        }
        return color
    }

    /// 네온 면 틴트 비율(강조색을 면 위에 얹는 양)
    static let neonMix = 0.14

    /// 네온 면: `surface` 위에 강조색을 `neonMix` 만큼 얹은 색
    static func neonFace(_ accent: SettingsRGB, over surface: SettingsRGB) -> SettingsRGB {
        surface.mixed(with: accent, neonMix)
    }

    /// 네온 면 위 글자색: 강조색을 흰색 쪽으로 25% 섞은 색을, 면 `surface`(+틴트) 위 대비 4.5 이상이 되도록 밝힌다.
    /// 가장 밝은 면(입력칸)을 기준으로 해서 더 어두운 면(카드·사이드바) 위에서도 만족한다.
    static func neonText(_ accent: SettingsRGB, over surface: SettingsRGB) -> SettingsRGB {
        legible(accent.lightened(0.25), on: neonFace(accent, over: surface))
    }

    /// 클리어 글라스 설정 창의 면·글자: 틴트의 색상을 어두운 면으로 눌러 만들고(배경 < 사이드바 < 카드), 글자는 틴트를 흰색 쪽으로 크게 밝힌 색.
    /// 면 휘도를 고정 상한으로 눌러서 틴트가 아무리 밝아도(투명 `#E8EEF5`, 라임) 글자 대비가 틴트와 무관하게 확보된다. 뷰와 테스트가 같은 함수를 읽는다.
    static func clearGlassSurfaces(tint: SettingsRGB) -> (background: SettingsRGB, sidebar: SettingsRGB, card: SettingsRGB, text: SettingsRGB, muted: SettingsRGB, line: Double) {
        (tint.scaled(toLuminance: 0.006), tint.scaled(toLuminance: 0.013), tint.scaled(toLuminance: 0.032),
         tint.lightened(0.90), tint.lightened(0.78), 0.14)
    }
}

/// 설정 창 색: 본체 색(`OverlayBody`)이 면·글자를, 포커스 색(`focusHex`)이 선택·강조를 정한다. 값은 모두 `make` 한 곳에서 도출한다.
struct SettingsPalette: Equatable {
    struct Swatches: Equatable {
        var background: SettingsRGB
        var sidebar: SettingsRGB
        var card: SettingsRGB
        /// 카드 안의 입력칸·세그먼트 트랙·꺼진 토글 트랙(카드보다 한 단계 밝은 면)
        var field: SettingsRGB
        /// 사이드바 선택 알약 면(사이드바 위에 강조색을 옅게 얹은 색). 위 글자는 `text`
        var selection: SettingsRGB
        /// 사이드바 선택 알약 위 글자색(플랫 = 본문 글자색, 네온 = 강조색 밝은 색)
        var selectionText: SettingsRGB
        var text: SettingsRGB
        var muted: SettingsRGB
        /// 강조색 그대로(면을 채울 때)
        var accent: SettingsRGB
        /// 강조색을 글자·선·아이콘에 쓸 때: 카드 면 위 대비 4.5 이상으로 보정한 색
        var accentText: SettingsRGB
        /// 강조색 면 위의 글자색(흰색/검정 중 대비가 높은 쪽)
        var onAccent: SettingsRGB
        /// 네온 강조 면(필드 면 위에 강조색을 옅게 얹은 색)
        var neonFace: SettingsRGB
        /// 네온 면 위의 글자색(강조색을 흰색 쪽으로 25% 섞고 대비 4.5 이상으로 보정)
        var neonText: SettingsRGB
    }

    let style: FocusStyle
    let swatches: Swatches
    /// 구분선·테두리(본체마다 투명도가 다르다)
    let line: Color

    var background: Color { swatches.background.color }
    var sidebar: Color { swatches.sidebar.color }
    var card: Color { swatches.card.color }
    var field: Color { swatches.field.color }
    var selection: Color { swatches.selection.color }
    var selectionText: Color { swatches.selectionText.color }
    var text: Color { swatches.text.color }
    var muted: Color { swatches.muted.color }
    var accent: Color { swatches.accent.color }
    var accentText: Color { swatches.accentText.color }
    var onAccent: Color { swatches.onAccent.color }
    var isNeon: Bool { style == .neon }
    /// 강조 알약·세그먼트·토글 켜짐의 면: 플랫은 솔리드 강조색, 네온은 옅은 틴트
    var accentFace: Color { isNeon ? swatches.neonFace.color : swatches.accent.color }
    /// 위 강조 면 위의 글자색(플랫 = 흰/검정 중 대비 높은 쪽, 네온 = 강조색의 밝은 색)
    var onAccentFace: Color { isNeon ? swatches.neonText.color : swatches.onAccent.color }
    /// 네온 강조선·글로우에 쓰는 색(헤어라인과 같은, 면 위에서 읽히게 보정된 강조색)
    var glowColor: Color { swatches.accentText.color }
    /// 번짐(그림자·블러)을 그릴지: 포커스 불빛 토글. 꺼도 `style` 은 그대로라 면 틴트·헤어라인·글자색 같은 네온의 선택 구분은 남는다.
    let glow: Bool
    /// 번짐 그림자 색: 네온이고 불빛이 켜져 있을 때만 `opacity` 로 보이고, 아니면 투명(켬 렌더는 예전과 같은 그림자 값)
    func halo(_ opacity: Double) -> Color { isNeon && glow ? glowColor.opacity(opacity) : .clear }

    static func make(body: OverlayBody, focusHex: String, style: FocusStyle, glassTint: String = GlassTints.defaultHex, glow: Bool = true) -> SettingsPalette {
        let accent = SettingsRGB(hex: focusHex) ?? SettingsRGB(hex: FocusColors.defaultHex) ?? .white
        let surfaces: (background: SettingsRGB, sidebar: SettingsRGB, card: SettingsRGB, text: SettingsRGB, muted: SettingsRGB, line: Double)
        switch body {
        case .darkGray:
            // 중립 회색: 파랑·보라 기운이 없는 면. 페이지 배경은 한 단계 어둡게, 카드는 한 단계 밝게(카드 대비를 높인다)
            surfaces = (SettingsRGB(0.070, 0.070, 0.074), SettingsRGB(0.105, 0.105, 0.109), SettingsRGB(0.180, 0.180, 0.186),
                        SettingsRGB(0.949, 0.949, 0.953), SettingsRGB(0.730, 0.730, 0.750), 0.09)
        case .darkGlass:
            // 검정에 가까운 면에 약간 푸른빛(유리처럼 차갑게), 경계선은 더 또렷하게
            surfaces = (SettingsRGB(0.016, 0.022, 0.040), SettingsRGB(0.040, 0.054, 0.092), SettingsRGB(0.088, 0.108, 0.168),
                        SettingsRGB(0.929, 0.949, 1.0), SettingsRGB(0.690, 0.740, 0.830), 0.12)
        case .clearGlass:
            let tint = GlassTints.normalized(glassTint).flatMap { SettingsRGB(hex: $0) } ?? SettingsRGB(hex: GlassTints.defaultHex) ?? .white
            surfaces = ContrastMath.clearGlassSurfaces(tint: tint)
        }
        let field = surfaces.card.lightened(0.10)
        // 카드보다 밝은 입력칸 면 위에서도 읽히도록 field 기준으로 보정한다(카드는 더 어두워 자동으로 만족)
        let accentText = ContrastMath.legible(accent, on: field)
        let neon = style == .neon
        // 네온: 면은 옅은 강조색 틴트(어두운 면 위), 글자는 강조색을 25% 흰색 쪽으로 섞은 밝은 색을 그 면 위 대비 4.5 이상으로 보정
        let neonFace = ContrastMath.neonFace(accent, over: field)
        let neonText = ContrastMath.neonText(accent, over: field)
        let swatches = Swatches(
            background: surfaces.background, sidebar: surfaces.sidebar, card: surfaces.card,
            field: field,
            selection: neon ? ContrastMath.neonFace(accent, over: surfaces.sidebar) : surfaces.sidebar.mixed(with: accentText, 0.24),
            selectionText: neon ? neonText : surfaces.text,
            text: surfaces.text, muted: surfaces.muted,
            accent: accent,
            accentText: accentText,
            onAccent: ContrastMath.onAccent(accent),
            neonFace: neonFace,
            neonText: neonText)
        return SettingsPalette(style: style, swatches: swatches, line: Color.white.opacity(surfaces.line), glow: glow)
    }
}

/// 의미가 고정된 경고색(본체·포커스 색과 무관하게 어두운 면 위에서 모두 읽힌다). 미리보기의 오류 점도 쓴다.
enum SettingsTheme {
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let warn = Color(red: 1.0, green: 0.706, blue: 0.329)
}

// 뷰는 `@Environment(\.settingsPalette)` 로 읽는다. 값이 바뀌면 SwiftUI 가 그 환경을 읽는 뷰만 다시 그린다.
// 모델의 정적 접근과 달리 관찰 대상이 아닌 하위 뷰(슬롯 편집기 등)도 모델 구독 없이 갱신되기 때문에 환경 방식을 골랐다.
private struct SettingsPaletteKey: EnvironmentKey {
    static var defaultValue: SettingsPalette { SettingsPalette.make(body: OverlaySettings().bodyTheme, focusHex: FocusColors.defaultHex, style: OverlaySettings().focusStyle) }
}

extension EnvironmentValues {
    var settingsPalette: SettingsPalette {
        get { self[SettingsPaletteKey.self] }
        set { self[SettingsPaletteKey.self] = newValue }
    }
}
