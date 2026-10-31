import SwiftUI

/// 패널 모양 > 표시 탭: 무엇을 보여 줄지(아이콘·앱 이름·숫자·타일 라벨). 테마 전용 항목은 다른 테마에서 비활성 + 설명.
struct PanelDisplayTab: View {
    @ObservedObject var model: SettingsModel

    private var overlay: OverlaySettings { model.draft.overlay }
    private var isOrbit: Bool { overlay.theme == .orbit }
    private var plateEditable: Bool { SettingsDraft.canEditSolidBacking(model.draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: OneUI.cardGap) {
            OneUICard(title: "공통") {
                OneUIToggleRow(
                    symbol: "square.stack.3d.down.right", title: "앱 박스·원 뒤 배경 불투명",
                    subtitle: plateEditable
                        ? "켜면 바탕화면이 비치지 않습니다. 투명도 슬라이더는 그 위 면 색의 농도를 조절합니다."
                        : "글라스 본체는 바탕화면이 비치도록 바닥판을 쓰지 않습니다",
                    // 비활성일 때는 실제로 바닥판이 없으므로 꺼진 모양으로 보인다(저장된 값은 그대로)
                    isOn: overlay.solidBacking && plateEditable, enabled: plateEditable, warnSubtitle: !plateEditable) { model.draft.overlay.solidBacking = $0 }
                OneUIDivider()
                OneUIToggleRow(
                    symbol: "app.dashed", title: "슬롯에 앱 아이콘 표시", subtitle: "끄면 앱 슬롯도 두 글자 약어로 표시합니다.",
                    isOn: overlay.showIcons) { model.draft.overlay.showIcons = $0 }
                OneUIDivider()
                OneUIToggleRow(
                    symbol: "number", title: "숫자 표시(1~8)", subtitle: "끄면 숫자만 숨기고 1~8 키 단축키는 그대로 동작합니다. 오비트는 번호 배지가 숨겨집니다.",
                    isOn: overlay.showNumbers) { model.draft.overlay.showNumbers = $0 }
            }
            OneUICard(title: "파이 전용") {
                namePlacementRow
            }
            OneUICard(title: "오비트 전용") {
                OneUIToggleRow(
                    symbol: "tag", title: "타일 이름 표시",
                    subtitle: isOrbit ? "타일 아래에 앱 이름을 보여 줍니다." : "오비트 테마에서만 적용됩니다.",
                    isOn: overlay.showTileLabels, enabled: isOrbit, warnSubtitle: !isOrbit) { model.draft.overlay.showTileLabels = $0 }
            }
            centerNameCard
        }
    }

    /// 앱 이름 표시 위치(위 / 가운데 원 / 숨김). 오비트는 항상 가운데 원판에 표시하므로 비활성으로 둔다.
    private var namePlacementRow: some View {
        OneUIRow(
            symbol: "textformat", title: "앱 이름 위치",
            subtitle: isOrbit ? "파이 테마에서만 적용됩니다. 오비트는 항상 가운데 원에 표시됩니다." : "선택된 앱의 이름을 어디에 띄울지 정합니다.",
            warnSubtitle: isOrbit) {
            OneUISegmented(
                options: [
                    (value: OverlayNamePlacement.top, title: "위"),
                    (value: OverlayNamePlacement.center, title: "가운데 원"),
                    (value: OverlayNamePlacement.hidden, title: "숨김"),
                ],
                selected: overlay.namePlacement, accessibilityPrefix: "앱 이름 표시 위치", enabled: !isOrbit) { value in
                chewyChange { model.draft.overlay.namePlacement = value }
            }
            .frame(width: 220)
        }
    }

    // MARK: 중앙 원 글자

    /// 중앙 원에 이름이 보일 때만 의미가 있다: 오비트는 항상, 파이는 이름 위치가 '가운데 원'일 때
    private var centerNameActive: Bool { isOrbit || overlay.namePlacement == .center }

    private static let weightLabels: [NameWeight: String] = [.light: "얇게", .regular: "보통", .medium: "중간", .semibold: "굵게", .bold: "더 굵게"]

    private var centerNameCard: some View {
        let auto = overlay.centerNameSize == 0
        let size = auto ? SettingsDraft.autoCenterNameSize(model.draft) : overlay.centerNameSize
        let sliderOn = centerNameActive && !auto
        return OneUICard(title: "중앙 원 글자") {
            OneUIRow(
                symbol: "bold", title: "글자 굵기",
                subtitle: centerNameActive ? "중앙 원에 표시되는 앱 이름의 굵기" : "파이에서 이름 위치를 '가운데 원'으로 하면 적용됩니다",
                warnSubtitle: !centerNameActive, enabled: centerNameActive) {
                OneUISegmented(
                    options: NameWeight.allCases.map { (value: $0, title: Self.weightLabels[$0] ?? $0.displayName) },
                    selected: overlay.centerNameWeight, accessibilityPrefix: "중앙 원 글자 굵기", enabled: centerNameActive) { weight in
                    chewyChange { model.draft.overlay.centerNameWeight = weight }
                }
                .frame(width: 320)
            }
            OneUIDivider()
            OneUIToggleRow(
                symbol: "textformat.size", title: "글자 크기 자동", subtitle: "켜면 원 크기에 맞춰 글자 크기가 정해집니다.",
                isOn: auto, enabled: centerNameActive) { model.draft = SettingsDraft.settingCenterNameAuto(model.draft, auto: $0) }
            OneUIDivider()
            OneUISliderRow(
                symbol: "textformat", title: "글자 크기", subtitle: "10~32pt",
                accessibilityLabel: "중앙 원 글자 크기", valueText: auto ? "자동" : "\(size)pt",
                value: Double(size),
                range: Double(Limits.centerNameSizeRange.lowerBound)...Double(Limits.centerNameSizeRange.upperBound)) {
                    model.draft = SettingsDraft.settingCenterNameSize(model.draft, to: Int($0.rounded()))
                }
                // 자동이거나 중앙 글자가 안 보이는 상태에서는 조작할 수 없다(값 칸에는 '자동' 표시)
                .opacity(sliderOn ? 1 : 0.4)
                .allowsHitTesting(sliderOn)
                .accessibilityHidden(!sliderOn)
        }
    }
}
