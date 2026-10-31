import SwiftUI

/// 오버레이와 설정 미리보기가 같이 읽는 색 합성 결과. 본체 색(`OverlayBody`: 면·글자·테두리·유리 질감)과
/// 포커스(`FocusStyle` × `#RRGGBB`: 선택됐을 때의 모양)를 따로 받아 합친다. 본체는 포커스 색을 전혀 모른다.
/// 뷰가 쓰는 층별 불투명도와 대비 테스트가 재는 합성식은 모두 이 파일의 같은 함수·상수에서 나온다(모델과 실제가 어긋나지 않게).
struct PaletteColors: Equatable {
    struct RGB: Equatable {
        let r: Double, g: Double, b: Double

        init(r: Double, g: Double, b: Double) {
            self.r = r; self.g = g; self.b = b
        }

        init(white: Double) { self.init(r: white, g: white, b: white) }

        static let white = RGB(r: 1, g: 1, b: 1)
        static let black = RGB(r: 0, g: 0, b: 0)

        var color: Color { Color(red: r, green: g, blue: b) }

        /// WCAG 상대 휘도
        var luminance: Double {
            func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }

        /// 두 색을 `t`(0…1) 비율로 섞는다.
        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }

        /// 휘도가 `limit` 이하가 될 때까지 검정 쪽으로(1% 단위) 섞는다. 이미 낮으면 그대로. 색상은 보존되고 명도만 눌린다.
        func darkened(toLuminance limit: Double) -> RGB {
            for step in 0...100 {
                let c = mixed(with: .black, Double(step) / 100)
                if c.luminance <= limit { return c }
            }
            return .black
        }
    }

    /// WCAG 대비 비율(1…21)
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 글자 대비 하한(WCAG AA)
    static let minTextContrast = 4.5
    /// 본체 면 휘도 하한: 검은 배경에서도 조각이 사라지지 않게(darkGray 의 회색 0.20 은 약 0.033)
    static let minSurfaceLuminance = 0.033

    // MARK: 본체

    /// 본체 한 종류의 상수. 색(`Color`)은 레거시 값이 바이트 단위로 같게 나와야 해서 RGB 와 따로 둔다.
    struct BodySpec: Equatable {
        let surface: RGB
        let hover: RGB
        let ink: RGB
        /// 광택·헤어라인·중앙 원 테두리 하이라이트 색(글자와 따로 둬서 글라스 틴트가 질감에만 드러나게 한다). 기존 본체는 `ink` 와 같다.
        let rim: RGB
        let glassTint: RGB
        let surfaceColor: Color
        let hoverColor: Color
        let inkColor: Color
        let rimColor: Color
        let capsuleColor: Color
        let glassTintColor: Color
        /// pie 조각·중앙 원판 채움에 설정 alpha 에 곱하는 배율(1 보다 작을수록 더 투명)
        let faceScale: Double
        /// pie 조각·중앙 원판 아래 까는 검은 스크림(설정 alpha 에 곱함). 투명한 유리가 밝은 바탕에서도 글자를 받치게 한다. 0 이면 층 없음.
        let faceBacking: Double
        /// 면 위쪽 광택(`rim` 불투명도). 아래로 갈수록 투명해진다.
        let sheenTop: Double
        /// 헤어라인 세기 배율과 그림자 쪽 끝 하한(어두운 바탕에서 윤곽이 사라지지 않게)
        let hairlineBoost: Double
        let hairlineFloor: Double
        /// orbit 타일의 검은 받침 불투명도(설정 alpha 0.74 기준)와 유리 그라데이션 위/아래 배율
        let tileBase: Double
        let tileGlossTop: Double
        let tileGlossBottom: Double
        /// orbit 타일·중앙 원판에 면 색을 얼마나 입힐지(0…1)
        let surfaceWeight: Double
        /// orbit 중앙 원판의 검은 받침 불투명도(설정 alpha 0.74 기준)
        let hubBase: Double
        /// 불투명 바닥판 색(면 색보다 약간 어둡게). 글라스 본체는 바닥판을 쓰지 않는다(`usesBackingPlate`).
        let plate: RGB
        let plateColor: Color
    }

    /// 앱 박스·중앙 원 뒤에 불투명 바닥판을 까는지. 글라스 본체는 바탕화면이 비쳐야 하므로 설정(`solidBacking`)과 무관하게 항상 깔지 않는다.
    static func usesBackingPlate(body: OverlayBody, solid: Bool) -> Bool {
        switch body {
        case .darkGray: return solid
        case .darkGlass, .clearGlass: return false
        }
    }

    /// darkGray: 지금까지의 기본 모양(회색 0.20 면, 흰 글씨, 흰 유리). 값은 레거시 상수 그대로다.
    private static let darkGraySpec = BodySpec(
        surface: RGB(white: 0.20), hover: RGB(white: 0.28), ink: .white, rim: .white, glassTint: .white,
        surfaceColor: Color(white: 0.20), hoverColor: Color(white: 0.28), inkColor: .white, rimColor: .white, capsuleColor: Color(white: 0.1), glassTintColor: .white,
        faceScale: 1, faceBacking: 0, sheenTop: OverlayMetrics.glassSheenTop, hairlineBoost: 1, hairlineFloor: 0.10,
        tileBase: 0.38, tileGlossTop: 1, tileGlossBottom: 1, surfaceWeight: 0, hubBase: 0.45,
        plate: RGB(white: 0.12), plateColor: Color(white: 0.12))

    /// darkGlass: 푸른기가 도는 블랙 유리. 바닥판 없이 바탕화면이 비친다. 면 휘도 하한(0.035)을 지키고 위→아래 광택·헤어라인을 강하게 해
    /// 검은 바탕에서도 윤곽이 남는다. 흰 글씨는 밝은 바탕(흰 바탕 극단)에서도 4.5 이상이어야 해서, 바닥판이 하던 일을 면 아래 검은 스크림
    /// (`faceBacking`·`tileBase`·`hubBase`)이 맡는다 — 어두운 바탕에서는 거의 안 보이고 밝은 바탕에서만 연기색으로 눌러 준다.
    private static let darkGlassSpec: BodySpec = {
        let surface = RGB(r: 0.18, g: 0.21, b: 0.29)
        let tint = RGB(r: 0.80, g: 0.88, b: 1.0)
        return BodySpec(
            surface: surface, hover: surface.mixed(with: .white, 0.12), ink: .white, rim: .white, glassTint: tint,
            surfaceColor: surface.color, hoverColor: surface.mixed(with: .white, 0.12).color, inkColor: .white, rimColor: .white,
            capsuleColor: RGB(r: 0.03, g: 0.05, b: 0.09).color, glassTintColor: tint.color,
            faceScale: 0.78, faceBacking: 0.75, sheenTop: 0.20, hairlineBoost: 1.3, hairlineFloor: 0.20,
            tileBase: 0.74, tileGlossTop: 1.1, tileGlossBottom: 0.35, surfaceWeight: 1.0, hubBase: 0.45,
            plate: RGB(white: 0.05), plateColor: Color(white: 0.05))
    }()

    /// clearGlass 면의 휘도 상한(평소 / hover)과 orbit 유리 색조의 상한. 틴트 색상은 그대로 두고 명도만 눌러, 밝은 틴트(투명·라임·호박)에서도 흰 글자가 읽힌다.
    static let clearSurfaceLuminance = 0.08
    static let clearHoverLuminance = 0.11
    static let clearTintLuminance = 0.22

    /// clearGlass: 바탕이 비치는 반투명 유리에 틴트를 입힌 본체. 면·hover 는 틴트를 어두운 쪽으로 눌러(`darkened`) 만들고(글자는 흰색),
    /// 광택·헤어라인(`rim`)은 틴트를 흰색 쪽으로 30% 밝혀 틴트가 질감에 또렷이 드러나게 한다. 면이 덜 덮이는 대신 검은 스크림이 글자를 받친다.
    private static func clearGlassSpec(tintHex: String) -> BodySpec {
        let c = GlassTints.normalized(tintHex).flatMap(FocusColors.rgb) ?? FocusColors.rgb(GlassTints.defaultHex) ?? (r: 0.435, g: 0.694, b: 1)
        let tint = RGB(r: c.r, g: c.g, b: c.b)
        let surface = tint.darkened(toLuminance: clearSurfaceLuminance)
        let hover = tint.darkened(toLuminance: clearHoverLuminance)
        let glass = tint.darkened(toLuminance: clearTintLuminance)
        let rim = tint.mixed(with: .white, 0.30)
        return BodySpec(
            surface: surface, hover: hover, ink: .white, rim: rim, glassTint: glass,
            surfaceColor: surface.color, hoverColor: hover.color, inkColor: .white, rimColor: rim.color,
            capsuleColor: tint.mixed(with: .black, 0.93).color, glassTintColor: glass.color,
            faceScale: 0.55, faceBacking: 0.75, sheenTop: 0.16, hairlineBoost: 1.3, hairlineFloor: 0.22,
            tileBase: 0.45, tileGlossTop: 1.0, tileGlossBottom: 0.6, surfaceWeight: 1.0, hubBase: 0.36,
            plate: RGB(white: 0.05), plateColor: Color(white: 0.05))
    }

    static func spec(for body: OverlayBody, glassTint: String = GlassTints.defaultHex) -> BodySpec {
        switch body {
        case .darkGray: return darkGraySpec
        case .darkGlass: return darkGlassSpec
        case .clearGlass: return clearGlassSpec(tintHex: glassTint)
        }
    }

    // MARK: 포커스 상수

    /// 플랫 선택 면의 채움 불투명도(강조색이 선명하게): pie 조각과 orbit 타일이 같다.
    static let flatFaceOpacity = 0.94
    /// 플랫 면 위 글자의 어두운 쪽 후보(순수 검정보다 부드럽다). 대비가 모자라면 순수 검정·흰색으로 넘어간다.
    static let softDarkGlyph = RGB(white: 0.1)
    /// 네온 선택 받침의 출발값과 상한: 상한보다 진하면 유리 느낌이 사라진다.
    static let neonSelectedBase = 0.55
    static let neonSelectedBaseMax = 0.95
    /// 네온 선택 면에 얹는 강조색 불투명도(위 → 아래) — pie 조각 / orbit 타일. 아주 옅게 얹는다.
    static let neonFaceTop = 0.14
    static let neonFaceBottom = 0.20
    static let neonTileAccentTop = 0.16
    static let neonTileAccentBottom = 0.12
    /// 네온 글자색에 섞는 강조색 비율
    static let neonGlyphMix = 0.25
    /// 글자 대비를 잴 설정 alpha 표본: 허용 범위 양 끝과 기준값 0.74
    static var alphaSamples: [Double] { [Limits.alphaRange.lowerBound, 0.74, Limits.alphaRange.upperBound] }

    // MARK: 층별 불투명도(뷰와 대비 모델이 같이 읽는다)

    /// pie 조각 한 장의 층. `sel`(0/1)은 선택 여부를 불투명도로 실어 보낸다(분기가 바뀌면 뷰 정체성이 바뀌어 선택 스프링이 페이드로 변한다).
    struct WedgeLayers: Equatable {
        /// 면 아래 검은 받침 불투명도
        let underlay: Double
        /// 면 그룹(채움 + 광택 + 네온 강조색)의 불투명도
        let face: Double
        let accentTop: Double, accentBottom: Double
    }

    static func wedgeLayers(spec: BodySpec, style: FocusStyle, selectedBase: Double, alpha: Double, sel: Double) -> WedgeLayers {
        let rest = alpha * spec.faceScale
        let backing = spec.faceBacking * alpha
        switch style {
        case .flat:
            return WedgeLayers(underlay: backing * (1 - sel), face: rest + (flatFaceOpacity - rest) * sel, accentTop: 0, accentBottom: 0)
        case .neon:
            // 선택 받침은 alpha 와 무관하다: 투명도를 낮춰도 밝은 바탕에서 글자 대비를 지킨다.
            return WedgeLayers(underlay: backing + (selectedBase - backing) * sel, face: rest, accentTop: neonFaceTop * sel, accentBottom: neonFaceBottom * sel)
        }
    }

    /// orbit 타일 한 장의 층. 순서: 검은 받침 → 본체 면 → 유리 색조(위→아래) → 강조색(네온, 위→아래) → 플랫 강조 면(`solid`, 광택 포함)
    struct TileLayers: Equatable {
        let base: Double
        let surface: Double
        let tintTop: Double, tintBottom: Double
        let accentTop: Double, accentBottom: Double
        /// 플랫 선택 면 그룹의 불투명도
        let solid: Double
    }

    static func tileLayers(spec: BodySpec, style: FocusStyle, selectedBase: Double, alpha: Double, hovered: Bool, sel: Double) -> TileLayers {
        let scale = OrbitMetrics.glassScale(alpha: alpha)
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        let normalBase = spec.tileBase * scale
        // 선택된 타일은 hover 유리 색조를 쓰지 않는다(선택 면은 hover 와 무관하게 같은 모양, 글자 대비 모델도 단순해진다)
        let glassHover = hovered && sel < 0.5
        let top = OrbitMetrics.glassTop(selected: false, hovered: glassHover) * spec.tileGlossTop
        let bottom = OrbitMetrics.glassBottom(selected: false, hovered: glassHover) * spec.tileGlossBottom
        switch style {
        case .flat:
            let rest = 1 - sel
            return TileLayers(base: clamp(normalBase * rest), surface: clamp(spec.surfaceWeight * 0.5 * scale * rest),
                              tintTop: clamp(top * scale * rest), tintBottom: clamp(bottom * scale * rest),
                              accentTop: 0, accentBottom: 0, solid: flatFaceOpacity * sel)
        case .neon:
            // 선택 타일의 유리 색조 배율은 1 을 넘기지 않는다: alpha 0.74 보다 높을 때 유리가 짙어져 어두운 받침을 덮으면 글자 대비가 깎인다.
            let tintScale = scale + (min(scale, 1) - scale) * sel
            return TileLayers(base: clamp(normalBase + (selectedBase - normalBase) * sel), surface: clamp(spec.surfaceWeight * 0.5 * scale),
                              tintTop: clamp(top * tintScale), tintBottom: clamp(bottom * tintScale),
                              accentTop: neonTileAccentTop * sel, accentBottom: neonTileAccentBottom * sel, solid: 0)
        }
    }

    /// 선택 면(pie 조각·orbit 타일)의 배경색 모음. 검정·흰 바탕 극단 × 표본 alpha × hover × 위/아래 그라데이션 끝을 모두 낸다.
    /// 층은 `wedgeLayers`/`tileLayers` 로 실제 뷰와 같은 값을 쓴다.
    static func selectedFaces(spec: BodySpec, style: FocusStyle, accent: RGB, selectedBase: Double, solid: Bool = false,
                              alphas: [Double] = alphaSamples, backdrops: [RGB] = [.black, .white]) -> [RGB] {
        var faces: [RGB] = []
        for alpha in alphas {
            // 바닥판이 있으면 바탕화면이 비치지 않으므로 바탕은 바닥판 색 하나다
            for backdrop in (solid ? [spec.plate] : backdrops) {
                for hovered in [false, true] {
                    let wedge = wedgeLayers(spec: spec, style: style, selectedBase: selectedBase, alpha: alpha, sel: 1)
                    let tile = tileLayers(spec: spec, style: style, selectedBase: selectedBase, alpha: alpha, hovered: hovered, sel: 1)
                    for top in [true, false] {
                        // pie 조각: 받침 → 면 그룹
                        let fill = style == .flat ? accent : (hovered ? spec.hover : spec.surface)
                        var group = fill.mixed(with: spec.rim, top ? spec.sheenTop : 0)
                        if style == .neon { group = group.mixed(with: accent, top ? wedge.accentTop : wedge.accentBottom) }
                        faces.append(backdrop.mixed(with: .black, wedge.underlay).mixed(with: group, wedge.face))
                        // orbit 타일: 받침 → 면 → 색조 → 강조(네온) / 강조 면 그룹(플랫)
                        var t = backdrop.mixed(with: .black, tile.base).mixed(with: spec.surface, tile.surface)
                            .mixed(with: spec.glassTint, top ? tile.tintTop : tile.tintBottom)
                        if style == .neon {
                            t = t.mixed(with: accent, top ? tile.accentTop : tile.accentBottom)
                        } else {
                            t = t.mixed(with: accent.mixed(with: spec.rim, top ? spec.sheenTop : 0), tile.solid)
                        }
                        faces.append(t)
                    }
                }
            }
        }
        return faces
    }

    /// 원판·배지 한 장의 층(검은 받침 → 면 색 → 유리 색조). orbit 중앙 원판과 번호 배지가 뷰와 대비 모델에서 같이 읽는다.
    struct DiscLayers {
        let base: Double
        let surface: Double
        let tint: Double
    }

    static func orbitHubLayers(spec: BodySpec, alpha: Double) -> DiscLayers {
        let scale = OrbitMetrics.glassScale(alpha: alpha)
        return DiscLayers(base: spec.hubBase * scale, surface: spec.surfaceWeight * 0.6 * scale, tint: 0.10 * scale)
    }

    /// orbit 번호 배지: 타일 면 위에 검은 받침과 유리 색조만 한 번 더 얹는다.
    static func badgeLayers(alpha: Double) -> DiscLayers {
        let scale = OrbitMetrics.glassScale(alpha: alpha)
        return DiscLayers(base: 0.35 * scale, surface: 0, tint: 0.10 * scale)
    }

    /// 선택되지 않은 면 위 글자(번호·약어·중앙 이름)의 배경색 모음: pie 조각(평소/hover × 위/아래 광택)·pie 중앙 원판·orbit 타일(평소/hover × 위/아래 색조)·
    /// 번호 배지·orbit 중앙 원판. 층은 뷰와 같은 `wedgeLayers`/`tileLayers`/`orbitHubLayers`/`badgeLayers` 에서 온다. 바닥판이 있으면 바탕은 바닥판 하나다.
    static func restFaces(spec: BodySpec, solid: Bool = false, alphas: [Double] = alphaSamples, backdrops: [RGB] = [.black, .white]) -> [RGB] {
        var faces: [RGB] = []
        for alpha in alphas {
            let wedge = wedgeLayers(spec: spec, style: .flat, selectedBase: 0, alpha: alpha, sel: 0)
            let hub = orbitHubLayers(spec: spec, alpha: alpha)
            let badge = badgeLayers(alpha: alpha)
            for backdrop in (solid ? [spec.plate] : backdrops) {
                let under = backdrop.mixed(with: .black, wedge.underlay)
                for fill in [spec.surface, spec.hover] {
                    for sheen in [spec.sheenTop, 0] { faces.append(under.mixed(with: fill.mixed(with: spec.rim, sheen), wedge.face)) }
                }
                faces.append(under.mixed(with: spec.surface, wedge.face))
                for hovered in [false, true] {
                    let tile = tileLayers(spec: spec, style: .flat, selectedBase: 0, alpha: alpha, hovered: hovered, sel: 0)
                    for top in [true, false] {
                        let t = backdrop.mixed(with: .black, tile.base).mixed(with: spec.surface, tile.surface)
                            .mixed(with: spec.glassTint, top ? tile.tintTop : tile.tintBottom)
                        faces.append(t)
                        faces.append(t.mixed(with: .black, badge.base).mixed(with: spec.glassTint, badge.tint))
                    }
                }
                faces.append(backdrop.mixed(with: .black, hub.base).mixed(with: spec.surface, hub.surface).mixed(with: spec.glassTint, hub.tint))
            }
        }
        return faces
    }

    /// 선택 면 위 글자색·플랫 채움색·네온 받침을 도출한다.
    /// 플랫: 본체 `ink`/부드러운 어두운 글자 중 더 잘 읽히는 쪽, 4.5 에 못 미치면 순수 흰색·검정까지 넓힌다.
    /// 실제 면은 채움 0.94 + 바탕 누출 6% + 위쪽 흰 광택이라 순수 포커스 색 단색일 때의 이론(흰/검정 한쪽 ≥ 4.58)이 중간 명도 색에서 깨진다.
    /// 그래서 최악 층 합성에서도 어느 글자도 4.5 에 못 미치면, 채움색만 흰색/검정 쪽으로 가장 적게 옮긴 `flatFill` 을 돌려준다(필요 없으면 `accent` 그대로).
    /// 네온: `ink` 에 강조색 25% 를 섞은 밝은 색을 대비 4.5 까지 흰색 쪽으로 보정하고, 그래도 모자라면(밝은 면 + 밝은 바탕) 받침을 조금씩 진하게 한다.
    static func selectionFields(spec: BodySpec, style: FocusStyle, accent: RGB, solid: Bool = false) -> (glyph: RGB, base: Double, flatFill: RGB) {
        switch style {
        case .flat:
            func glyph(for fill: RGB) -> (glyph: RGB, worst: Double) {
                let faces = selectedFaces(spec: spec, style: .flat, accent: fill, selectedBase: 0, solid: solid)
                func worst(_ glyph: RGB) -> Double { faces.map { contrast(glyph, $0) }.min() ?? 0 }
                func best(_ candidates: [RGB]) -> RGB {
                    var winner = candidates[0]
                    for c in candidates.dropFirst() where worst(c) > worst(winner) { winner = c }
                    return winner
                }
                let soft = best([spec.ink, softDarkGlyph])
                let pick = worst(soft) >= minTextContrast ? soft : best([spec.ink, softDarkGlyph, .white, .black])
                return (pick, worst(pick))
            }
            let original = glyph(for: accent)
            if original.worst >= minTextContrast { return (original.glyph, 0, accent) }
            // 흰색·검정 쪽 중 4.5 를 처음 맞추는 최소 이동(1% 단위)을 고른다. 이동량이 같으면 흰색 쪽을 먼저 본다.
            var winner: (fill: RGB, glyph: RGB, t: Double)?
            for target in [RGB.white, RGB.black] {
                for step in 1...100 {
                    let t = Double(step) / 100
                    let fill = accent.mixed(with: target, t)
                    let g = glyph(for: fill)
                    if g.worst >= minTextContrast {
                        if winner == nil || t < winner!.t { winner = (fill, g.glyph, t) }
                        break
                    }
                }
            }
            if let w = winner { return (w.glyph, 0, w.fill) }
            return (original.glyph, 0, accent)
        case .neon:
            let mix = spec.ink.mixed(with: accent, neonGlyphMix)
            var base = neonSelectedBase
            while true {
                let faces = selectedFaces(spec: spec, style: .neon, accent: accent, selectedBase: base, solid: solid)
                var t = 0.0
                while faces.contains(where: { contrast(mix.mixed(with: .white, t), $0) < minTextContrast }) && t < 1 { t += 0.05 }
                let glyph = mix.mixed(with: .white, min(t, 1))
                if !faces.contains(where: { contrast(glyph, $0) < minTextContrast }) || base >= neonSelectedBaseMax { return (glyph, base, accent) }
                base = min(base + 0.05, neonSelectedBaseMax)
            }
        }
    }

    // MARK: 합성 결과

    let body: OverlayBody
    let style: FocusStyle
    /// 앱 박스(조각·타일)·중앙 원 뒤에 불투명 바닥판을 까는지. 켜면 면 합성의 바탕은 검정/흰 극단이 아니라 바닥판 색 하나다.
    let solid: Bool
    let spec: BodySpec
    /// 선택 조각·타일, 중앙 원 호의 강조색(포커스 색)
    let accentRGB: RGB
    let accent: Color
    /// 플랫 선택 면(pie 조각·orbit 타일 채움)에 실제로 쓰는 색. 포커스 색 그대로로는 글자 대비 4.5 를 못 맞추는 중간 명도 색만
    /// 흰/검정 쪽으로 최소한 옮겨 둔다. 모델(`selectedFaces`)과 뷰가 같은 값을 읽는다. 중앙 원 호·테두리는 원래 `accent`.
    let flatFillRGB: RGB
    let flatFill: Color
    /// 조각·타일·중앙 원판의 기본 면 색 / hover 때 / 글자·기호 / 이름 캡슐 바탕 / orbit 유리 색조
    var surface: Color { spec.surfaceColor }
    var surfaceHover: Color { spec.hoverColor }
    var ink: Color { spec.inkColor }
    /// 광택·헤어라인 색(글자와 따로: 글라스 틴트가 질감에만 드러난다)
    var rim: Color { spec.rimColor }
    var capsule: Color { spec.capsuleColor }
    var glassTint: Color { spec.glassTintColor }
    var surfaceRGB: RGB { spec.surface }
    var inkRGB: RGB { spec.ink }
    var surfaceWeight: Double { spec.surfaceWeight }
    /// 선택 면 위의 글자색(pie 조각·orbit 타일 공통)
    let selectedGlyph: Color
    let selectedGlyphRGB: RGB
    /// 네온 선택 면의 검은 받침 불투명도(alpha 와 무관). 플랫은 0.
    let selectedBase: Double
    /// 포커스 색 불빛(번짐·글로우·빛) 표시 여부(설정 `focusGlow`). 대비 모델·면 틴트·선 색은 이 값과 무관하다: 끄면 번짐만 사라진다.
    let glow: Bool
    /// 불빛 세기: 네온이고 불빛이 켜져 있으면 1(선택 조각·타일, 중앙 원 호·가이드의 번짐), 아니면 0.
    /// '네온인가'는 `style == .neon` 으로 따로 본다: 불빛을 꺼도 면 틴트·선 색은 네온 그대로여야 한다.
    var glowStrength: Double { style == .neon && glow ? 1 : 0 }
    /// 플랫 선택 orbit 타일 둘레의 은은한 번짐 색(네온은 별도 이중 글로우를 쓰므로, 불빛이 꺼져도 투명)
    var tileHalo: Color { style == .neon || !glow ? .clear : accent }

    /// 중앙 원 테두리·안쪽 선의 하이라이트 색: 네온은 강조색, 플랫은 본체 글자색
    var rimInk: Color { style == .neon ? accent : rim }

    private static var cache: [String: PaletteColors] = [:]
    private static let yellowHex = "#FAE32E"

    /// 본체·포커스 스타일·`#RRGGBB`·글라스 틴트로 색을 합성한다. 해석할 수 없는 색은 기본(포커스: `FocusColors.defaultHex`, 틴트: 하늘)으로 본다.
    /// `solid` 는 요청이고, 실제로 바닥판을 까는지는 본체가 정한다(`usesBackingPlate`). 틴트는 클리어 글라스에서만 결과에 영향을 준다.
    /// `glow` 는 포커스 색 불빛(번짐) 표시 여부로, 대비 계산(면·글자색)에는 들어가지 않는다 — 불빛을 꺼도 글자 대비가 그대로다.
    /// 오버레이가 조각마다 읽으므로 같은 입력은 한 번만 계산한다(네온은 대비 보정 루프가 있다). 캐시 키에 `glow` 가 들어가 켬/끔이 서로 다른 값이다.
    static func make(body: OverlayBody, style: FocusStyle, hex: String, solid: Bool = false, glassTint: String = GlassTints.defaultHex, glow: Bool = true) -> PaletteColors {
        let normalized = FocusColors.normalized(hex) ?? FocusColors.defaultHex
        let tint = GlassTints.normalized(glassTint) ?? GlassTints.defaultHex
        let plated = usesBackingPlate(body: body, solid: solid)
        let key = "\(body.rawValue)|\(style.rawValue)|\(normalized)|\(plated)|\(body == .clearGlass ? tint : "-")|\(glow)"
        if let hit = cache[key] { return hit }
        let spec = spec(for: body, glassTint: tint)
        // 노랑 프리셋(`#FAE32E`)은 상수(0.98, 0.89, 0.18)를 그대로 둔다: 8비트에서 되돌린 값(0.9804…)과 미세하게 달라 가장자리 픽셀이 1~2 단계 달라지기 때문이다.
        let c = normalized == yellowHex ? (r: 0.98, g: 0.89, b: 0.18) : (FocusColors.rgb(normalized) ?? (r: 0.98, g: 0.89, b: 0.18))
        let accent = RGB(r: c.r, g: c.g, b: c.b)
        let fields = selectionFields(spec: spec, style: style, accent: accent, solid: plated)
        let made = PaletteColors(body: body, style: style, solid: plated, spec: spec, accentRGB: accent, accent: accent.color,
                                 flatFillRGB: fields.flatFill, flatFill: fields.flatFill.color,
                                 selectedGlyph: fields.glyph == softDarkGlyph ? Color(white: 0.1) : (fields.glyph == spec.ink ? spec.inkColor : fields.glyph.color),
                                 selectedGlyphRGB: fields.glyph, selectedBase: fields.base, glow: glow)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = made
        return made
    }

    /// 상태가 없을 때 쓰는 임시 색(다크 그레이 + 플랫 노랑 프리셋). 설정 기본값과는 무관하며, 레거시 상수 검증의 기준이다.
    static var standard: PaletteColors { make(body: .darkGray, style: .flat, hex: yellowHex) }

    /// 바닥판 색: 앱 박스·중앙 원 뒤에 깐다(불투명). 켜져 있을 때만 값이 있다.
    var plate: Color? { solid ? spec.plateColor : nil }

    func wedgeLayers(alpha: Double, sel: Double) -> WedgeLayers {
        Self.wedgeLayers(spec: spec, style: style, selectedBase: selectedBase, alpha: alpha, sel: sel)
    }

    func tileLayers(alpha: Double, hovered: Bool, sel: Double) -> TileLayers {
        Self.tileLayers(spec: spec, style: style, selectedBase: selectedBase, alpha: alpha, hovered: hovered, sel: sel)
    }
}
