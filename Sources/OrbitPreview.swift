import SwiftUI

/// 설정 창용 orbit 미리보기. `PiePreview` 와 같은 init 시그니처·치수 계산(`PiePreviewMetrics`)을 써서 설정 창이 그대로 갈아 끼울 수 있다.
/// 타일·중앙 원판·가이드는 오버레이와 같은 뷰(`OrbitTile`/`OrbitHub`/`OrbitGuides`)로 그리고, 움직임·입력은 없다.
struct OrbitPreview: View {
    /// 8칸. nil 이면 빈 슬롯(`+`), 문자열은 타일에 쓰는 약어
    let labels: [String?]
    /// 슬롯 이름(타일 아래 라벨과 중앙 원판 글자). 빈 슬롯은 nil
    let names: [String?]
    let selected: Int
    var invalid: Set<Int> = []
    let style: PiePreviewStyle
    let metrics: PiePreviewMetrics
    let icons: [NSImage?]
    var onSelect: ((Int) -> Void)?
    /// 정적 미리보기라 기본은 끔. 시험 렌더만 정지 프레임(`frozen`)을 넣는다.
    var hubPulse: HubPulseSource = .off

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
        let geometry = OrbitGeometry(pie: metrics.geometry)
        return ZStack {
            OrbitGuides(geometry: geometry, palette: style.colors)
            ForEach(0..<PieGeometry.slots, id: \.self) { tile($0, geometry: geometry) }
            OrbitHub(geometry: geometry, alpha: style.alpha, name: names[selected], nameID: "preview", palette: style.colors,
                     nameWeight: style.centerNameWeight, nameSize: style.centerNameSize, pulse: hubPulse)
        }
        .frame(width: geometry.pie.boxSize, height: geometry.pie.boxSize)
        .scaleEffect(metrics.scale)
        .frame(width: metrics.side, height: metrics.side)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            if let index = metrics.slotIndex(at: tap.location) { onSelect?(index) }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("패널 미리보기: 슬롯 \(selected + 1) 선택됨")
    }

    private func tile(_ index: Int, geometry: OrbitGeometry) -> some View {
        let isSelected = index == selected
        let center = geometry.tileCenter(index: index)
        let labelAt = geometry.labelCenter(index: index, selected: isSelected)
        return ZStack {
            OrbitTile(geometry: geometry, index: index, corner: geometry.tileCorner(setting: style.cornerSetting), alpha: style.alpha,
                      selected: isSelected, hovered: false, icon: labels[index] != nil ? icons[index] : nil, label: labels[index], palette: style.colors, showNumber: style.showNumbers)
                .scaleEffect(isSelected ? OrbitMetrics.selectedScale : 1)
                .offset(x: center.x, y: center.y)

            if let name = names[index], style.showTileLabels {
                OrbitTileLabel(name: name, geometry: geometry, palette: style.colors)
                    .offset(x: labelAt.x, y: labelAt.y)
            }

            if invalid.contains(index) {
                // 검증 문제가 있는 슬롯: 타일 왼쪽 위 모서리에 작은 점(디자인을 해치지 않게)
                let dot = CGPoint(x: center.x - geometry.tileSide / 2, y: center.y - geometry.tileSide / 2)
                Circle().fill(SettingsTheme.danger).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .offset(x: dot.x, y: dot.y)
            }
        }
    }
}
