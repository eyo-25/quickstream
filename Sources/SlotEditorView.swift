import SwiftUI

/// 선택한 슬롯의 이름·라벨·동작 편집(카드 하나)
struct SlotEditorView: View {
    @Binding var slot: Slot
    let slotIndex: Int
    let apps: [InstalledApp]

    var body: some View {
        OneUICard(title: "슬롯 \(slotIndex + 1) 편집") {
            OneUIRow(title: "이름") {
                TextField("슬롯 이름", text: Binding(get: { slot.name }, set: { slot.name = String($0.prefix(40)) }))
                    .oneUIField()
                    .frame(width: 260)
                    .accessibilityLabel("슬롯 \(slotIndex + 1) 이름")
            }
            OneUIDivider(inset: OneUI.rowInset)
            OneUIRow(title: "라벨", subtitle: "0~3자. 비우면 이름에서 자동으로 만듭니다.") {
                TextField(slotInitials(slot.name), text: Binding(
                    get: { slot.label ?? "" },
                    set: { slot = SettingsDraft.withLabel(slot, String($0.prefix(3))) }))
                    .oneUIField()
                    .frame(width: 90)
                    .accessibilityLabel("슬롯 \(slotIndex + 1) 라벨")
            }
            OneUIDivider(inset: OneUI.rowInset)
            ActionEditorView(
                action: Binding(
                    get: { slot.action },
                    set: { slot = SettingsDraft.applyingAction($0, to: slot, apps: apps) }),
                apps: apps,
                allowMacro: true,
                label: "슬롯 \(slotIndex + 1)")
        }
    }
}
