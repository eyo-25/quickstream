import SwiftUI

/// orbit 테마의 색·투명도 규칙. 흰 유리 계열이고 노랑을 쓰지 않는다.
enum OrbitMetrics {
    static let selectedScale: CGFloat = 1.14
    /// 가이드 선(타일 궤도 실선 원 / 바깥 점선 원 / 중앙→타일 방사 점선)의 글자색 불투명도와 굵기
    static let guideOrbitOpacity = 0.40
    static let guideOuterOpacity = 0.38
    static let guideSpokeOpacity = 0.34
    static let guideLineWidth: CGFloat = 1.2
    /// 네온 스타일의 가이드(강조색)
    static let neonGuideOpacity = 0.40
    /// 밝은 배경에서도 가이드가 보이도록 아래에 까는 어두운 선의 불투명도
    static let guideUnderOpacity = 0.40
    /// 유리 채움 배율: 기준 alpha 0.74 를 배율 1.0 으로 둔다(설정 기본 alpha 와는 별개의 기준값)
    static func glassScale(alpha: Double) -> Double { alpha / 0.74 }
    static func glassTop(selected: Bool, hovered: Bool) -> Double { selected ? 0.40 : (hovered ? 0.30 : 0.24) }
    static func glassBottom(selected: Bool, hovered: Bool) -> Double { selected ? 0.28 : (hovered ? 0.16 : 0.10) }
}

/// orbit 테마의 순수 기하. 방향 섹터·중앙 원·링 영역 판정은 pie 의 `PieGeometry` 를 그대로 쓰고(슬롯 1=12시, 시계 방향, 45° 간격),
/// 여기서는 타일 크기·위치와 번호 배지·이름 라벨의 자리만 정한다. 모든 좌표는 링 중심 기준, y 아래가 +.
struct OrbitGeometry: Equatable {
    let pie: PieGeometry

    static let badgeSize: CGFloat = 16
    /// 이름 캡슐이 차지하는 칸의 높이(글자 10~12.5pt + 세로 패딩 8 + 여유)와 타일과의 간격
    static let labelHeight: CGFloat = 24
    static let labelGap: CGFloat = 3
    /// 라벨 칸 폭의 하한(캡슐 패딩 20 + 글자 40pt 정도): 아주 좁은 띠에서는 라벨 폭이 아니라 타일을 줄여 이 폭을 지킨다.
    static let minLabelWidth: CGFloat = 60
    /// 타일 한 변의 하한. 라벨이 링 영역 상자(링 반지름 + 24) 안에 들어오는 최소 크기이기도 하다.
    static let minTileSide: CGFloat = 24
    static let selectedScale = OrbitMetrics.selectedScale
    /// 타일 중심에서 모서리까지의 거리 / 타일 한 변(대각선 방향 기준), 보통 크기
    static let restHalfDiagonal: CGFloat = 0.5 * CGFloat(2).squareRoot()
    /// 중앙 원판과 타일 사이 최소 간격 / 라벨 사이 최소 간격
    static let hubGap: CGFloat = 6
    static let labelHubGap: CGFloat = 3

    /// 타일 한 변: 링 반지름의 27%. 중앙 원이 커서 띠가 좁으면 타일 아래 라벨이 중앙 원판·이웃 타일에 닿지 않을 만큼 줄인다.
    let tileSide: CGFloat
    /// 이름 캡슐 칸의 폭. 중앙 원판·이웃 타일에 닿지 않는 최대 폭(타일 한 변의 2배 상한).
    let labelWidth: CGFloat

    init(pie: PieGeometry) {
        self.pie = pie
        let preferred = pie.outerRadius * 0.27
        var side = preferred
        if Self.labelHalfWidth(pie: pie, side: side) * 2 < Self.minLabelWidth {
            // 라벨 폭은 타일이 작을수록 넓어진다(궤도가 바깥으로 나가고 타일·라벨이 줄어든다). 폭 하한을 지키는 가장 큰 타일을 이분법으로 찾는다.
            var lo = Self.minTileSide, hi = preferred
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if Self.labelHalfWidth(pie: pie, side: mid) * 2 >= Self.minLabelWidth { lo = mid } else { hi = mid }
            }
            side = lo
        }
        tileSide = side
        // 타일이 아주 작아져도 라벨 칸은 폭 하한을 지킨다(상한은 타일 폭의 2배)
        labelWidth = max(0, min(max(side * 2, Self.minLabelWidth), Self.labelHalfWidth(pie: pie, side: side) * 2))
    }

    var ring: CGFloat { pie.outerRadius }
    var hub: CGFloat { pie.hubRadius }
    /// 타일 중심 궤도: 보통 크기 타일의 모서리가 링 안쪽 가장자리(클릭 영역 경계)에 닿는 반지름
    var orbitRadius: CGFloat { Self.orbitRadius(ring: ring, side: tileSide) }
    var iconSize: CGFloat { tileSide * 0.5 }
    var labelFontSize: CGFloat { min(12.5, max(10, tileSide * 0.145)) }

    private static func orbitRadius(ring: CGFloat, side: CGFloat) -> CGFloat { ring - restHalfDiagonal * side }

    /// 타일 한 변이 `side` 일 때 라벨 칸의 최대 반폭(음수면 어떤 폭으로도 못 놓는다). 슬롯 8개 × 선택/보통 두 상태에서
    /// ① 중앙 원판과 `labelHubGap` 이상 ② 이웃 타일(선택 확대 크기)·이웃 라벨과 안 겹침 ③ 링 영역 상자 안, 을 모두 만족하는 한계의 최솟값이다.
    /// 타일 자체가 중앙 원판(`hubGap`)에 닿으면 음수다.
    private static func labelHalfWidth(pie: PieGeometry, side: CGFloat) -> CGFloat {
        let ring = pie.outerRadius, hub = pie.hubRadius
        let orbit = orbitRadius(ring: ring, side: side)
        let box = ring + 24
        let hubReach = hub + labelHubGap
        func distanceToOrigin(_ r: CGRect) -> CGFloat { hypot(max(r.minX, 0, -r.maxX), max(r.minY, 0, -r.maxY)) }
        let tiles = (0..<PieGeometry.slots).map { i -> CGRect in
            let c = PieGeometry.offset(index: i, radius: orbit)
            let s = side * selectedScale
            return CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
        }
        if tiles.contains(where: { distanceToOrigin($0) < hub + hubGap }) { return -1 }

        var limit = CGFloat.infinity
        for i in 0..<PieGeometry.slots {
            let tile = PieGeometry.offset(index: i, radius: orbit)
            for selected in [false, true] {
                let c = labelCenter(tile: tile, side: side, selected: selected)
                let y0 = c.y - labelHeight / 2, y1 = c.y + labelHeight / 2
                // ① 중앙 원판: 라벨의 세로 범위가 원점에서 dy 만큼 떨어져 있으면 가로로 sqrt(r² - dy²) 이상 떨어져야 한다
                let dy = max(y0, 0, -y1)
                if dy < hubReach { limit = min(limit, abs(c.x) - (hubReach * hubReach - dy * dy).squareRoot()) }
                // ③ 상자 안
                if y1 > box { return -1 }
                limit = min(limit, box - abs(c.x))
                // ② 이웃 타일: 세로 범위가 겹치는 타일과는 가로로 떨어져야 한다
                for (j, t) in tiles.enumerated() where j != i && y0 < t.maxY && t.minY < y1 {
                    limit = min(limit, t.minX > c.x ? t.minX - c.x : (t.maxX < c.x ? c.x - t.maxX : -1))
                }
            }
            // 이웃 라벨(선택된 라벨 기준, 세로로 겹치면 가로 반폭의 합이 중심 간격 이하)
            let c = labelCenter(tile: tile, side: side, selected: true)
            for j in (i + 1)..<PieGeometry.slots {
                let d = labelCenter(tile: PieGeometry.offset(index: j, radius: orbit), side: side, selected: true)
                if abs(c.y - d.y) < labelHeight { limit = min(limit, abs(c.x - d.x) / 2) }
            }
        }
        return limit
    }

    func tileCenter(index: Int) -> CGPoint { PieGeometry.offset(index: index, radius: orbitRadius) }

    /// 설정 `radius`(24…56)를 타일 한 변의 20%~40% 모서리로 선형 대응시킨다.
    func tileCorner(setting: Int) -> CGFloat {
        let range = Limits.radiusRange
        let t = Double(min(max(setting, range.lowerBound), range.upperBound) - range.lowerBound)
            / Double(range.upperBound - range.lowerBound)
        return tileSide * CGFloat(0.20 + 0.20 * t)
    }

    func tileRect(index: Int, scale: CGFloat = 1) -> CGRect {
        let c = tileCenter(index: index)
        let side = tileSide * scale
        return CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
    }

    /// 번호 배지: 타일 오른쪽 위 모서리에 걸친다(타일 중심 기준 오프셋). 그 자리가 중앙 원판에 너무 가까우면(좁은 띠) 위쪽 왼쪽 모서리로,
    /// 그래도 중앙 원판과 간격이 모자라면 둘 중 더 먼 쪽으로 옮긴다. 라벨은 늘 타일 아래라 배지를 가리지 않는다.
    func badgeOffset(index: Int) -> CGPoint {
        let edge = tileSide / 2 + 2
        let candidates = [CGPoint(x: edge, y: -edge), CGPoint(x: -edge, y: -edge)]
        let c = tileCenter(index: index)
        func clearance(_ o: CGPoint) -> CGFloat {
            let r = CGRect(x: c.x + o.x - Self.badgeSize / 2, y: c.y + o.y - Self.badgeSize / 2, width: Self.badgeSize, height: Self.badgeSize)
            return hypot(max(r.minX, 0, -r.maxX), max(r.minY, 0, -r.maxY)) - hub
        }
        if let fit = candidates.first(where: { clearance($0) >= Self.hubGap }) { return fit }
        return clearance(candidates[0]) >= clearance(candidates[1]) ? candidates[0] : candidates[1]
    }

    func badgeCenter(index: Int) -> CGPoint {
        let c = tileCenter(index: index)
        let offset = badgeOffset(index: index)
        return CGPoint(x: c.x + offset.x, y: c.y + offset.y)
    }

    func badgeRect(index: Int) -> CGRect {
        let c = badgeCenter(index: index)
        return CGRect(x: c.x - Self.badgeSize / 2, y: c.y - Self.badgeSize / 2, width: Self.badgeSize, height: Self.badgeSize)
    }

    /// 이름 라벨은 언제나 타일 바로 아래다(위로 올라가지 않는다). 선택 타일은 커지므로 그만큼 타일에서 더 떨어뜨려 겹치지 않게 한다.
    func labelCenter(index: Int, selected: Bool = false) -> CGPoint {
        Self.labelCenter(tile: tileCenter(index: index), side: tileSide, selected: selected)
    }

    private static func labelCenter(tile c: CGPoint, side: CGFloat, selected: Bool) -> CGPoint {
        let grow = selected ? side / 2 * (selectedScale - 1) : 0
        return CGPoint(x: c.x, y: c.y + side / 2 + labelGap + labelHeight / 2 + grow)
    }

    func labelRect(index: Int, selected: Bool = false) -> CGRect {
        let c = labelCenter(index: index, selected: selected)
        return CGRect(x: c.x - labelWidth / 2, y: c.y - Self.labelHeight / 2, width: labelWidth, height: Self.labelHeight)
    }
}

/// 중앙 원 가장자리에서 각 타일 방향으로 뻗는 점선
struct OrbitSpokes: Shape {
    let geometry: OrbitGeometry

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let from = geometry.hub + 8
        let to = geometry.orbitRadius - geometry.tileSide * 0.62
        var path = Path()
        guard to > from else { return path }
        for i in 0..<PieGeometry.slots {
            let p0 = PieGeometry.offset(index: i, radius: from)
            let p1 = PieGeometry.offset(index: i, radius: to)
            path.move(to: CGPoint(x: c.x + p0.x, y: c.y + p0.y))
            path.addLine(to: CGPoint(x: c.x + p1.x, y: c.y + p1.y))
        }
        return path
    }
}

/// 동심 원(타일 궤도)·바깥 점선 원·방사 점선. 세 배경 모두에서 또렷하도록 글자색 계열로 칠하고, 밝은 배경에서도 보이게 같은 선을 어둡게
/// 약하게 한 겹 아래에 깐다. 네온 스타일은 강조색을 띠고 은은히 발광한다.
struct OrbitGuides: View {
    let geometry: OrbitGeometry
    let palette: PaletteColors

    var body: some View {
        let neon = palette.style == .neon
        let tint = neon ? palette.accent : palette.ink
        return ZStack {
            lines(.black, orbit: OrbitMetrics.guideUnderOpacity, outer: OrbitMetrics.guideUnderOpacity, spoke: OrbitMetrics.guideUnderOpacity)
                .offset(y: 0.7)
            lines(tint,
                  orbit: neon ? OrbitMetrics.neonGuideOpacity : OrbitMetrics.guideOrbitOpacity,
                  outer: neon ? OrbitMetrics.neonGuideOpacity : OrbitMetrics.guideOuterOpacity,
                  spoke: neon ? OrbitMetrics.neonGuideOpacity : OrbitMetrics.guideSpokeOpacity)
        }
        .neonGlow(palette.accent, strength: palette.glowStrength * 0.5)
    }

    private func lines(_ color: Color, orbit: Double, outer: Double, spoke: Double) -> some View {
        let width = OrbitMetrics.guideLineWidth
        return ZStack {
            Circle()
                .stroke(color.opacity(orbit), lineWidth: width)
                .frame(width: geometry.orbitRadius * 2, height: geometry.orbitRadius * 2)
            Circle()
                .stroke(color.opacity(outer), style: StrokeStyle(lineWidth: width, dash: [2, 6]))
                .frame(width: geometry.ring * 2, height: geometry.ring * 2)
            OrbitSpokes(geometry: geometry)
                .stroke(color.opacity(spoke), style: StrokeStyle(lineWidth: width, dash: [2, 4]))
        }
    }
}

/// 타일 하나(유리 + 아이콘/약어/`+` + 번호 배지). 타일 중심이 이 뷰의 중심이다. 위치·확대·눌림은 호출 측이 정한다.
/// 글자·아이콘은 항상 100% 흰색이고, 반투명은 유리 채움에만 있다.
struct OrbitTile: View {
    let geometry: OrbitGeometry
    let index: Int
    let corner: CGFloat
    let alpha: Double
    let selected: Bool
    let hovered: Bool
    /// 앱 아이콘(없으면 약어)
    let icon: NSImage?
    /// 약어. nil 이면 빈 슬롯(`+`)
    let label: String?
    let palette: PaletteColors
    /// 1~8 번호 배지를 그릴지(설정 `showNumbers`). false 면 배지 전체를 숨긴다(레이아웃·판정은 그대로).
    var showNumber = true
    /// 아이콘이 뒤늦게 도착할 때 크로스페이드할지(미리보기는 끈다)
    var crossfade = false
    /// 배지에 쓸 키 표기(대문자). nil 이면 번호(index + 1), 빈 문자열이면 이 칸에는 배지를 그리지 않는다.
    var keyLabel: String? = nil

    var body: some View {
        let side = geometry.tileSide
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let neon = palette.style == .neon
        let sel: Double = selected ? 1 : 0
        return ZStack {
            ZStack {
                if neon {
                    neonGlass(shape: shape, sel: sel)
                } else {
                    flatGlass(shape: shape, sel: sel)
                }
            }
            .frame(width: side, height: side)
            // 밝은 바탕에서 흰 유리가 사라지지 않도록 타일 바깥쪽에 약한 어두운 그림자를 깐다. 선택 타일은 강조색 글로우도 더한다.
            // 네온은 면 아래로 비치지 않도록 바깥쪽에만 이중 글로우를 둔다.
            .background {
                ZStack {
                    pieOutsideShadow(shape.fill(Color.black).frame(width: side, height: side), opacity: selected ? 0.5 : 0.3)
                    if neon && palette.glow {
                        neonOutsideGlow(shape.fill(Color.black).frame(width: side, height: side), color: palette.accent.opacity(sel))
                    }
                }
            }
            .shadow(color: palette.tileHalo.opacity(selected ? 0.30 : 0), radius: 12)
            .animation(Motion.animation(Motion.snap), value: selected)
            .animation(Motion.animation(Motion.snap), value: hovered)

            glyph
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)

            if showNumber, keyLabel != "" {
                badge
                    .offset(x: geometry.badgeOffset(index: index).x, y: geometry.badgeOffset(index: index).y)
            }
        }
        .frame(width: side, height: side)
    }

    /// 층별 불투명도는 `PaletteColors.tileLayers` 가 정한다(글자 대비 모델과 같은 값). 선택 여부는 분기가 아니라 불투명도(`sel`)로 넘겨
    /// 선택 스프링 동안 뷰 정체성이 유지된다.
    /// 플랫: 평소는 본체 유리, 선택되면 유리 층이 빠지고 포커스 색 면(+광택)이 `flatFaceOpacity` 로 차오른다.
    private func flatGlass(shape: RoundedRectangle, sel: Double) -> some View {
        let layers = palette.tileLayers(alpha: alpha, hovered: hovered, sel: sel)
        return ZStack {
            if let plate = palette.plate { shape.fill(plate) }
            // 밝은 바탕에서도 흰 글자가 읽히도록 유리 아래에 약한 어두운 바탕을 깐다(어두운 바탕에서는 거의 티가 나지 않는다)
            shape.fill(Color.black.opacity(layers.base))
            shape.fill(palette.surface.opacity(layers.surface))
            shape.fill(LinearGradient(colors: [palette.glassTint.opacity(layers.tintTop), palette.glassTint.opacity(layers.tintBottom)], startPoint: .top, endPoint: .bottom))
            // 선택 면: pie 조각과 같은 합성(강조색 + 위쪽 광택을 한 장으로 묶어 투명도를 준다)
            ZStack {
                shape.fill(palette.flatFill)
                shape.fill(LinearGradient(colors: [palette.rim.opacity(palette.spec.sheenTop), palette.rim.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            .compositingGroup()
            .opacity(layers.solid)
            shape.strokeBorder(selected ? OverlayMetrics.glassHairline(palette, selected: true, strength: 1.15, span: 0.8)
                                        : OverlayMetrics.glassHairline(palette, selected: false, strength: hovered ? 1.15 : 1),
                               lineWidth: OverlayMetrics.hairlineWidth)
        }
    }

    /// 네온: 평소는 본체 유리 그대로. 선택(`sel`)되면 받침을 조금 진하게 하고 강조색을 아주 옅게(위 0.20 → 아래 0.14) 얹으며,
    /// 강조색 헤어라인·안쪽 가장자리 번짐을 더한다.
    private func neonGlass(shape: RoundedRectangle, sel: Double) -> some View {
        let layers = palette.tileLayers(alpha: alpha, hovered: hovered, sel: sel)
        return ZStack {
            if let plate = palette.plate { shape.fill(plate) }
            shape.fill(Color.black.opacity(layers.base))
            shape.fill(palette.surface.opacity(layers.surface))
            shape.fill(LinearGradient(colors: [palette.glassTint.opacity(layers.tintTop), palette.glassTint.opacity(layers.tintBottom)], startPoint: .top, endPoint: .bottom))
            shape.fill(LinearGradient(colors: [palette.accent.opacity(layers.accentTop), palette.accent.opacity(layers.accentBottom)], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(OverlayMetrics.glassHairline(palette, selected: false, strength: hovered ? 1.15 : 1), lineWidth: OverlayMetrics.hairlineWidth)
            shape.strokeBorder(OverlayMetrics.neonHairline(accent: palette.accent), lineWidth: OverlayMetrics.neonRimWidth)
                .opacity(sel)
            if palette.glow {
                NeonInnerGlow(color: palette.accent, amount: 0.25 * sel) { d in
                    RoundedRectangle(cornerRadius: max(corner - d, 0), style: .continuous).inset(by: d).fill(Color.black)
                }
            }
        }
    }

    private var glyph: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.iconSize, height: geometry.iconSize)
                    .transition(.opacity)
            } else if let label {
                Text(label)
                    .font(.system(size: geometry.tileSide * 0.3, weight: .bold))
                    .foregroundColor(selected ? palette.selectedGlyph : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: geometry.tileSide * 0.8)
                    .transition(.opacity)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: geometry.tileSide * 0.38, weight: .regular))
                    .foregroundColor(selected ? palette.selectedGlyph : palette.ink)
                    .transition(.opacity)
            }
        }
        .animation(crossfade ? Motion.animation(.easeInOut(duration: 0.18)) : nil, value: icon != nil)
    }

    /// 1~8 번호 키 배지: 안쪽 약한 유리 채움 + 흰 테두리 + 얇은 숫자
    private var badge: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            shape.fill(Color.black.opacity(PaletteColors.badgeLayers(alpha: alpha).base))
            shape.fill(palette.glassTint.opacity(PaletteColors.badgeLayers(alpha: alpha).tint))
            shape.strokeBorder(OverlayMetrics.glassHairline(palette, selected: false, strength: 0.7), lineWidth: OverlayMetrics.hairlineWidth)
            Text(keyLabel ?? "\(index + 1)")
                .font(OverlayMetrics.wedgeNumberFont(size: 10))
                .foregroundColor(palette.ink)
        }
        .frame(width: OrbitGeometry.badgeSize, height: OrbitGeometry.badgeSize)
        .background { pieOutsideShadow(shape.fill(Color.black).frame(width: OrbitGeometry.badgeSize, height: OrbitGeometry.badgeSize)) }
    }
}

/// 타일 아래 이름: 어두운 유리 캡슐 위의 글자색 글씨. 캡슐은 글자 길이에 맞춰 줄고 `labelWidth` 를 넘으면 말줄임한다.
struct OrbitTileLabel: View {
    let name: String
    let geometry: OrbitGeometry
    let palette: PaletteColors

    var body: some View {
        GlassCapsuleText(text: name, fontSize: geometry.labelFontSize, weight: OverlayMetrics.labelWeight, maxWidth: geometry.labelWidth, palette: palette)
            .frame(width: geometry.labelWidth, height: OrbitGeometry.labelHeight)
    }
}

/// 중앙 원판: 선택된 슬롯 이름만(빈 슬롯이면 `빈 슬롯`). 아이콘·밑줄·장식·안내 문구는 없다.
struct OrbitHub: View {
    let geometry: OrbitGeometry
    let alpha: Double
    /// 선택된 슬롯 이름. nil 이면 빈 슬롯
    let name: String?
    /// 이름이 바뀔 때 교차 페이드하려면 이름을 가리키는 식별자(빈 슬롯은 "empty")
    let nameID: String
    let palette: PaletteColors
    var animated = false
    /// 중앙 이름 글자 굵기·크기 설정(크기 0 = 자동). 오버레이는 `OverlayState`, 미리보기는 `PiePreviewStyle` 에서 온다.
    var nameWeight: NameWeight = .medium
    var nameSize = 0
    /// 선택 변경 때의 중앙 원 빛. 오버레이만 `live` 로 넘기고 미리보기는 끈다.
    var pulse: HubPulseSource = .off

    var body: some View {
        let hub = geometry.hub
        let border = geometry.pie.hubBorder
        let size = hub * 2
        let hubLayers = PaletteColors.orbitHubLayers(spec: palette.spec, alpha: alpha)
        return ZStack {
            if let plate = palette.plate { Circle().fill(plate) }
            Circle().fill(Color.black.opacity(hubLayers.base))
            Circle().fill(palette.surface.opacity(hubLayers.surface))
            Circle().fill(palette.glassTint.opacity(hubLayers.tint))
            hubInnerGlow(palette: palette)
            HubPulseGlow(palette: palette, source: pulse, border: border)
            Circle().strokeBorder(OverlayMetrics.hubHairline(palette), lineWidth: border)
            Circle().inset(by: border + 3).stroke(OverlayMetrics.glassHairline(palette, selected: false, strength: 0.8, ink: palette.rimInk), lineWidth: OverlayMetrics.hairlineWidth)
            texts
        }
        .frame(width: size, height: size)
        .background { hubBackdrop(size: size, palette: palette) }
    }

    /// 선택된 슬롯 이름(최대 2줄)만. pie 의 `center` 이름과 같은 뷰를 쓴다.
    private var texts: some View {
        HubNameText(hub: geometry.hub, border: geometry.pie.hubBorder, width: geometry.hub * 1.5, name: name, nameID: nameID, ink: palette.ink,
                    weight: nameWeight, sizeSetting: nameSize, animated: animated)
    }
}

/// 오버레이에 그려지는 orbit 장면. 링 중심에 놓이고, 입력·창 덮기·페이드는 `OverlayView` 의 공통 경로가 맡는다.
struct OrbitScene: View {
    @ObservedObject var model: OverlayModel
    let tab: TabView
    let state: OverlayState

    private var palette: PaletteColors { state.colors }

    var body: some View {
        let geometry = OrbitGeometry(pie: PieGeometry(state: state))
        let current = model.selected < tab.slots.count ? tab.slots[model.selected] : nil
        let fade = model.appeared ? Motion.animation(.easeOut(duration: 0.12).delay(0.08)) : nil
        return ZStack {
            OrbitGuides(geometry: geometry, palette: palette)
                .opacity(model.appeared ? 1 : 0)
                .animation(fade, value: model.appeared)

            ForEach(0..<PieGeometry.slots, id: \.self) { i in
                tileContainer(index: i, geometry: geometry)
                    .zIndex(i == model.selected ? 1 : 0)
            }

            OrbitHub(geometry: geometry, alpha: state.alpha, name: current?.name, nameID: current?.id ?? "empty", palette: palette, animated: model.appeared,
                     nameWeight: state.centerNameWeight, nameSize: state.centerNameSize, pulse: .live(model.hubPulse))
                .scaleEffect(model.appeared ? 1 : OverlayMotion.hubFrom)
                .animation(OverlayMotion.appearAnimation(appeared: model.appeared), value: model.appeared)
        }
        .frame(width: geometry.pie.boxSize, height: geometry.pie.boxSize)
    }

    /// 탭이 바뀌면 내용의 id 가 바뀌어 이전 타일은 빠지고 새 타일이 차례로 오른다(자리 컨테이너는 그대로).
    private func tileContainer(index: Int, geometry: OrbitGeometry) -> some View {
        let slot = index < tab.slots.count ? tab.slots[index] : nil
        return ZStack {
            tileLayer(index: index, slot: slot, geometry: geometry)
                .id("\(tab.id)#\(index)")
                .transition(OverlayMotion.tabTransition(index: index))
        }
        .frame(width: geometry.pie.boxSize, height: geometry.pie.boxSize)
        .animation(model.appeared ? Motion.animation(Motion.soft) : nil, value: model.tabIndex)
    }

    private func tileLayer(index: Int, slot: SlotView?, geometry: OrbitGeometry) -> some View {
        let selected = index == model.selected
        let hovered = model.hovered == index
        let pressed = model.confirming == index || model.pressedSlot == index
        let center = geometry.tileCenter(index: index)
        let labelAt = geometry.labelCenter(index: index, selected: selected)
        let icon = slot.flatMap { model.icons[$0.id] }
        return ZStack {
            OrbitTile(geometry: geometry, index: index, corner: geometry.tileCorner(setting: state.radius), alpha: state.alpha,
                      selected: selected, hovered: hovered, icon: icon, label: slot?.label, palette: palette, showNumber: state.showNumbers, crossfade: model.appeared,
                      keyLabel: model.keyLabel(index))
                .scaleEffect(selected ? OrbitMetrics.selectedScale : 1)
                .animation(Motion.animation(Motion.chewy), value: selected)
                .scaleEffect(pressed ? OverlayMotion.pressScale : 1)
                .animation(Motion.animation(Motion.snap), value: pressed)
                .offset(x: center.x, y: center.y)

            if let slot, state.showTileLabels {
                OrbitTileLabel(name: slot.name, geometry: geometry, palette: palette)
                    .offset(x: labelAt.x, y: labelAt.y)
                    .animation(Motion.animation(Motion.chewy), value: selected)
            }
        }
        // 등장: 링 중심에서 바깥으로 튀어나오며 커진다. 정지 상태는 scale 1·opacity 1.
        .scaleEffect(model.appeared ? 1 : OverlayMotion.tileFrom)
        .opacity(model.appeared ? 1 : 0)
        .animation(OverlayMotion.appearAnimation(appeared: model.appeared, index: index), value: model.appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot?.name ?? "빈 슬롯")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.run(index) }
    }
}
