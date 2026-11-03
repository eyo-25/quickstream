import SwiftUI

/// 설명 한 줄(보조 글자색)
struct HintText: View {
    @Environment(\.settingsPalette) private var pal
    let text: String
    var warn = false

    var body: some View {
        Text(text).font(.caption)
            .foregroundStyle(warn ? SettingsTheme.warn : pal.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func hintText(_ text: String) -> some View { HintText(text: text) }

extension View {
    /// 고를 수 있는 카드의 면·테두리. 선택되면 강조색 굵은 테두리. 모든 카드(테마·본체·포커스 칩)가 같은 모양을 쓴다.
    func selectableCard(chosen: Bool, cornerRadius: CGFloat) -> some View {
        modifier(SelectableCardModifier(chosen: chosen, cornerRadius: cornerRadius))
    }
}

private struct SelectableCardModifier: ViewModifier {
    @Environment(\.settingsPalette) private var pal
    let chosen: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(chosen ? pal.field : pal.field.opacity(0.45), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(chosen ? pal.accentText : pal.line, lineWidth: chosen ? (pal.isNeon ? 1.2 : 2) : 1)
                    // 네온: 선택된 카드만 이중 글로우
                    .shadow(color: chosen ? pal.halo(0.45) : .clear, radius: 8)
                    .shadow(color: chosen ? pal.halo(0.25) : .clear, radius: 18)
                    .allowsHitTesting(false))
    }
}

/// 현재 테마에 맞는 미리보기(파이/오비트). 두 뷰는 init 시그니처와 클릭→슬롯 환산이 같다.
struct ThemedPreview: View {
    let theme: OverlayTheme
    let slots: [Slot?]
    let icons: [NSImage?]
    let selected: Int
    var invalid: Set<Int> = []
    let style: PiePreviewStyle
    let maxSize: CGFloat
    let referenceRing: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        switch theme {
        case .pie:
            PiePreview(slots: slots, icons: icons, selected: selected, invalid: invalid, style: style, maxSize: maxSize, referenceRing: referenceRing, onSelect: onSelect)
        case .orbit:
            OrbitPreview(slots: slots, icons: icons, selected: selected, invalid: invalid, style: style, maxSize: maxSize, referenceRing: referenceRing, onSelect: onSelect)
        }
    }
}

extension OverlayTheme {
    var displayName: String {
        switch self {
        case .pie: return "파이"
        case .orbit: return "오비트"
        }
    }
}

/// 미리보기 바탕: 그라디언트 없이 단색(반투명 조각과 글씨가 읽히는 중간 어두운 슬레이트)
struct FlatPreviewBackdrop<Content: View>: View {
    static var color: Color { Color(red: 0.17, green: 0.19, blue: 0.24) }
    let height: CGFloat
    var cornerRadius: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Self.color
            content
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
