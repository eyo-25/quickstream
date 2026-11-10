import SwiftUI
import UniformTypeIdentifiers

/// 사이드바에서 탭 행을 끌 때 싣는 값(탭 id). 글자로 싣지 않아 입력칸 위에 놓아도 글자가 들어가지 않는다.
struct TabDragItem: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}


/// 화면 전환 키: 같은 종류의 패널로 돌아와도 키가 같으면 전환하지 않는다
private func contentKey(_ selection: SettingsModel.Selection) -> String {
    switch selection {
    case .general: return "general"
    case .panel: return "panel"
    case .about: return "about"
    case let .tab(id): return "tab:\(id)"
    }
}

/// 변경을 쫀득한 스프링으로 감싼다(동작 줄이기이면 즉시). 표현만 바꾸고 클로저의 로직은 그대로 실행된다.
func chewyChange(_ body: () -> Void) {
    withAnimation(Motion.animation(Motion.chewy), body)
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    /// 선택한 본체 색·포커스 색에서 도출한 설정 창 색. 하위 뷰는 환경으로 받는다(모델을 구독하지 않는 슬롯 편집기 등도 즉시 따라온다).
    private var pal: SettingsPalette { model.palette }

    var body: some View {
        VStack(spacing: 0) {
            if let warning = model.warning {
                VStack(alignment: .leading, spacing: 2) {
                    Text("설정 파일을 읽지 못해 기본값을 사용 중입니다. \(warning)").fontWeight(.semibold)
                    Text("저장하면 기존 파일은 .bak 으로 보존됩니다.")
                }
                .font(.callout)
                .foregroundStyle(SettingsTheme.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(SettingsTheme.warn.opacity(0.12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("경고: 설정 파일을 읽지 못해 기본값을 사용 중입니다. 저장하면 기존 파일은 백업으로 보존됩니다.")
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                SettingsSidebar(model: model)
                    .frame(width: 236)
                    .background(pal.sidebar)
                Divider().overlay(pal.line)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider().overlay(pal.line)
            SettingsFooter(model: model)
        }
        .background(pal.background)
        .foregroundStyle(pal.text)
        .tint(pal.accentText)
        .preferredColorScheme(.dark)
        .environment(\.settingsPalette, pal)
        .animation(Motion.animation(Motion.soft), value: pal)
        .animation(Motion.animation(Motion.soft), value: model.warning)
    }

    /// 우측 패널. 항목이 바뀌면 새 패널이 6~8pt 옆에서 스프링으로 들어오며 크로스페이드한다.
    /// 나가는 패널은 투명해질 뿐 입력을 받지 않는다(allowsHitTesting) — 빠르게 연속 전환해도 막히지 않는다.
    private var content: some View {
        ZStack(alignment: .topLeading) {
            pane
                .id(contentKey(model.selection))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 8)),
                    removal: .opacity))
        }
        .animation(Motion.animation(Motion.soft), value: contentKey(model.selection))
        .clipped()
    }

    /// 각 화면은 스스로 스크롤과 큰 제목을 가진다(`OneUIPage`).
    @ViewBuilder private var pane: some View {
        switch model.selection {
        case .general:
            GeneralPane(model: model)
        case .panel:
            PanelPane(model: model)
        case .about:
            AboutPane(model: model)
        case .tab:
            if let index = model.tabIndex {
                TabsPane(model: model, tabIndex: index)
            } else {
                GeneralPane(model: model)
            }
        }
    }
}

/// 눌렀을 때 살짝 쪼그라들었다가 스프링으로 돌아오는 버튼 스타일(스타일 자체는 내용을 바꾸지 않는다)
struct SquishButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(Motion.animation(Motion.snap), value: configuration.isPressed)
    }
}

/// 사이드바 행: 아이콘 칩 + 제목. 선택 강조는 행 사이를 미끄러지는(matchedGeometryEffect) 큰 알약 하나, hover 는 snap 페이드.
private struct SidebarRow: View {
    @Environment(\.settingsPalette) private var pal
    let symbol: String
    let title: String
    let detail: String?
    let selected: Bool
    let warn: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @StateObject private var hover = OneUIHover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                OneUIIconChip(symbol: symbol, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .medium)).lineLimit(1)
                        .foregroundStyle(selected ? pal.selectionText : pal.text)
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(selected ? pal.selectionText : pal.muted).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if warn { Text("⚠").foregroundStyle(SettingsTheme.warn).accessibilityLabel("문제 있음") }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 999, style: .continuous).fill(pal.text.opacity(hover.on && !selected ? 0.06 : 0))
                    if selected {
                        SelectionPill()
                            .matchedGeometryEffect(id: "sidebar-selection", in: namespace)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { hover.on = $0 }
        .animation(Motion.animation(Motion.snap), value: hover.on)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsSidebar: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: SettingsModel
    @Namespace private var selectionSpace

    /// 선택 이동은 soft 스프링으로 강조가 미끄러지게 한다. 선택값만 바꾸며 다른 로직은 없다.
    private func select(_ selection: SettingsModel.Selection) {
        withAnimation(Motion.animation(Motion.soft)) { model.selection = selection }
    }

    private func tabHasIssue(_ i: Int) -> Bool { model.issues.contains { $0.tabIndex == i } }
    private var generalHasIssue: Bool { model.issues.contains { $0.tabIndex == nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                header("설정")
                row(symbol: "gearshape", title: "일반", detail: nil, selected: model.selection == .general, warn: generalHasIssue) {
                    select(.general)
                }
                row(symbol: "circle.hexagongrid", title: "패널 모양", detail: nil, selected: model.selection == .panel, warn: false) {
                    select(.panel)
                }

                HStack {
                    header("탭 (\(model.draft.tabs.count)/\(Limits.maxTabs))")
                    Spacer()
                    addButton
                }
                .padding(.top, 14)

                ForEach(Array(model.draft.tabs.enumerated()), id: \.element.id) { i, tab in
                    let selected = model.selection == .tab(tab.id)
                    VStack(alignment: .leading, spacing: 4) {
                        row(symbol: "square.grid.2x2", title: tab.name.isEmpty ? "(이름 없음)" : tab.name, detail: nil, selected: selected, warn: tabHasIssue(i)) {
                            select(.tab(tab.id))
                        }
                        .draggable(TabDragItem(id: tab.id))
                        if selected {
                            tabTools(index: i, tab: tab)
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
                        }
                    }
                    // 놓을 자리 표시: 끌고 온 탭이 이 탭이 있던 자리로 들어간다(위에서 내려오면 아래로, 아래에서 올라오면 위로 밀린다)
                    .overlay {
                        if model.tabDropTarget == tab.id {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.accentText, lineWidth: 2)
                        }
                    }
                    .dropDestination(for: TabDragItem.self) { items, _ in
                        model.tabDropTarget = nil
                        guard let dragged = items.first else { return false }
                        chewyChange { model.moveTab(id: dragged.id, onto: tab.id) }
                        return true
                    } isTargeted: { targeted in
                        if targeted { model.tabDropTarget = tab.id } else if model.tabDropTarget == tab.id { model.tabDropTarget = nil }
                    }
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }

                header("정보").padding(.top, 14)
                row(symbol: "info.circle", title: "퀵스트림 정보", detail: nil, selected: model.selection == .about, warn: false) {
                    select(.about)
                }
            }
            .padding(12)
            .animation(Motion.animation(Motion.chewy), value: model.draft.tabs.map(\.id))
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(pal.muted)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(symbol: String, title: String, detail: String?, selected: Bool, warn: Bool, action: @escaping () -> Void) -> some View {
        SidebarRow(symbol: symbol, title: title, detail: detail, selected: selected, warn: warn, namespace: selectionSpace, action: action)
    }

    private var addButton: some View {
        Button { chewyChange { model.addTab() } } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .disabled(!SettingsDraft.canAddTab(model.draft))
        .accessibilityLabel("탭 추가")
    }

    private func tabTools(index i: Int, tab: Tab) -> some View {
        HStack(spacing: 6) {
            iconButton("arrow.up", "\(tab.name) 탭 위로 이동", disabled: i == 0) { chewyChange { model.moveSelectedTab(by: -1) } }
            iconButton("arrow.down", "\(tab.name) 탭 아래로 이동", disabled: i == model.draft.tabs.count - 1) { chewyChange { model.moveSelectedTab(by: 1) } }
            iconButton("plus.square.on.square", "\(tab.name) 탭 복제", disabled: !SettingsDraft.canAddTab(model.draft)) {
                chewyChange { model.duplicateSelectedTab() }
            }
            iconButton("trash", "\(tab.name) 탭 삭제", disabled: model.draft.tabs.count <= 1, destructive: true) { chewyChange { model.removeSelectedTab() } }
        }
        .padding(.leading, 12)
        .padding(.bottom, 2)
    }
}

/// 작은 원형 아이콘 버튼(접근성 레이블 필수)
func iconButton(_ symbol: String, _ label: String, disabled: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
    OneUIIconButton(symbol: symbol, label: label, destructive: destructive, action: action)
        .disabled(disabled)
}

private struct OneUIIconButton: View {
    @Environment(\.settingsPalette) private var pal
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = OneUIHover()
    let symbol: String
    let label: String
    let destructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(destructive ? SettingsTheme.danger : pal.text)
                .frame(width: 28, height: 28)
                .background(Circle().fill(pal.field))
                .overlay(Circle().fill(pal.text.opacity(hover.on && isEnabled ? 0.1 : 0)))
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .buttonStyle(SquishButtonStyle(pressedScale: 0.9))
        .onHover { hover.on = $0 }
        .animation(Motion.animation(Motion.snap), value: hover.on)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 흔들림: 값이 1 늘 때마다 좌우로 한 번 왕복한다. 두 번 왕복(≈2회 짧게)하도록 사인 2주기.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 4
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // 정수 지점(애니메이션 시작/끝)에서는 sin 이 0 이라 정지 상태에는 변위가 남지 않는다
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(progress * .pi * 4), y: 0))
    }
}

/// 하단 영역: 자주 쓰는 조작(되돌리기/저장)을 큰 알약 버튼으로 둔다.
private struct SettingsFooter: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                // 종류가 바뀔 때만(저장 성공 → "변경 사항 없음" 등) 새 문구가 아래에서 튀어 오른다
                status
                    .id(model.statusKind)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .animation(Motion.animation(Motion.chewy), value: model.statusKind)
            .modifier(ShakeEffect(progress: CGFloat(model.errorFeedback)))
            .animation(Motion.animation(.linear(duration: 0.34)), value: model.errorFeedback)
            .lineLimit(2)
            .accessibilityElement(children: .combine)
            OneUIPillButton(title: "되돌리기", kind: .secondary, large: true) { model.revert() }
                .disabled(!model.isDirty)
                .accessibilityLabel("변경 사항 되돌리기")
            OneUIPillButton(title: "저장", kind: .primary, large: true) { chewyChange { model.save() } }
                .disabled(!model.canSave)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("설정 저장")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(pal.sidebar)
    }

    @ViewBuilder private var status: some View {
        if let error = model.saveError {
            Text("저장하지 못했습니다: \(error)").foregroundStyle(SettingsTheme.danger)
        } else if let first = model.issues.first {
            Text("⚠ \(first.text)\(model.issues.count > 1 ? " 외 \(model.issues.count - 1)건" : "")").foregroundStyle(SettingsTheme.danger)
        } else if model.isDirty {
            Text("저장하지 않은 변경 사항이 있습니다")
        } else {
            Text("변경 사항 없음 · \(model.store.fileURL.path)").foregroundStyle(pal.muted)
        }
    }
}
