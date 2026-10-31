import SwiftUI

/// 선택한 탭의 편집 패널(이름·종류 + 슬롯 링 미리보기/목록/편집)
struct TabsPane: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: SettingsModel
    let tabIndex: Int

    private var tab: Tab { model.draft.tabs[tabIndex] }
    private var slots: [Slot] { tab.slots }
    private var selected: Int { max(0, min(model.selectedSlot, slots.count - 1)) }
    private var tabIssues: [ValidationIssue] { model.issues.filter { $0.tabIndex == tabIndex } }
    private var invalidSlots: Set<Int> { Set(tabIssues.compactMap(\.slotIndex)) }

    var body: some View {
        // 전환 중 나가는 패널이 이미 지워진 탭 인덱스로 다시 그려져도 범위를 벗어나지 않게 한다
        if model.draft.tabs.indices.contains(tabIndex) { editor }
    }

    private var editor: some View {
        OneUIPage(title: tab.name.isEmpty ? "(이름 없음)" : tab.name, subtitle: nil) {
            tabCard
            if tab.type == .recentApps {
                OneUICard(title: nil) {
                    OneUIRow(symbol: "clock.arrow.circlepath", title: "최근 사용 순",
                             subtitle: "현재 실행 중인 앱이 최근 사용 순으로 자동 채워집니다.")
                }
            } else {
                previewCard
                slotListCard
                if slots.indices.contains(selected) {
                    SlotEditorView(slot: slotBinding(selected), slotIndex: selected, apps: model.apps)
                        .id(slots[selected].id)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
        }
        // 슬롯 추가/삭제/이동/선택은 모두 같은 스프링으로 자리를 잡는다. 슬롯 id 배열과 선택 번호만 본다(이름 타이핑에는 반응하지 않는다).
        .animation(Motion.animation(Motion.chewy), value: slots.map(\.id))
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
                        selected: selected, invalid: invalidSlots,
                        style: PiePreviewStyle(model.draft.overlay), maxSize: 280, referenceRing: model.draft.overlay.ringSize,
                        onSelect: { i in
                            if slots.indices.contains(i) {
                                model.selectedSlot = i
                            } else if SettingsDraft.canAddSlot(model.draft, tab: tabIndex) {
                                // 빈 칸(+)을 누르면 맨 끝에 새 슬롯을 추가하고 고른다(눌린 조각이 아닌 슬롯이 선택되지 않게)
                                chewyChange {
                                    model.draft = SettingsDraft.addSlot(model.draft, tab: tabIndex)
                                    model.selectedSlot = slots.count
                                }
                            }
                        })
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                hintText("조각을 눌러 슬롯을 고릅니다. 번호는 링 위치입니다 (1 = 12시, 시계 방향).")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    private func slotBinding(_ i: Int) -> Binding<Slot> {
        Binding(
            get: {
                let list = model.draft.tabs.indices.contains(tabIndex) ? model.draft.tabs[tabIndex].slots : []
                return list.indices.contains(i) ? list[i] : Slot(id: "", name: "", label: nil, action: SettingsDraft.defaultAction(.launchApp))
            },
            set: { value in
                model.draft = SettingsDraft.updateSlot(model.draft, tab: tabIndex, at: i) { $0 = value }
            })
    }

    private var slotListCard: some View {
        OneUICard(title: "슬롯 (\(slots.count)/\(Limits.slots))") {
            OneUIRow(symbol: "plus", title: "슬롯 추가", enabled: SettingsDraft.canAddSlot(model.draft, tab: tabIndex), action: {
                let newIndex = slots.count
                chewyChange {
                    model.draft = SettingsDraft.addSlot(model.draft, tab: tabIndex)
                    model.selectedSlot = newIndex
                }
            })
            .accessibilityLabel("슬롯 추가")
            if slots.isEmpty {
                OneUIDivider(inset: OneUI.rowInset)
                hintText("슬롯이 없습니다. ‘슬롯 추가’를 눌러 시작하세요.")
                    .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                OneUIDivider(inset: OneUI.rowInset)
                slotRow(i, slot)
            }
            ForEach(Array(tabIssues.filter { $0.slotIndex != nil }.enumerated()), id: \.offset) { _, issue in
                OneUIDivider(inset: OneUI.rowInset)
                Text(issue.text).font(.callout).foregroundStyle(SettingsTheme.danger)
                    .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
            }
        }
    }

    private func slotRow(_ i: Int, _ slot: Slot) -> some View {
        let isSelected = i == selected
        return HStack(spacing: 6) {
            Button { chewyChange { model.selectedSlot = i } } label: {
                HStack(spacing: 14) {
                    // 번호 칩: 선택되면 포커스 색 면 + 면 위 글자색
                    Text("\(i + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? pal.onAccentFace : pal.accentText)
                        .frame(width: OneUI.chipSize, height: OneUI.chipSize)
                        .background(isSelected ? pal.accentFace : pal.accentText.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: OneUI.chipSize * 0.3, style: .continuous))
                        .accessibilityHidden(true)
                    Text(slot.name.isEmpty ? "(이름 없음)" : slot.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(pal.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if invalidSlots.contains(i) { Text("⚠").foregroundStyle(SettingsTheme.warn).accessibilityLabel("문제 있음") }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SquishButtonStyle(pressedScale: 0.985))
            .accessibilityLabel("슬롯 \(i + 1) \(slot.name) 선택")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            iconButton("arrow.up", "슬롯 \(i + 1) 위로 이동", disabled: i == 0) {
                chewyChange {
                    model.draft = SettingsDraft.moveSlot(model.draft, tab: tabIndex, at: i, by: -1)
                    model.selectedSlot = i - 1
                }
            }
            iconButton("arrow.down", "슬롯 \(i + 1) 아래로 이동", disabled: i == slots.count - 1) {
                chewyChange {
                    model.draft = SettingsDraft.moveSlot(model.draft, tab: tabIndex, at: i, by: 1)
                    model.selectedSlot = i + 1
                }
            }
            iconButton("plus.square.on.square", "슬롯 \(i + 1) 복제", disabled: !SettingsDraft.canAddSlot(model.draft, tab: tabIndex)) {
                chewyChange {
                    model.draft = SettingsDraft.duplicateSlot(model.draft, tab: tabIndex, at: i)
                    model.selectedSlot = i + 1
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
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
    }
}
