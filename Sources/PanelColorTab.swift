import SwiftUI
import AppKit

/// 패널 모양 > 색상 탭: ① 본체 색(다크 그레이 / 다크 글라스 / 클리어 글라스, 포커스 색 없음) ② 클리어 글라스일 때 글라스 틴트 ③ 포커스 색(스타일 × 색).
struct PanelColorTab: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.settingsPalette) private var pal

    private var overlay: OverlaySettings { model.draft.overlay }

    var body: some View {
        VStack(alignment: .leading, spacing: OneUI.cardGap) {
            bodyCard
            if overlay.bodyTheme == .clearGlass { tintCard }
            styleCard
            paletteCard
        }
    }

    // MARK: 본체

    private var bodyCard: some View {
        OneUICard(title: "본체") {
            HStack(spacing: 12) {
                ForEach(OverlayBody.allCases, id: \.self) { kind in
                    let chosen = overlay.bodyTheme == kind
                    Button {
                        chewyChange { model.draft.overlay.bodyTheme = kind }
                    } label: {
                        VStack(spacing: 8) {
                            BodySwatch(kind: kind, glassTint: overlay.glassTintHex)
                            Text(kind.displayName).font(.system(size: 14, weight: chosen ? .semibold : .medium))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .selectableCard(chosen: chosen, cornerRadius: 20)
                    }
                    .buttonStyle(SquishButtonStyle(pressedScale: 0.97))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("본체 색: \(kind.displayName)")
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(14)
            OneUIDivider(inset: OneUI.rowInset)
            Text("면·글자·테두리·유리 질감만 정합니다. 선택됐을 때의 색은 아래 포커스 색이 정합니다. 이 설정 창도 선택한 색을 따릅니다.")
                .font(.system(size: 12))
                .foregroundStyle(pal.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
        }
    }

    // MARK: 포커스 색

    private var styleCard: some View {
        OneUICard(title: "포커스 스타일") {
            OneUIRow(
                symbol: "sparkles", title: "선택 표시 방식",
                subtitle: overlay.focusStyle == .flat
                    ? "플랫: 선택된 조각·타일을 강조색으로 채웁니다."
                    : "네온: 면은 투명하게 두고 밝은 가장자리선과 이중 글로우로 빛납니다.") {
                OneUISegmented(
                    options: FocusStyle.allCases.map { (value: $0, title: $0.displayName) },
                    selected: overlay.focusStyle, accessibilityPrefix: "포커스 스타일") { style in
                    chewyChange { model.draft.overlay.focusStyle = style }
                }
                .frame(width: 168)
            }
            OneUIDivider()
            // 플랫도 중앙 원 글로우와 타일 halo 가 있어 스타일과 무관하게 켜고 끌 수 있다
            OneUIToggleRow(
                symbol: "lightbulb", title: "포커스 불빛",
                subtitle: "선택된 조각·타일과 중앙 원의 번짐 효과. 끄면 번짐만 사라지고 선택 색은 유지됩니다",
                isOn: overlay.focusGlow) { model.draft.overlay.focusGlow = $0 }
        }
    }

    private var paletteCard: some View {
        OneUICard(title: "포커스 색") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(FocusColors.presets, id: \.id) { preset in
                    presetChip(preset)
                }
            }
            .padding(14)
            OneUIDivider(inset: OneUI.rowInset)
            customColorRow
        }
    }

    private func chooseHex(_ hex: String) {
        withAnimation(Motion.animation(Motion.chewy)) { model.draft = SettingsDraft.settingFocusHex(model.draft, to: hex) }
    }

    private func presetChip(_ preset: FocusPreset) -> some View {
        let chosen = overlay.focusHex == preset.hex
        let color = SettingsRGB(hex: preset.hex)?.color ?? .white
        let neon = overlay.focusStyle == .neon
        let glows = neon && overlay.focusGlow
        return Button {
            chooseHex(preset.hex)
        } label: {
            VStack(spacing: 4) {
                Capsule().fill(color).frame(width: 30, height: 10)
                    // 네온이고 포커스 불빛이 켜져 있으면 견본이 은은히 빛난다(이중 글로우)
                    .shadow(color: glows ? color.opacity(0.75) : .clear, radius: glows ? 3 : 0)
                    .shadow(color: glows ? color.opacity(0.45) : .clear, radius: glows ? 8 : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Self.chipBackdrop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(preset.label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(5)
            .selectableCard(chosen: chosen, cornerRadius: 16)
        }
        .buttonStyle(SquishButtonStyle(pressedScale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("포커스 색: \(preset.label) \(preset.hex)")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// 칩 견본 바탕(어두운 단색): 밝은 색과 글로우가 모두 보인다
    private static let chipBackdrop = Color(red: 0.12, green: 0.13, blue: 0.17)

    // MARK: 사용자 지정 색

    private var isCustom: Bool { !FocusColors.presets.contains { $0.hex == overlay.focusHex } }
    private var hexInvalid: Bool { FocusColors.normalized(model.focusHexInput) == nil }

    /// ColorPicker ↔ hex 입력 ↔ 프리셋이 모두 `draft.overlay.focusHex` 한 값을 통해 동기화된다.
    private var customColorRow: some View {
        customRow(
            subject: "포커스 색", current: overlay.focusHex, input: $model.focusHexInput, invalid: hexInvalid, isCustom: isCustom,
            choose: chooseHex, edit: { model.draft = SettingsDraft.settingFocusHex(model.draft, to: $0) })
    }

    /// 포커스 색과 글라스 틴트가 함께 쓰는 사용자 지정 행(ColorPicker + `#RRGGBB` 입력).
    /// 입력 칸은 유효할 때만 draft 에 반영하므로(`edit`) 잘못된 입력은 입력 칸에만 남는다.
    private func customRow(subject: String, current: String, input: Binding<String>, invalid: Bool, isCustom: Bool,
                           choose: @escaping (String) -> Void, edit: @escaping (String) -> Void) -> some View {
        OneUIRow(
            symbol: "eyedropper", title: "사용자 지정",
            subtitle: invalid ? "#RRGGBB 형식으로 입력하세요" : (isCustom ? "직접 고른 색을 쓰는 중입니다." : "원하는 색을 직접 고르거나 입력하세요."),
            warnSubtitle: invalid) {
            HStack(spacing: 10) {
                ColorPicker("\(subject) 직접 고르기", selection: Binding(
                    get: { SettingsRGB(hex: current)?.color ?? .white },
                    set: { color in
                        if let hex = Self.hex(of: color) { choose(hex) }
                    }), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("\(subject) 직접 고르기")
                TextField("#RRGGBB", text: Binding(
                    get: { input.wrappedValue },
                    set: { text in
                        input.wrappedValue = text
                        edit(text)
                    }))
                    .font(.system(.body, design: .monospaced))
                    .oneUIField(cornerRadius: 16)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(invalid ? SettingsTheme.danger : (isCustom ? pal.accentText : Color.clear), lineWidth: 2))
                    .frame(width: 124)
                    .accessibilityLabel("\(subject) 16진수 입력")
            }
        }
    }

    // MARK: 글라스 틴트

    private var tintIsCustom: Bool { !GlassTints.presets.contains { $0.hex == overlay.glassTintHex } }
    private var tintInvalid: Bool { GlassTints.normalized(model.glassTintInput) == nil }

    private func chooseTint(_ hex: String) {
        withAnimation(Motion.animation(Motion.chewy)) { model.draft = SettingsDraft.settingGlassTint(model.draft, to: hex) }
    }

    /// 클리어 글라스를 골랐을 때만 보인다(다른 본체는 틴트를 쓰지 않는다).
    private var tintCard: some View {
        OneUICard(title: "글라스 틴트") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(GlassTints.presets, id: \.id) { preset in
                    tintChip(preset)
                }
            }
            .padding(14)
            OneUIDivider(inset: OneUI.rowInset)
            customRow(
                subject: "글라스 틴트", current: overlay.glassTintHex, input: $model.glassTintInput, invalid: tintInvalid, isCustom: tintIsCustom,
                choose: chooseTint, edit: { model.draft = SettingsDraft.settingGlassTint(model.draft, to: $0) })
        }
    }

    /// 칩: 실제 클리어 글라스 견본(`BodySwatch`)을 작게 보여 줘서 투명한 유리에 입힌 결과를 고르기 전에 본다. 선택은 테두리 + 체크로도 표시한다.
    private func tintChip(_ preset: GlassTintPreset) -> some View {
        let chosen = overlay.glassTintHex == preset.hex
        return Button {
            chooseTint(preset.hex)
        } label: {
            VStack(spacing: 4) {
                BodySwatch(kind: .clearGlass, glassTint: preset.hex, height: 40)
                HStack(spacing: 3) {
                    if chosen { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                    // 유리에 입힌 결과는 어둡게 눌려 비슷해 보이므로, 고른 원색을 작은 점으로 함께 보여 준다
                    Circle().fill(SettingsRGB(hex: preset.hex)?.color ?? .white).frame(width: 8, height: 8)
                    Text(preset.label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(5)
            .selectableCard(chosen: chosen, cornerRadius: 16)
        }
        .buttonStyle(SquishButtonStyle(pressedScale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("글라스 틴트: \(preset.label) \(preset.hex)")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// SwiftUI Color → `#RRGGBB`(sRGB). 변환할 수 없으면 nil.
    static func hex(of color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { min(255, max(0, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// 본체 카드 견본: 본체 색(면·글자·유리 질감)만 보여 준다. 강조색은 넣지 않는다.
/// 면·광택·받침·테두리는 실제 오버레이가 읽는 `PaletteColors.spec(for:glassTint:)`/`wedgeLayers` 값을 그대로 읽어, 본체 상수를 바꾸면 견본도 따라온다.
/// 광택·테두리 색은 오버레이처럼 `rimColor` 를 쓴다(클리어 글라스는 틴트색, 다른 본체는 글자색과 같다).
private struct BodySwatch: View {
    let kind: OverlayBody
    /// 클리어 글라스 견본이 읽는 틴트(다른 본체는 무시한다)
    let glassTint: String
    /// 틴트 칩은 작게 쓴다
    var height: CGFloat = 100

    var body: some View {
        let spec = PaletteColors.spec(for: kind, glassTint: glassTint)
        let compact = height < 60
        // 선택되지 않은 조각의 기본 층: 검은 받침 → 면 그룹(면 + 위쪽 광택). 견본은 본체 종류 비교용이라 설정 alpha 와 무관하게 0.74 로 고정한다(기본 alpha 가 낮아도 면 색이 읽히게).
        let layers = PaletteColors.wedgeLayers(spec: spec, style: .flat, selectedBase: 0, alpha: 0.74, sel: 0)
        let shape = RoundedRectangle(cornerRadius: compact ? 8 : 12)
        ZStack {
            // 바탕에 밝은 띠를 깔아 글라스의 투명도·광택이 보이게 한다(견본 바탕일 뿐 강조색이 아니다)
            FlatPreviewBackdrop<EmptyView>.color
            LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                shape.fill(Color.black.opacity(layers.underlay))
                ZStack {
                    shape.fill(spec.surfaceColor)
                    shape.fill(LinearGradient(colors: [spec.rimColor.opacity(spec.sheenTop), spec.rimColor.opacity(0)], startPoint: .top, endPoint: .center))
                }
                .compositingGroup()
                .opacity(layers.face)
                shape.stroke(spec.rimColor.opacity(spec.hairlineFloor * spec.hairlineBoost), lineWidth: 1)
            }
            .frame(maxWidth: 96).frame(height: height * 0.56)
            .padding(.horizontal, compact ? 8 : 0)
            if !compact {
                HStack(spacing: 6) {
                    Text("Aa").font(.system(size: 18, weight: .semibold))
                    Text("앱 이름").font(.system(size: 12, weight: .regular))
                }
                .foregroundStyle(spec.inkColor)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10))
        .accessibilityHidden(true)
    }
}

extension OverlayBody {
    var displayName: String {
        switch self {
        case .darkGray: return "다크 그레이"
        case .darkGlass: return "다크 글라스"
        case .clearGlass: return "클리어 글라스"
        }
    }
}

extension FocusStyle {
    var displayName: String {
        switch self {
        case .flat: return "플랫"
        case .neon: return "네온"
        }
    }
}
