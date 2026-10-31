import SwiftUI

/// 패널 모양 > 모양 탭: 테마 카드, 공통 슬라이더(투명도·모서리), 현재 테마의 크기 슬라이더.
struct PanelShapeTab: View {
    @ObservedObject var model: SettingsModel

    private var overlay: OverlaySettings { model.draft.overlay }

    var body: some View {
        VStack(alignment: .leading, spacing: OneUI.cardGap) {
            themeCard
            commonCard
            sizeCard
        }
    }
    /// 테마를 바꿀 때는 `theme` 만 바꾼다. 크기는 테마별로 따로 있어 덮어쓰지 않는다.
    private func chooseTheme(_ theme: OverlayTheme) {
        withAnimation(Motion.animation(Motion.chewy)) { model.draft.overlay.theme = theme }
    }

    /// 테마 카드 두 장. 각 카드는 그 테마 자신의 크기로 그려진다. 카드 전체가 하나의 버튼이다.
    private var themeCard: some View {
        OneUICard(title: "테마") {
            HStack(spacing: 12) {
                ForEach(OverlayTheme.allCases, id: \.self) { theme in
                    let chosen = overlay.theme == theme
                    Button {
                        chooseTheme(theme)
                    } label: {
                        VStack(spacing: 8) {
                            PanelPreviewView(model: model, theme: theme, height: 190, cornerRadius: 16, accessibilityHidden: true)
                            Text(theme.displayName).font(.system(size: 14, weight: chosen ? .semibold : .medium))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .selectableCard(chosen: chosen, cornerRadius: 20)
                    }
                    .buttonStyle(SquishButtonStyle(pressedScale: 0.97))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("오버레이 테마: \(theme.displayName)")
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(14)
        }
    }

    /// 두 테마 공통
    private var commonCard: some View {
        OneUICard(title: "공통") {
            OneUISliderRow(
                symbol: "circle.lefthalf.filled", title: "면 투명도", subtitle: "앱 박스·원 면 색의 농도. 글자와 아이콘은 흐려지지 않습니다.",
                accessibilityLabel: "면 투명도", valueText: String(format: "%.2f", overlay.alpha),
                value: overlay.alpha, range: Limits.alphaRange, step: 0.01) { model.draft.overlay.alpha = $0 }
            OneUIDivider()
            OneUISliderRow(
                symbol: "roundedcorner", title: "모서리", subtitle: "조각·타일의 둥근 정도",
                accessibilityLabel: "모서리 반경", valueText: "\(overlay.radius)px",
                value: Double(overlay.radius),
                range: Double(Limits.radiusRange.lowerBound)...Double(Limits.radiusRange.upperBound)) { model.draft.overlay.radius = Int($0.rounded()) }
        }
    }

    /// 현재 선택된 테마의 크기만 편집한다(제목에 어느 테마인지 표시).
    private var sizeCard: some View {
        let name = overlay.theme.displayName
        let centerRange = Limits.centerRange(ring: overlay.ringSize)
        // 파일이 상한을 넘는 값이어도(그릴 땐 보정됨) 손잡이와 숫자가 같은 값을 가리키게 표시만 보정한다
        let shownCenter = min(overlay.centerSize, centerRange.upperBound)
        return OneUICard(title: "\(name) 크기") {
            OneUISliderRow(
                symbol: "circle.dashed", title: "바깥 크기", subtitle: "링 바깥 반지름",
                accessibilityLabel: "\(name) 바깥 크기", valueText: "\(overlay.ringSize)px",
                value: Double(overlay.ringSize),
                range: Double(Limits.ringRange.lowerBound)...Double(Limits.ringRange.upperBound)) {
                    model.draft = SettingsDraft.settingRing(model.draft, to: Int($0.rounded()))
                }
            OneUIDivider()
            OneUISliderRow(
                symbol: "smallcircle.circle", title: "중앙 원 크기", subtitle: "바깥 크기에 맞춰 상한이 정해집니다.",
                accessibilityLabel: "\(name) 중앙 원 크기", valueText: "\(shownCenter)px",
                value: Double(shownCenter),
                range: Double(centerRange.lowerBound)...Double(centerRange.upperBound)) {
                    model.draft = SettingsDraft.settingCenter(model.draft, to: Int($0.rounded()))
                }
            OneUIDivider()
            OneUISliderRow(
                symbol: "circle.dotted", title: "테두리 굵기", subtitle: "중앙 원 테두리",
                accessibilityLabel: "\(name) 중앙 원 테두리 굵기", valueText: "\(overlay.centerBorder)px",
                value: Double(overlay.centerBorder),
                range: Double(Limits.centerBorderRange.lowerBound)...Double(Limits.centerBorderRange.upperBound)) {
                    model.draft = SettingsDraft.settingBorder(model.draft, to: Int($0.rounded()))
                }
            OneUIDivider()
            OneUIRow(
                symbol: "arrow.counterclockwise", title: "이 테마 크기를 기본값으로",
                subtitle: "파이와 오비트는 크기를 따로 가집니다. 다른 테마의 크기는 그대로입니다.",
                enabled: overlay.sizes != overlay.theme.defaultSizes,
                action: { chewyChange { model.draft = SettingsDraft.resettingSizes(model.draft) } })
        }
    }
}
