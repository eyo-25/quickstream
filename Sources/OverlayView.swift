import SwiftUI

/// 숫자 글씨(조각 가장자리의 1~8)의 스타일. 오버레이와 설정 미리보기가 같은 곳을 읽어 서로 어긋나지 않게 한다.
enum OverlayMetrics {
    static let numberWeight = Font.Weight.regular

    /// 조각 가장자리 1~8 숫자의 글꼴
    static func wedgeNumberFont(size: CGFloat) -> Font {
        .system(size: size, weight: numberWeight, design: .default).monospacedDigit()
    }

    /// 글자색(본체 `ink`), 선택 조각 위에서만 선택 면 위 글자색(`selectedGlyph`: 포커스 색에서 알고리즘으로 정한다)
    static func wedgeNumberColor(selected: Bool, palette: PaletteColors) -> Color { selected ? palette.selectedGlyph : palette.ink }

    /// 제목(선택된 앱 이름: pie 위쪽·중앙 원, orbit 중앙·타일 아래 라벨)의 글꼴. 굵지 않은 SF Pro 에 아주 약한 자간을 줘 가볍고 깔끔하게 보인다.
    /// 오버레이와 설정 미리보기가 모두 여기서 읽는다.
    static let titleWeight = Font.Weight.medium
    static let labelWeight = Font.Weight.regular
    static let titleTracking: CGFloat = 0.3
    static func titleFont(size: CGFloat, weight: Font.Weight = titleWeight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// 네온 선택 면: 강조색 헤어라인 굵기와 호 선 굵기(얇게)
    static let neonRimWidth: CGFloat = 1.3
    static let neonLineWidth: CGFloat = 1.5

    /// 네온 선택 면에 얹는 강조색 그라데이션(위 → 아래로 살짝 짙게). 불투명도는 층(`WedgeLayers`/`TileLayers`)이 정한다(0 이면 투명).
    static func neonFace(accent: Color, top: Double, bottom: Double, center: UnitPoint, span: CGFloat) -> LinearGradient {
        LinearGradient(colors: [accent.opacity(top), accent.opacity(bottom)],
                       startPoint: UnitPoint(x: center.x, y: center.y - span), endPoint: UnitPoint(x: center.x, y: center.y + span))
    }

    /// 네온 선택 면의 강조색 헤어라인: 윗변·왼쪽 위가 더 밝은 방향성 그라데이션
    static func neonHairline(accent: Color, center: UnitPoint = .center, span: CGFloat = 0.5) -> LinearGradient {
        diagonal(top: 1.0, floor: 0.55, center: center, span: span, ink: accent)
    }

    /// 중앙 이름(orbit 중앙·pie `center`)의 글자 크기: 중앙 원 크기에 맞춰 12~30pt
    static func centerNameSize(hub: CGFloat) -> CGFloat { min(30, max(12, hub * 0.30)) }

    /// 중앙 이름의 **유효** 글자 크기. `setting` 0 은 자동(위 `centerNameSize` 와 같은 값).
    /// 직접 고른 값은 두 줄 높이(`size * 2.6`, `HubNameText` 프레임 높이 규칙)가 테두리 안쪽 지름(`2*(hub-border)-4`)을 넘지 않게
    /// 상한을 건다: 설정 창은 원 크기와 글자 크기를 따로 고르므로, 작은 원에 큰 글자를 골라도 원 밖으로 나가지 않아야 한다.
    /// 원이 너무 작아 최소값(10pt)도 못 맞추면 상한을 우선한다(범위 하한을 지키는 것보다 원 안에 머무는 것이 낫다).
    static func centerNameFontSize(hub: CGFloat, border: CGFloat, setting: Int) -> CGFloat {
        if setting == 0 { return centerNameSize(hub: hub) }
        let fit = max(0, (2 * (hub - border) - 4) / 2.6)
        return min(CGFloat(setting), fit)
    }

    /// 선택 변경 때 중앙 원 빛의 시간 곡선: 숨결처럼 올라가는 구간(0.18s 직선)과 더 긴 내려가는 구간(0.45s ease-out). 총 0.63s.
    static let hubPulseRise = 0.18
    static let hubPulseDuration = 0.63

    /// 빛의 피크 불투명도: 네온은 0.10, 플랫은 0.06(중앙 원판 배경이 살짝 숨 쉬는 정도 — 번쩍이지 않는다).
    static func hubPulsePeak(_ palette: PaletteColors) -> Double { palette.style == .neon ? 0.10 : 0.06 }

    /// 시작 후 `elapsed` 초의 빛 불투명도(0 → peak → 0). 범위 밖(시작 전·끝난 뒤)은 0.
    static func hubPulseOpacity(elapsed: Double, peak: Double) -> Double {
        guard elapsed > 0, elapsed < hubPulseDuration else { return 0 }
        if elapsed <= hubPulseRise { return peak * elapsed / hubPulseRise }
        let u = (elapsed - hubPulseRise) / (hubPulseDuration - hubPulseRise)
        return peak * (1 - u) * (1 - u)
    }

    /// 중앙 이름 폭: 원 반지름의 1.5배, 단 테두리 안쪽(지름 − 2×테두리 − 4)을 넘지 않게
    static func centerNameWidth(hub: CGFloat, border: CGFloat) -> CGFloat { min(hub * 1.5, 2 * (hub - border) - 4) }

    /// 조각 기본 채움(불투명 색; 설정 alpha 는 층 `WedgeLayers.face` 로 따로 곱한다). 플랫 선택 조각만 면 채움색(`flatFill`: 글자 대비 때문에 포커스 색을 살짝 보정한 값일 수 있다), 네온은 선택이어도 본체 면이다.
    static func wedgeFill(selected: Bool, hovered: Bool, palette: PaletteColors) -> Color {
        selected && palette.style == .flat ? palette.flatFill : (hovered ? palette.surfaceHover : palette.surface)
    }
    /// 글라스 헤어라인 굵기. 균일한 흰 테두리 대신 빛이 닿는 쪽만 얇게 밝다.
    static let hairlineWidth: CGFloat = 0.9

    /// 왼쪽 위(빛이 닿는 쪽)는 본체 `rim` 색이고 오른쪽 아래로 갈수록 옅어지는 방향성 헤어라인(다크 그레이·다크 글라스는 `rim` = 글자색). 그림자 쪽 끝도 0 이 아니라
    /// 본체의 하한(`hairlineFloor`)을 두어 어두운 바탕에서 윤곽이 사라지지 않게 한다. 기준은 `center`(UnitPoint)에서 ±`span` 만큼의 대각선이다(기본은 뷰 전체).
    /// `ink` 를 따로 주면(중앙 원의 `rimInk`) 그 색으로 칠한다.
    static func glassHairline(_ palette: PaletteColors, selected: Bool, strength: Double = 1, center: UnitPoint = .center, span: CGFloat = 0.5, ink: Color? = nil) -> LinearGradient {
        let boost = palette.spec.hairlineBoost
        return diagonal(top: (selected ? 0.85 : 0.55) * strength * boost, floor: palette.spec.hairlineFloor * strength, center: center, span: span, ink: ink ?? palette.rim)
    }

    /// 중앙 원 테두리(굵기는 `centerBorder` 설정): 균일한 띠가 아니라 같은 방향성 글라스 그라데이션
    static func hubHairline(_ palette: PaletteColors) -> LinearGradient {
        diagonal(top: 0.35 * palette.spec.hairlineBoost, floor: palette.spec.hairlineFloor, center: .center, span: 0.5, ink: palette.rimInk)
    }

    /// 유리 광택의 위쪽 글자색 불투명도 기본값(darkGray). 본체마다 `BodySpec.sheenTop` 으로 정한다.
    static let glassSheenTop = 0.07

    /// 위→아래로 아주 옅은 유리 광택(위쪽 `palette.spec.sheenTop` → 아래 투명). 색은 본체 `rim`.
    static func glassSheen(_ palette: PaletteColors, center: UnitPoint = .center, span: CGFloat = 0.5) -> LinearGradient {
        LinearGradient(colors: [palette.rim.opacity(palette.spec.sheenTop), palette.rim.opacity(0)],
                       startPoint: UnitPoint(x: center.x, y: center.y - span), endPoint: UnitPoint(x: center.x, y: center.y + span))
    }

    private static func diagonal(top: Double, floor: Double, center: UnitPoint, span: CGFloat, ink: Color) -> LinearGradient {
        LinearGradient(colors: [ink.opacity(top), ink.opacity(floor)],
                       startPoint: UnitPoint(x: center.x - span, y: center.y - span), endPoint: UnitPoint(x: center.x + span, y: center.y + span))
    }

    /// 중앙 원판 채움(조각과 같은 면 색 + 설정 alpha)
    static func hubFill(alpha: Double, palette: PaletteColors) -> Color { palette.surface.opacity(alpha * palette.spec.faceScale) }

    /// 중앙 원판의 포커스 글로우: 가까운 번짐 / 넓은 번짐 불투명도와 반경, 안쪽 가장자리 빛. 네온이면 `hubGlowNeonBoost` 배로 한 단계 더 강하다(플랫은 '살짝').
    static let hubGlowNear = 0.18
    static let hubGlowNearRadius: CGFloat = 10
    static let hubGlowFar = 0.10
    static let hubGlowFarRadius: CGFloat = 26
    static let hubInnerGlow = 0.10
    static let hubGlowNeonBoost = 1.6
    /// 불빛을 끄면 0(중앙 원 번짐·안쪽 빛이 아예 그려지지 않는다).
    static func hubGlowStrength(_ palette: PaletteColors) -> Double { palette.glow ? (palette.style == .neon ? hubGlowNeonBoost : 1) : 0 }
}

/// 클릭이 닿은 곳의 의미. `PieGeometry.clickTarget` 이 정하고 `OverlayModel.click` 이 수행한다.
enum ClickTarget: Equatable {
    case close
    case slot(Int)
    case selected
}

/// 방사형 파이의 순수 기하. 그리기·입력 판정·테스트가 같은 값을 쓴다.
/// 각도는 12시가 0, 시계 방향이 +. 링 중심이 원점이고 y 는 아래가 +.
/// 링 크기는 설정(`OverlayState.ringRadius/centerRadius`)이 정하고, 나머지는 모두 거기서 계산한다.
struct PieGeometry: Equatable {
    static let slots = 8
    static let step = 360.0 / Double(slots)
    /// 인접 조각 사이의 일정한 틈(평행한 두 변 사이 거리)
    static let gap: CGFloat = 9
    /// 중앙 원과 조각 안쪽 가장자리 사이 간격
    static let hubClearance: CGFloat = 16

    let outerRadius: CGFloat
    let hubRadius: CGFloat
    /// 중앙 원 테두리와 선택 호의 선 굵기(pt)
    let hubBorder: CGFloat

    /// 설정이 범위를 벗어나도(손으로 고친 파일 등) 그려지는 모양이 깨지지 않게 여기서 한 번 더 잡는다.
    /// 테두리는 중앙 원 반지름의 절반을 넘지 않는다(선이 원 중심을 침범하지 않게).
    init(ringRadius: Int, centerRadius: Int, centerBorder: Int = 4) {
        outerRadius = CGFloat(min(max(ringRadius, Limits.ringRange.lowerBound), Limits.ringRange.upperBound))
        let centerLimits = Limits.centerRange(ring: Int(outerRadius))
        hubRadius = CGFloat(min(max(centerRadius, centerLimits.lowerBound), centerLimits.upperBound))
        let borderLimit = max(Limits.centerBorderRange.lowerBound, min(Limits.centerBorderRange.upperBound, Int(hubRadius / 2)))
        hubBorder = CGFloat(min(max(centerBorder, Limits.centerBorderRange.lowerBound), borderLimit))
    }

    var innerRadius: CGFloat { hubRadius + Self.hubClearance }
    var thickness: CGFloat { outerRadius - innerRadius }
    /// 조각 안에서 아이콘이 놓이는 반지름(두께의 중간)
    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    /// 조각 두께에 맞춰 줄어드는 아이콘 크기
    var iconSize: CGFloat { min(56, thickness * 0.45) }
    /// 링이 그려지는 정사각 영역. 선택 조각이 튀어나오고 그림자가 번져도 잘리지 않도록 넉넉하다.
    var boxSize: CGFloat { outerRadius * 2 + 48 }

    /// 슬롯 1(index 0)이 12시 정중앙이고 시계 방향으로 45° 씩 진행하는 조각의 중심각(도)
    static func centerDegrees(index: Int) -> Double { Double(index) * step }

    /// 링 중심 기준 오프셋(y 아래가 +). 12시 시작, 시계 방향.
    static func offset(index: Int, radius: CGFloat) -> CGPoint {
        let a = centerDegrees(index: index) * Double.pi / 180
        return CGPoint(x: CGFloat(sin(a)) * radius, y: -CGFloat(cos(a)) * radius)
    }

    /// 방향(각도)만으로 정하는 슬롯: 슬롯 중심각 ±22.5° 섹터. 조각 사이 틈이어도 가장 가까운 조각이다.
    static func sector(dx: CGFloat, dy: CGFloat) -> Int {
        var degrees = atan2(Double(dx), Double(-dy)) * 180 / Double.pi
        if degrees < 0 { degrees += 360 }
        return Int((degrees / step).rounded()) % slots
    }

    /// 마우스 위치로 고르는 슬롯: 중앙 원 반지름 이상이면 화면 어디든(링 바깥 포함) 그 방향의 조각, 중앙 원 안은 nil.
    func directionIndex(dx: CGFloat, dy: CGFloat) -> Int? {
        isCenter(dx: dx, dy: dy) ? nil : Self.sector(dx: dx, dy: dy)
    }

    /// 중앙 원 안(경계 제외)인지. 여기서 클릭하면 오버레이를 닫는다.
    func isCenter(dx: CGFloat, dy: CGFloat) -> Bool {
        hypot(dx, dy) < hubRadius
    }

    /// 클릭으로 실행할 수 있는 슬롯: 링 영역(중앙 원 반지름 이상 ~ 링 바깥 반지름 이하)의 방향 조각. 그 밖은 nil.
    func clickIndex(dx: CGFloat, dy: CGFloat) -> Int? {
        let r = hypot(dx, dy)
        return r >= hubRadius && r <= outerRadius ? Self.sector(dx: dx, dy: dy) : nil
    }

    /// 클릭이 닿은 곳의 의미: 중앙 원 안 → 닫기, 링 영역(중앙 원 반지름 이상 ~ 바깥 반지름 이하) → 그 방향 조각,
    /// 링 밖 → 현재 선택된 조각(어느 조각인지는 모델이 안다).
    func clickTarget(dx: CGFloat, dy: CGFloat) -> ClickTarget {
        if isCenter(dx: dx, dy: dy) { return .close }
        return hypot(dx, dy) <= outerRadius ? .slot(Self.sector(dx: dx, dy: dy)) : .selected
    }

    /// 창 좌표의 점 → 링 중심 기준 좌표(y 아래가 +). 링 중심이 바뀌어도(디스플레이·표시 때마다) 같은 상대 위치는 같은 판정을 낳는다.
    static func relative(_ point: CGPoint, ringCenter: CGPoint) -> (dx: CGFloat, dy: CGFloat) {
        (point.x - ringCenter.x, point.y - ringCenter.y)
    }


    // MARK: 중앙 원의 선택 호

    /// `from` 에서 `to`(도)까지 가장 짧게 도는 부호 있는 각도 차: (-180, 180]
    static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// 현재 누적 각도에서 슬롯 `index` 의 중심각으로 최단 경로로 도착한 새 누적 각도
    static func accumulate(angle: Double, toIndex index: Int) -> Double {
        angle + shortestDelta(from: angle, to: centerDegrees(index: index))
    }

    /// 호 반폭(도): 조각 반폭에서 (호 반지름 위의 틈 각도 + 둥근 끝이 더 나가는 각도)를 뺀다.
    /// 그려진 호(끝 모양 포함)가 조각 사이 틈을 넘지 않고, 틈이 호에도 이어져 보인다. 테두리가 굵어도(12pt) 마찬가지다.
    var arcHalfSpan: Double {
        let gapAngle = asin(Double(Self.gap / 2 / hubBorderRadius)) * 180 / Double.pi
        let capAngle = asin(Double(hubBorder / 2 / hubBorderRadius)) * 180 / Double.pi
        return Self.step / 2 - gapAngle - capAngle
    }

    /// 조각 바깥 가장자리의 1~8 숫자 위치와 크기. 오버레이와 설정 미리보기가 같은 값을 쓴다.
    func numberPoint(index: Int) -> CGPoint {
        Self.offset(index: index, radius: outerRadius - max(11, thickness * 0.12))
    }

    var numberSize: CGFloat { min(13, thickness * 0.2) }

    /// 호의 (시작, 끝) 각도(도). `center` 는 누적 중심각.
    func arcRange(center: Double) -> (start: Double, end: Double) {
        (center - arcHalfSpan, center + arcHalfSpan)
    }

    /// 테두리 선의 중심 반지름: 선 바깥 가장자리가 중앙 원 반지름에 정확히 닿는다.
    var hubBorderRadius: CGFloat { hubRadius - hubBorder / 2 }

    /// 설정의 `overlay.radius`(슬라이더 범위)를 조각 모서리 반지름 2~18pt 로 선형 대응시킨다.
    static func cornerRadius(setting: Int) -> CGFloat {
        let range = Limits.radiusRange
        let t = Double(min(max(setting, range.lowerBound), range.upperBound) - range.lowerBound)
            / Double(range.upperBound - range.lowerBound)
        return CGFloat(2 + 16 * t)
    }
}

/// 중앙 원 테두리 위의 선택 호. 중심각(도)이 애니메이션 값이라 슬롯 사이를 연속으로 따라 돈다.
struct HubArc: Shape {
    var center: Double
    let geometry: PieGeometry

    var animatableData: Double {
        get { center }
        set { center = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let range = geometry.arcRange(center: center)
        let toScreen = { (degrees: Double) in degrees * Double.pi / 180 - Double.pi / 2 }
        var path = Path()
        path.addRelativeArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: geometry.hubBorderRadius,
            startAngle: .radians(toScreen(range.start)), delta: .radians((range.end - range.start) * Double.pi / 180))
        return path
    }
}

/// 환형 부채꼴 한 조각. 가장자리는 모서리 반지름만큼 안쪽으로 줄여 그려 두고,
/// 호출 측이 같은 색으로 `fill` + 두께 2×corner 의 둥근 `stroke` 를 겹치면 원래 크기에서 모서리가 둥글어진다.
/// 틈이 평행선이 되도록 옆변은 경계선에서 (gap/2 + corner) 만큼 떨어진 직선이다.
struct PieSlice: Shape {
    let index: Int
    let corner: CGFloat
    let geometry: PieGeometry

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let edge = Double(PieGeometry.gap / 2 + corner)
        let ri = Double(geometry.innerRadius + corner)
        let ro = Double(geometry.outerRadius - corner)
        let half = PieGeometry.step / 2 * Double.pi / 180
        let mid = PieGeometry.centerDegrees(index: index) * Double.pi / 180
        // 반지름 r 에서 옆변 위 점의 각도: 경계 광선에서 평행하게 edge 만큼 안쪽 → asin(edge / r) 만큼 회전
        func start(_ r: Double) -> Double { mid - half + asin(edge / r) - Double.pi / 2 }
        func end(_ r: Double) -> Double { mid + half - asin(edge / r) - Double.pi / 2 }
        func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: c.x + CGFloat(r * cos(a)), y: c.y + CGFloat(r * sin(a))) }

        var path = Path()
        path.move(to: point(ri, start(ri)))
        path.addLine(to: point(ro, start(ro)))
        path.addRelativeArc(center: c, radius: CGFloat(ro), startAngle: .radians(start(ro)), delta: .radians(end(ro) - start(ro)))
        path.addLine(to: point(ri, end(ri)))
        path.addRelativeArc(center: c, radius: CGFloat(ri), startAngle: .radians(end(ri)), delta: .radians(start(ri) - end(ri)))
        path.closeSubpath()
        return path
    }
}

/// 조각 하나의 배경: 채움(설정 alpha 적용) + 위→아래로 아주 옅은 유리 광택 + 왼쪽 위만 밝은 헤어라인 + 바깥 그림자.
/// 오버레이와 설정 미리보기가 같이 쓴다. 채움은 불투명으로 겹쳐 그린 뒤 한 장으로 투명도를 주고(겹친 띠가 진하게 비치지 않게),
/// 헤어라인은 alpha 와 무관하게 윤곽 안쪽 `hairlineWidth` 만큼만 그린다(채움 위로 덧칠해 얼룩지지 않게 채움 실루엣을 파낸다).
/// 포커스 색이 네온이면 선택 조각은 솔리드 채움 대신 "투명하게 빛난다": 본체 면 위에 강조색을 아주 옅게 얹고, 강조색 헤어라인·안쪽 번짐·바깥 글로우를 더한다.
struct WedgeBackground: View {
    let index: Int
    let corner: CGFloat
    let geometry: PieGeometry
    let selected: Bool
    let hovered: Bool
    let alpha: Double
    let palette: PaletteColors

    private var shape: PieSlice { PieSlice(index: index, corner: corner, geometry: geometry) }
    private var band: CGFloat { corner * 2 }
    /// 빛의 방향(왼쪽 위 → 오른쪽 아래)은 링 전체가 아니라 조각 자신의 가운데를 기준으로 잡는다
    private var light: (center: UnitPoint, span: CGFloat) {
        let box = geometry.boxSize
        let mid = PieGeometry.offset(index: index, radius: geometry.midRadius)
        return (UnitPoint(x: (box / 2 + mid.x) / box, y: (box / 2 + mid.y) / box), geometry.thickness * 0.6 / box)
    }

    private func silhouette<S: ShapeStyle>(_ width: CGFloat, _ style: S) -> some View {
        ZStack {
            shape.fill(style)
            shape.stroke(style, style: StrokeStyle(lineWidth: width, lineJoin: .round))
        }
    }

    /// 윤곽 안쪽 `inner` 폭 만큼 파낸 고리(채움 위로 덧칠해 얼룩지지 않게)
    private func ring<S: ShapeStyle>(_ style: S, inner: CGFloat) -> some View {
        silhouette(band, style)
            .mask {
                Rectangle().padding(-40)
                    .overlay { silhouette(inner, Color.black).blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }

    @ViewBuilder
    var body: some View {
        if palette.style == .neon { neonBody } else { flatBody }
    }

    /// 플랫: 선택 조각은 포커스 색으로 채운다(글자는 `selectedGlyph`). 본체가 유리(`faceBacking` > 0)면 면 아래에 검은 받침을 깔아 밝은 바탕에서도 글자를 받친다.
    private var flatBody: some View {
        let line = OverlayMetrics.hairlineWidth
        let (center, span) = light
        let layers = palette.wedgeLayers(alpha: alpha, sel: selected ? 1 : 0)
        return ZStack {
            if let plate = palette.plate { silhouette(band, plate) }
            if palette.spec.faceBacking > 0 {
                silhouette(band - 2 * line, Color.black).compositingGroup().opacity(layers.underlay)
            }
            ZStack {
                silhouette(band - 2 * line, OverlayMetrics.wedgeFill(selected: selected, hovered: hovered, palette: palette))
                // 광택은 윤곽 없이 그라데이션 한 장을 불투명 실루엣으로 잘라 낸다. 채움과 선을 따로 칠하면 겹치는 안쪽 띠가 윤곽처럼 비친다.
                Rectangle()
                    .fill(OverlayMetrics.glassSheen(palette, center: center, span: span))
                    .mask { silhouette(band - 2 * line, Color.black) }
            }
            .compositingGroup()
            .opacity(layers.face)
            ring(OverlayMetrics.glassHairline(palette, selected: selected, center: center, span: span), inner: band - 2 * line)
        }
        .background { pieOutsideShadow(silhouette(band, Color.black)) }
    }

    /// 네온: 선택 여부는 분기가 아니라 `sel`(0/1)로 불투명도에 실어 보낸다(분기가 바뀌면 뷰 정체성이 바뀌어 선택 스프링이 페이드로 변한다).
    /// 층별 불투명도는 `PaletteColors.wedgeLayers` 가 정한다(글자 대비 모델과 같은 값).
    private var neonBody: some View {
        let line = OverlayMetrics.hairlineWidth
        let face = band - 2 * line
        let sel: Double = selected ? 1 : 0
        let (center, span) = light
        let layers = palette.wedgeLayers(alpha: alpha, sel: sel)
        return ZStack {
            // 면 아래 받침: 본체 유리의 약한 받침, 선택되면 밝은 바탕에서도 밝은 글자가 읽히게 진해진다(alpha 와 무관)
            if let plate = palette.plate { silhouette(band, plate) }
            silhouette(face, Color.black).compositingGroup().opacity(layers.underlay)
            ZStack {
                silhouette(face, OverlayMetrics.wedgeFill(selected: false, hovered: hovered, palette: palette))
                Rectangle()
                    .fill(OverlayMetrics.glassSheen(palette, center: center, span: span))
                    .mask { silhouette(face, Color.black) }
                // 본체 면 위에 강조색을 아주 옅게(위 → 아래 살짝 짙게)
                Rectangle()
                    .fill(OverlayMetrics.neonFace(accent: palette.accent, top: layers.accentTop, bottom: layers.accentBottom, center: center, span: span))
                    .mask { silhouette(face, Color.black) }
            }
            .compositingGroup()
            .opacity(layers.face)
            if palette.glow {
                NeonInnerGlow(color: palette.accent, amount: 0.25 * sel) { d in silhouette(max(face - 2 * d, 0), Color.black) }
            }
            ring(OverlayMetrics.glassHairline(palette, selected: false, center: center, span: span), inner: face)
            ring(OverlayMetrics.neonHairline(accent: palette.accent, center: center, span: span), inner: band - 2 * OverlayMetrics.neonRimWidth)
                .opacity(sel)
        }
        .background {
            ZStack {
                if palette.glow { neonOutsideGlow(silhouette(band, Color.black), color: palette.accent.opacity(sel)) }
                pieOutsideShadow(silhouette(band, Color.black))
            }
        }
    }
}

/// 반투명 도형 아래에 그림자가 깔리면 안쪽이 얼룩져 보인다. 도형 바깥쪽만 남도록 실루엣으로 파낸다.
func pieOutsideShadow<S: View>(_ silhouette: S, opacity: Double = 0.3) -> some View {
    silhouette
        .shadow(color: .black.opacity(opacity), radius: 8, y: 3)
        .mask {
            Rectangle().padding(-40)
                .overlay { silhouette.blendMode(.destinationOut) }
                .compositingGroup()
        }
}

/// 바깥 번짐: 실루엣 바깥쪽에만 강조색 이중 글로우(가까운 것 + 넓은 것)를 둔다(면 아래로 비쳐 면을 꽉 채우지 않게 안쪽은 파낸다).
func outsideGlow<S: View>(_ silhouette: S, color: Color, near: Double, nearRadius: CGFloat, far: Double, farRadius: CGFloat) -> some View {
    silhouette
        .shadow(color: color.opacity(near), radius: nearRadius)
        .shadow(color: color.opacity(far), radius: farRadius)
        .mask {
            Rectangle().padding(-60)
                .overlay { silhouette.blendMode(.destinationOut) }
                .compositingGroup()
        }
}

/// 네온 선택 면의 바깥 번짐(강하게)
func neonOutsideGlow<S: View>(_ silhouette: S, color: Color) -> some View {
    outsideGlow(silhouette, color: color, near: 0.50, nearRadius: 6, far: 0.28, farRadius: 20)
}

/// 중앙 원판 뒤: 포커스 색의 은은한 바깥 글로우 + 바깥 그림자. 오버레이(pie·orbit)와 설정 미리보기가 함께 쓴다.
/// 글로우는 배경 레이어라 클릭 판정에 영향이 없고, 바닥판 실루엣(원판) 바깥으로만 번진다.
func hubBackdrop(size: CGFloat, palette: PaletteColors) -> some View {
    let k = OverlayMetrics.hubGlowStrength(palette)
    let disc = Circle().fill(Color.black).frame(width: size, height: size)
    return ZStack {
        // 불빛이 꺼지면 포커스 색 번짐만 빠지고, 가독성용 검은 그림자는 남는다.
        if k > 0 {
            outsideGlow(disc, color: palette.accent, near: OverlayMetrics.hubGlowNear * k, nearRadius: OverlayMetrics.hubGlowNearRadius,
                        far: OverlayMetrics.hubGlowFar * k, farRadius: OverlayMetrics.hubGlowFarRadius)
        }
        pieOutsideShadow(disc)
    }
}

/// 중앙 원판 안쪽 가장자리의 아주 옅은 포커스 색 빛(가장자리 `hubInnerGlow` → 안쪽 0). 원판 면 바로 위, 테두리 아래에 둔다.
@ViewBuilder
func hubInnerGlow(palette: PaletteColors) -> some View {
    if palette.glow {
        NeonInnerGlow(color: palette.accent, amount: OverlayMetrics.hubInnerGlow * OverlayMetrics.hubGlowStrength(palette)) { d in
            Circle().inset(by: d).fill(Color.black)
        }
    }
}

/// 중앙 원 빛 입력. 오버레이는 `live`(선택이 바뀔 때마다 처음부터), 설정 미리보기는 `off`(정적), 시험 렌더는 `frozen`(그 경과 시간의 정지 프레임).
enum HubPulseSource: Equatable {
    case off
    case live(Int)
    case frozen(Double)
}

/// 선택이 바뀔 때 중앙 원판 면 안쪽에 한 번 은은하게 번졌다 사라지는 포커스 색 방사형 빛. 원판 테두리(`border`) 안쪽 면에만 그려져
/// 테두리·바깥으로 번지지 않는다. 빛이 없을 때(불투명도 0, 동작 줄이기, `off`)는 층을 아예 그리지 않아 정적 렌더가 그대로다. 글자 아래, 테두리 아래에 둔다.
struct HubPulseGlow: View {
    let palette: PaletteColors
    let source: HubPulseSource
    /// 중앙 원 테두리 굵기(pt): 빛은 이만큼 안쪽 면에만 칠한다
    let border: CGFloat

    /// 불빛이 꺼졌거나 동작 줄이기면 층을 아예 그리지 않는다(`live` 의 키프레임 애니메이터도 만들지 않는다).
    static func isActive(palette: PaletteColors, reduced: Bool) -> Bool { palette.glow && !reduced }

    var body: some View {
        let peak = OverlayMetrics.hubPulsePeak(palette)
        switch source {
        case .off:
            EmptyView()
        case .frozen(let elapsed):
            if palette.glow {
                Self.glow(palette: palette, opacity: OverlayMetrics.hubPulseOpacity(elapsed: elapsed, peak: peak), border: border)
            }
        case .live(let trigger):
            if Self.isActive(palette: palette, reduced: Motion.reduced) {
                // 값 = 시작 후 경과 시간. 곡선은 `hubPulseOpacity` 한 곳에서만 정의한다.
                Color.clear.keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, elapsed in
                    Self.glow(palette: palette, opacity: OverlayMetrics.hubPulseOpacity(elapsed: elapsed, peak: peak), border: border)
                } keyframes: { _ in
                    // 트리거마다 0 으로 되돌린 뒤 재생한다(진행 중에 다시 트리거돼도 현재 값에서 이어지지 않고 처음부터).
                    KeyframeTrack {
                        MoveKeyframe(0.0)
                        LinearKeyframe(OverlayMetrics.hubPulseDuration, duration: OverlayMetrics.hubPulseDuration)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 키프레임 콘텐츠 클로저는 메인 액터 밖(nonisolated)에서 불리므로, 인스턴스 메서드가 아닌 `nonisolated` 정적 함수로 둔다
    /// (View 안의 멤버는 메인 액터로 추론돼 그 클로저에서 부르면 격리 경고가 난다. Swift 6 모드에선 오류다).
    @ViewBuilder nonisolated private static func glow(palette: PaletteColors, opacity: Double, border: CGFloat) -> some View {
        if opacity > 0 {
            // 가운데가 가장 밝고 가장자리로 갈수록 거의 0 이 된다(가장자리 띠가 번쩍이지 않게). 테두리 안쪽 원으로만 그리고,
            // 호출 측에서 글자·테두리 아래에 놓인다.
            Circle().inset(by: border)
                .fill(EllipticalGradient(colors: [palette.accent.opacity(opacity), palette.accent.opacity(opacity * 0.1)],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                .allowsHitTesting(false)
        }
    }
}

/// 네온 안쪽 가장자리 번짐: 윤곽에서 안쪽으로 4단계(1.2pt 간격)로 옅어지는 강조색. blur 없이 같은 모양을 안쪽으로 줄여 가며 파낸 고리를 겹친다.
/// `silhouette(d)` 는 윤곽을 d 만큼 안쪽으로 줄인 불투명 실루엣을 돌려준다. `amount` 는 가장자리에서의 총 불투명도.
struct NeonInnerGlow<S: View>: View {
    let color: Color
    let amount: Double
    let silhouette: (CGFloat) -> S

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { k in
                Rectangle().fill(color)
                    .mask { silhouette(0) }
                    .mask {
                        Rectangle().padding(-20)
                            .overlay { silhouette(CGFloat(k + 1) * 1.2).blendMode(.destinationOut) }
                            .compositingGroup()
                    }
                    .opacity(amount / 4)
            }
        }
    }
}

/// 중앙 원 안의 선택된 이름(글자만, 최대 2줄). orbit 중앙과 pie 의 `center` 이름이 같이 쓴다.
/// 이름이 바뀔 때 아래에서 위로 밀리며 교차 페이드하고, 길면 `minimumScaleFactor` 로 줄인다.
struct HubNameText: View {
    let hub: CGFloat
    let border: CGFloat
    let width: CGFloat
    let name: String?
    let nameID: String
    let ink: Color
    /// 글자 굵기와 크기 설정(크기 0 = 자동). 오버레이와 설정 미리보기가 같은 값을 넘긴다.
    var weight: NameWeight = .medium
    var sizeSetting = 0
    var animated = false

    var body: some View {
        let nameSize = OverlayMetrics.centerNameFontSize(hub: hub, border: border, setting: sizeSetting)
        return ZStack {
            Text(name ?? "빈 슬롯")
                .font(OverlayMetrics.titleFont(size: nameSize, weight: weight.fontWeight))
                .tracking(OverlayMetrics.titleTracking)
                .foregroundColor(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .id(nameID)
                .transition(.asymmetric(
                    insertion: AnyTransition.offset(y: 12).combined(with: .opacity),
                    removal: AnyTransition.offset(y: -12).combined(with: .opacity)))
        }
        .frame(width: width, height: nameSize * 2.6)
        .animation(animated ? Motion.animation(Motion.chewy) : nil, value: nameID)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

extension NameWeight {
    /// 굵기 설정 → SwiftUI 굵기. 오버레이·미리보기가 같은 표를 읽는다(`medium` 이 기존 `titleWeight`).
    var fontWeight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// 이름을 어디에 보여 줄지(순수 규칙). orbit 은 이름이 항상 중앙이라 위치 설정을 무시한다.
enum OverlayNameLayout {
    static func showsTopName(theme: OverlayTheme, placement: OverlayNamePlacement) -> Bool { theme == .pie && placement == .top }
    static func showsCenterName(theme: OverlayTheme, placement: OverlayNamePlacement) -> Bool {
        theme == .orbit || (theme == .pie && placement == .center)
    }
}

extension OverlayState {
    var showsTopName: Bool { OverlayNameLayout.showsTopName(theme: theme, placement: namePlacement) }
    var showsCenterName: Bool { OverlayNameLayout.showsCenterName(theme: theme, placement: namePlacement) }
}

/// 이름 라벨: 흰 글씨(그림자 한 겹) 뒤에 은은한 어두운 유리 캡슐. 밝은 배경(브라우저·문서·Finder)에서도 읽히게 하려는 것이다.
/// 캡슐은 글자 길이에 맞춰 줄고, `maxWidth`(캡슐 전체 폭)를 넘으면 글자를 말줄임한다.
struct GlassCapsuleText: View {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4

    let text: String
    let fontSize: CGFloat
    var weight: Font.Weight = OverlayMetrics.titleWeight
    let maxWidth: CGFloat
    let palette: PaletteColors

    var body: some View {
        Text(text)
            .font(OverlayMetrics.titleFont(size: fontSize, weight: weight))
            .tracking(OverlayMetrics.titleTracking)
            .foregroundColor(palette.ink)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: max(maxWidth - 2 * Self.horizontalPadding, 0))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background {
                Capsule()
                    .fill(palette.capsule.opacity(0.45))
                    .overlay(Capsule().strokeBorder(OverlayMetrics.glassHairline(palette, selected: false, strength: 0.8), lineWidth: OverlayMetrics.hairlineWidth))
            }
    }
}

extension View {
    /// 네온 스타일의 형광 발광: 강조색 이중 글로우(가까운 것 + 넓은 것). `strength` 가 0 이면 아무것도 덧붙이지 않는다(플랫은 픽셀이 그대로다).
    /// 글로우는 모양 밖으로 번지지만 그리기만 할 뿐이라 클릭 판정에는 영향이 없다(시각 레이어는 모두 `allowsHitTesting(false)`).
    @ViewBuilder
    func neonGlow(_ color: Color, strength: Double) -> some View {
        if strength > 0 {
            shadow(color: color.opacity(0.50 * strength), radius: 6)
                .shadow(color: color.opacity(0.28 * strength), radius: 20)
        } else {
            self
        }
    }
}

extension OverlayState {
    /// 본체·포커스 스타일·포커스 색·글라스 틴트를 합성한 색: 오버레이가 색을 읽는 한 곳
    var colors: PaletteColors { PaletteColors.make(body: bodyTheme, style: focusStyle, hex: focusHex, solid: solidBacking, glassTint: glassTintHex, glow: focusGlow) }
}

extension PieGeometry {
    /// 두 테마가 같은 판정 기하(방향 섹터·중앙 원·링 영역)를 쓰므로 상태에서 한 곳으로 만든다.
    init(state: OverlayState) {
        self.init(ringRadius: state.ringRadius, centerRadius: state.centerRadius, centerBorder: state.centerBorder)
    }
}

extension OverlayMotion {
    /// 등장 애니메이션: 올라가는 방향(appeared == true)에만 스프링을 건다. 내리는 방향은 창이 투명할 때 즉시 일어난다.
    static func appearAnimation(appeared: Bool, index: Int = 0, step: Double = appearStep) -> Animation? {
        appeared ? Motion.animation(Motion.staggered(Motion.chewy, index: index, step: step)) : nil
    }

    /// 탭이 바뀔 때: 이전 타일은 축소·페이드로 빠지고 새 타일이 차례로 튀어 오른다.
    static func tabTransition(index: Int) -> AnyTransition {
        let insert = Motion.animation(Motion.staggered(Motion.chewy, index: index, step: tabStep))
        return .asymmetric(
            insertion: AnyTransition.scale(scale: tileFrom).combined(with: .opacity).animation(insert),
            removal: AnyTransition.scale(scale: 0.8).combined(with: .opacity).animation(Motion.animation(Motion.exit))
        )
    }
}

/// 반투명은 조각·중앙 원판의 배경색 alpha 로만 만든다. 아이콘·글자·`+` 에는 영구 opacity/블러를 쓰지 않는다.
/// 아래의 `.opacity(appeared ? 1 : 0)` 등은 등장·전환 순간에만 0 이 되고, 정지 상태(appeared == true)에서는 항상 1 이다.
///
/// 창은 디스플레이 전체를 덮는다. 눈에는 투명하지만 거의 보이지 않는 채움을 깔아 마우스 입력을 흡수하고(클릭이 아래 창으로
/// 새지 않게), 링은 모델이 알려 주는 `ringCenter` 에 그린다. 애니메이션은 창이 아니라 링 중심을 앵커로 한다.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    /// 상태의 색(상태가 없으면 `PaletteColors.standard` 임시 색). 모양 테마와 독립이다.
    private var palette: PaletteColors { model.state?.colors ?? PaletteColors.standard }
    private var showNumbers: Bool { model.state?.showNumbers ?? true }

    var body: some View {
        Group {
            if let state = model.state, let tab = model.tab {
                GeometryReader { proxy in
                    panel(state: state, tab: tab, size: proxy.size)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: model.epoch) { replayAppear() }
    }

    // MARK: 등장

    /// 등장 애니메이션: 올라가는 방향(appeared == true)에만 스프링을 건다. 내리는 방향은 창이 투명할 때 즉시 일어난다.
    private func appearAnim(_ index: Int = 0, step: Double = OverlayMotion.appearStep) -> Animation? {
        OverlayMotion.appearAnimation(appeared: model.appeared, index: index, step: step)
    }

    /// present() 가 appeared 를 false 로 내려 둔 상태에서 올린다. 실제 움직임은 각 요소의 `.animation(_, value: appeared)` 가 담당.
    private func replayAppear() {
        model.appeared = true
    }

    private func panel(state: OverlayState, tab: TabView, size: CGSize) -> some View {
        let geometry = PieGeometry(state: state)
        let corner = PieGeometry.cornerRadius(setting: state.radius)
        let center = model.ringCenter
        let current = model.selected < tab.slots.count ? tab.slots[model.selected] : nil
        let nameSize = min(34, max(22, geometry.outerRadius * 0.12))
        return ZStack(alignment: .topLeading) {
            inputLayer(geometry: geometry)

            ZStack(alignment: .topLeading) {
                switch state.theme {
                case .pie:
                    if state.showsTopName {
                        nameLabel(current, fontSize: nameSize)
                            .frame(width: size.width, height: nameSize * 1.5)
                            .position(x: center.x, y: center.y - geometry.outerRadius - max(30, nameSize * 1.4))
                    }
                    ring(tab: tab, alpha: state.alpha, corner: corner, geometry: geometry)
                        .position(center)
                case .orbit:
                    // 조작·입력·창 덮기는 위의 공통 경로를 그대로 쓰고, 그리기만 다르다(이름은 중앙 원판 안에 있다)
                    OrbitScene(model: model, tab: tab, state: state)
                        .position(center)
                }
            }
            .frame(width: size.width, height: size.height)
            // 사라질 때의 살짝 축소도 창 전체가 아니라 링 중심 기준이다
            .scaleEffect(model.leaving ? OverlayMotion.panelLeaving : 1,
                         anchor: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)))
            .animation(model.leaving ? Motion.animation(Motion.exit) : nil, value: model.leaving)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: 입력

    private func relative(_ point: CGPoint) -> (dx: CGFloat, dy: CGFloat) {
        PieGeometry.relative(point, ringCenter: model.ringCenter)
    }

    /// 창 전체를 덮는 입력층. 알파 0 이면 창 서버가 클릭을 아래 창으로 통과시키므로 눈에 안 띄는 값(≈2%)으로 채운다.
    /// 마우스는 화면 어디서든 방향으로 조각을 고른다. 클릭은 `PieGeometry.clickTarget` 규칙을 따른다:
    /// 중앙 원 → 닫기, 링 영역 → 그 방향 조각 실행, 링 밖 → 현재 선택된 조각 실행.
    /// 이 층만 클릭을 받도록 위의 시각 레이어(링·허브·이름)는 모두 `allowsHitTesting(false)` 다.
    private func inputLayer(geometry: PieGeometry) -> some View {
        Color.black.opacity(0.02)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let p = relative(location)
                    let index = geometry.directionIndex(dx: p.dx, dy: p.dy)
                    if model.hovered != index { model.hovered = index }
                    // 커서가 실제로 움직였을 때만 선택을 바꾼다(키보드 선택을 되돌리지 않게)
                    if model.hoverGate.shouldSelect(at: location), let index, model.selected != index { model.selected = index }
                case .ended:
                    if model.hovered != nil { model.hovered = nil }
                }
            }
            .gesture(pressGesture(geometry: geometry))
    }

    /// 제스처는 눌린 곳·현재 위치가 어느 영역인지만 알려 주고, 눌림 표시와 실행 규칙은 모델이 정한다(창 없이 테스트할 수 있게).
    private func pressGesture(geometry: PieGeometry) -> some Gesture {
        func target(at point: CGPoint) -> ClickTarget {
            let p = relative(point)
            return geometry.clickTarget(dx: p.dx, dy: p.dy)
        }
        return DragGesture(minimumDistance: 0)
            .onChanged { drag in model.pointerChanged(start: target(at: drag.startLocation), current: target(at: drag.location)) }
            .onEnded { drag in model.pointerReleased(start: target(at: drag.startLocation), end: target(at: drag.location)) }
    }

    // MARK: 이름

    /// 선택된 슬롯의 이름만 링 위에 크게. 바뀔 때 아래에서 위로 살짝 밀리며 교차 페이드한다.
    private func nameLabel(_ current: SlotView?, fontSize: CGFloat) -> some View {
        ZStack {
            GlassCapsuleText(text: current?.name ?? "빈 슬롯", fontSize: fontSize, maxWidth: 560, palette: palette)
                .id(current?.id ?? "empty")
                .transition(.asymmetric(
                    insertion: AnyTransition.offset(y: 12).combined(with: .opacity),
                    removal: AnyTransition.offset(y: -12).combined(with: .opacity)))
        }
        .animation(model.appeared ? Motion.animation(Motion.chewy) : nil, value: current?.id)
        .opacity(model.appeared ? 1 : 0)
        .animation(model.appeared ? Motion.animation(.easeOut(duration: 0.12).delay(0.08)) : nil, value: model.appeared)
    }

    // MARK: 링

    private func ring(tab: TabView, alpha: Double, corner: CGFloat, geometry: PieGeometry) -> some View {
        ZStack {
            ForEach(0..<PieGeometry.slots, id: \.self) { i in
                slotContainer(index: i, tab: tab, alpha: alpha, corner: corner, geometry: geometry)
                    .zIndex(i == model.selected ? 1 : 0)
            }

            hub(alpha: alpha, geometry: geometry)
                .scaleEffect(model.appeared ? 1 : OverlayMotion.hubFrom)
                .animation(appearAnim(), value: model.appeared)
        }
        .frame(width: geometry.boxSize, height: geometry.boxSize)
    }

    // MARK: 슬롯

    /// 슬롯 자리. 탭이 바뀌면 내용의 id 가 바뀌어 이전 조각은 빠지고 새 조각이 차례로 오른다(자리 컨테이너는 그대로).
    private func slotContainer(index: Int, tab: TabView, alpha: Double, corner: CGFloat, geometry: PieGeometry) -> some View {
        let slot = index < tab.slots.count ? tab.slots[index] : nil
        return ZStack {
            slotView(index: index, slot: slot, alpha: alpha, corner: corner, geometry: geometry)
                .id("\(tab.id)#\(index)")
                .transition(OverlayMotion.tabTransition(index: index))
        }
        .frame(width: geometry.boxSize, height: geometry.boxSize)
        .animation(model.appeared ? Motion.animation(Motion.soft) : nil, value: model.tabIndex)
    }

    private func slotView(index: Int, slot: SlotView?, alpha: Double, corner: CGFloat, geometry: PieGeometry) -> some View {
        let selected = index == model.selected
        let hovered = model.hovered == index
        let pressed = model.confirming == index || model.pressedSlot == index
        let mid = PieGeometry.offset(index: index, radius: geometry.midRadius)
        let out = PieGeometry.offset(index: index, radius: OverlayMotion.selectedPop)
        let half = geometry.boxSize / 2
        // 1~8 숫자 키 단축키를 조각 바깥 가장자리에 작게 보여 준다
        let numberPoint = geometry.numberPoint(index: index)
        let numberSize = geometry.numberSize
        // 눌림·선택 확대의 중심은 링 중심이 아니라 조각 자신의 가운데다
        let anchor = UnitPoint(x: (half + mid.x) / geometry.boxSize, y: (half + mid.y) / geometry.boxSize)
        return ZStack {
            WedgeBackground(index: index, corner: corner, geometry: geometry, selected: selected, hovered: hovered, alpha: alpha, palette: palette)
                .animation(Motion.animation(Motion.snap), value: selected)
                .animation(Motion.animation(Motion.snap), value: hovered)

            tileBody(slot: slot, selected: selected, iconSize: geometry.iconSize)
                .offset(x: mid.x, y: mid.y)

            if showNumbers, !model.keyLabel(index).isEmpty {
                Text(model.keyLabel(index))
                    .font(OverlayMetrics.wedgeNumberFont(size: numberSize))
                    .foregroundColor(OverlayMetrics.wedgeNumberColor(selected: selected, palette: palette))
                    .offset(x: numberPoint.x, y: numberPoint.y)
                    .animation(Motion.animation(Motion.snap), value: selected)
            }
        }
        .scaleEffect(selected ? OverlayMotion.selectedScale : 1, anchor: anchor)
        .offset(x: selected ? out.x : 0, y: selected ? out.y : 0)
        .animation(Motion.animation(Motion.chewy), value: selected)
        .scaleEffect(pressed ? OverlayMotion.pressScale : 1, anchor: anchor)
        .animation(Motion.animation(Motion.snap), value: pressed)
        // 등장: 링 중심에서 바깥으로 튀어나오며 커진다. 정지 상태는 scale 1·opacity 1.
        .scaleEffect(model.appeared ? 1 : OverlayMotion.tileFrom)
        .opacity(model.appeared ? 1 : 0)
        .animation(appearAnim(index), value: model.appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot?.name ?? "빈 슬롯")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.run(index) }
    }

    /// 조각 안에는 아이콘만. 아이콘이 없는 액션은 약어, 빈 슬롯은 `+`. 선택되면 글자·기호는 어둡게.
    private func tileBody(slot: SlotView?, selected: Bool, iconSize: CGFloat) -> some View {
        let icon = slot.flatMap { model.icons[$0.id] }
        return ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .transition(.opacity)
            } else if let slot {
                Text(slot.label)
                    .font(.system(size: iconSize * 0.6, weight: .bold))
                    .foregroundColor(selected ? palette.selectedGlyph : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: iconSize * 1.5)
                    .transition(.opacity)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: iconSize * 0.8, weight: .medium))
                    .foregroundColor(selected ? palette.selectedGlyph : palette.ink)
                    .transition(.opacity)
            }
        }
        // 아이콘이 뒤늦게 도착해 약어 → 아이콘으로 바뀔 때 크로스페이드
        .animation(model.appeared ? Motion.animation(.easeInOut(duration: 0.18)) : nil, value: icon != nil)
        .animation(Motion.animation(Motion.snap), value: selected)
    }

    // MARK: 중앙

    /// 글자·아이콘·장식 없는 중앙 원판(조각과 같은 채움 규칙). 테두리 위에 선택 조각 방향의 구간만 강조색으로 칠한다.
    /// 이름 위치가 `center` 이면 선택된 이름만 글자로 보여 준다(orbit 중앙과 같은 스타일).
    private func hub(alpha: Double, geometry: PieGeometry) -> some View {
        let size = geometry.hubRadius * 2
        let neon = palette.style == .neon
        let current = model.tab.flatMap { model.selected < $0.slots.count ? $0.slots[model.selected] : nil }
        return ZStack {
            if let plate = palette.plate { Circle().fill(plate) }
            if palette.spec.faceBacking > 0 {
                Circle().fill(Color.black.opacity(palette.spec.faceBacking * alpha))
            }
            Circle().fill(OverlayMetrics.hubFill(alpha: alpha, palette: palette))
            hubInnerGlow(palette: palette)
            HubPulseGlow(palette: palette, source: .live(model.hubPulse), border: geometry.hubBorder)
            Circle().strokeBorder(OverlayMetrics.hubHairline(palette), lineWidth: geometry.hubBorder)
            if model.state?.showsCenterName == true {
                HubNameText(hub: geometry.hubRadius, border: geometry.hubBorder, width: OverlayMetrics.centerNameWidth(hub: geometry.hubRadius, border: geometry.hubBorder),
                            name: current?.name, nameID: current?.id ?? "empty", ink: palette.ink,
                            weight: model.state?.centerNameWeight ?? .medium, sizeSetting: model.state?.centerNameSize ?? 0, animated: model.appeared)
            }
            HubArc(center: model.arcAngle, geometry: geometry)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: neon ? OverlayMetrics.neonLineWidth : geometry.hubBorder, lineCap: .round))
                .neonGlow(palette.accent, strength: palette.glowStrength)
                .animation(model.appeared ? Motion.animation(Motion.chewy) : nil, value: model.arcAngle)
        }
        .frame(width: size, height: size)
        .background { hubBackdrop(size: size, palette: palette) }
    }
}
