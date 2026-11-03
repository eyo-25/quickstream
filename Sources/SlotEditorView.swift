import AppKit
import SwiftUI

/// 선택한 슬롯의 이름·라벨·키·방향키·동작 편집(카드 하나)
struct SlotEditorView: View {
    @Environment(\.settingsPalette) private var pal
    @Binding var slot: Slot
    let slotIndex: Int
    let apps: [InstalledApp]
    /// 키 녹화 중 테두리 색(설정 창의 포커스 색)
    var accent = NSColor(srgbRed: 0.302, green: 0.639, blue: 1.0, alpha: 1)
    /// 이 키를 슬롯 키로 못 쓰는 이유(닫기 키·같은 탭의 다른 슬롯과 겹침). 쓸 수 있으면 nil.
    var keyConflict: (String) -> String? = { _ in nil }
    /// 이 방향을 이미 쓰는 같은 탭의 다른 슬롯 링 위치(없으면 nil)
    var directionOwner: (SlotDirection) -> Int? = { _ in nil }
    /// 키·방향 변경(nil 이면 기본으로 되돌림). 겹침 검사와 저장 형태 정리는 호출 측(`SettingsDraft`)이 한다.
    var onKey: (String?) -> Void = { _ in }
    var onDirection: (SlotDirection?) -> Void = { _ in }
    var keyHint: String?
    var onKeyHint: (String?) -> Void = { _ in }

    private var defaultKey: String { SlotKey.defaultKey(position: slotIndex) }
    private var defaultDirection: SlotDirection { SlotDirection.ring(slotIndex) }
    private var currentDirection: SlotDirection { slot.direction ?? defaultDirection }

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
            OneUIRow(
                title: "키",
                subtitle: keyHint ?? "오버레이에서 이 키(영문자·숫자)를 누르면 실행합니다. 기본은 칸 번호 \(defaultKey)이고, Delete 로 기본으로 되돌립니다.",
                warnSubtitle: keyHint != nil) {
                KeyRecorder(
                    display: SlotKey.display(slot.key ?? defaultKey) + (slot.key == nil || slot.key == defaultKey ? " (기본)" : ""),
                    accent: accent,
                    accessibilityLabel: "슬롯 \(slotIndex + 1) 키 녹화. 클릭한 뒤 영문자나 숫자 키를 누르세요",
                    validate: keyConflict,
                    onChange: onKey,
                    onHint: onKeyHint)
                    .frame(width: 130, height: 30)
            }
            OneUIDivider(inset: OneUI.rowInset)
            OneUIRow(
                title: "방향키",
                subtitle: "방향키로 이 슬롯을 고르는 조합입니다(대각선은 두 키를 함께). 기본은 링 위치의 방향 \(defaultDirection.label) 입니다.") {
                directionMenu
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

    /// 8방향 + 없음. 같은 탭의 다른 슬롯이 쓰는 방향은 누가 쓰는지 보이고 고를 수 없다.
    private var directionMenu: some View {
        Menu {
            ForEach(SlotDirection.allCases, id: \.self) { direction in
                let owner = directionOwner(direction)
                Button {
                    onDirection(direction)
                } label: {
                    Text(menuTitle(direction, owner: owner))
                }
                .disabled(owner != nil)
            }
            if slot.direction != nil {
                Divider()
                Button("기본으로 되돌리기 (\(defaultDirection.label))") { onDirection(nil) }
                    .disabled(directionOwner(defaultDirection) != nil)
            }
        } label: {
            Text(currentDirection.label + (currentDirection == defaultDirection ? " (기본)" : ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.accentText)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(pal.accentText.opacity(0.18), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("슬롯 \(slotIndex + 1) 방향키: \(currentDirection.label)")
    }

    private func menuTitle(_ direction: SlotDirection, owner: Int?) -> String {
        var title = direction.label
        if direction == defaultDirection { title += " (기본)" }
        if let owner { title += " — 슬롯 \(owner + 1) 사용 중" }
        return title
    }
}
