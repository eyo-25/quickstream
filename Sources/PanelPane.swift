import SwiftUI

/// 패널 모양 화면: 현재 테마의 실제 모양 미리보기를 위에 고정하고(스크롤해도 상단 바 밑에 남는다),
/// 아래에서 모양/색상/표시 탭을 고른다. 탭 선택은 모델(`panelTab`)이 쥔다.
struct PanelPane: View {
    @ObservedObject var model: SettingsModel

    /// 탭별 고정 미리보기 높이: 슬라이더가 많은 '모양' 탭은 270, 색·표시를 보며 고르는 탭은 더 크게 360.
    /// 고정된 동안에도 컨트롤이 보이도록 상단 바(44)와 최소 컨트롤 띠(220)를 먼저 남기고 나머지를 미리보기에 쓴다:
    /// `min(원하는 높이, viewport − 44 − 220)`, 하한 160. 960×680 에서는 색·표시가 ≈350(모양 270 보다 큼), 820×560 에서는 ≈230.
    static func previewHeight(tab: PanelTab, viewport: CGFloat) -> CGFloat {
        let wanted: CGFloat = tab == .shape ? 270 : 360
        return min(wanted, max(160, (viewport - 44 - 220).rounded()))
    }

    var body: some View {
        GeometryReader { proxy in
            let height = Self.previewHeight(tab: model.panelTab, viewport: proxy.size.height)
            OneUIPage(
                title: "패널 모양", subtitle: "오버레이의 모양·색·표시를 정합니다. 위 미리보기는 편집 내용을 바로 보여 줍니다.",
                pinnedHeight: height,
                pinned: {
                    PanelPreviewView(model: model, theme: model.draft.overlay.theme, height: height, cornerRadius: OneUI.cardRadius, accessibilityHidden: true)
                }
            ) {
                OneUISegmented(
                    options: PanelTab.allCases.map { (value: $0, title: $0.title) }, selected: model.panelTab,
                    accessibilityPrefix: "패널 설정 탭") { tab in
                    withAnimation(Motion.animation(Motion.chewy)) { model.panelTab = tab }
                }
                tabContent
            }
            // 탭을 바꾸면 미리보기 높이가 부드럽게 변한다(동작 줄이기이면 즉시)
            .animation(Motion.animation(Motion.soft), value: height)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.panelTab {
        case .shape: PanelShapeTab(model: model)
        case .color: PanelColorTab(model: model)
        case .display: PanelDisplayTab(model: model)
        }
    }
}

/// draft 의 슬롯·모양 값으로 그린 오버레이 미리보기. `theme` 를 주면 그 테마 자신의 크기로 그려진다
/// (테마 카드가 서로의 크기와 무관하게 각자의 모습을 보여 준다).
struct PanelPreviewView: View {
    @ObservedObject var model: SettingsModel
    let theme: OverlayTheme
    let height: CGFloat
    var cornerRadius: CGFloat = 10
    var accessibilityHidden = false
    /// 기준 링: 현재 링과 이 값 중 큰 쪽이 영역에 꼭 맞는다. 그래서 기본 크기(250)에서도 영역을 크게 채우고,
    /// 바깥 크기 슬라이더로 줄이면(이 값 이하) 줄어드는 모습이 그대로 보이며, 더 키우면 영역에 맞춰 축소된다.
    static let minReferenceRing = 260

    var body: some View {
        let slots = model.draft.tabs.first?.slots ?? []
        var overlay = model.draft.overlay
        overlay.theme = theme
        return FlatPreviewBackdrop(height: height, cornerRadius: cornerRadius) {
            ThemedPreview(
                theme: theme, slots: slots,
                icons: PiePreview.icons(for: slots, showIcons: overlay.showIcons, catalog: model.catalog),
                keyLabels: Keymap.build(slots: slots, closeKey: model.draft.closeKey).keyLabels, selected: 0,
                style: PiePreviewStyle(overlay), maxSize: height, referenceRing: max(overlay.ringSize, PanelPreviewView.minReferenceRing))
        }
        // 미리보기가 자체 탭 제스처로 클릭을 먹지 않게 한다(카드 안에서 쓰일 때 카드 전체가 하나의 버튼이다)
        .allowsHitTesting(false)
        .accessibilityHidden(accessibilityHidden)
    }
}
