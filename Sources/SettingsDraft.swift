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
    static func canAddRecentTab(_ s: Settings) -> Bool { !s.tabs.contains { $0.type == .recentApps } }

    static func addTab(_ s: Settings, _ type: TabKind, name: String? = nil) -> Settings {
        guard canAddTab(s), type != .recentApps || canAddRecentTab(s) else { return s }
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

    /// 탭 복제: 탭 id 와 모든 슬롯 id 를 재부여하고 원본 바로 뒤에 둔다. 최근 앱 탭은 하나만 허용되므로 복제할 수 없다.
    static func duplicateTab(_ s: Settings, at index: Int) -> Settings {
        guard s.tabs.indices.contains(index), canAddTab(s), s.tabs[index].type != .recentApps else { return s }
        var copy = s.tabs[index]
        copy.id = newId("tab", taken: s.tabs.map(\.id))
        copy.name = String("\(copy.name) 복사".prefix(20))
        var slotIds: [String] = []
        copy.slots = copy.slots.map { slot in
            var c = slot
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

    // MARK: 슬롯

    private static func editSlots(_ s: Settings, _ tabIndex: Int, _ body: (inout [Slot]) -> Void) -> Settings {
        guard s.tabs.indices.contains(tabIndex), s.tabs[tabIndex].type != .recentApps else { return s }
        var next = s
        body(&next.tabs[tabIndex].slots)
        return next
    }

    static func canAddSlot(_ s: Settings, tab tabIndex: Int) -> Bool {
        s.tabs.indices.contains(tabIndex) && s.tabs[tabIndex].type != .recentApps && s.tabs[tabIndex].slots.count < Limits.slots
    }

    /// 새 슬롯: 기본 이름 "슬롯 N" + 빈 앱 액션(사용자가 채워야 검증을 통과한다)
    static func addSlot(_ s: Settings, tab tabIndex: Int) -> Settings {
        guard canAddSlot(s, tab: tabIndex) else { return s }
        return editSlots(s, tabIndex) { slots in
            slots.append(Slot(id: newId("slot", taken: slots.map(\.id)), name: "슬롯 \(slots.count + 1)", label: nil, action: defaultAction(.launchApp)))
        }
    }

    static func removeSlot(_ s: Settings, tab tabIndex: Int, at slotIndex: Int) -> Settings {
        editSlots(s, tabIndex) { slots in
            if slots.indices.contains(slotIndex) { slots.remove(at: slotIndex) }
        }
    }

    static func moveSlot(_ s: Settings, tab tabIndex: Int, at slotIndex: Int, by delta: Int) -> Settings {
        editSlots(s, tabIndex) { $0 = moved($0, slotIndex, delta) }
    }

    /// 슬롯 복제: 원본 바로 뒤에 새 id 로 삽입. 8개면 불가.
    static func duplicateSlot(_ s: Settings, tab tabIndex: Int, at slotIndex: Int) -> Settings {
        guard canAddSlot(s, tab: tabIndex), s.tabs[tabIndex].slots.indices.contains(slotIndex) else { return s }
        return editSlots(s, tabIndex) { slots in
            var copy = slots[slotIndex]
            copy.id = newId("slot", taken: slots.map(\.id))
            slots.insert(copy, at: slotIndex + 1)
        }
    }

    static func updateSlot(_ s: Settings, tab tabIndex: Int, at slotIndex: Int, _ body: (inout Slot) -> Void) -> Settings {
        editSlots(s, tabIndex) { slots in
            if slots.indices.contains(slotIndex) { body(&slots[slotIndex]) }
        }
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

    /// 저장 파일 왕복(Codable)을 거친 정규형. 알 수 없는 상태(최근 앱 탭의 슬롯 등)는 디코딩이 정리한다.
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
