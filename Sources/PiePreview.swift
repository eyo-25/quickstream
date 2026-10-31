import SwiftUI

/// 미리보기에 넘기는 모양 값. draft 의 오버레이 설정을 그대로 옮겨, 슬라이더가 곧바로 미리보기에 반영된다.
struct PiePreviewStyle: Equatable {
    var alpha: Double
    /// `overlay.radius` 설정값(조각 모서리 pt 로의 변환은 오버레이와 같은 `PieGeometry.cornerRadius(setting:)`)
    var cornerSetting: Int
    var ringSize: Int
    var centerSize: Int
    var centerBorder: Int
    /// 본체 색 테마(모양 테마와 독립) / 포커스 스타일 / 포커스 색(`#RRGGBB`)
    var bodyTheme: OverlayBody
    /// 클리어 글라스 본체의 틴트 색(`#RRGGBB`)
    var glassTintHex: String
    var focusStyle: FocusStyle
    var focusHex: String
    /// 앱 이름 위치(pie 전용: center 면 중앙 원 안에 선택된 이름) 와 1~8 숫자 표시 여부, orbit 타일 아래 이름 표시 여부
    var namePlacement: OverlayNamePlacement
    var showNumbers: Bool
    var showTileLabels: Bool
    /// 앱 박스·중앙 원 뒤 불투명 바닥판
    var solidBacking: Bool
    /// 중앙 원 이름 글자 굵기·크기(pt; 0 = 자동). 오버레이와 같은 `HubNameText` 가 읽는다.
    var centerNameWeight: NameWeight
    var centerNameSize: Int
    /// 포커스 색 불빛(번짐·글로우) 표시 여부. 끄면 미리보기도 오버레이처럼 번짐이 없다.
    var focusGlow: Bool

    /// 본체·포커스를 합성한 색(미리보기가 읽는 한 곳)
    var colors: PaletteColors { PaletteColors.make(body: bodyTheme, style: focusStyle, hex: focusHex, solid: solidBacking, glassTint: glassTintHex, glow: focusGlow) }

    /// 크기(ringSize·centerSize·centerBorder)는 설정의 현재 테마 값(`OverlaySettings.sizes`)을 읽는다. 테마별로 각자 가진 값이다.
    init(_ overlay: OverlaySettings) {
        alpha = overlay.alpha
        cornerSetting = overlay.radius
        ringSize = overlay.ringSize
        centerSize = overlay.centerSize
        centerBorder = overlay.centerBorder
        bodyTheme = overlay.bodyTheme
        glassTintHex = overlay.glassTintHex
        focusStyle = overlay.focusStyle
        focusHex = overlay.focusHex
        namePlacement = overlay.namePlacement
        showNumbers = overlay.showNumbers
        showTileLabels = overlay.showTileLabels
        solidBacking = overlay.solidBacking
        centerNameWeight = overlay.centerNameWeight
        centerNameSize = overlay.centerNameSize
        focusGlow = overlay.focusGlow
    }
}

/// 미리보기의 순수 치수. 오버레이와 같은 `PieGeometry` 로 실제 크기를 구하고, 표시 폭에 맞춰 비율로 줄인다.
struct PiePreviewMetrics: Equatable {
    let geometry: PieGeometry
    let corner: CGFloat
    /// 실제 오버레이 pt → 미리보기 pt 배율
    let scale: CGFloat
    /// 미리보기 정사각 영역 한 변
    let side: CGFloat

    /// - referenceRing: 이 바깥 반지름의 링이 `maxSize` 에 꼭 맞는 배율을 쓴다. 최대 링(320)을 주면 크기 슬라이더로 줄어드는 모습이
    ///   그대로 보이고, 현재 링을 주면 언제나 영역을 꽉 채운다.
    init(style: PiePreviewStyle, maxSize: CGFloat, referenceRing: Int) {
        geometry = PieGeometry(ringRadius: style.ringSize, centerRadius: style.centerSize, centerBorder: style.centerBorder)
        corner = PieGeometry.cornerRadius(setting: style.cornerSetting)
        let reference = PieGeometry(ringRadius: referenceRing, centerRadius: 0)
        scale = maxSize / reference.boxSize
        side = maxSize
    }

    /// 미리보기 영역 안의 점(좌상단 원점) → 클릭한 슬롯. 오버레이와 같은 `clickIndex` 판정이라 중앙 원 안·링 밖은 nil.
    func slotIndex(at point: CGPoint) -> Int? {
        geometry.clickIndex(dx: (point.x - side / 2) / scale, dy: (point.y - side / 2) / scale)
    }
}

/// 설정 창용 파이 미리보기: 실제 오버레이와 같은 조각·중앙 원 도형으로 그린다(아이콘 대신 약어). 슬롯이 없으면 `+`.
struct PiePreview: View {
    /// 8칸. nil 이면 빈 슬롯(`+`), 문자열은 조각에 쓰는 약어
    let labels: [String?]
    /// 슬롯 이름(이름 위치가 `center` 일 때 중앙에 보이는 선택된 슬롯 이름). 빈 슬롯은 nil
    let names: [String?]
    let selected: Int
    var invalid: Set<Int> = []
    let style: PiePreviewStyle
    let metrics: PiePreviewMetrics
    /// 슬롯별 앱 아이콘(없으면 약어). 오버레이처럼 아이콘이 있으면 아이콘을 그린다.
    let icons: [NSImage?]
    var onSelect: ((Int) -> Void)?
    /// 정적 미리보기라 기본은 끔. 시험 렌더만 정지 프레임(`frozen`)을 넣는다.
    var hubPulse: HubPulseSource = .off

    /// `showIcons` 가 켜져 있을 때 슬롯 대상 앱의 아이콘을 카탈로그에서 가져온다(카탈로그가 캐시한다). 못 얻으면 nil → 약어.
    static func icons(for slots: [Slot], showIcons: Bool, catalog: AppCatalog, pixels: Int = 112) -> [NSImage?] {
        (0..<PieGeometry.slots).map { i in
            guard showIcons, slots.indices.contains(i), let target = Deck.iconTarget(for: slots[i].action),
                  let png = catalog.iconPNG(for: target, pixels: pixels) else { return nil }
            return NSImage(data: png)
        }
    }

    init(slots: [Slot], icons: [NSImage?] = [], selected: Int, invalid: Set<Int> = [], style: PiePreviewStyle, maxSize: CGFloat, referenceRing: Int, onSelect: ((Int) -> Void)? = nil) {
        self.icons = (0..<PieGeometry.slots).map { icons.indices.contains($0) ? icons[$0] : nil }
        labels = (0..<PieGeometry.slots).map { slots.indices.contains($0) ? SettingsDraft.displayLabel(slots[$0]) : nil }
        names = (0..<PieGeometry.slots).map { slots.indices.contains($0) ? slots[$0].name : nil }
        self.selected = selected
        self.invalid = invalid
        self.style = style
        metrics = PiePreviewMetrics(style: style, maxSize: maxSize, referenceRing: referenceRing)
        self.onSelect = onSelect
    }

    var body: some View {
        let geometry = metrics.geometry
        ZStack {
            ForEach(0..<PieGeometry.slots, id: \.self) { slotView($0) }
            hub
        }
        .frame(width: geometry.boxSize, height: geometry.boxSize)
        .scaleEffect(metrics.scale)
        .frame(width: metrics.side, height: metrics.side)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            if let index = metrics.slotIndex(at: tap.location) { onSelect?(index) }
        })
        // 선택 변경만 chewy 로 움직인다. 슬라이더 값(알파·크기 등)은 애니메이션 없이 즉시 따라간다.
        .animation(Motion.animation(Motion.chewy), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("패널 미리보기: 슬롯 \(selected + 1) 선택됨")
    }

    private func slotView(_ index: Int) -> some View {
        let geometry = metrics.geometry
        let corner = metrics.corner
        let isSelected = index == selected
        let mid = PieGeometry.offset(index: index, radius: geometry.midRadius)
        let out = PieGeometry.offset(index: index, radius: OverlayMotion.selectedPop)
        let half = geometry.boxSize / 2
        let numberPoint = geometry.numberPoint(index: index)
        let numberSize = geometry.numberSize
        let anchor = UnitPoint(x: (half + mid.x) / geometry.boxSize, y: (half + mid.y) / geometry.boxSize)
        let label = labels[index]

        return ZStack {
            // 오버레이와 같은 조각 배경(채움 + 유리 광택 + 왼쪽 위 헤어라인 + 그림자)
            WedgeBackground(index: index, corner: corner, geometry: geometry, selected: isSelected, hovered: false, alpha: style.alpha, palette: style.colors)

            Group {
                if label != nil, let icon = icons[index] {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.iconSize, height: geometry.iconSize)
                } else if let label {
                    Text(label)
                        .font(.system(size: geometry.iconSize * 0.6, weight: .bold))
                        .foregroundColor(isSelected ? style.colors.selectedGlyph : style.colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: geometry.iconSize * 1.5)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: geometry.iconSize * 0.8, weight: .medium))
                        .foregroundColor(isSelected ? style.colors.selectedGlyph : style.colors.ink)
                }
            }
            .offset(x: mid.x, y: mid.y)

            if style.showNumbers {
                Text("\(index + 1)")
                    .font(OverlayMetrics.wedgeNumberFont(size: numberSize))
                    .foregroundColor(OverlayMetrics.wedgeNumberColor(selected: isSelected, palette: style.colors))
                    .offset(x: numberPoint.x, y: numberPoint.y)
            }

            if invalid.contains(index) {
                // 검증 문제가 있는 슬롯: 조각 안쪽 가장자리에 작은 점(디자인을 해치지 않게)
                let dot = PieGeometry.offset(index: index, radius: geometry.innerRadius + 12)
                Circle().fill(SettingsTheme.danger).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .offset(x: dot.x, y: dot.y)
            }
        }
        .scaleEffect(isSelected ? OverlayMotion.selectedScale : 1, anchor: anchor)
        .offset(x: isSelected ? out.x : 0, y: isSelected ? out.y : 0)
    }

    private var hub: some View {
        let geometry = metrics.geometry
        let size = geometry.hubRadius * 2
        let neon = style.colors.style == .neon
        return ZStack {
            if let plate = style.colors.plate { Circle().fill(plate) }
            if style.colors.spec.faceBacking > 0 {
                Circle().fill(Color.black.opacity(style.colors.spec.faceBacking * style.alpha))
            }
            Circle().fill(OverlayMetrics.hubFill(alpha: style.alpha, palette: style.colors))
            hubInnerGlow(palette: style.colors)
            HubPulseGlow(palette: style.colors, source: hubPulse, border: geometry.hubBorder)
            Circle().strokeBorder(OverlayMetrics.hubHairline(style.colors), lineWidth: geometry.hubBorder)
            if style.namePlacement == .center {
                HubNameText(hub: geometry.hubRadius, border: geometry.hubBorder, width: OverlayMetrics.centerNameWidth(hub: geometry.hubRadius, border: geometry.hubBorder),
                            name: names[selected], nameID: "preview", ink: style.colors.ink,
                            weight: style.centerNameWeight, sizeSetting: style.centerNameSize)
            }
            HubArc(center: PieGeometry.centerDegrees(index: selected), geometry: geometry)
                .stroke(style.colors.accent, style: StrokeStyle(lineWidth: neon ? OverlayMetrics.neonLineWidth : geometry.hubBorder, lineCap: .round))
                .neonGlow(style.colors.accent, strength: style.colors.glowStrength)
        }
        .frame(width: size, height: size)
        .background { hubBackdrop(size: size, palette: style.colors) }
    }
}
