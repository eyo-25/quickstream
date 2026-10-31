import SwiftUI

// 설정 창 부품. 삼성 One UI 의 핵심(큰 제목 보기 영역 / 둥근 포커스 블록 / 아이콘 칩 행 / 알약 컨트롤)을
// 데스크톱에 맞게 옮겼다. 모든 색은 `settingsPalette`(본체 색 + 포커스 색)에서 읽는다.
// 모바일 가이드라 데스크톱에서 조정한 곳: 행 높이 56 은 지키되 카드 반지름은 24(모바일 28 근처)·아이콘 칩 34pt,
// 터치용 큰 여백 대신 좌우 28pt, 최대 콘텐츠 폭 760pt 로 넓은 창에서 줄이 늘어지지 않게 했다.

enum OneUI {
    static let cardRadius: CGFloat = 24
    static let pageInset: CGFloat = 28
    static let cardGap: CGFloat = 14
    static let rowMinHeight: CGFloat = 56
    static let chipSize: CGFloat = 34
    /// 행 안쪽 좌우 여백
    static let rowInset: CGFloat = 16
    /// 들여쓴 구분선의 시작 위치(행 여백 + 아이콘 칩 + 칩과 글자 사이)
    static let dividerInset: CGFloat = rowInset + chipSize + 14
    static let maxContentWidth: CGFloat = 760
    /// 큰 제목이 상단 바 제목으로 접히는 스크롤 거리
    static let collapseDistance: CGFloat = 56
}

/// hover 여부(@State 매크로를 쓸 수 없어 ObservableObject 로 둔다)
final class OneUIHover: ObservableObject {
    @Published var on = false
}

/// 알약 면 + 테두리. 테두리를 stroke 가 아니라 '테두리색 알약 위에 1pt 안쪽 면 알약'으로 겹쳐 그린다:
/// 반지름이 큰 RoundedRectangle 의 inset stroke 는 양 끝에 얇은 막대가 삐져나오는 렌더링 문제가 있었다(격리 렌더로 확인).
struct PillFace: View {
    let fill: Color
    let border: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(border)
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(fill).padding(1)
        }
    }
}

/// 글로우 세기(네온에서만 그려진다)
enum GlowLevel {
    case soft
    case strong
}

/// 강조 알약 면(주 버튼·세그먼트 선택·토글 켜짐). 플랫 = 솔리드 강조색 면 + 1pt 테두리.
/// 네온 = 옅은 강조 틴트 면 + 강조색 1.2pt 헤어라인 + 글로우(strong: 가까운 0.45/r8 + 넓은 0.25/r18, soft: 0.3/r6 한 겹).
/// 글로우는 그림자라 입력을 받지 않는다. 선택된 소수 요소에만 쓴다.
struct AccentPill: View {
    @Environment(\.settingsPalette) private var pal
    var glow: GlowLevel = .strong

    var body: some View {
        let neon = pal.isNeon
        ZStack {
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(pal.accentText)
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(pal.accentFace).padding(neon ? 1.2 : 1)
        }
        .shadow(color: pal.halo(glow == .strong ? 0.45 : 0.3), radius: glow == .strong ? 8 : 6)
        .shadow(color: glow == .strong ? pal.halo(0.25) : .clear, radius: 18)
        .allowsHitTesting(false)
    }
}

/// 사이드바 선택 알약: 플랫 = 옅은 강조 면 + 반투명 테두리, 네온 = 옅은 강조 면 + 강조색 헤어라인 + 이중 글로우.
struct SelectionPill: View {
    @Environment(\.settingsPalette) private var pal

    var body: some View {
        let neon = pal.isNeon
        ZStack {
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(neon ? pal.accentText : pal.accentText.opacity(0.45))
            RoundedRectangle(cornerRadius: 999, style: .continuous).fill(pal.selection).padding(neon ? 1.2 : 1)
        }
        .shadow(color: pal.halo(0.45), radius: 8)
        .shadow(color: pal.halo(0.25), radius: 18)
        .allowsHitTesting(false)
    }
}

// MARK: 페이지(보기 영역 + 접히는 큰 제목 + 위에 고정되는 영역)

private final class ScrollOffsetModel: ObservableObject {
    /// 접힘 정도 0(큰 제목) … 1(상단 바 제목). 동작 줄이기이면 0/1 로만 바뀐다.
    @Published var progress: Double = 0
    /// 고정 영역 자리표시자의 뷰포트 기준 위치. 상단 바 아래로 올라가면 거기서 멈춘다.
    @Published var pinnedTop: CGFloat = 400

    func update(_ metrics: PageMetrics) {
        guard let viewport = metrics.viewport else { return }
        if let anchor = metrics.anchor {
            var p = Double(min(1, max(0, (viewport - anchor) / OneUI.collapseDistance)))
            if Motion.reduced { p = p > 0.5 ? 1 : 0 }
            // 같은 값으로 매 프레임 발행하지 않는다
            if abs(p - progress) > 0.01 { progress = p }
        }
        if let pinned = metrics.pinned {
            let top = pinned - viewport
            if abs(top - pinnedTop) > 0.5 { pinnedTop = top }
        }
    }
}

/// 스크롤 영역 안팎에서 재는 전역 y 좌표 모음(영역마다 자기 값만 채워 합친다)
private struct PageMetrics: Equatable {
    var anchor: CGFloat?
    var pinned: CGFloat?
    var viewport: CGFloat?
}

private struct PageMetricsKey: PreferenceKey {
    static var defaultValue = PageMetrics()
    static func reduce(value: inout PageMetrics, nextValue: () -> PageMetrics) {
        let next = nextValue()
        if let v = next.anchor { value.anchor = v }
        if let v = next.pinned { value.pinned = v }
        if let v = next.viewport { value.viewport = v }
    }
}

/// 한 화면의 틀: 위는 보기 영역(큰 제목, 조작 요소 없음 + 넉넉한 빈 공간), 아래는 카드들(상호작용 영역).
/// 스크롤하면 큰 제목이 작은 상단 바 제목으로 접힌다. `pinned` 를 주면 제목 아래에 놓였다가 스크롤하면 상단 바 밑에 고정된다
/// (예: 설정을 만지는 동안 계속 보여야 하는 미리보기).
struct OneUIPage<Pinned: View, Content: View>: View {
    @Environment(\.settingsPalette) private var pal
    @StateObject private var scroll = ScrollOffsetModel()
    let title: String
    var subtitle: String?
    var pinnedHeight: CGFloat
    let pinned: Pinned
    let content: Content

    init(title: String, subtitle: String? = nil, pinnedHeight: CGFloat, @ViewBuilder pinned: () -> Pinned, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.pinnedHeight = pinnedHeight
        self.pinned = pinned()
        self.content = content()
    }

    private static var barHeight: CGFloat { 44 }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PageMetricsKey.self, value: PageMetrics(anchor: proxy.frame(in: .global).minY))
                    }
                    .frame(height: 0)
                    PageTitle(model: scroll, title: title, subtitle: subtitle)
                    if pinnedHeight > 0 {
                        // 고정 영역이 놓일 자리(스크롤되는 동안 위치를 재서 상단 바 밑에 멈추게 한다)
                        Color.clear
                            .frame(height: pinnedHeight)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: PageMetricsKey.self, value: PageMetrics(pinned: proxy.frame(in: .global).minY))
                            })
                            .padding(.top, 28)
                    }
                    VStack(alignment: .leading, spacing: OneUI.cardGap) { content }
                        .padding(.top, pinnedHeight > 0 ? OneUI.cardGap : 28)
                }
                .padding(.horizontal, OneUI.pageInset)
                .padding(.bottom, 32)
                .frame(maxWidth: OneUI.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 스크롤 영역(뷰포트) 위쪽의 전역 위치. 커스텀 좌표 공간 대신 전역 좌표 차이로 오프셋을 구한다.
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PageMetricsKey.self, value: PageMetrics(viewport: proxy.frame(in: .global).minY))
            })
            .onPreferenceChange(PageMetricsKey.self) { scroll.update($0) }
            if pinnedHeight > 0 {
                PinnedHost(model: scroll, barHeight: Self.barHeight, height: pinnedHeight) { pinned }
            }
            CollapsedBar(model: scroll, title: title)
        }
    }
}

extension OneUIPage where Pinned == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, pinnedHeight: 0, pinned: { EmptyView() }, content: content)
    }
}

/// 고정 영역: 자리표시자가 상단 바 아래로 올라가면 거기서 멈춘다. 바탕으로 뒤로 스크롤되는 카드를 가린다.
private struct PinnedHost<Inner: View>: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: ScrollOffsetModel
    let barHeight: CGFloat
    let height: CGFloat
    @ViewBuilder let inner: Inner

    var body: some View {
        let y = max(barHeight, model.pinnedTop)
        let stuck = model.pinnedTop < barHeight
        inner
            .frame(maxWidth: OneUI.maxContentWidth, alignment: .leading)
            .frame(height: height)
            .padding(.horizontal, OneUI.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 멈춘 동안에는 아래로 스크롤되는 카드가 비치지 않게 바탕을 깐다
            .background(alignment: .top) {
                pal.background.opacity(stuck ? 1 : 0).frame(height: height + OneUI.cardGap)
            }
            .offset(y: y)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct PageTitle: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: ScrollOffsetModel
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(pal.muted)
            }
        }
        .padding(.top, 36)
        .opacity(1 - model.progress)
        .offset(y: CGFloat(model.progress) * -6)
    }
}

private struct CollapsedBar: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: ScrollOffsetModel
    let title: String

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(pal.background.opacity(0.94))
        .overlay(alignment: .bottom) { Rectangle().fill(pal.line).frame(height: 1) }
        .opacity(model.progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: 카드·행

/// 둥근 포커스 블록. 제목은 카드 위의 작은 secondary 글씨.
struct OneUICard<Content: View>: View {
    @Environment(\.settingsPalette) private var pal
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pal.muted)
                    .padding(.leading, 14)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pal.card, in: RoundedRectangle(cornerRadius: OneUI.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: OneUI.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: OneUI.cardRadius, style: .continuous).stroke(pal.line))
        }
    }
}

/// 카드 안 행 사이의 들여쓴 가는 구분선
struct OneUIDivider: View {
    @Environment(\.settingsPalette) private var pal
    var inset: CGFloat = OneUI.dividerInset

    var body: some View {
        Rectangle().fill(pal.line).frame(height: 1).padding(.leading, inset)
    }
}

/// 둥근 사각 배경 + SF Symbol(포커스 색 계열)
struct OneUIIconChip: View {
    @Environment(\.settingsPalette) private var pal
    let symbol: String
    var size: CGFloat = OneUI.chipSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(pal.accentText.opacity(0.18))
            // 네온: 은은한 글로우(칩마다 한 겹)
            .shadow(color: pal.halo(0.28), radius: 5)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(pal.accentText))
            .accessibilityHidden(true)
    }
}

/// 행: 왼쪽 아이콘 칩, 제목 + 보조 설명(작은 secondary 한 줄), 오른쪽 컨트롤. 높이 ≥ 56. `action` 이 있으면 행 전체가 버튼이다.
struct OneUIRow<Trailing: View>: View {
    @Environment(\.settingsPalette) private var pal
    @StateObject private var hover = OneUIHover()
    var symbol: String?
    let title: String
    var subtitle: String?
    var warnSubtitle = false
    var enabled = true
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { rowBody }
                .buttonStyle(SquishButtonStyle(pressedScale: 0.99))
                .disabled(!enabled)
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        HStack(spacing: 14) {
            if let symbol { OneUIIconChip(symbol: symbol).opacity(enabled ? 1 : 0.4) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1).opacity(enabled ? 1 : 0.4)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(warnSubtitle ? SettingsTheme.warn : pal.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing.opacity(enabled ? 1 : 0.4)
        }
        .padding(.horizontal, OneUI.rowInset)
        .padding(.vertical, 10)
        .frame(minHeight: OneUI.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(pal.text.opacity(hover.on && enabled && action != nil ? 0.05 : 0))
        // (비활성이어도 설명은 그대로 읽혀야 한다: 칩·제목·컨트롤만 흐리게 한다)
        .onHover { hover.on = $0 }
        .animation(Motion.animation(Motion.snap), value: hover.on)
    }
}

extension OneUIRow where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, subtitle: String? = nil, warnSubtitle: Bool = false, enabled: Bool = true, action: (() -> Void)? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, warnSubtitle: warnSubtitle, enabled: enabled, action: action) { EmptyView() }
    }
}

// MARK: 컨트롤

/// 알약 토글: 큰 원형 썸, 켜면 포커스 색. 썸 색은 강조 면 위 글자색(`onAccent`)이라 어떤 포커스 색에서도 보인다.
struct OneUIToggleStyle: ToggleStyle {
    /// 행 안에서 쓸 때는 제목이 이미 왼쪽에 있어 라벨을 그리지 않는다
    var showsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        OneUIToggleBody(configuration: configuration, showsLabel: showsLabel)
    }

    private struct OneUIToggleBody: View {
        @Environment(\.settingsPalette) private var pal
        let configuration: ToggleStyleConfiguration
        let showsLabel: Bool

        var body: some View {
            let on = configuration.isOn
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 10) {
                    if showsLabel { configuration.label }
                    Spacer(minLength: 0)
                    ZStack(alignment: on ? .trailing : .leading) {
                        if on {
                            AccentPill(glow: .soft)
                        } else {
                            PillFace(fill: pal.field, border: pal.muted.opacity(0.5))
                        }
                        Circle()
                            // 켜짐 썸: 플랫 = 면 위 글자색(대비 보장), 네온 = 강조색(+글로우)
                            .fill(on ? (pal.isNeon ? pal.glowColor : pal.onAccent) : pal.muted)
                            .shadow(color: on ? pal.halo(0.6) : .clear, radius: 4)
                            .frame(width: 22, height: 22)
                            .padding(.horizontal, 4)
                    }
                    .frame(width: 52, height: 30)
                    .animation(Motion.animation(Motion.chewy), value: on)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SquishButtonStyle(pressedScale: 0.985))
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

/// 토글 한 줄(행 + 알약 토글). 바뀌는 값은 chewy 로 감싼다.
struct OneUIToggleRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isOn: Bool
    var enabled = true
    var warnSubtitle = false
    let onChange: (Bool) -> Void

    var body: some View {
        OneUIRow(symbol: symbol, title: title, subtitle: subtitle, warnSubtitle: warnSubtitle, enabled: enabled) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { v in chewyChange { onChange(v) } }))
                .toggleStyle(OneUIToggleStyle(showsLabel: false))
                .disabled(!enabled)
                .accessibilityLabel(title)
        }
    }
}

/// 알약 세그먼트: 선택 알약이 옆 칸으로 미끄러진다. AppKit 컨트롤이 아닌 순수 SwiftUI.
struct OneUISegmented<Value: Hashable>: View {
    @Environment(\.settingsPalette) private var pal
    @Namespace private var space
    let options: [(value: Value, title: String)]
    let selected: Value
    /// 접근성 라벨 앞머리(예: "패널 설정 탭")
    let accessibilityPrefix: String
    var enabled = true
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let chosen = option.value == selected
                Button { onSelect(option.value) } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: chosen ? .semibold : .medium))
                        .foregroundStyle(chosen ? pal.onAccentFace : pal.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if chosen {
                                AccentPill(glow: .strong)
                                    .matchedGeometryEffect(id: "segment", in: space)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                }
                .buttonStyle(SquishButtonStyle(pressedScale: 0.97))
                .accessibilityLabel("\(accessibilityPrefix): \(option.title)")
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(pal.field, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// 굵은 둥근 트랙 + 큰 썸의 슬라이더. 채워진 부분은 포커스 색. 드래그·방향키·VoiceOver 조절을 지원한다.
struct OneUISlider: View {
    @Environment(\.settingsPalette) private var pal
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let accessibilityLabel: String
    let valueText: String
    let onChange: (Double) -> Void

    private let thumb: CGFloat = 24
    private let track: CGFloat = 10

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let steps = ((clamped - range.lowerBound) / step).rounded()
        return min(range.upperBound, range.lowerBound + steps * step)
    }

    var body: some View {
        GeometryReader { proxy in
            let span = max(1, proxy.size.width - thumb)
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(fraction) * span
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous).fill(pal.field).frame(height: track)
                PillFace(fill: pal.accent, border: pal.accentText)
                    // 네온: 채워진 트랙에 약한 글로우(레이어 1개)
                    .shadow(color: pal.halo(0.35), radius: 6)
                    .frame(width: x + thumb / 2, height: track)
                Circle()
                    .fill(pal.text)
                    .overlay(Circle().stroke(pal.accentText, lineWidth: 3))
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: x)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = Double((drag.location.x - thumb / 2) / span)
                onChange(snapped(range.lowerBound + f * (range.upperBound - range.lowerBound)))
            })
        }
        .frame(height: 28)
        .focusable()
        .onMoveCommand { direction in
            let big = max(step, (range.upperBound - range.lowerBound) / 20)
            switch direction {
            case .left, .down: onChange(snapped(value - big))
            case .right, .up: onChange(snapped(value + big))
            @unknown default: break
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let big = max(step, (range.upperBound - range.lowerBound) / 20)
            switch direction {
            case .increment: onChange(snapped(value + big))
            case .decrement: onChange(snapped(value - big))
            @unknown default: break
            }
        }
    }
}

/// 슬라이더 한 줄: 위에 아이콘 칩·제목·설명·값, 아래에 슬라이더. 값이 바뀔 때는 짧은 snap 으로만 보간한다.
struct OneUISliderRow: View {
    @Environment(\.settingsPalette) private var pal
    let symbol: String
    let title: String
    var subtitle: String?
    let accessibilityLabel: String
    let valueText: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                OneUIIconChip(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(pal.muted) }
                }
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(pal.field, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
            }
            OneUISlider(value: value, range: range, step: step, accessibilityLabel: accessibilityLabel, valueText: valueText) { v in
                withAnimation(Motion.animation(Motion.snap)) { onChange(v) }
            }
            .padding(.leading, OneUI.dividerInset - OneUI.rowInset)
        }
        .padding(.horizontal, OneUI.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: OneUI.rowMinHeight)
    }
}

enum OneUIButtonKind {
    /// 주 버튼: 포커스 색 면
    case primary
    /// 보조 버튼: 면 색
    case secondary
    case destructive
}

/// 알약 버튼. 주 버튼은 포커스 색 면 + 면 위 글자색(대비 ≥ 4.5), 보조는 카드보다 밝은 면.
struct OneUIPillButton: View {
    @Environment(\.settingsPalette) private var pal
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = OneUIHover()
    let title: String
    var symbol: String?
    var kind: OneUIButtonKind = .secondary
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: large ? 14 : 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, large ? 24 : 16)
            .frame(height: large ? 40 : 32)
            .background {
                // 호버 층은 글자 아래(면 위)에 깐다: 글자까지 덮으면 글자색도 같이 변해 모델(`hoverFace` 위 `onAccent`)과 어긋난다
                ZStack {
                    if kind == .primary {
                        AccentPill(glow: .strong)
                    } else {
                        PillFace(fill: face, border: pal.line)
                    }
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(hoverTint.opacity(hover.on && isEnabled ? ContrastMath.hoverMix : 0))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        }
        .buttonStyle(SquishButtonStyle(pressedScale: 0.95))
        .onHover { hover.on = $0 }
        .animation(Motion.animation(Motion.snap), value: hover.on)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return pal.onAccentFace
        case .secondary: return pal.text
        case .destructive: return SettingsTheme.danger
        }
    }

    /// 호버 층 색: 주 버튼은 글자 대비를 지키도록 글자 반대 방향, 나머지는 본문 글자색
    private var hoverTint: Color {
        guard kind == .primary else { return pal.text }
        // 네온 면은 어두운 틴트라 검정을 얹어 글자 대비가 오히려 올라간다
        return pal.isNeon ? .black : ContrastMath.hoverTint(pal.swatches.accent).color
    }

    private var face: Color {
        kind == .primary ? pal.accent : pal.field
    }
}

extension View {
    /// 카드 안 입력칸(텍스트 필드·에디터) 모양: 카드보다 밝은 둥근 면
    func oneUIField(cornerRadius: CGFloat = 12) -> some View {
        modifier(OneUIFieldModifier(cornerRadius: cornerRadius))
    }
}

private struct OneUIFieldModifier: ViewModifier {
    @Environment(\.settingsPalette) private var pal
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(pal.field, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(pal.line))
    }
}
