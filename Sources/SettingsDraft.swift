import Foundation

/// 설정 창의 불변 편집 헬퍼(UI 와 무관한 순수 로직). 모든 함수는 새 Settings 를 돌려주고, 불가능한 편집은 입력을 그대로 돌려준다.
enum SettingsDraft {
    /// 슬롯 액션 종류(설정 창의 "동작 종류" 선택지). activateApp 은 사용자가 고르지 않고 옛 설정에만 남아 있을 수 있다.
    enum ActionKind: CaseIterable, Equatable {
        case launchApp, openURL, clipboardText, macroSequence, activateApp

        var label: String {
            switch self {
            case .launchApp: return "앱 실행/전환"
            case .openURL: return "URL 열기"
            case .clipboardText: return "클립보드 텍스트"
            case .macroSequence: return "매크로"
            case .activateApp: return "앱 전환(자동)"
            }
        }

        /// 슬롯에서 새로 고를 수 있는 종류
        static let slotChoices: [ActionKind] = [.launchApp, .openURL, .clipboardText, .macroSequence]
        /// 매크로 단계에서 고를 수 있는 종류(매크로 중첩·activate 금지)
        static let stepChoices: [ActionKind] = [.launchApp, .openURL, .clipboardText]
    }

    /// launch_app 이 담는 필드. 정확히 하나만 둔다.
    enum AppField { case bundleId, appPath }

    static func kind(of action: Action) -> ActionKind {
        switch action {
        case .launchApp: return .launchApp
        case .openURL: return .openURL
        case .clipboardText: return .clipboardText
        case .macroSequence: return .macroSequence
        case .activateApp: return .activateApp
        }
    }

    // MARK: id

    private static let idAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// 기존 id 와 겹치지 않는 `prefix-xxxxxx`
    static func newId(_ prefix: String, taken: some Collection<String>) -> String {
        let used = Set(taken)
        while true {
            let id = prefix + "-" + String((0..<6).map { _ in idAlphabet.randomElement()! })
            if !used.contains(id) { return id }
        }
    }

    // MARK: 라벨

    /// 앞뒤 공백을 지우고, 비면 nil(저장 데이터에서 필드를 생략한다)
    static func normalizeLabel(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func withLabel(_ slot: Slot, _ label: String) -> Slot {
        var next = slot
        next.label = normalizeLabel(label)
        return next
    }

    /// 타일에 표시되는 약어: 지정 라벨 또는 이름에서 자동 생성
    static func displayLabel(_ slot: Slot) -> String {
        slot.label ?? slotInitials(slot.name)
    }

    // MARK: 액션

    static func defaultAction(_ kind: ActionKind) -> Action {
        switch kind {
        case .launchApp: return .launchApp(bundleId: "", appPath: nil)
        case .openURL: return .openURL("https://")
        case .clipboardText: return .clipboardText("")
        case .macroSequence: return .macroSequence(stopOnError: true, steps: [defaultAction(.launchApp)])
        case .activateApp: return .activateApp(bundleId: "", pid: nil)
        }
    }

    /// 종류를 바꾸면 기존 필드는 버리고 새 종류의 기본값으로 시작한다.
    static func changeActionKind(_ action: Action, to kind: ActionKind) -> Action {
        self.kind(of: action) == kind ? action : defaultAction(kind)
    }

    /// launch_app: bundleId / appPath 중 선택한 하나만 둔다. 값이 비어도 선택한 필드를 유지한다(빈 값은 검증이 잡는다).
    /// 값 유무로 모드를 추론하면 ".app 경로" 모드를 켜거나 비울 수 없다.
    static func launchApp(_ field: AppField, _ value: String) -> Action {
        field == .bundleId ? .launchApp(bundleId: value, appPath: nil) : .launchApp(bundleId: nil, appPath: value)
    }

    // MARK: 탭

    static func canAddTab(_ s: Settings) -> Bool { s.tabs.count < Limits.maxTabs }

    static func addTab(_ s: Settings, _ type: TabKind, name: String? = nil) -> Settings {
        guard canAddTab(s) else { return s }
        var next = s
        next.tabs.append(Tab(id: newId("tab", taken: s.tabs.map(\.id)), name: name ?? type.label, type: type))
        return next
    }

    static func removeTab(_ s: Settings, at index: Int) -> Settings {
        guard s.tabs.count > 1, s.tabs.indices.contains(index) else { return s }
        var next = s
        next.tabs.remove(at: index)
        return next
    }

    static func moved<T>(_ list: [T], _ index: Int, _ delta: Int) -> [T] {
        let to = index + delta
        guard list.indices.contains(index), list.indices.contains(to) else { return list }
        var next = list
        next.insert(next.remove(at: index), at: to)
        return next
    }

    static func moveTab(_ s: Settings, at index: Int, by delta: Int) -> Settings {
        var next = s
        next.tabs = moved(s.tabs, index, delta)
        return next
    }

    /// 탭 복제: 탭 id 와 모든 슬롯 id 를 재부여하고 원본 바로 뒤에 둔다.
    static func duplicateTab(_ s: Settings, at index: Int) -> Settings {
        guard s.tabs.indices.contains(index), canAddTab(s) else { return s }
        var copy = s.tabs[index]
        copy.id = newId("tab", taken: s.tabs.map(\.id))
        copy.name = String("\(copy.name) 복사".prefix(20))
        var slotIds: [String] = []
        copy.slots = copy.slots.map { (slot: Slot?) -> Slot? in
            guard var c = slot else { return nil }
            c.id = newId("slot", taken: slotIds)
            slotIds.append(c.id)
            return c
        }
        var next = s
        next.tabs.insert(copy, at: index + 1)
        return next
    }

    static func renameTab(_ s: Settings, at index: Int, _ name: String) -> Settings {
        guard s.tabs.indices.contains(index) else { return s }
        var next = s
        next.tabs[index].name = name
        return next
    }

    // MARK: 슬롯 (링 위치 8칸 고정, 빈 칸 허용)

    /// 탭의 슬롯을 링 위치(0 = 12시, 시계 방향) 8칸으로 펼친다. 빈 칸은 nil.
    static func cells(_ tab: Tab) -> [Slot?] {
        let padded = tab.slots + [Slot?](repeating: nil, count: max(0, Limits.slots - tab.slots.count))
        return Array(padded.prefix(max(Limits.slots, tab.slots.count)))
    }

    /// 칸을 고쳐 돌려준다. 끝의 빈 칸은 떼어 저장 형태와 같게 둔다.
    private static func editCells(_ s: Settings, _ tabIndex: Int, _ body: (inout [Slot?]) -> Void) -> Settings {
        guard s.tabs.indices.contains(tabIndex) else { return s }
        var next = s
        var list = cells(s.tabs[tabIndex])
        body(&list)
        while list.last.map({ $0 == nil }) == true { list.removeLast() }
        next.tabs[tabIndex].slots = list
        return next
    }

    private static func isEmptyCell(_ tab: Tab, _ position: Int) -> Bool {
        (0..<Limits.slots).contains(position) && (position >= tab.slots.count || tab.slots[position] == nil)
    }

    /// 가장 앞의 빈 칸 위치(없으면 nil)
    static func firstEmptyPosition(_ tab: Tab) -> Int? {
        (0..<Limits.slots).first { isEmptyCell(tab, $0) }
    }

    static func canAddSlot(_ s: Settings, tab tabIndex: Int) -> Bool {
        s.tabs.indices.contains(tabIndex) && firstEmptyPosition(s.tabs[tabIndex]) != nil
    }

    /// 새 슬롯: 기본 이름 "슬롯 N"(N = 링 위치 번호) + 빈 앱 액션(사용자가 채워야 검증을 통과한다).
    /// `position` 을 안 주면 가장 앞의 빈 칸에 넣고, 준 칸이 비어 있지 않으면 바꾸지 않는다.
    static func addSlot(_ s: Settings, tab tabIndex: Int, at position: Int? = nil) -> Settings {
        guard s.tabs.indices.contains(tabIndex) else { return s }
        let tab = s.tabs[tabIndex]
        guard let target = position ?? firstEmptyPosition(tab), isEmptyCell(tab, target) else { return s }
        return editCells(s, tabIndex) { list in
            let taken = list.compactMap { $0?.id }
            list[target] = Slot(id: newId("slot", taken: taken), name: "슬롯 \(target + 1)", label: nil, action: defaultAction(.launchApp))
        }
    }

    /// 칸을 비운다(다른 칸은 그대로 — 뒤 슬롯이 당겨지지 않는다)
    static func removeSlot(_ s: Settings, tab tabIndex: Int, at position: Int) -> Settings {
        editCells(s, tabIndex) { list in
            if list.indices.contains(position) { list[position] = nil }
        }
    }

    /// 옮기거나 맞바꾼 슬롯의 지정 키·방향이 새 자리에서 다른 슬롯(또는 닫기 키)과 겹치면 그 지정을 풀어 기본으로 되돌린다.
    /// (예: ↑ 를 지정한 슬롯이 2번 칸으로 가면, 1번 칸으로 온 슬롯의 기본 ↑ 와 겹친다.) 옮긴 두 칸만 본다.
    private static func droppingConflicts(_ list: inout [Slot?], positions: [Int], closeKey: String) {
        for p in positions {
            guard var slot = list[p] else { continue }
            let snapshot = list
            func othersContain(_ test: (Slot, Int) -> Bool) -> Bool {
                snapshot.enumerated().contains { q, entry in q != p && entry.map { test($0, q) } == true }
            }
            if let key = slot.key.flatMap(SlotKey.normalize), key == closeKey || othersContain({ Keymap.effectiveKey($0, position: $1) == key }) {
                slot.key = nil
            }
            if let direction = slot.direction, direction != .off, othersContain({ Keymap.effectiveDirection($0, position: $1) == direction }) {
                slot.direction = nil
            }
            list[p] = slot
        }
    }

    /// 드래그로 슬롯 옮기기: 빈 칸이면 그 칸으로 옮기고, 찬 칸이면 둘을 맞바꾼다. 출발 칸이 비었거나 같은 칸이면 바꾸지 않는다.
    /// 옮긴 슬롯의 지정 키·방향이 새 자리에서 겹치면 그 지정은 풀린다.
    static func moveSlot(_ s: Settings, tab tabIndex: Int, from: Int, to: Int) -> Settings {
        guard s.tabs.indices.contains(tabIndex), from != to,
              (0..<Limits.slots).contains(from), (0..<Limits.slots).contains(to),
              !isEmptyCell(s.tabs[tabIndex], from) else { return s }
        return editCells(s, tabIndex) { list in
            list.swapAt(from, to)
            droppingConflicts(&list, positions: [from, to], closeKey: s.closeKey)
        }
    }

    /// 슬롯 복제본이 들어갈 칸: `position` 다음의 빈 칸(끝까지 가서 없으면 처음부터). 복제할 슬롯이 없거나 빈 칸이 없으면 nil.
    static func duplicateTarget(_ tab: Tab, at position: Int) -> Int? {
        guard (0..<Limits.slots).contains(position), !isEmptyCell(tab, position) else { return nil }
        let order = Array((position + 1)..<Limits.slots) + Array(0..<position)
        return order.first { isEmptyCell(tab, $0) }
    }

    /// 슬롯 복제: 새 id 로 `duplicateTarget` 칸에 넣는다. 빈 칸이 없으면 불가.
    static func duplicateSlot(_ s: Settings, tab tabIndex: Int, at position: Int) -> Settings {
        guard s.tabs.indices.contains(tabIndex), let target = duplicateTarget(s.tabs[tabIndex], at: position) else { return s }
        return editCells(s, tabIndex) { list in
            guard var copy = list[position] else { return }
            copy.id = newId("slot", taken: list.compactMap { $0?.id })
            // 복제본은 키·방향을 이어받지 않는다(같은 탭에서 겹치면 저장이 막힌다). 기본 배정을 따른다.
            copy.key = nil
            copy.direction = nil
            list[target] = copy
        }
    }

    static func updateSlot(_ s: Settings, tab tabIndex: Int, at position: Int, _ body: (inout Slot) -> Void) -> Settings {
        editCells(s, tabIndex) { list in
            guard list.indices.contains(position), var slot = list[position] else { return }
            body(&slot)
            list[position] = slot
        }
    }

    // MARK: 키 배정 (슬롯 키·방향키·닫기 키)

    /// 이 탭에서 `key` 를 쓰는 다른 슬롯의 링 위치(지정값과 기본 숫자 모두 본다). 없으면 nil.
    static func slotUsingKey(_ s: Settings, tab tabIndex: Int, key: String, except position: Int) -> Int? {
        guard s.tabs.indices.contains(tabIndex) else { return nil }
        for (p, entry) in cells(s.tabs[tabIndex]).enumerated() where p != position {
            if let slot = entry, Keymap.effectiveKey(slot, position: p) == key { return p }
        }
        return nil
    }

    /// 이 탭에서 `direction` 을 쓰는 다른 슬롯의 링 위치(지정값과 링 기본 방향 모두 본다). `off` 는 겹쳐도 되므로 항상 nil.
    static func slotUsingDirection(_ s: Settings, tab tabIndex: Int, direction: SlotDirection, except position: Int) -> Int? {
        guard direction != .off, s.tabs.indices.contains(tabIndex) else { return nil }
        for (p, entry) in cells(s.tabs[tabIndex]).enumerated() where p != position {
            if let slot = entry, Keymap.effectiveDirection(slot, position: p) == direction { return p }
        }
        return nil
    }

    /// 슬롯 키로 `key` 를 못 쓰는 이유(쓸 수 있으면 nil). 영문자·숫자 한 글자가 아니거나, 닫기 키이거나, 같은 탭의 다른 슬롯이 쓰는 키다.
    static func slotKeyConflict(_ s: Settings, tab tabIndex: Int, at position: Int, key: String) -> String? {
        guard let normalized = SlotKey.normalize(key) else { return "영문자 또는 숫자 키만 쓸 수 있습니다" }
        if normalized == s.closeKey { return "닫기 키(\(SlotKey.display(normalized)))와 같습니다" }
        if let other = slotUsingKey(s, tab: tabIndex, key: normalized, except: position) {
            return "슬롯 \(other + 1) 이(가) 이미 \(SlotKey.display(normalized)) 키를 씁니다"
        }
        return nil
    }

    /// 닫기 키로 `key` 를 못 쓰는 이유(쓸 수 있으면 nil). 영문자·숫자 한 글자가 아니거나, 어느 탭의 슬롯이 이미 쓰는 키다.
    static func closeKeyConflict(_ s: Settings, key: String) -> String? {
        guard let normalized = SlotKey.normalize(key) else { return "영문자 또는 숫자 키만 쓸 수 있습니다" }
        for tab in s.tabs {
            for (p, entry) in cells(tab).enumerated() {
                if let slot = entry, Keymap.effectiveKey(slot, position: p) == normalized {
                    return "탭 ‘\(tab.name)’ 의 슬롯 \(p + 1) 이(가) 이미 \(SlotKey.display(normalized)) 키를 씁니다"
                }
            }
        }
        return nil
    }

    /// 슬롯 키를 정한다. nil(또는 기본 숫자와 같은 키)이면 기본으로 되돌린다. 쓸 수 없는 키면, 기본으로 되돌릴 때도 그 기본 숫자를 다른 곳이 쓰고 있으면 바꾸지 않는다.
    static func settingSlotKey(_ s: Settings, tab tabIndex: Int, at position: Int, to key: String?) -> Settings {
        let requested = key ?? SlotKey.defaultKey(position: position)
        guard slotKeyConflict(s, tab: tabIndex, at: position, key: requested) == nil, let normalized = SlotKey.normalize(requested) else { return s }
        let stored: String? = normalized == SlotKey.defaultKey(position: position) ? nil : normalized
        return updateSlot(s, tab: tabIndex, at: position) { $0.key = stored }
    }

    /// 슬롯의 방향키 배정을 정한다. nil(또는 링 기본 방향과 같은 값)이면 기본으로 되돌린다. 같은 탭의 다른 슬롯이 쓰는 방향이면(기본으로 되돌릴 때도) 바꾸지 않는다.
    static func settingSlotDirection(_ s: Settings, tab tabIndex: Int, at position: Int, to direction: SlotDirection?) -> Settings {
        let requested = direction ?? SlotDirection.ring(position)
        guard slotUsingDirection(s, tab: tabIndex, direction: requested, except: position) == nil else { return s }
        let stored: SlotDirection? = requested == SlotDirection.ring(position) ? nil : requested
        return updateSlot(s, tab: tabIndex, at: position) { $0.direction = stored }
    }

    /// 닫기 키를 정한다. 쓸 수 없는 키면 바꾸지 않는다.
    static func settingCloseKey(_ s: Settings, to key: String) -> Settings {
        guard closeKeyConflict(s, key: key) == nil, let normalized = SlotKey.normalize(key) else { return s }
        var next = s
        next.closeKey = normalized
        return next
    }

    // MARK: 매크로 단계

    struct Macro: Equatable {
        var stopOnError: Bool
        var steps: [Action]

        init(stopOnError: Bool, steps: [Action]) {
            self.stopOnError = stopOnError
            self.steps = steps
        }

        init?(_ action: Action) {
            guard case let .macroSequence(stop, steps) = action else { return nil }
            self.init(stopOnError: stop, steps: steps)
        }

        var action: Action { .macroSequence(stopOnError: stopOnError, steps: steps) }
    }

    static func addStep(_ m: Macro) -> Macro {
        guard m.steps.count < Limits.maxMacroSteps else { return m }
        var next = m
        next.steps.append(defaultAction(.launchApp))
        return next
    }

    static func removeStep(_ m: Macro, at index: Int) -> Macro {
        guard m.steps.count > 1, m.steps.indices.contains(index) else { return m }
        var next = m
        next.steps.remove(at: index)
        return next
    }

    static func moveStep(_ m: Macro, at index: Int, by delta: Int) -> Macro {
        var next = m
        next.steps = moved(m.steps, index, delta)
        return next
    }

    /// 단계에는 매크로·activate 를 둘 수 없으므로 그 종류로의 변경은 무시한다.
    static func changeStepKind(_ m: Macro, at index: Int, to kind: ActionKind) -> Macro {
        guard m.steps.indices.contains(index), ActionKind.stepChoices.contains(kind) else { return m }
        var next = m
        next.steps[index] = changeActionKind(m.steps[index], to: kind)
        return next
    }

    static func setStep(_ m: Macro, at index: Int, _ step: Action) -> Macro {
        guard m.steps.indices.contains(index) else { return m }
        var next = m
        next.steps[index] = step
        return next
    }

    // MARK: 패널 크기(현재 테마의 크기만 편집한다. 파이와 오비트는 서로 연동되지 않는다)

    /// 현재 테마의 바깥 크기를 바꾼다. 중앙 원이 새 상한(바깥 − 최소 두께)을 넘으면 상한으로 줄여, 사용자가 검증 오류를 만나지 않게 한다.
    static func settingRing(_ s: Settings, to value: Int) -> Settings {
        var next = s
        let ring = min(max(value, Limits.ringRange.lowerBound), Limits.ringRange.upperBound)
        next.overlay.ringSize = ring
        next.overlay.centerSize = min(next.overlay.centerSize, Limits.centerRange(ring: ring).upperBound)
        return next
    }

    /// 현재 테마의 중앙 원 크기. 현재 바깥 크기에 맞는 범위로 보정한다.
    static func settingCenter(_ s: Settings, to value: Int) -> Settings {
        var next = s
        let range = Limits.centerRange(ring: s.overlay.ringSize)
        next.overlay.centerSize = min(max(value, range.lowerBound), range.upperBound)
        return next
    }

    /// 현재 테마의 중앙 원 테두리 굵기
    static func settingBorder(_ s: Settings, to value: Int) -> Settings {
        var next = s
        next.overlay.centerBorder = min(max(value, Limits.centerBorderRange.lowerBound), Limits.centerBorderRange.upperBound)
        return next
    }

    /// 현재 테마의 크기만 그 테마의 기본값으로 되돌린다(다른 테마의 크기는 그대로).
    static func resettingSizes(_ s: Settings) -> Settings {
        var next = s
        next.overlay.sizes = s.overlay.theme.defaultSizes
        return next
    }

    // MARK: 포커스 색

    /// 포커스 색을 `#RRGGBB`(또는 `RRGGBB`/`#RGB`)로 바꾼다. 해석할 수 없는 입력은 draft 를 그대로 돌려준다(오염 금지).
    static func settingFocusHex(_ s: Settings, to text: String) -> Settings {
        guard let hex = FocusColors.normalized(text) else { return s }
        var next = s
        next.overlay.focusHex = hex
        return next
    }

    // MARK: 글라스 틴트

    /// 클리어 글라스 틴트를 `#RRGGBB`(또는 `RRGGBB`/`#RGB`)로 바꾼다. 해석할 수 없는 입력은 draft 를 그대로 돌려준다(오염 금지).
    static func settingGlassTint(_ s: Settings, to hex: String) -> Settings {
        guard let normalized = GlassTints.normalized(hex) else { return s }
        var next = s
        next.overlay.glassTintHex = normalized
        return next
    }

    /// '앱 박스·원 뒤 배경 불투명' 토글을 바꿀 수 있는지: 지금 본체가 바닥판을 쓸 수 있을 때만(글라스 본체는 항상 아님).
    /// 판단은 오버레이가 읽는 `PaletteColors.usesBackingPlate` 한 곳이다. 비활성이어도 저장된 값은 건드리지 않아 본체를 되돌리면 이전 값이 살아난다.
    static func canEditSolidBacking(_ s: Settings) -> Bool {
        PaletteColors.usesBackingPlate(body: s.overlay.bodyTheme, solid: true)
    }

    // MARK: 중앙 원 글자

    /// 자동 크기를 끌 때 슬라이더가 시작할 값: 지금 자동으로 그려지는 크기(렌더 쪽 순수 함수)를 범위 안 정수로.
    static func autoCenterNameSize(_ s: Settings) -> Int {
        let auto = OverlayMetrics.centerNameSize(hub: CGFloat(s.overlay.centerSize)).rounded()
        return min(max(Int(auto), Limits.centerNameSizeRange.lowerBound), Limits.centerNameSizeRange.upperBound)
    }

    /// 중앙 원 글자 크기를 바꾼다. 0 이하는 자동(0), 그 밖에는 `Limits.centerNameSizeRange` 로 보정한다.
    static func settingCenterNameSize(_ s: Settings, to value: Int) -> Settings {
        var next = s
        next.overlay.centerNameSize = value <= 0 ? 0 : min(max(value, Limits.centerNameSizeRange.lowerBound), Limits.centerNameSizeRange.upperBound)
        return next
    }

    /// 글자 크기 '자동' 토글. 켜면 0, 끄면 지금 자동 크기에 가까운 값에서 시작한다(이미 직접 고른 값이면 그대로).
    static func settingCenterNameAuto(_ s: Settings, auto: Bool) -> Settings {
        if auto { return settingCenterNameSize(s, to: 0) }
        guard s.overlay.centerNameSize == 0 else { return s }
        return settingCenterNameSize(s, to: autoCenterNameSize(s))
    }

    // MARK: 변경 여부

    /// 저장 파일 왕복(Codable)을 거친 정규형. 저장 형식으로 정리되지 않는 상태는 디코딩이 정리한다.
    static func normalized(_ s: Settings) -> Settings {
        guard let data = try? JSONEncoder().encode(s), let back = try? JSONDecoder().decode(Settings.self, from: data) else { return s }
        return back
    }

    static func isDirty(baseline: Settings, draft: Settings) -> Bool {
        normalized(baseline) != normalized(draft)
    }

    // MARK: 앱 선택기

    /// 설치된 앱 검색: 지역화 이름("계산기"), 원래 이름("Calculator"), bundleId 어느 쪽으로든 찾는다.
    static func matches(_ app: InstalledApp, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return [app.name, app.altName ?? "", app.bundleId].contains { $0.lowercased().contains(q) }
    }

    /// `.app` 경로의 파일 이름(확장자 제외). `.app` 이 아니거나 이름이 비면 nil.
    static func appFileName(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// 앱 실행 동작이 가리키는 앱의 파일 이름. 경로는 그대로, 번들 ID 는 설치된 앱 목록에서 경로를 찾아 얻는다. 못 찾으면 nil.
    static func appFileName(of action: Action, apps: [InstalledApp]) -> String? {
        guard case let .launchApp(bundleId, appPath) = action else { return nil }
        if let appPath { return appFileName(path: appPath) }
        guard let bundleId, let app = apps.first(where: { $0.bundleId == bundleId }) else { return nil }
        return appFileName(path: app.appPath)
    }

    /// 슬롯의 동작을 `newAction` 으로 바꾼다. 앱이 바뀌어 파일 이름을 알 수 있으면 이름(검증기와 같은 UTF-16 40유닛 상한)과 라벨을 그 파일 이름으로 다시 정한다.
    /// 사용자가 정한 이름·라벨도 덮어쓴다. 파일 이름을 알 수 없는 편집(번들 ID 직접 입력 중, 종류 변경 등)은 이름·라벨을 건드리지 않는다.
    /// 약어가 검증기 상한(UTF-16 3유닛)을 넘으면(이모지·NFD 한글 등) 라벨은 비워 화면이 이름에서 만들게 한다.
    static func applyingAction(_ newAction: Action, to slot: Slot, apps: [InstalledApp]) -> Slot {
        var next = slot
        next.action = newAction
        guard newAction != slot.action, let fileName = appFileName(of: newAction, apps: apps) else { return next }
        var name = fileName
        while name.utf16.count > 40 { name.removeLast() }
        next.name = name
        let initials = slotInitials(fileName)
        next.label = initials.utf16.count <= 3 ? normalizeLabel(initials) : nil
        return next
    }
}
