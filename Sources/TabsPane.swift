import SwiftUI
import UniformTypeIdentifiers

/// 슬롯 목록에서 행을 끌 때 싣는 값(어느 탭의 몇 번 칸인지). 글자로 싣지 않아 입력칸에 놓아도 글자가 들어가지 않는다.
struct SlotDragItem: Codable, Transferable {
    let tabId: String
    let position: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// 선택한 탭의 편집 패널(이름·종류 + 슬롯 링 미리보기/목록/편집)
struct TabsPane: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: SettingsModel
    let tabIndex: Int

    /// 탭을 지운 직후 나가는 패널은 이미 없어진 인덱스로 다시 계산될 수 있다(탭 이름 Binding 의 get 은 `body` 의 범위 확인을 거치지 않는다). 그때는 빈 탭으로 본다.
    private var tab: Tab { model.draft.tabs.indices.contains(tabIndex) ? model.draft.tabs[tabIndex] : Tab(id: "", name: "", type: .custom) }
    /// 링 위치 8칸(0 = 12시, 시계 방향). 빈 칸은 nil.
    private var slots: [Slot?] { SettingsDraft.cells(tab) }
    private var selected: Int { max(0, min(model.selectedSlot, Limits.slots - 1)) }
    private var tabIssues: [ValidationIssue] { model.issues.filter { $0.tabIndex == tabIndex } }
    private var invalidSlots: Set<Int> { Set(tabIssues.compactMap(\.slotIndex)) }

    var body: some View {
        // 전환 중 나가는 패널이 이미 지워진 탭 인덱스로 다시 그려져도 범위를 벗어나지 않게 한다
        if model.draft.tabs.indices.contains(tabIndex) { editor }
    }

    private var editor: some View {
        OneUIPage(title: tab.name.isEmpty ? "(이름 없음)" : tab.name, subtitle: nil) {
            tabCard
            previewCard
            slotListCard
            if let slot = slots[selected] {
                SlotEditorView(
                    slot: slotBinding(selected), slotIndex: selected, apps: model.apps,
                    accent: model.palette.swatches.accentText.nsColor,
                    keyConflict: { SettingsDraft.slotKeyConflict(model.draft, tab: tabIndex, at: selected, key: $0) },
                    directionOwner: { SettingsDraft.slotUsingDirection(model.draft, tab: tabIndex, direction: $0, except: selected) },
                    onKey: { key in
                        // 기본으로 되돌리려는데 그 기본 키(칸 번호 숫자)를 다른 슬롯이 이미 쓰면 막고 이유를 보인다
                        let fallback = SlotKey.defaultKey(position: selected)
                        if key == nil, let reason = SettingsDraft.slotKeyConflict(model.draft, tab: tabIndex, at: selected, key: fallback) {
                            model.slotKeyHint = "기본 키(\(SlotKey.display(fallback)))로 되돌릴 수 없습니다 — \(reason)"
                            return
                        }
                        model.draft = SettingsDraft.settingSlotKey(model.draft, tab: tabIndex, at: selected, to: key)
                    },
                    onDirection: { model.draft = SettingsDraft.settingSlotDirection(model.draft, tab: tabIndex, at: selected, to: $0) },
                    keyHint: model.slotKeyHint,
                    onKeyHint: { model.slotKeyHint = $0 })
                    .id(slot.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        // 슬롯 추가/삭제/이동/선택은 모두 같은 스프링으로 자리를 잡는다. 칸별 슬롯 id 와 선택 번호만 본다(이름 타이핑에는 반응하지 않는다).
        .animation(Motion.animation(Motion.chewy), value: slots.map { $0?.id })
        .animation(Motion.animation(Motion.chewy), value: selected)
    }

    /// 이름 편집 + 종류 칩 (+ 탭 단위 검증 이슈)
    private var tabCard: some View {
        OneUICard(title: "탭") {
            OneUIRow(title: "탭 이름") {
                TextField("탭 이름", text: Binding(
                    get: { tab.name },
                    set: { model.draft = SettingsDraft.renameTab(model.draft, at: tabIndex, String($0.prefix(20))) }))
                    .oneUIField()
                    .frame(width: 260)
                    .accessibilityLabel("탭 이름")
            }
            OneUIDivider(inset: OneUI.rowInset)
            OneUIRow(title: "탭 종류") {
                Text(tab.type.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pal.accentText)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(pal.accentText.opacity(0.18), in: Capsule())
                    .accessibilityLabel("탭 종류: \(tab.type.label)")
            }
            ForEach(Array(tabIssues.filter { $0.slotIndex == nil }.enumerated()), id: \.offset) { _, issue in
                OneUIDivider(inset: OneUI.rowInset)
                Text(issue.text).font(.callout).foregroundStyle(SettingsTheme.danger)
                    .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
            }
        }
    }

    private var previewCard: some View {
        OneUICard(title: "슬롯 미리보기") {
            VStack(spacing: 10) {
                FlatPreviewBackdrop(height: 280) {
                    // 실제 오버레이와 같은 모양. 조각을 누르면 그 슬롯을 편집한다(링 크기에 맞춰 영역을 꽉 채운다).
                    ThemedPreview(
                        theme: model.draft.overlay.theme, slots: slots, icons: PiePreview.icons(for: slots, showIcons: model.draft.overlay.showIcons, catalog: model.catalog),
                        keyLabels: Keymap.build(slots: tab.slots, closeKey: model.draft.closeKey).keyLabels,
                        selected: selected, invalid: invalidSlots,
                        style: PiePreviewStyle(model.draft.overlay), maxSize: 280, referenceRing: model.draft.overlay.ringSize,
                        onSelect: { i in
                            if slots[i] != nil {
                                model.selectedSlot = i
                            } else if SettingsDraft.canAddSlot(model.draft, tab: tabIndex) {
                                // 빈 조각을 누르면 그 자리에 새 슬롯을 만들고 고른다
                                chewyChange {
                                    model.draft = SettingsDraft.addSlot(model.draft, tab: tabIndex, at: i)
                                    model.selectedSlot = i
                                }
                            }
                        })
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                hintText("조각을 누르면 그 슬롯을 편집하고, 빈 조각을 누르면 그 자리에 새 슬롯을 만듭니다. 번호는 링 위치입니다 (1 = 12시, 시계 방향).")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    private func slotBinding(_ i: Int) -> Binding<Slot> {
        Binding(
            get: {
                let list = model.draft.tabs.indices.contains(tabIndex) ? SettingsDraft.cells(model.draft.tabs[tabIndex]) : []
                return (list.indices.contains(i) ? list[i] : nil) ?? Slot(id: "", name: "", label: nil, action: SettingsDraft.defaultAction(.launchApp))
            },
            set: { value in
                model.draft = SettingsDraft.updateSlot(model.draft, tab: tabIndex, at: i) { $0 = value }
            })
    }

    /// 링 위치 번호(1~8)에 대응하는 시계 방향 표기. 손으로 고친 파일의 8칸 밖 슬롯은 "범위 밖".
    private static let clockLabels = ["12시", "1시 반", "3시", "4시 반", "6시", "7시 반", "9시", "10시 반"]
    private static func clockLabel(_ i: Int) -> String { clockLabels.indices.contains(i) ? clockLabels[i] : "범위 밖" }

    private var slotListCard: some View {
        OneUICard(title: "슬롯 (\(slots.compactMap { $0 }.count)/\(Limits.slots))") {
            // 8칸 밖(손으로 고친 파일)에 슬롯이 있으면 지울 수 있게 그 칸까지 보인다. 8칸 밖의 빈 칸은 숨긴다.
            ForEach(0..<slots.count, id: \.self) { i in
                if i < Limits.slots || slots[i] != nil {
                    if i > 0 { OneUIDivider(inset: OneUI.rowInset) }
                    if let slot = slots[i] { slotRow(i, slot) } else { emptyRow(i) }
                }
            }
            OneUIDivider(inset: OneUI.rowInset)
            hintText("빈 칸의 + 로 슬롯을 추가합니다. 슬롯을 끌어 다른 칸에 놓으면 옮기고, 슬롯이 있는 칸이면 서로 바꿉니다. 칸은 비워 둬도 됩니다(예: 12시와 6시만).")
                .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
            ForEach(Array(tabIssues.filter { $0.slotIndex != nil }.enumerated()), id: \.offset) { _, issue in
                OneUIDivider(inset: OneUI.rowInset)
                Text(issue.text).font(.callout).foregroundStyle(SettingsTheme.danger)
                    .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
            }
        }
    }

    /// 칸마다 같은 드롭 처리: 끌어온 슬롯이 이 칸으로 옮겨지거나(빈 칸) 이 칸의 슬롯과 바뀐다(찬 칸).
    private func droppable<Content: View>(_ i: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay {
                if model.slotDropTarget == i {
                    Rectangle().stroke(pal.accentText, lineWidth: 2)
                }
            }
            .dropDestination(for: SlotDragItem.self) { items, _ in
                model.slotDropTarget = nil
                guard let dragged = items.first, dragged.tabId == tab.id else { return false }
                let next = SettingsDraft.moveSlot(model.draft, tab: tabIndex, from: dragged.position, to: i)
                guard next != model.draft else { return false }
                chewyChange {
                    model.draft = next
                    model.selectedSlot = i
                }
                return true
            } isTargeted: { targeted in
                if targeted { model.slotDropTarget = i } else if model.slotDropTarget == i { model.slotDropTarget = nil }
            }
    }

    private func numberChip(_ i: Int, selected isSelected: Bool, filled: Bool) -> some View {
        Text("\(i + 1)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? pal.onAccentFace : (filled ? pal.accentText : pal.muted))
            .frame(width: OneUI.chipSize, height: OneUI.chipSize)
            .background(isSelected ? pal.accentFace : (filled ? pal.accentText.opacity(0.18) : pal.muted.opacity(0.14)),
                        in: RoundedRectangle(cornerRadius: OneUI.chipSize * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    private func emptyRow(_ i: Int) -> some View {
        let isSelected = i == selected
        return droppable(i) {
            Button {
                chewyChange {
                    model.draft = SettingsDraft.addSlot(model.draft, tab: tabIndex, at: i)
                    model.selectedSlot = i
                }
            } label: {
                HStack(spacing: 14) {
                    numberChip(i, selected: isSelected, filled: false)
                    Text("비어 있음")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(pal.muted)
                    Spacer(minLength: 0)
                    Text(Self.clockLabel(i)).font(.system(size: 12)).foregroundStyle(pal.muted)
                    Image(systemName: "plus").foregroundStyle(pal.accentText)
                }
                .padding(.horizontal, OneUI.rowInset).padding(.vertical, 8)
                .frame(minHeight: OneUI.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(SquishButtonStyle(pressedScale: 0.985))
            .accessibilityLabel("\(Self.clockLabel(i)) 칸(\(i + 1)번)에 슬롯 추가")
        }
    }

    private func slotRow(_ i: Int, _ slot: Slot) -> some View {
        let isSelected = i == selected
        return droppable(i) {
            HStack(spacing: 6) {
                Button { chewyChange { model.selectedSlot = i } } label: {
                    HStack(spacing: 14) {
                        // 번호 칩: 선택되면 포커스 색 면 + 면 위 글자색
                        numberChip(i, selected: isSelected, filled: true)
                        Text(slot.name.isEmpty ? "(이름 없음)" : slot.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(pal.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Self.clockLabel(i)).font(.system(size: 12)).foregroundStyle(pal.muted)
                        if invalidSlots.contains(i) { Text("⚠").foregroundStyle(SettingsTheme.warn).accessibilityLabel("문제 있음") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SquishButtonStyle(pressedScale: 0.985))
                .draggable(SlotDragItem(tabId: tab.id, position: i))
                .accessibilityLabel("슬롯 \(i + 1) \(slot.name) 선택")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                iconButton("plus.square.on.square", "슬롯 \(i + 1) 복제", disabled: !SettingsDraft.canAddSlot(model.draft, tab: tabIndex)) {
                    chewyChange {
                        // 복제본이 들어가는 칸을 고른다
                        guard let target = SettingsDraft.duplicateTarget(tab, at: i) else { return }
                        model.draft = SettingsDraft.duplicateSlot(model.draft, tab: tabIndex, at: i)
                        model.selectedSlot = target
                    }
                }
                iconButton("trash", "슬롯 \(i + 1) 삭제", destructive: true) {
                    chewyChange { model.draft = SettingsDraft.removeSlot(model.draft, tab: tabIndex, at: i) }
                }
            }
            .padding(.horizontal, OneUI.rowInset).padding(.vertical, 8)
            .frame(minHeight: OneUI.rowMinHeight)
            .background(isSelected ? pal.selection : Color.clear)
            .overlay(alignment: .leading) {
                // 문제 있는 슬롯은 왼쪽 가장자리 경고색 막대로 표시한다
                Rectangle().fill(invalidSlots.contains(i) ? SettingsTheme.warn : Color.clear).frame(width: 3)
            }
        }
    }
}
