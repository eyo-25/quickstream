import AppKit
import Carbon.HIToolbox
import Foundation

// 설정 창의 순수 로직(편집 헬퍼·변경 감지·앱 검색·단축키 녹화 해석). UI 는 띄우지 않는다.

private typealias D = SettingsDraft

/// 빈 커스텀 + 고정 앱(8칸 가득) + 커스텀(5칸) 탭을 가진 픽스처
private func fixture() -> Settings {
    func slot(_ id: String, _ name: String, _ action: Action) -> Slot { Slot(id: id, name: name, label: nil, action: action) }
    var s = Settings()
    s.tabs = [
        Tab(id: "extra", name: "추가 탭", type: .custom),
        Tab(id: "pinned", name: "고정 앱", type: .pinnedApps,
            slots: (1...8).map { slot("p\($0)", "앱 \($0)", .launchApp(bundleId: "com.example.app\($0)", appPath: nil)) }),
        Tab(id: "meeting", name: "회의용 퀵", type: .custom,
            slots: [
                slot("m1", "구글", .openURL("https://google.com")),
                slot("m2", "메모", .clipboardText("hi")),
                slot("m3", "매크로", .macroSequence(stopOnError: true, steps: [.openURL("https://a.example")])),
                slot("m4", "넷", .openURL("https://b.example")),
                slot("m5", "다섯", .openURL("https://c.example")),
            ]),
    ]
    return s
}

private func isGeneratedId(_ id: String, _ prefix: String) -> Bool {
    guard id.hasPrefix(prefix + "-") else { return false }
    let tail = id.dropFirst(prefix.count + 1)
    return tail.count == 6 && tail.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
}

/// 채워진 슬롯만 링 위치 순서로
private func slots(_ s: Settings, _ tab: Int) -> [Slot] { s.tabs[tab].slots.compactMap { $0 } }
/// 링 위치 8칸(빈 칸은 nil)
private func cells(_ s: Settings, _ tab: Int) -> [Slot?] { D.cells(s.tabs[tab]) }
private func allIds(_ s: Settings) -> [String] { s.tabs.flatMap { [$0.id] + $0.slots.compactMap { $0?.id } } }

private func calculator() -> InstalledApp {
    InstalledApp(bundleId: "com.apple.calculator", name: "계산기", altName: "Calculator", appPath: "/System/Applications/Calculator.app")
}

func runSettingsTests() {
    tabEditing()
    slotEditing()
    actionEditing()
    macroEditing()
    keyAssignmentEditing()
    dirtyDetection()
    appPicker()
    shortcutRecording()
    feedbackState()
    recordingPauseAndAppRefresh()
    recordingRealPaths()
    overlaySizeEditing()
    piePreviewMetrics()
    themeSwitching()
    bodyAndFocusSelection()
    glassTintSelection()
    settingsPaletteContrast()
    clearGlassWindowContrast()
    nameAndNumberOptions()
    centerNameOptions()
    focusGlowToggle()
}

private func tabEditing() {
    section("Settings: 탭 편집")

    var s = fixture()
    while s.tabs.count < Limits.maxTabs { s = D.addTab(s, .custom) }
    checkEqual(Set(s.tabs.map(\.id)).count, 8, "추가한 탭 id 는 서로 다르다")
    check(s.tabs.suffix(5).allSatisfy { isGeneratedId($0.id, "tab") }, "새 탭 id 는 tab-xxxxxx 형식")
    var over = s
    for _ in 0..<3 { over = D.addTab(over, .custom) }
    checkEqual(over.tabs.count, 8, "탭은 8개를 넘길 수 없다")
    check(D.addTab(D.addTab(Settings.defaults, .custom), .pinnedApps).tabs.last?.slots.isEmpty == true, "새 탭은 슬롯 없이 시작")

    let base = fixture()

    var one = base
    while one.tabs.count > 1 { one = D.removeTab(one, at: 0) }
    checkEqual(D.removeTab(one, at: 0).tabs.count, 1, "마지막 1개 탭은 삭제 불가")
    checkEqual(D.removeTab(base, at: 9), base, "범위 밖 삭제는 무시")

    let ids = base.tabs.map(\.id)
    checkEqual(D.moveTab(base, at: 0, by: -1).tabs.map(\.id), ids, "맨 위 탭을 위로 이동해도 변화 없음")
    checkEqual(D.moveTab(base, at: 2, by: 1).tabs.map(\.id), ids, "맨 아래 탭을 아래로 이동해도 변화 없음")
    checkEqual(D.moveTab(base, at: 0, by: 1).tabs.map(\.id), ["pinned", "extra", "meeting"], "안쪽 이동은 자리를 바꾼다")

    let dup = D.duplicateTab(base, at: 2)
    checkEqual(dup.tabs.count, 4, "복제는 탭을 하나 늘린다")
    checkEqual(dup.tabs[3].name, "회의용 퀵 복사", "복제본은 원본 바로 뒤, 이름에 ' 복사'")
    checkEqual(Set(allIds(dup)).count, allIds(dup).count, "복제 후 탭/슬롯 id 가 모두 유일")
    checkEqual(slots(dup, 3).map(\.name), slots(base, 2).map(\.name), "복제본 슬롯 내용은 같다")
    var edited = dup
    edited.tabs[3].slots[0]?.name = "바뀜"
    checkEqual(edited.tabs[2].slots[0]?.name, "구글", "복제본 편집이 원본에 영향 없음")
    var long = base
    long.tabs[2].name = String(repeating: "가", count: 20)
    checkEqual(D.duplicateTab(long, at: 2).tabs[3].name.count, 20, "복제 이름은 20자 상한")

    var full = base
    while full.tabs.count < 8 { full = D.addTab(full, .custom) }
    checkEqual(D.duplicateTab(full, at: 1), full, "탭이 가득 차면 복제 불가")

    let defaults = Settings.defaults
    checkEqual(defaults.tabs.map(\.type), [.pinnedApps], "기본 설정은 고정 앱 탭 하나")
    checkEqual(D.removeTab(defaults, at: 0), defaults, "기본 탭도 마지막 하나라 삭제 불가")
    checkEqual(D.moveTab(defaults, at: 0, by: 1), defaults, "탭이 하나면 이동은 변화 없음")
    checkEqual(D.renameTab(base, at: 1, "새 이름").tabs[1].name, "새 이름", "탭 이름 변경")

    // 사이드바 드래그: 끈 탭이 놓은 탭의 자리로 가고 선택은 그대로 따라간다
    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft = fixture()
        model.selection = .tab("meeting")
        model.moveTab(id: "meeting", onto: "extra")
        checkEqual(model.draft.tabs.map(\.id), ["meeting", "extra", "pinned"], "아래 탭을 위 탭에 놓으면 그 자리로 간다")
        checkEqual(model.tabIndex, 0, "선택된 탭은 새 자리를 따라간다")
        model.moveTab(id: "meeting", onto: "pinned")
        checkEqual(model.draft.tabs.map(\.id), ["extra", "pinned", "meeting"], "위 탭을 아래 탭에 놓으면 그 자리로 가고 사이가 밀린다")
        let before = model.draft
        model.moveTab(id: "extra", onto: "extra")
        model.moveTab(id: "없는 탭", onto: "pinned")
        model.moveTab(id: "pinned", onto: "없는 탭")
        checkEqual(model.draft, before, "같은 탭·없는 탭은 순서를 바꾸지 않는다")
    }

    // 마지막 자리의 선택된 탭을 지우면 이웃 탭이 선택되고, 하나 남으면 더 지울 수 없다
    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft = fixture()
        model.selection = .tab("meeting")
        model.removeSelectedTab()
        checkEqual(model.draft.tabs.map(\.id), ["extra", "pinned"], "마지막 탭 삭제")
        checkEqual(model.selection, .tab("pinned"), "지운 자리의 이웃 탭이 선택된다")
        model.removeSelectedTab()
        checkEqual(model.selection, .tab("extra"), "다시 이웃 탭 선택")
        model.removeSelectedTab()
        checkEqual(model.draft.tabs.map(\.id), ["extra"], "마지막 하나는 지울 수 없다")
    }
}

private func slotEditing() {
    section("Settings: 슬롯 편집")

    var s = D.addTab(fixture(), .custom)
    let t = s.tabs.count - 1
    for _ in 0..<12 { s = D.addSlot(s, tab: t) }
    checkEqual(slots(s, t).count, 8, "슬롯은 8개까지만")
    checkEqual(Set(slots(s, t).map(\.id)).count, 8, "슬롯 id 유일")
    check(slots(s, t).allSatisfy { isGeneratedId($0.id, "slot") }, "슬롯 id 형식")
    checkEqual(slots(s, t).first?.name, "슬롯 1", "기본 이름은 슬롯 N(N = 링 위치 번호)")
    checkEqual(D.duplicateSlot(s, tab: t, at: 0), s, "가득 차면 슬롯 복제 불가")
    check(!D.canAddSlot(s, tab: t), "가득 차면 추가 불가")

    // 중간이 비어도 된다: 12시와 6시만
    var sparse = D.addSlot(D.addSlot(Settings.defaults, tab: 0, at: 0), tab: 0, at: 4)
    checkEqual(cells(sparse, 0).map { $0 != nil }, [true, false, false, false, true, false, false, false], "12시(1번)와 6시(5번)만 채움")
    checkEqual(cells(sparse, 0)[4]?.name, "슬롯 5", "기본 이름은 링 위치 번호")
    checkEqual(sparse.tabs[0].slots.count, 5, "끝의 빈 칸은 저장 형태에서 뺀다")
    checkEqual(D.addSlot(sparse, tab: 0, at: 4), sparse, "슬롯이 있는 칸에는 추가 불가")
    checkEqual(D.addSlot(sparse, tab: 0, at: 8), sparse, "범위 밖 칸에는 추가 불가")
    checkEqual(cells(D.addSlot(sparse, tab: 0), 0)[1]?.name, "슬롯 2", "위치를 안 주면 가장 앞의 빈 칸")
    let tabJSON = try! JSONEncoder().encode(sparse.tabs[0])
    check(String(data: tabJSON, encoding: .utf8)?.contains("null") == true, "중간 빈 칸은 null 로 저장")
    checkEqual(try! JSONDecoder().decode(Tab.self, from: tabJSON), sparse.tabs[0], "빈 칸이 있는 탭의 저장 왕복")
    let denseJSON = #"{"id":"t","name":"탭","type":"custom","slots":[{"id":"a","name":"A","action":{"type":"open_url","url":"https://a.example"}}]}"#
    checkEqual(try! JSONDecoder().decode(Tab.self, from: Data(denseJSON.utf8)).slots.map { $0?.id }, ["a"], "예전 형식(빈 칸 없는 배열)은 앞 칸부터 그대로 읽는다")
    checkEqual(slots(D.removeSlot(sparse, tab: 0, at: 0), 0).map(\.name), ["슬롯 5"], "삭제는 그 칸만 비운다")
    check(cells(D.removeSlot(sparse, tab: 0, at: 0), 0)[4] != nil, "삭제해도 뒤 슬롯이 당겨지지 않는다")

    // 드래그: 빈 칸으로 옮기기 / 찬 칸과 맞바꾸기
    let movedToEmpty = D.moveSlot(sparse, tab: 0, from: 0, to: 2)
    checkEqual(cells(movedToEmpty, 0).map { $0 != nil }, [false, false, true, false, true, false, false, false], "빈 칸으로 옮김")
    checkEqual(cells(movedToEmpty, 0)[2]?.id, cells(sparse, 0)[0]?.id, "옮긴 슬롯은 그대로(id 유지)")
    let swapped = D.moveSlot(sparse, tab: 0, from: 0, to: 4)
    checkEqual([cells(swapped, 0)[0]?.id, cells(swapped, 0)[4]?.id], [cells(sparse, 0)[4]?.id, cells(sparse, 0)[0]?.id], "찬 칸과는 서로 바꿈")
    checkEqual(D.moveSlot(sparse, tab: 0, from: 0, to: 0), sparse, "같은 칸은 변화 없음")
    checkEqual(D.moveSlot(sparse, tab: 0, from: 1, to: 3), sparse, "빈 칸을 끌 수는 없다")
    checkEqual(D.moveSlot(sparse, tab: 0, from: 0, to: 8), sparse, "범위 밖으로는 옮길 수 없다")
    checkEqual(D.moveSlot(sparse, tab: 9, from: 0, to: 1), sparse, "없는 탭은 무시")
    sparse = D.moveSlot(sparse, tab: 0, from: 4, to: 7)
    checkEqual(sparse.tabs[0].slots.count, 8, "끝 칸으로 옮기면 저장 형태도 8칸")

    let base = fixture()
    let names = slots(base, 1).map(\.name)
    checkEqual(slots(D.moveSlot(base, tab: 1, from: 0, to: 1), 1).map(\.name).prefix(2).map { $0 }, [names[1], names[0]], "가득 찬 탭에서도 끌면 서로 바뀐다")

    checkEqual(slots(D.removeSlot(base, tab: 2, at: 0), 2).count, 4, "슬롯 삭제")
    checkEqual(D.duplicateTarget(base.tabs[2], at: 0), 5, "복제본은 다음 빈 칸으로")
    checkEqual(D.duplicateTarget(base.tabs[1], at: 0), nil, "빈 칸이 없으면 복제 불가")
    let dup = D.duplicateSlot(base, tab: 2, at: 0)
    checkEqual(slots(dup, 2).count, 6, "슬롯 복제")
    checkEqual(cells(dup, 2)[5]?.name, "구글", "복제본은 다음 빈 칸에")
    check(cells(dup, 2)[5]?.id != cells(base, 2)[0]?.id, "복제본은 새 id")
    checkEqual(Set(slots(dup, 2).map(\.id)).count, 6, "복제 후 id 유일")

    // 복제 칸은 끝에서 처음으로 돌아간다: 0번(12시)만 비어 있을 때 7번 칸의 복제본은 0번으로, 가득 차면 복제 불가
    var ring = Settings.defaults
    for position in [7, 1, 2, 3, 4, 5, 6] { ring = D.addSlot(ring, tab: 0, at: position) }
    checkEqual(D.duplicateTarget(ring.tabs[0], at: 7), 0, "7번 칸 복제본은 처음 빈 칸(0번)으로 돌아간다")
    checkEqual(cells(D.duplicateSlot(ring, tab: 0, at: 7), 0)[0]?.name, "슬롯 8", "돌아간 칸에 복제본이 들어간다")
    checkEqual(D.duplicateTarget(D.addSlot(ring, tab: 0, at: 0).tabs[0], at: 7), nil, "가득 찬 링은 복제 불가")

    // 새 슬롯 → 앱 선택 시 기본 이름이 앱 이름으로 바뀐다
    var added = D.removeSlot(base, tab: 1, at: 7)
    added = D.addSlot(added, tab: 1)
    let newName = cells(added, 1)[7]?.name ?? ""
    check(newName.hasPrefix("슬롯 "), "자동 부여된 기본 이름")
    checkEqual(D.applyingAction(.launchApp(bundleId: "com.apple.calculator", appPath: nil), to: Slot(id: "n", name: newName, label: nil, action: D.defaultAction(.launchApp)), apps: [calculator()]).name, "Calculator", "새 슬롯에 앱을 고르면 파일 이름으로 채움")

    // 라벨
    checkEqual(D.normalizeLabel("  "), nil, "빈 라벨은 nil")
    checkEqual(D.normalizeLabel(" AB "), "AB", "라벨 공백 제거")
    var labeled = slots(base, 1)[0]
    labeled.label = "ZZ"
    checkEqual(D.withLabel(labeled, "").label, nil, "라벨을 비우면 nil")
    let encoded = String(data: (try? JSONEncoder().encode(D.withLabel(labeled, " "))) ?? Data(), encoding: .utf8) ?? ""
    check(!encoded.contains("label"), "비운 라벨은 저장 JSON 에서 생략")
    checkEqual(D.displayLabel(D.withLabel(labeled, "")), slotInitials("앱 1"), "라벨이 없으면 이름에서 자동 생성")
    checkEqual(D.displayLabel(labeled), "ZZ", "지정 라벨 우선")

    let updated = D.updateSlot(base, tab: 1, at: 0) { $0.name = "다른 이름" }
    checkEqual(slots(updated, 1)[0].name, "다른 이름", "슬롯 갱신")
}

private func actionEditing() {
    section("Settings: 동작 종류")

    let from = Action.openURL("https://a.example")
    checkEqual(D.changeActionKind(from, to: .clipboardText), .clipboardText(""), "종류를 바꾸면 이전 필드를 버린다")
    checkEqual(D.changeActionKind(from, to: .openURL), from, "같은 종류는 그대로")
    for kind in D.ActionKind.slotChoices {
        checkEqual(D.kind(of: D.defaultAction(kind)), kind, "기본값 종류 일치: \(kind)")
    }
    checkEqual(D.defaultAction(.openURL), .openURL("https://"), "URL 기본값")
    checkEqual(D.changeActionKind(.launchApp(bundleId: "x", appPath: nil), to: .openURL), .openURL("https://"), "앱 → URL 은 URL 기본값")

    // launch_app 필드: 값이 비어도 선택한 모드를 유지
    checkEqual(D.launchApp(.appPath, ""), .launchApp(bundleId: nil, appPath: ""), "빈 경로도 appPath 모드 유지")
    checkEqual(D.launchApp(.bundleId, ""), .launchApp(bundleId: "", appPath: nil), "빈 번들 ID 도 bundleId 모드 유지")
    checkEqual(D.launchApp(.appPath, "/Applications/A.app"), .launchApp(bundleId: nil, appPath: "/Applications/A.app"), "경로 하나만")
    checkEqual(D.launchApp(.bundleId, "com.a.b"), .launchApp(bundleId: "com.a.b", appPath: nil), "번들 ID 하나만")

    // 새 슬롯의 빈 앱 액션은 사용자가 채워야 한다(빈 번들 ID)
    let s = D.addSlot(fixture(), tab: 2)
    checkEqual(slots(s, 2).last?.action, .launchApp(bundleId: "", appPath: nil), "새 슬롯은 빈 앱 액션")
}

private func macroEditing() {
    section("Settings: 매크로 단계")

    var m = D.Macro(D.defaultAction(.macroSequence))!
    checkEqual(m.steps.count, 1, "기본 매크로는 한 단계")
    for _ in 0..<20 { m = D.addStep(m) }
    checkEqual(m.steps.count, Limits.maxMacroSteps, "단계 16개 상한")
    checkEqual(D.moveStep(m, at: 0, by: -1).steps, m.steps, "첫 단계 위로 이동은 무시")
    checkEqual(D.moveStep(m, at: 15, by: 1).steps, m.steps, "마지막 단계 아래로 이동은 무시")

    let changed = D.changeStepKind(m, at: 0, to: .openURL)
    checkEqual(D.kind(of: changed.steps[0]), .openURL, "단계 종류 변경")
    checkEqual(changed.steps[1], m.steps[1], "다른 단계는 그대로")
    checkEqual(D.changeStepKind(m, at: 0, to: .macroSequence), m, "단계에 매크로 금지")
    checkEqual(D.changeStepKind(m, at: 0, to: .activateApp), m, "단계에 activate 금지")

    var two = D.Macro(stopOnError: true, steps: [.openURL("https://a.example"), .clipboardText("x")])
    two = D.removeStep(two, at: 0)
    checkEqual(two.steps, [.clipboardText("x")], "단계 삭제")
    checkEqual(D.removeStep(two, at: 0), two, "마지막 단계는 삭제 불가")
    checkEqual(D.setStep(two, at: 0, .openURL("https://z.example")).steps, [.openURL("https://z.example")], "단계 값 설정")
    checkEqual(D.Macro(.openURL("https://a.example")), nil, "매크로가 아니면 Macro 로 열 수 없다")
}

private func keyAssignmentEditing() {
    section("Settings: 슬롯 키·방향키·닫기 키")

    var s = Settings.defaults
    s = D.addSlot(D.addSlot(s, tab: 0, at: 0), tab: 0, at: 1)
    func slotKey(_ x: Settings, _ p: Int) -> String? { x.tabs[0].slots[p]?.key }
    func slotDirection(_ x: Settings, _ p: Int) -> SlotDirection? { x.tabs[0].slots[p]?.direction }

    checkEqual(slotKey(D.settingSlotKey(s, tab: 0, at: 0, to: "w"), 0), "w", "슬롯 키 지정")
    checkEqual(slotKey(D.settingSlotKey(s, tab: 0, at: 0, to: "W"), 0), "w", "대문자는 소문자로 저장")
    checkEqual(D.settingSlotKey(s, tab: 0, at: 0, to: "2"), s, "다른 슬롯의 기본 숫자(2)는 못 쓴다")
    check(D.slotKeyConflict(s, tab: 0, at: 0, key: "2")?.contains("슬롯 2") == true, "겹치는 슬롯을 알려 준다")
    checkEqual(D.settingSlotKey(s, tab: 0, at: 0, to: "q"), s, "닫기 키(Q)는 못 쓴다")
    check(D.slotKeyConflict(s, tab: 0, at: 0, key: "q")?.contains("닫기 키") == true, "닫기 키와 겹침 안내")
    checkEqual(D.settingSlotKey(s, tab: 0, at: 0, to: "-"), s, "영문자·숫자가 아니면 바꾸지 않는다")
    check(D.slotKeyConflict(s, tab: 0, at: 0, key: "가") != nil, "한글 문자는 쓸 수 없다")
    checkEqual(slotKey(D.settingSlotKey(s, tab: 0, at: 0, to: "1"), 0), nil, "자기 기본 숫자와 같으면 저장하지 않는다")
    let withW = D.settingSlotKey(s, tab: 0, at: 0, to: "w")
    checkEqual(slotKey(D.settingSlotKey(withW, tab: 0, at: 0, to: nil), 0), nil, "nil 은 기본으로 되돌림")
    checkEqual(slotKey(D.settingSlotKey(withW, tab: 0, at: 1, to: "w"), 1), nil, "다른 슬롯이 이미 쓰는 지정 키는 못 쓴다")
    checkEqual(D.settingSlotKey(withW, tab: 0, at: 1, to: "1").tabs[0].slots[1]?.key, "1", "비워 둔 1번 칸의 기본 숫자는 이제 2번 칸이 쓸 수 있다")

    checkEqual(slotDirection(D.settingSlotDirection(s, tab: 0, at: 0, to: .right), 0), .right, "방향 지정")
    checkEqual(D.settingSlotDirection(s, tab: 0, at: 0, to: .upRight), s, "다른 슬롯의 기본 방향(↗)은 못 쓴다")
    check(D.slotUsingDirection(s, tab: 0, direction: .upRight, except: 0) == 1, "그 방향을 쓰는 슬롯")
    checkEqual(slotDirection(D.settingSlotDirection(s, tab: 0, at: 0, to: SlotDirection.off), 0), SlotDirection.off, "방향키로 고르지 않음")
    checkEqual(slotDirection(D.settingSlotDirection(s, tab: 0, at: 0, to: .up), 0), nil, "링 기본 방향과 같으면 저장하지 않는다")
    check(D.slotUsingDirection(s, tab: 0, direction: SlotDirection.off, except: 0) == nil, "끈 방향은 겹쳐도 된다")

    checkEqual(D.settingCloseKey(s, to: "x").closeKey, "x", "닫기 키 지정")
    checkEqual(D.settingCloseKey(s, to: "1"), s, "슬롯이 쓰는 숫자는 닫기 키로 못 쓴다")
    check(D.closeKeyConflict(s, key: "1")?.contains("슬롯 1") == true, "닫기 키 겹침 안내")
    checkEqual(D.settingCloseKey(s, to: "ab"), s, "형식이 맞지 않으면 바꾸지 않는다")
    checkEqual(D.settingCloseKey(s, to: "8").closeKey, "8", "빈 칸의 기본 숫자는 닫기 키로 쓸 수 있다")

    // 기본으로 되돌리는 것도 겹침 검사를 받는다: 되돌린 기본 키·방향을 다른 슬롯이 이미 쓰면 바꾸지 않는다
    var reset = D.settingSlotKey(D.settingSlotKey(s, tab: 0, at: 0, to: "w"), tab: 0, at: 1, to: "1")
    checkEqual(slotKey(reset, 1), "1", "1번 칸이 W 로 바뀐 사이 2번 칸이 숫자 1 을 지정")
    checkEqual(D.settingSlotKey(reset, tab: 0, at: 0, to: nil), reset, "1번 칸을 기본(1)으로 되돌리면 2번 칸의 1 과 겹쳐 되돌리지 않는다")
    reset = D.settingSlotDirection(D.settingSlotDirection(s, tab: 0, at: 0, to: SlotDirection.off), tab: 0, at: 1, to: .up)
    checkEqual(D.settingSlotDirection(reset, tab: 0, at: 0, to: nil), reset, "1번 칸을 기본 방향(↑)으로 되돌리면 2번 칸의 ↑ 와 겹쳐 되돌리지 않는다")

    // 복제본은 지정한 키·방향을 이어받지 않는다(겹쳐서 저장이 막히지 않게)
    let custom = D.settingSlotDirection(D.settingSlotKey(s, tab: 0, at: 0, to: "w"), tab: 0, at: 0, to: .down)
    let duplicated = D.duplicateSlot(custom, tab: 0, at: 0)
    checkEqual(duplicated.tabs[0].slots[2]?.key, nil, "복제본은 기본 키")
    check(duplicated.tabs[0].slots[2]?.direction == nil, "복제본은 기본 방향")
    check(slotKey(duplicated, 0) == "w" && slotDirection(duplicated, 0) == .down, "원본의 지정은 그대로")
    checkEqual(SettingsValidator.validate(duplicated).filter { $0.text.contains("키") || $0.text.contains("방향") }.map(\.text), [], "복제해도 키·방향 겹침 오류가 생기지 않는다")

    // 옮긴 슬롯의 지정이 새 자리에서 겹치면 풀린다(손으로 고친 파일처럼 기본과 같은 방향이 저장돼 있는 경우)
    var handEdited = s
    handEdited.tabs[0].slots[0]?.direction = .up
    let swappedAway = D.moveSlot(handEdited, tab: 0, from: 0, to: 1)
    checkEqual(slotDirection(swappedAway, 1), nil, "1번 슬롯이 2번 칸으로 가면 ↑ 지정이 풀려 새 자리의 기본 방향을 쓴다")
    checkEqual(SettingsValidator.validate(swappedAway).filter { $0.text.contains("방향") }.map(\.text), [], "맞바꾼 뒤 방향 겹침 오류가 없다")

    // 고쳐진 설정은 검증을 통과한다(새 슬롯의 빈 앱 동작은 사용자가 채워야 하므로 URL 동작을 넣는다)
    var edited = s
    for p in 0..<2 { edited = D.updateSlot(edited, tab: 0, at: p) { $0.action = .openURL("https://\(p).example") } }
    edited = D.settingSlotKey(edited, tab: 0, at: 0, to: "w")
    edited = D.settingSlotDirection(edited, tab: 0, at: 1, to: .left)
    edited = D.settingCloseKey(edited, to: "x")
    checkEqual(SettingsValidator.validate(edited).map(\.text), [], "키 배정을 고친 설정은 유효")
}

private func dirtyDetection() {
    section("Settings: isDirty")

    let s = fixture()
    check(!D.isDirty(baseline: s, draft: s), "같으면 변경 없음")
    check(D.isDirty(baseline: s, draft: D.updateSlot(s, tab: 1, at: 0) { $0.name = "다른 이름" }), "실제 편집은 변경")
    check(D.isDirty(baseline: s, draft: D.addTab(s, .custom)), "탭 추가는 변경")

    // 파일로 저장했다 읽은 값(정규화)과 편집 중 값이 표현만 다르면 변경이 아니다

    var withLabel = D.updateSlot(s, tab: 1, at: 0) { $0.label = "ZZ" }
    let data = try! JSONEncoder().encode(withLabel)
    let saved = try! JSONDecoder().decode(Settings.self, from: data)
    check(!D.isDirty(baseline: saved, draft: withLabel), "저장 왕복 후에는 변경으로 보지 않는다")
    withLabel = D.updateSlot(withLabel, tab: 1, at: 0) { $0.label = nil }
    check(D.isDirty(baseline: saved, draft: withLabel), "라벨을 지우면 변경")

    // 매크로의 stopOnError 기본값(true)을 JSON 에서 생략한 파일을 읽은 것과 같다
    let legacy = #"{"type":"macro_sequence","steps":[{"type":"open_url","url":"https://a.example"}]}"#
    let action = try! JSONDecoder().decode(Action.self, from: Data(legacy.utf8))
    let a = D.updateSlot(s, tab: 2, at: 0) { $0.action = action }
    let b = D.updateSlot(s, tab: 2, at: 0) { $0.action = .macroSequence(stopOnError: true, steps: [.openURL("https://a.example")]) }
    check(!D.isDirty(baseline: a, draft: b), "stopOnError 생략 표기와 명시 표기는 같다")

    // 끝에 붙은 빈 칸(null)은 저장 형태에서 떨어지므로 변경이 아니다. 슬롯을 비우는 것은 변경이다.
    var padded = s
    padded.tabs[2].slots += [nil, nil, nil]
    check(!D.isDirty(baseline: s, draft: padded), "끝에 붙은 빈 칸은 변경이 아니다")
    check(D.isDirty(baseline: s, draft: D.removeSlot(s, tab: 2, at: 0)), "슬롯을 비우면 변경")

}

private func appPicker() {
    section("Settings: 앱 검색")

    let calc = calculator()
    for q in ["계산기", "calc", "CALCULATOR", "apple.calculator", "  계산  "] {
        check(D.matches(calc, query: q), "'\(q)' 로 검색된다")
    }
    check(!D.matches(calc, query: "safari"), "무관한 검색어는 제외")
    check(D.matches(calc, query: ""), "빈 검색어는 전체")
    check(D.matches(InstalledApp(bundleId: "com.x.y", name: "엑스", altName: nil, appPath: "/x.app"), query: "엑"), "altName 이 없어도 검색")

    // 앱이 바뀌면 이름·라벨을 파일 이름으로 다시 정한다
    let base = Slot(id: "s", name: "내 계산기", label: "ZZ", action: D.defaultAction(.launchApp))
    let picked = D.applyingAction(.launchApp(bundleId: calc.bundleId, appPath: nil), to: base, apps: [calc])
    checkEqual(picked.name, "Calculator", "고른 앱은 파일 이름으로 이름을 덮어씀")
    checkEqual(picked.label, "CA", "라벨도 파일 이름에서 만듦")
    let typed = D.applyingAction(.launchApp(bundleId: nil, appPath: "/Applications/Visual Studio Code.app"), to: base, apps: [])
    checkEqual(typed.name, "Visual Studio Code", "경로 직접 입력은 파일 이름 사용")
    checkEqual(typed.label, "VS", "여러 단어는 앞 두 단어 첫 글자")
    checkEqual(D.applyingAction(.launchApp(bundleId: nil, appPath: "/Applications/Visual Studio Code.app"), to: typed, apps: []), typed, "같은 동작이면 그대로")
    checkEqual(D.applyingAction(.launchApp(bundleId: nil, appPath: "/Applications/Foo"), to: base, apps: []).name, "내 계산기", ".app 이 아닌 경로는 이름 유지")
    checkEqual(D.applyingAction(.launchApp(bundleId: "unknown.app", appPath: nil), to: base, apps: [calc]).name, "내 계산기", "목록에 없는 번들 ID 는 이름 유지")
    checkEqual(D.applyingAction(.openURL("https://a.com"), to: base, apps: [calc]).name, "내 계산기", "앱 동작이 아니면 이름 유지")
    let longApp = InstalledApp(bundleId: "l", name: "l", altName: nil, appPath: "/Applications/\(String(repeating: "A", count: 60)).app")
    checkEqual(D.applyingAction(.launchApp(bundleId: "l", appPath: nil), to: base, apps: [longApp]).name.count, 40, "이름은 40자 상한")
    let emojiApp = InstalledApp(bundleId: "e", name: "e", altName: nil, appPath: "/Applications/🙂🙂Pad.app")
    let emoji = D.applyingAction(.launchApp(bundleId: "e", appPath: nil), to: base, apps: [emojiApp])
    checkEqual(emoji.label, nil, "UTF-16 3유닛을 넘는 약어는 라벨을 비움")
    let nfdName = String(repeating: "\u{1112}\u{1161}\u{11AB}", count: 20)
    let nfdApp = InstalledApp(bundleId: "n", name: "n", altName: nil, appPath: "/Applications/\(nfdName).app")
    let nfd = D.applyingAction(.launchApp(bundleId: "n", appPath: nil), to: base, apps: [nfdApp])
    check(nfd.name.utf16.count <= 40 && !nfd.name.isEmpty, "이름은 UTF-16 40유닛 상한")
    check(nfd.label == nil, "NFD 한글 약어는 3유닛 초과라 라벨 비움")
}

private func shortcutRecording() {
    section("Settings: 단축키 녹화")

    typealias R = ShortcutRecording
    checkEqual(R.interpret(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: .option), .accelerator("Alt+Q"), "Alt+Q")
    checkEqual(R.interpret(keyCode: UInt16(kVK_Space), modifierFlags: [.command, .shift]), .accelerator("Command+Shift+Space"), "Command+Shift+Space")
    checkEqual(R.interpret(keyCode: UInt16(kVK_F12), modifierFlags: .control), .accelerator("Control+F12"), "Control+F12")
    checkEqual(R.interpret(keyCode: UInt16(kVK_ANSI_Keypad5), modifierFlags: .option), .accelerator("Alt+num5"), "키패드 5 는 메인 열 5 와 다르다")
    checkEqual(R.interpret(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: []), .needsModifier, "수정키 없음")
    checkEqual(R.interpret(keyCode: UInt16(kVK_F5), modifierFlags: []), .needsModifier, "F5 만 눌러도 수정키 필요")
    checkEqual(R.interpret(keyCode: UInt16(kVK_Option), modifierFlags: .option), .ignore, "수정키만 눌림은 무시")
    checkEqual(R.interpret(keyCode: UInt16(kVK_RightCommand), modifierFlags: .command), .ignore, "오른쪽 Command 만 눌림도 무시")
    checkEqual(R.interpret(keyCode: UInt16(kVK_Escape), modifierFlags: []), .cancel, "Esc 는 녹화 취소")
    checkEqual(R.interpret(keyCode: UInt16(kVK_Escape), modifierFlags: .option), .cancel, "수정키+Esc 도 취소")
    checkEqual(R.interpret(keyCode: 0x5F, modifierFlags: .option), .needsModifier, "지원하지 않는 키")

    checkEqual(Accelerator.display("Alt+Q"), "⌥Q", "표시: ⌥Q")
    checkEqual(Accelerator.display("Command+Shift+Space"), "⇧⌘Space", "표시: ⇧⌘Space")
    checkEqual(Accelerator.display("Control+Alt+Up"), "⌃⌥↑", "표시: ⌃⌥↑")
}

private final class FeedbackStore: SettingsStoring {
    var current = Settings.defaults
    var warning: String?
    var fileURL = URL(fileURLWithPath: "/tmp/qs-feedback-settings.json")
    func reload() -> Settings { current }
    func save(_ settings: Settings) -> ActionResult { current = settings; return .success }
}

private final class FeedbackCatalog: AppCatalog {
    func frontmostApp() -> RunningApp? { nil }
    func activate(bundleId: String, pid: Int32?) async -> ActionResult { .success }
    func refocus(bundleId: String, pid: Int32?) -> Bool { true }
    func open(bundleId: String?, appPath: String?) async -> ActionResult { .success }
    func installedApps() async -> [InstalledApp] { [] }
    func iconPNG(for target: IconTarget, pixels: Int) -> Data? { nil }
}

/// 애니메이션 표현을 구동하는 순수 상태(상태 문구 종류, 오류 피드백 카운터)와, 그것이 저장 결과를 바꾸지 않음
private func feedbackState() {
    section("Settings: 상태 문구·오류 피드백")

    MainActor.assumeIsolated {
        var result = ActionResult.success
        let store = FeedbackStore()
        let model = SettingsModel(store: store, catalog: FeedbackCatalog(), save: { _ in result }, checkForUpdates: {}, versionText: { "t" })
        var savedCount = 0
        model.onSaved = { savedCount += 1 }

        checkEqual(model.statusKind, .clean, "처음에는 깨끗")
        checkEqual(model.errorFeedback, 0, "처음 피드백 0")

        model.draft.overlay.alpha = 0.5
        checkEqual(model.statusKind, .dirty, "수정하면 변경됨")
        checkEqual(model.errorFeedback, 0, "정상 수정은 피드백을 늘리지 않는다")

        result = .failure("디스크 가득")
        model.save()
        checkEqual(model.statusKind, .saveError, "저장 실패 문구")
        checkEqual(model.errorFeedback, 1, "저장 실패 때 1 증가")
        check(model.isDirty && model.draft.overlay.alpha == 0.5, "실패해도 draft 는 보존")
        checkEqual(savedCount, 0, "저장 실패에서는 창을 닫지 않는다")

        model.draft.overlay.alpha = 0.6
        checkEqual(model.statusKind, .dirty, "다시 수정하면 오류 문구가 사라진다")
        result = .success
        model.save()
        checkEqual(model.statusKind, .clean, "저장 성공 후 깨끗")
        checkEqual(model.errorFeedback, 1, "성공은 피드백을 늘리지 않는다")
        checkEqual(model.baseline.overlay.alpha, 0.6, "저장 결과는 애니메이션과 무관하게 draft 그대로")
        checkEqual(savedCount, 1, "저장 성공에서 한 번 알린다")

        model.save()
        checkEqual(model.errorFeedback, 1, "변경 없는 저장 시도는 피드백 없음")
        checkEqual(savedCount, 1, "변경 없는 저장 시도는 알리지 않는다")

        model.draft.overlay.alpha = 9
        checkEqual(model.statusKind, .issue, "검증 문제 문구")
        checkEqual(model.errorFeedback, 1, "편집으로 문제가 생겨도 카운터는 그대로")
        model.draft.overlay.alpha = 8
        model.draft.overlay.alpha = 0.7
        model.draft.shortcut = "Alt+W"
        checkEqual(model.errorFeedback, 1, "draft 편집은 카운터를 바꾸지 않는다")
        model.draft.overlay.alpha = 9
        model.save()
        checkEqual(model.errorFeedback, 2, "검증에 막힌 저장 시도는 피드백")
        checkEqual(model.baseline.overlay.alpha, 0.6, "막힌 저장은 아무것도 저장하지 않는다")
        checkEqual(savedCount, 1, "검증에 막힌 저장은 알리지 않는다")
    }
}

private final class CountingCatalog: AppCatalog {
    private(set) var scans = 0
    var list: [InstalledApp] = []
    func frontmostApp() -> RunningApp? { nil }
    func activate(bundleId: String, pid: Int32?) async -> ActionResult { .success }
    func refocus(bundleId: String, pid: Int32?) -> Bool { true }
    func open(bundleId: String?, appPath: String?) async -> ActionResult { .success }
    func installedApps() async -> [InstalledApp] { scans += 1; return list }
    func iconPNG(for target: IconTarget, pixels: Int) -> Data? { nil }
}

/// 단축키 녹화 중 전역 단축키 일시 해제 알림과, 창을 다시 열 때의 설치 앱 재스캔
private func recordingPauseAndAppRefresh() {
    section("Settings: 녹화 일시정지 알림·앱 목록 재스캔")

    MainActor.assumeIsolated {
        var events: [Bool] = []
        let catalog = CountingCatalog()
        let model = SettingsModel(store: FeedbackStore(), catalog: catalog, save: { _ in .success }, checkForUpdates: {}, versionText: { "t" },
                                  onRecordingChange: { events.append($0) })

        model.setShortcutRecording(true)
        model.setShortcutRecording(true)
        checkEqual(events, [true], "중복 시작은 한 번만 알린다")
        // 녹화 확정(false) 뒤에 창 닫기(false)가 겹쳐 와도 재등록은 한 번이다
        model.setShortcutRecording(false)
        model.setShortcutRecording(false)
        checkEqual(events, [true, false], "종료 중복도 한 번만, 마지막은 항상 false")

        // 녹화 중에 창이 닫히면(setShortcutRecording(false)) 반드시 false 로 끝난다
        model.setShortcutRecording(true)
        model.setShortcutRecording(false)
        checkEqual(events, [true, false, true, false], "녹화 중 닫기: true → false")

        // 설치 앱 목록: 창을 다시 열 때마다 새로 읽고, 새 결과가 반영된다
        let before = catalog.scans
        catalog.list = [InstalledApp(bundleId: "new.app", name: "새 앱", altName: nil, appPath: "/Applications/New.app")]
        model.resetFromStore()
        // 재스캔은 백그라운드에서 끝나므로 고정 시간이 아니라 조건이 맞을 때까지(최대 5초) 기다린다. 느린 CI 러너(Intel)에서 0.2초로는 모자랐다.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !(catalog.scans > before && !model.apps.isEmpty) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        checkEqual(catalog.scans, before + 1, "다시 열면 재스캔")
        checkEqual(model.apps.map(\.bundleId), ["new.app"], "새로 설치한 앱이 목록에 나타난다")
    }
}

/// 실제 경로(녹화 버튼, 설정 창 닫기/키 창 상실)에서 녹화 종료가 반드시 전달되는지. 창은 화면에 띄우지 않는다.
private func recordingRealPaths() {
    section("Settings: 녹화 종료 실제 경로")

    MainActor.assumeIsolated {
        _ = NSApplication.shared

        for end in ["resign", "dismantle"] {
            var events: [Bool] = []
            let button = ShortcutRecorder.RecorderButton()
            button.onRecordingChange = { events.append($0) }
            button.performClick(nil)
            checkEqual(events, [true], "클릭하면 녹화 시작이 동기로 알려진다(\(end))")
            if end == "resign" { _ = button.resignFirstResponder() } else { button.endRecording() }
            checkEqual(events, [true, false], "녹화 종료가 알려진다(\(end))")
            button.endRecording()
            checkEqual(events, [true, false], "종료 중복은 다시 알리지 않는다(\(end))")
        }

        for close in ["close", "resignKey"] {
            var events: [Bool] = []
            let controller = SettingsWindowController(
                store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success },
                checkForUpdates: {}, versionText: { "t" }, onRecordingChange: { events.append($0) })
            controller.model.setShortcutRecording(true)
            if close == "close" {
                controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
            } else {
                controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
            }
            checkEqual(events, [true, false], "녹화 중 \(close) 이면 false 로 끝난다")
        }
    }
}

private func overlaySizeEditing() {
    section("Settings: 패널 크기 편집")
    var s = Settings.defaults
    s.overlay.ringSize = 320
    s.overlay.centerSize = 240
    let shrunk = D.settingRing(s, to: 200)
    checkEqual(shrunk.overlay.centerSize, 128, "바깥을 줄이면 중앙 원이 상한(ring-72)으로 보정")
    checkEqual(SettingsValidator.validate(shrunk).map(\.text), [], "보정 결과는 유효")
    checkEqual(D.settingRing(s, to: 300).overlay.centerSize, 228, "ring 300 이면 240 → 228 로 보정")
    checkEqual(D.settingRing(Settings.defaults, to: 300).overlay.centerSize, 78, "상한 안이면 중앙 원 유지(오비트 기본 78)")

    check(D.isDirty(baseline: .defaults, draft: D.settingRing(.defaults, to: 251)), "바깥 크기 변경은 dirty")
    var c = Settings.defaults
    c.overlay.centerSize = 113
    check(D.isDirty(baseline: .defaults, draft: c), "중앙 원 변경은 dirty")

    var border = Settings.defaults
    border.overlay.centerBorder = 7
    check(D.isDirty(baseline: .defaults, draft: border), "테두리 굵기 변경은 dirty")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft.overlay.centerBorder = 9
        model.resetToDefaults()
        checkEqual(model.draft.overlay.centerBorder, 4, "초기화 → 테두리 4(오비트 기본)")
        model.draft = D.settingRing(model.draft, to: 180)
        model.draft.overlay.centerBorder = 9
        model.revert()
        checkEqual(model.draft.overlay.centerBorder, 4, "되돌리기 → 테두리 4(오비트 기본)")
        model.draft = D.settingRing(model.draft, to: 180)
        model.draft.overlay.centerBorder = 9
        model.resetToDefaults()
        model.draft = D.settingRing(model.draft, to: 180)
        model.draft.overlay.centerSize = 100
        model.resetToDefaults()
        checkEqual(model.draft.overlay.ringSize, 258, "초기화 → 바깥 258(오비트 기본)")
        checkEqual(model.draft.overlay.centerSize, 78, "초기화 → 중앙 78(오비트 기본)")
        model.draft = D.settingRing(model.draft, to: 180)
        model.revert()
        checkEqual(model.draft.overlay.ringSize, 258, "되돌리기 → 바깥 258(오비트 기본)")
    }
}

private func piePreviewMetrics() {
    section("Settings: 파이 미리보기 치수")

    // 어떤 링 크기도 표시 폭 안에 들어가고(최대 링 기준 배율), 선택 조각이 튀어나와도 잘리지 않는다
    for ring in [160, 250, 320] {
        var o = OverlaySettings()
        o.ringSize = ring
        let m = PiePreviewMetrics(style: PiePreviewStyle(o), maxSize: 280, referenceRing: Limits.ringRange.upperBound)
        check(m.geometry.boxSize * m.scale <= 280 + 0.001, "링 \(ring) 은 280 안")
        check((m.geometry.outerRadius + OverlayMotion.selectedPop) * 2 * m.scale <= 280, "링 \(ring) 선택 조각 포함 280 안")
        let fit = PiePreviewMetrics(style: PiePreviewStyle(o), maxSize: 280, referenceRing: ring)
        checkEqual(fit.geometry.boxSize * fit.scale, 280, "현재 링 기준이면 영역을 꽉 채운다(링 \(ring))")
    }

    // draft 값을 그대로 쓴다
    var o = OverlaySettings()
    o.alpha = 0.6; o.radius = 30; o.ringSize = 200; o.centerSize = 80; o.centerBorder = 6
    let style = PiePreviewStyle(o)
    checkEqual(style, PiePreviewStyle(o), "같은 입력은 같은 값")
    checkEqual(style.alpha, 0.6, "alpha"); checkEqual(style.cornerSetting, 30, "radius")
    checkEqual(style.ringSize, 200, "ring"); checkEqual(style.centerSize, 80, "center"); checkEqual(style.centerBorder, 6, "border")
    let m = PiePreviewMetrics(style: style, maxSize: 280, referenceRing: 200)
    checkEqual(m.geometry, PieGeometry(ringRadius: 200, centerRadius: 80, centerBorder: 6), "오버레이와 같은 PieGeometry")
    checkEqual(m.corner, PieGeometry.cornerRadius(setting: 30), "오버레이와 같은 모서리 변환")

    // 좌표 → 슬롯: 스케일을 적용한 경계 양쪽
    let c = m.side / 2
    let hub = m.geometry.hubRadius * m.scale, outer = m.geometry.outerRadius * m.scale
    check(m.slotIndex(at: CGPoint(x: c, y: c)) == nil, "중앙 원 안은 nil")
    check(m.slotIndex(at: CGPoint(x: c, y: c - hub + 1)) == nil, "중앙 원 경계 안쪽")
    checkEqual(m.slotIndex(at: CGPoint(x: c, y: c - hub - 1)), 0, "경계 바깥은 1번(12시)")
    checkEqual(m.slotIndex(at: CGPoint(x: c, y: c - outer + 1)), 0, "링 바깥 경계 안쪽")
    check(m.slotIndex(at: CGPoint(x: c, y: c - outer - 1)) == nil, "링 밖은 nil")
    checkEqual(m.slotIndex(at: CGPoint(x: c + (hub + outer) / 2, y: c)), 2, "3시 방향은 3번")
    checkEqual(m.slotIndex(at: CGPoint(x: c - (hub + outer) / 2, y: c)), 6, "9시 방향은 7번")
}

private func themeSwitching() {
    section("Settings: 테마 전환·크기 독립")
    // 테마를 바꿔도 두 테마의 크기는 그대로다(프리셋 자동 적용 없음)
    var s = Settings.defaults
    s.overlay.pieSizes = ThemeSizes(ring: 200, center: 80, border: 6)
    s.overlay.orbitSizes = ThemeSizes(ring: 310, center: 100, border: 2)
    var toOrbit = s
    toOrbit.overlay.theme = .orbit
    checkEqual([toOrbit.overlay.pieSizes, toOrbit.overlay.orbitSizes], [s.overlay.pieSizes, s.overlay.orbitSizes], "테마 전환은 두 테마의 크기를 바꾸지 않는다")
    checkEqual([toOrbit.overlay.ringSize, toOrbit.overlay.centerSize, toOrbit.overlay.centerBorder], [310, 100, 2], "오비트로 바꾸면 오비트 자신의 크기")
    var back = toOrbit
    back.overlay.theme = .pie
    checkEqual([back.overlay.ringSize, back.overlay.centerSize, back.overlay.centerBorder], [200, 80, 6], "파이로 돌아오면 파이 자신의 크기")
    // 손대지 않은 기본값도 테마 전환으로 덮어써지지 않는다
    var fresh = Settings.defaults
    fresh.overlay.theme = .pie // 기본이 오비트라 파이로 바꿔야 달라진다
    checkEqual(fresh.overlay.pieSizes, OverlayTheme.pie.defaultSizes, "기본 파이 크기 유지")
    checkEqual(fresh.overlay.orbitSizes, OverlayTheme.orbit.defaultSizes, "기본 오비트 크기 유지")
    checkEqual(SettingsValidator.validate(toOrbit).map(\.text), [], "전환 결과는 유효")
    check(D.isDirty(baseline: .defaults, draft: fresh), "테마만 달라도 dirty(기본 오비트 → 파이)")
    // 슬라이더 편집은 현재 테마에만
    var e = Settings.defaults
    e.overlay.theme = .pie // 기본이 오비트이므로 파이 편집은 명시적으로 파이를 고른 뒤
    let orbitBefore = e.overlay.orbitSizes
    e = D.settingRing(e, to: 200)
    e = D.settingCenter(e, to: 90)
    e = D.settingBorder(e, to: 7)
    checkEqual(e.overlay.pieSizes, ThemeSizes(ring: 200, center: 90, border: 7), "파이 편집은 파이 크기")
    checkEqual(e.overlay.orbitSizes, orbitBefore, "파이 편집은 오비트를 건드리지 않는다")
    e.overlay.theme = .orbit
    // 기본 중앙 원(78)은 ring 160 의 상한(88) 안이라 보정 시험이 되지 않는다: 큰 값을 명시해 둔다
    e = D.settingCenter(e, to: 96)
    let pieBefore = e.overlay.pieSizes
    e = D.settingRing(e, to: 280)
    e = D.settingBorder(e, to: 5)
    checkEqual(e.overlay.orbitSizes, ThemeSizes(ring: 280, center: 96, border: 5), "오비트 편집은 오비트 크기")
    checkEqual(e.overlay.pieSizes, pieBefore, "오비트 편집은 파이를 건드리지 않는다")
    // 바깥 크기를 줄이면 중앙 원이 현재 테마의 상한으로 보정
    let shrunk = D.settingRing(e, to: 160)
    checkEqual(shrunk.overlay.orbitSizes.center, Limits.centerRange(ring: 160).upperBound, "바깥을 줄이면 중앙 원이 상한으로")
    checkEqual(shrunk.overlay.pieSizes, pieBefore, "보정은 다른 테마에 영향 없음")
    checkEqual(D.settingCenter(e, to: 9999).overlay.centerSize, Limits.centerRange(ring: 280).upperBound, "중앙 원은 상한을 넘지 못한다")
    checkEqual(D.settingBorder(e, to: 99).overlay.centerBorder, Limits.centerBorderRange.upperBound, "테두리는 범위로 보정")

    // 이 테마 크기를 기본값으로: 현재 테마만
    var r = Settings.defaults
    r.overlay.pieSizes = ThemeSizes(ring: 200, center: 80, border: 6)
    r.overlay.orbitSizes = ThemeSizes(ring: 310, center: 100, border: 2)
    r.overlay.theme = .orbit
    let reset = D.resettingSizes(r)
    checkEqual(reset.overlay.orbitSizes, OverlayTheme.orbit.defaultSizes, "오비트 기본값으로")
    checkEqual(reset.overlay.pieSizes, ThemeSizes(ring: 200, center: 80, border: 6), "파이는 그대로")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft.overlay.theme = .pie
        model.resetToDefaults()
        checkEqual(model.draft.overlay.theme, .orbit, "초기화 → 기본 테마 orbit")
        checkEqual([model.draft.overlay.pieSizes, model.draft.overlay.orbitSizes], [OverlayTheme.pie.defaultSizes, OverlayTheme.orbit.defaultSizes], "초기화 → 각 테마 기본 크기")
        model.draft.overlay.theme = .pie
        model.revert()
        checkEqual(model.draft.overlay.theme, .orbit, "되돌리기 → 기본 테마 orbit")
        checkEqual(model.panelTab, .shape, "패널 탭 기본은 모양")
        model.panelTab = .color
        model.draft.overlay.alpha = 0.5
        model.revert()
        checkEqual(model.panelTab, .color, "되돌리기는 화면 탭을 바꾸지 않는다")
    }
}

private func bodyAndFocusSelection() {
    section("Settings: 본체·포커스 색")
    // normalized 경계
    checkEqual(FocusColors.normalized("#abc"), "#AABBCC", "#abc → 3자리 확장")
    checkEqual(FocusColors.normalized("ABCDEF"), "#ABCDEF", "# 없는 6자리")
    checkEqual(FocusColors.normalized("  #fae32e \n"), "#FAE32E", "앞뒤 공백 제거")
    for bad in ["", "#", "#12", "#1234", "#12345", "#1234567", "#GGGGGG", "#12 456", "##ABCDEF", "red", "#ABCDEFG"] {
        check(FocusColors.normalized(bad) == nil, "잘못된 색은 nil: \(bad)")
    }
    // settingFocusHex
    let base = Settings.defaults
    checkEqual(D.settingFocusHex(base, to: "ff7edb").overlay.focusHex, "#FF7EDB", "유효한 입력은 정규화되어 적용")
    checkEqual(D.settingFocusHex(base, to: "#zz"), base, "잘못된 입력은 draft 를 그대로 둔다")
    checkEqual(D.settingFocusHex(base, to: ""), base, "빈 입력도 그대로")

    // dirty: 각각 잡히고 서로 독립
    var body = base; body.overlay.bodyTheme = .clearGlass // 기본은 다크 글라스이므로 다른 본체로 바꿔야 달라진다
    var style = base; style.overlay.focusStyle = .flat
    var hex = base; hex.overlay.focusHex = "#FF7EDB"
    for (name, changed) in [("본체", body), ("스타일", style), ("색", hex)] {
        check(D.isDirty(baseline: base, draft: changed), "\(name) 변경은 dirty")
        check(!D.isDirty(baseline: changed, draft: changed), "같은 \(name) 은 깨끗")
    }
    var combo = body
    combo.overlay.focusStyle = .neon
    combo.overlay.focusHex = "#19F9D8"
    var bodyOnly = combo; bodyOnly.overlay.bodyTheme = .darkGray
    checkEqual([bodyOnly.overlay.focusStyle, bodyOnly.overlay.focusHex == "#19F9D8"] as [AnyHashable], [FocusStyle.neon, true] as [AnyHashable], "본체 변경은 포커스 스타일·색에 영향 없음")
    var styleOnly = combo; styleOnly.overlay.focusStyle = .flat
    checkEqual([styleOnly.overlay.bodyTheme == .clearGlass, styleOnly.overlay.focusHex == "#19F9D8"], [true, true], "스타일 변경은 본체·색에 영향 없음")
    var hexOnly = D.settingFocusHex(combo, to: "#123456")
    checkEqual([hexOnly.overlay.bodyTheme == .clearGlass, hexOnly.overlay.focusStyle == .neon], [true, true], "색 변경은 본체·스타일에 영향 없음")
    hexOnly.overlay.theme = .orbit
    checkEqual(hexOnly.overlay.focusHex, "#123456", "테마 전환은 포커스 색 유지")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        checkEqual(model.focusHexInput, FocusColors.defaultHex, "입력 칸 초기값 = 현재 색")
        // 입력 칸: 유효할 때만 draft 반영
        model.focusHexInput = "#12"
        model.draft = D.settingFocusHex(model.draft, to: model.focusHexInput)
        checkEqual(model.draft.overlay.focusHex, FocusColors.defaultHex, "잘못된 입력은 draft 를 오염시키지 않는다")
        checkEqual(model.focusHexInput, "#12", "잘못된 입력은 입력 칸에 남는다")
        model.draft.overlay.alpha = 0.6
        checkEqual(model.focusHexInput, "#12", "무관한 편집은 입력 칸을 지우지 않는다")
        // 프리셋 선택 → 입력 칸 동기화
        model.draft = D.settingFocusHex(model.draft, to: "#FF7EDB")
        checkEqual(model.focusHexInput, "#FF7EDB", "프리셋 선택이 입력 칸을 갱신")
        // 입력 칸에서 줄임 표기 → 정규화된 값이 draft 에, 입력 칸은 치는 그대로
        model.focusHexInput = "#abc"
        model.draft = D.settingFocusHex(model.draft, to: model.focusHexInput)
        checkEqual(model.draft.overlay.focusHex, "#AABBCC", "줄임 표기는 정규화")
        checkEqual(model.focusHexInput, "#abc", "치는 중인 글자는 그대로")
        // 되돌리기/초기화 → 입력 칸 동기화
        model.revert()
        checkEqual(model.focusHexInput, FocusColors.defaultHex, "되돌리기 → 입력 칸")
        model.draft.overlay.focusHex = "#101040"
        model.resetToDefaults()
        checkEqual(model.focusHexInput, FocusColors.defaultHex, "초기화 → 입력 칸")
        // 설정 창 색은 draft 를 따른다
        model.draft.overlay.bodyTheme = .darkGlass
        model.draft.overlay.focusHex = "#FF7EDB"
        model.draft.overlay.focusStyle = .flat
        checkEqual(model.palette, SettingsPalette.make(body: .darkGlass, focusHex: "#FF7EDB", style: .flat), "model.palette 는 draft 의 본체·포커스 색·스타일")
        model.draft.overlay.focusStyle = .neon
        checkEqual(model.palette, SettingsPalette.make(body: .darkGlass, focusHex: "#FF7EDB", style: .neon), "스타일을 바꾸면 창 색이 네온으로")
    }
}

private func settingsPaletteContrast() {
    section("Settings: 설정 창 색 대비")
    var hexes = FocusColors.presets.map(\.hex)
    hexes += ["#000000", "#FFFFFF", "#101040", "#FFFFE0", "#FF0000", "#0000FF", "#00FF00", "#808080", "#7F7F7F", "#767676", "#FFFF00", "#000080"]
    // 8단계 격자(512색)도 훑는다
    for r in stride(from: 0, through: 255, by: 37) {
        for g in stride(from: 0, through: 255, by: 37) {
            for b in stride(from: 0, through: 255, by: 37) { hexes.append(String(format: "#%02X%02X%02X", r, g, b)) }
        }
    }
    var worstOnAccent = 100.0, worstAccentText = 100.0, worstText = 100.0
    for body in OverlayBody.allCases {
        for hex in hexes {
            let p = SettingsPalette.make(body: body, focusHex: hex, style: .flat).swatches
            let pairs: [(String, Double)] = [
                ("글자/배경", ContrastMath.ratio(p.text, p.background)),
                ("글자/사이드바", ContrastMath.ratio(p.text, p.sidebar)),
                ("글자/카드", ContrastMath.ratio(p.text, p.card)),
                ("보조/배경", ContrastMath.ratio(p.muted, p.background)),
                ("보조/사이드바", ContrastMath.ratio(p.muted, p.sidebar)),
                ("보조/카드", ContrastMath.ratio(p.muted, p.card)),
                ("강조글자/카드", ContrastMath.ratio(p.accentText, p.card)),
                ("강조글자/사이드바", ContrastMath.ratio(p.accentText, p.sidebar)),
                ("강조글자/배경", ContrastMath.ratio(p.accentText, p.background)),
                ("강조면 위 글자", ContrastMath.ratio(p.onAccent, p.accent)),
                ("글자/입력칸", ContrastMath.ratio(p.text, p.field)),
                ("강조글자/입력칸", ContrastMath.ratio(p.accentText, p.field)),
                ("보조/입력칸", ContrastMath.ratio(p.muted, p.field)),
                ("글자/사이드바 선택", ContrastMath.ratio(p.text, p.selection)),
                ("주 버튼 호버 면 위 글자", ContrastMath.ratio(p.onAccent, ContrastMath.hoverFace(p.accent))),
                ("경고/카드", ContrastMath.ratio(SettingsRGB(1.0, 0.706, 0.329), p.card)),
                ("오류/카드", ContrastMath.ratio(SettingsRGB(1.0, 0.42, 0.42), p.card)),
                ("오류/사이드바", ContrastMath.ratio(SettingsRGB(1.0, 0.42, 0.42), p.sidebar)),
            ]
            for (name, ratio) in pairs where ratio < ContrastMath.minimumText {
                check(false, "\(body.rawValue) \(hex): \(name) 대비 \(ratio) < 4.5")
            }
            worstOnAccent = min(worstOnAccent, pairs[9].1)
            worstAccentText = min(worstAccentText, pairs[6].1)
            worstText = min(worstText, pairs[2].1)
        }
    }
    check(worstOnAccent >= 4.5 && worstAccentText >= 4.5 && worstText >= 4.5, "모든 본체 × 포커스 색에서 대비 4.5 이상(\(hexes.count)색)")
    // 호버를 글자와 같은 방향(본문 글자색)으로 섞던 이전 방식은 중간 명도 색에서 4.5 아래로 내려갔다: 표본이 그 구간을 실제로 덮는지 확인
    var sameDirectionBreaks = 0
    for body in OverlayBody.allCases {
        for hex in hexes {
            let p = SettingsPalette.make(body: body, focusHex: hex, style: .flat).swatches
            if ContrastMath.ratio(p.onAccent, p.accent.mixed(with: p.text, ContrastMath.hoverMix)) < 4.5 { sameDirectionBreaks += 1 }
        }
    }
    check(sameDirectionBreaks > 0, "표본에 '글자와 같은 방향 호버'가 깨지는 색이 있다(\(sameDirectionBreaks)건)")
    // 흰/검정 글자가 갈리는 경계(휘도 ≈ 0.18, 회색 ≈ 0x75) 주변 회색: 글자가 호버 층에 덮이지 않으므로 글자는 그대로 두고 면만 호버 색으로 잰다
    for level in 0x6C...0x80 {
        let hex = String(format: "#%02X%02X%02X", level, level, level)
        guard let accent = SettingsRGB(hex: hex) else { continue }
        check(ContrastMath.ratio(ContrastMath.onAccent(accent), ContrastMath.hoverFace(accent)) >= 4.5, "호버 면 위 글자 대비 ≥ 4.5(경계 회색 \(hex))")
    }

    // 네온: 면은 옅은 강조 틴트, 글자는 강조색 밝은 색. 프로덕션 함수(`ContrastMath.neonFace/neonText`)와 팔레트 값으로 잰다.
    var neonWorst = 100.0
    for body in OverlayBody.allCases {
        for hex in hexes {
            let pal = SettingsPalette.make(body: body, focusHex: hex, style: .neon)
            let p = pal.swatches
            guard let accent = SettingsRGB(hex: hex) else { check(false, "hex 해석: \(hex)"); continue }
            let faces: [(String, SettingsRGB)] = [
                ("입력칸 위 네온 면", p.neonFace),
                ("카드 위 네온 면", ContrastMath.neonFace(accent, over: p.card)),
                ("사이드바 위 네온 면(선택·하단 바)", ContrastMath.neonFace(accent, over: p.sidebar)),
                ("배경 위 네온 면", ContrastMath.neonFace(accent, over: p.background)),
            ]
            for (name, face) in faces {
                let ratio = ContrastMath.ratio(p.neonText, face)
                neonWorst = min(neonWorst, ratio)
                if ratio < 4.5 { check(false, "\(body.rawValue) \(hex) 네온: \(name) 위 글자 대비 \(ratio) < 4.5") }
            }
            let selectionRatio = ContrastMath.ratio(p.selectionText, p.selection)
            neonWorst = min(neonWorst, selectionRatio)
            if selectionRatio < 4.5 { check(false, "\(body.rawValue) \(hex) 네온: 선택 알약 위 글자 대비 \(selectionRatio) < 4.5") }
            // 뷰가 읽는 팔레트 값이 순수 함수와 같다
            check(p.neonText == ContrastMath.neonText(accent, over: p.field) && p.neonFace == ContrastMath.neonFace(accent, over: p.field), "팔레트 네온 값 = 순수 함수 값(\(hex))")
            check(pal.isNeon && pal.accentFace == p.neonFace.color && pal.onAccentFace == p.neonText.color, "네온은 면=틴트, 글자=밝은 색(\(hex))")
            let flat = SettingsPalette.make(body: body, focusHex: hex, style: .flat)
            check(!flat.isNeon && flat.accentFace == p.accent.color && flat.onAccentFace == p.onAccent.color, "플랫은 솔리드 강조 면 + 흰/검정 글자(\(hex))")
            check(flat.swatches.selection != p.selection, "플랫/네온 선택 알약 면이 다르다(\(hex))")
        }
    }
    check(neonWorst >= 4.5, "네온 면 위 글자 대비 최저 \(neonWorst) ≥ 4.5 (본체 \(OverlayBody.allCases.count) × \(hexes.count)색)")
    // 어둡거나 채도 낮은 색에서는 글자가 밝게 보정된다
    let dim = SettingsRGB(hex: "#101040")!
    check(ContrastMath.luminance(ContrastMath.neonText(dim, over: SettingsPalette.make(body: .darkGray, focusHex: "#101040", style: .neon).swatches.field)) > ContrastMath.luminance(dim), "어두운 강조색의 네온 글자는 밝아진다")

    // 강조색 면 위 글자색 선택 함수
    for hex in hexes {
        guard let accent = SettingsRGB(hex: hex) else { check(false, "hex 해석: \(hex)"); continue }
        let on = ContrastMath.onAccent(accent)
        check(ContrastMath.ratio(on, accent) >= 4.5, "강조색 \(hex) 위 글자 대비 ≥ 4.5")
        check(on == .white || on == .black, "글자색은 흰색/검정: \(hex)")
    }
    checkEqual(ContrastMath.onAccent(SettingsRGB(hex: "#FFFFE0")!), .black, "밝은 강조색 → 검정 글자")
    checkEqual(ContrastMath.onAccent(SettingsRGB(hex: "#101040")!), .white, "어두운 강조색 → 흰 글자")

    // 보정: 이미 읽히는 색은 그대로, 어두운 색은 밝아진다
    let card = SettingsPalette.make(body: .darkGray, focusHex: "#FFFFFF", style: .flat).swatches.card
    let yellow = SettingsRGB(hex: "#FAE32E")!
    checkEqual(ContrastMath.legible(yellow, on: card), yellow, "읽히는 강조색은 보정하지 않는다")
    let navy = SettingsRGB(hex: "#101040")!
    check(ContrastMath.luminance(ContrastMath.legible(navy, on: card)) > ContrastMath.luminance(navy), "어두운 강조색은 밝아진다")

    // 본체 두 가지는 서로 다른 면, 같은 포커스 색이면 강조색은 같다
    let gray = SettingsPalette.make(body: .darkGray, focusHex: "#FF7EDB", style: .flat).swatches
    let glass = SettingsPalette.make(body: .darkGlass, focusHex: "#FF7EDB", style: .flat).swatches
    check(gray.background != glass.background && gray.card != glass.card, "본체마다 면이 다르다")
    checkEqual(gray.accent, glass.accent, "포커스 색은 본체와 무관")
    check(abs(gray.card.r - gray.card.b) < 0.02, "다크 그레이 면은 중립 회색")
    check(glass.card.b > glass.card.r, "다크 글라스 면은 푸른빛")
}

private func glassTintSelection() {
    section("Settings: 글라스 본체·틴트")
    let base = Settings.defaults
    checkEqual(base.overlay.glassTintHex, "#6FB1FF", "기본 틴트는 하늘색")
    checkEqual(base.overlay.bodyTheme, .darkGlass, "기본 본체는 다크 글라스")

    // 정규화 setter: 유효(소문자·# 없음·3자리)는 정규화, 무효는 draft 그대로
    checkEqual(D.settingGlassTint(base, to: "ff8fc7").overlay.glassTintHex, "#FF8FC7", "유효한 틴트는 대문자로 정규화")
    checkEqual(D.settingGlassTint(base, to: "#abc").overlay.glassTintHex, "#AABBCC", "3자리 틴트 확장")
    for bad in ["", "#12", "nope", "#GGGGGG", "##ABCDEF"] {
        checkEqual(D.settingGlassTint(base, to: bad), base, "무효한 틴트는 draft 를 그대로 둔다: \(bad)")
    }
    checkEqual(D.settingGlassTint(base, to: "#FF8FC7").overlay.focusHex, base.overlay.focusHex, "틴트 변경은 포커스 색에 영향 없음")

    // dirty
    let pink = D.settingGlassTint(base, to: "#FF8FC7")
    check(D.isDirty(baseline: base, draft: pink), "틴트 변경은 dirty")
    check(!D.isDirty(baseline: pink, draft: pink), "같은 틴트는 깨끗")
    var clear = base; clear.overlay.bodyTheme = .clearGlass
    check(D.isDirty(baseline: base, draft: clear), "클리어 글라스 선택은 dirty")

    // 바닥판 토글: 글라스 본체에서는 편집 불가, 값은 보존된다
    var solidOff = base; solidOff.overlay.solidBacking = false
    var grayBase = base; grayBase.overlay.bodyTheme = .darkGray
    check(D.canEditSolidBacking(grayBase), "다크 그레이에서는 바닥판 토글 편집 가능")
    check(!D.canEditSolidBacking(base), "기본(다크 글라스)에서는 바닥판 토글 비활성")
    for body in [OverlayBody.darkGlass, .clearGlass] {
        var s = solidOff; s.overlay.bodyTheme = body
        check(!D.canEditSolidBacking(s), "\(body.rawValue) 에서는 바닥판 토글 비활성")
        var on = base; on.overlay.bodyTheme = body
        check(!D.canEditSolidBacking(on), "\(body.rawValue) 에서는 값이 true 여도 비활성")
        check(!PaletteColors.usesBackingPlate(body: body, solid: true), "오버레이도 \(body.rawValue) 에서 바닥판을 쓰지 않는다")
    }
    var back = solidOff; back.overlay.bodyTheme = .clearGlass; back.overlay.bodyTheme = .darkGray
    checkEqual(back.overlay.solidBacking, false, "본체를 되돌리면 이전 solidBacking 값 그대로")
    check(D.canEditSolidBacking(back), "본체를 되돌리면 다시 편집 가능")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        checkEqual(model.glassTintInput, "#6FB1FF", "틴트 입력 칸 초기값 = 현재 틴트")
        model.glassTintInput = "#12"
        model.draft = D.settingGlassTint(model.draft, to: model.glassTintInput)
        checkEqual(model.draft.overlay.glassTintHex, "#6FB1FF", "잘못된 입력은 draft 를 오염시키지 않는다")
        checkEqual(model.glassTintInput, "#12", "잘못된 입력은 입력 칸에 남는다")
        model.draft.overlay.alpha = 0.6
        checkEqual(model.glassTintInput, "#12", "무관한 편집은 입력 칸을 지우지 않는다")
        model.draft = D.settingGlassTint(model.draft, to: "#FF8FC7")
        checkEqual(model.glassTintInput, "#FF8FC7", "프리셋 선택이 입력 칸을 갱신")
        check(model.isDirty, "틴트 변경으로 dirty")
        model.revert()
        checkEqual(model.draft.overlay.glassTintHex, "#6FB1FF", "되돌리기 → 기본 틴트")
        checkEqual(model.glassTintInput, "#6FB1FF", "되돌리기 → 입력 칸")
        model.draft.overlay.bodyTheme = .clearGlass
        model.draft = D.settingGlassTint(model.draft, to: "#B8F26B")
        model.resetToDefaults()
        checkEqual(model.draft.overlay.glassTintHex, "#6FB1FF", "초기화 → 기본 틴트")
        checkEqual(model.draft.overlay.bodyTheme, .darkGlass, "초기화 → 기본 본체(다크 글라스)")
        checkEqual(model.glassTintInput, "#6FB1FF", "초기화 → 입력 칸")
        // 설정 창 색은 틴트를 따른다
        model.draft.overlay.bodyTheme = .clearGlass
        model.draft = D.settingGlassTint(model.draft, to: "#FF8FC7")
        checkEqual(model.palette, SettingsPalette.make(body: .clearGlass, focusHex: model.draft.overlay.focusHex, style: model.draft.overlay.focusStyle, glassTint: "#FF8FC7"), "model.palette 는 draft 의 틴트를 따른다")
        let skyPalette = SettingsPalette.make(body: .clearGlass, focusHex: model.draft.overlay.focusHex, style: model.draft.overlay.focusStyle)
        check(model.palette != skyPalette, "틴트가 바뀌면 창 색이 바뀐다")
    }
}

private func clearGlassWindowContrast() {
    section("Settings: 클리어 글라스 설정 창 대비")
    var tints = GlassTints.presets.map(\.hex)
    tints += ["#000000", "#FFFFFF", "#E8EEF5", "#B8F26B", "#FFFF00", "#00FF00", "#0000FF", "#000080", "#101040", "#808080", "#FF0000"]
    for r in stride(from: 0, through: 255, by: 51) {
        for g in stride(from: 0, through: 255, by: 51) {
            for b in stride(from: 0, through: 255, by: 51) { tints.append(String(format: "#%02X%02X%02X", r, g, b)) }
        }
    }
    var focusSamples = FocusColors.presets.map(\.hex)
    focusSamples += ["#000000", "#FFFFFF", "#101040", "#808080", "#767676"]
    var worst = 100.0
    var samples = 0
    for style in FocusStyle.allCases {
        for tint in tints {
            for focus in focusSamples {
                let pal = SettingsPalette.make(body: .clearGlass, focusHex: focus, style: style, glassTint: tint)
                let p = pal.swatches
                guard let accent = SettingsRGB(hex: focus) else { check(false, "hex 해석: \(focus)"); continue }
                var pairs: [(String, Double)] = []
                for (faceName, face) in [("배경", p.background), ("사이드바", p.sidebar), ("카드", p.card), ("입력칸", p.field)] {
                    pairs.append(("글자/\(faceName)", ContrastMath.ratio(p.text, face)))
                    pairs.append(("보조/\(faceName)", ContrastMath.ratio(p.muted, face)))
                    pairs.append(("강조글자/\(faceName)", ContrastMath.ratio(p.accentText, face)))
                }
                pairs.append(("글자/사이드바 선택", ContrastMath.ratio(p.selectionText, p.selection)))
                pairs.append(("강조면 위 글자", ContrastMath.ratio(p.onAccent, p.accent)))
                pairs.append(("주 버튼 호버 면 위 글자", ContrastMath.ratio(p.onAccent, ContrastMath.hoverFace(p.accent))))
                pairs.append(("경고/카드", ContrastMath.ratio(SettingsRGB(1.0, 0.706, 0.329), p.card)))
                pairs.append(("오류/카드", ContrastMath.ratio(SettingsRGB(1.0, 0.42, 0.42), p.card)))
                pairs.append(("오류/사이드바", ContrastMath.ratio(SettingsRGB(1.0, 0.42, 0.42), p.sidebar)))
                if style == .neon {
                    for face in [p.neonFace, ContrastMath.neonFace(accent, over: p.card), ContrastMath.neonFace(accent, over: p.sidebar), ContrastMath.neonFace(accent, over: p.background)] {
                        pairs.append(("네온 면 위 글자", ContrastMath.ratio(p.neonText, face)))
                    }
                }
                samples += 1
                for (name, ratio) in pairs {
                    worst = min(worst, ratio)
                    if ratio < ContrastMath.minimumText { check(false, "\(style) 틴트 \(tint) 포커스 \(focus): \(name) 대비 \(ratio) < 4.5") }
                }
            }
        }
    }
    check(worst >= ContrastMath.minimumText, "클리어 글라스 창 대비 최저 \(String(format: "%.2f", worst)) ≥ 4.5 (\(samples)조합: 스타일 2 × 틴트 \(tints.count) × 포커스 \(focusSamples.count))")

    // 면은 항상 어둡고 배경 < 사이드바 < 카드 순(틴트가 밝아도 눌리고, 어두워도 단차가 생긴다)
    for tint in tints {
        let p = SettingsPalette.make(body: .clearGlass, focusHex: FocusColors.defaultHex, style: .flat, glassTint: tint).swatches
        let l = [p.background, p.sidebar, p.card].map(ContrastMath.luminance)
        if !(l[0] < l[1] && l[1] < l[2] && l[2] <= 0.04) { check(false, "틴트 \(tint): 면 휘도 순서/상한 \(l)") }
    }
    // 틴트가 창 색에 실제로 반영된다(같은 틴트 계열 색상, 다른 틴트는 다른 면)
    let sky = SettingsPalette.make(body: .clearGlass, focusHex: FocusColors.defaultHex, style: .flat, glassTint: "#6FB1FF").swatches
    let pinkP = SettingsPalette.make(body: .clearGlass, focusHex: FocusColors.defaultHex, style: .flat, glassTint: "#FF8FC7").swatches
    check(sky.card != pinkP.card && sky.card.b > sky.card.r, "하늘 틴트 면은 푸른 기운")
    check(pinkP.card.r > pinkP.card.g, "분홍 틴트 면은 붉은 기운")
    // 해석 불가 틴트는 기본 틴트와 같다
    checkEqual(SettingsPalette.make(body: .clearGlass, focusHex: FocusColors.defaultHex, style: .flat, glassTint: "nope"),
               SettingsPalette.make(body: .clearGlass, focusHex: FocusColors.defaultHex, style: .flat), "잘못된 틴트는 기본 틴트로")
    // 다른 본체는 틴트를 쓰지 않는다
    checkEqual(SettingsPalette.make(body: .darkGlass, focusHex: FocusColors.defaultHex, style: .flat, glassTint: "#FF8FC7"),
               SettingsPalette.make(body: .darkGlass, focusHex: FocusColors.defaultHex, style: .flat), "다크 글라스 창 색은 틴트와 무관")
}

private func nameAndNumberOptions() {
    section("Settings: 앱 이름 위치·숫자·타일 라벨")
    var a = Settings.defaults
    a.overlay.namePlacement = .top // 기본은 가운데 원이므로 다른 위치로 바꿔야 달라진다
    check(D.isDirty(baseline: .defaults, draft: a), "이름 위치 변경은 dirty")
    var b = Settings.defaults
    b.overlay.showNumbers = false
    check(D.isDirty(baseline: .defaults, draft: b), "숫자 표시 변경은 dirty")
    var labels = Settings.defaults
    labels.overlay.showTileLabels = false
    check(D.isDirty(baseline: .defaults, draft: labels), "타일 라벨 변경은 dirty")
    var solid = Settings.defaults
    solid.overlay.solidBacking = false
    check(D.isDirty(baseline: .defaults, draft: solid), "불투명 바닥 변경은 dirty")
    checkEqual(Settings.defaults.overlay.solidBacking, true, "기본값은 불투명 바닥")
    var solidAll = labels
    solidAll.overlay.solidBacking = false
    check(solidAll.overlay.showTileLabels == false && solidAll.overlay.alpha == Settings.defaults.overlay.alpha, "불투명 바닥은 라벨·투명도와 독립")
    var alphaOnly = solid
    alphaOnly.overlay.alpha = 0.5
    checkEqual(alphaOnly.overlay.solidBacking, false, "투명도 변경은 불투명 바닥에 영향 없음")
    check(!D.isDirty(baseline: a, draft: a), "같은 값은 깨끗")

    // 서로·다른 설정과 독립
    var all = Settings.defaults
    all.overlay.namePlacement = .hidden
    all.overlay.showNumbers = false
    all.overlay.showTileLabels = false
    all.overlay.theme = .orbit
    checkEqual(all.overlay.namePlacement, .hidden, "테마 전환은 이름 위치 유지")
    checkEqual(all.overlay.showNumbers, false, "테마 전환은 숫자 표시 유지")
    checkEqual(all.overlay.showTileLabels, false, "테마 전환은 타일 라벨 유지")
    var c = all
    c.overlay.namePlacement = .top
    checkEqual([c.overlay.showNumbers, c.overlay.showTileLabels], [false, false], "이름 위치 변경은 나머지에 영향 없음")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft.overlay.namePlacement = .top
        model.draft.overlay.showNumbers = false
        model.draft.overlay.showTileLabels = false
        model.revert()
        checkEqual(model.draft.overlay.namePlacement, .center, "되돌리기 → center(기본)")
        checkEqual(model.draft.overlay.showNumbers, true, "되돌리기 → true")
        checkEqual(model.draft.overlay.showTileLabels, true, "되돌리기 → 타일 라벨 true")
        model.draft.overlay.namePlacement = .hidden
        model.draft.overlay.showNumbers = false
        model.draft.overlay.showTileLabels = false
        model.resetToDefaults()
        checkEqual(model.draft.overlay.namePlacement, .center, "초기화 → center(기본)")
        checkEqual(model.draft.overlay.showNumbers, true, "초기화 → true")
        checkEqual(model.draft.overlay.showTileLabels, true, "초기화 → 타일 라벨 true")
        model.draft.overlay.solidBacking = false
        model.revert()
        checkEqual(model.draft.overlay.solidBacking, true, "되돌리기 → 불투명 바닥 true")
        model.draft.overlay.solidBacking = false
        model.resetToDefaults()
        checkEqual(model.draft.overlay.solidBacking, true, "초기화 → 불투명 바닥 true")
    }
}

private func centerNameOptions() {
    section("Settings: 중앙 원 글자 굵기·크기")
    let range = Limits.centerNameSizeRange
    // 기본: 자동(0) + 보통
    checkEqual(Settings.defaults.overlay.centerNameSize, 0, "기본 글자 크기는 자동(0)")
    checkEqual(Settings.defaults.overlay.centerNameWeight, .regular, "기본 굵기는 보통")

    // 범위 보정
    checkEqual(D.settingCenterNameSize(.defaults, to: 18).overlay.centerNameSize, 18, "범위 안 값은 그대로")
    checkEqual(D.settingCenterNameSize(.defaults, to: 3).overlay.centerNameSize, range.lowerBound, "하한 미만은 10")
    checkEqual(D.settingCenterNameSize(.defaults, to: 99).overlay.centerNameSize, range.upperBound, "상한 초과는 32")
    checkEqual(D.settingCenterNameSize(.defaults, to: 0).overlay.centerNameSize, 0, "0 은 자동")
    checkEqual(D.settingCenterNameSize(.defaults, to: -5).overlay.centerNameSize, 0, "음수도 자동")

    // 자동 토글 왕복: 끄면 지금 자동 크기(렌더 쪽 순수 함수)에서 시작, 다시 켜면 0
    let base = Settings.defaults
    let off = D.settingCenterNameAuto(base, auto: false)
    checkEqual(off.overlay.centerNameSize, D.autoCenterNameSize(base), "자동 해제 → 현재 자동 크기에서 시작")
    check(range.contains(off.overlay.centerNameSize), "시작값은 범위 안")
    checkEqual(D.autoCenterNameSize(base), Int(OverlayMetrics.centerNameSize(hub: CGFloat(base.overlay.centerSize)).rounded()), "시작값 = OverlayMetrics.centerNameSize")
    checkEqual(D.settingCenterNameAuto(off, auto: true).overlay.centerNameSize, 0, "자동 재설정 → 0")
    var custom = base
    custom.overlay.centerNameSize = 22
    checkEqual(D.settingCenterNameAuto(custom, auto: false).overlay.centerNameSize, 22, "이미 직접 고른 값은 해제해도 유지")
    // 원 크기가 작으면 시작값도 작아진다(12 하한 이상, 범위 안)
    var small = base
    small.overlay.theme = .pie
    small.overlay.pieSizes = ThemeSizes(ring: 160, center: 40, border: 4)
    check(range.contains(D.autoCenterNameSize(small)), "작은 원의 시작값도 범위 안")

    // dirty·독립
    var weight = base; weight.overlay.centerNameWeight = .bold
    var size = base; size.overlay.centerNameSize = 20
    check(D.isDirty(baseline: base, draft: weight), "굵기 변경은 dirty")
    check(D.isDirty(baseline: base, draft: size), "크기 변경은 dirty")
    check(!D.isDirty(baseline: weight, draft: weight), "같은 값은 깨끗")
    var both = weight; both.overlay.centerNameSize = 20
    checkEqual([both.overlay.centerNameWeight == .bold, both.overlay.centerNameSize == 20], [true, true], "굵기·크기는 서로 독립")
    var themed = both; themed.overlay.theme = .pie
    checkEqual([themed.overlay.centerNameWeight == .bold, themed.overlay.centerNameSize == 20], [true, true], "테마 전환은 글자 설정 유지")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        model.draft.overlay.centerNameWeight = .light
        model.draft = D.settingCenterNameSize(model.draft, to: 28)
        model.revert()
        checkEqual([model.draft.overlay.centerNameWeight == .regular, model.draft.overlay.centerNameSize == 0], [true, true], "되돌리기 → regular / 자동")
        model.draft.overlay.centerNameWeight = .bold
        model.draft = D.settingCenterNameSize(model.draft, to: 28)
        model.resetToDefaults()
        checkEqual([model.draft.overlay.centerNameWeight == .regular, model.draft.overlay.centerNameSize == 0], [true, true], "초기화 → regular / 자동")
    }
}

private func focusGlowToggle() {
    section("Settings: 포커스 불빛 토글")
    let base = Settings.defaults
    check(base.overlay.focusGlow, "기본은 켬")
    var off = base
    off.overlay.focusGlow = false
    check(D.isDirty(baseline: base, draft: off), "불빛 끔은 dirty")
    check(!D.isDirty(baseline: off, draft: off), "같은 값은 깨끗")

    // 대비는 불빛 토글에 흔들리지 않는다: 번짐만 게이트하고 면·글자 색은 같아야 한다
    let hexes = [FocusColors.defaultHex, "#FFD60A", "#000080", "#FFFFFF", "#32D6FF"]
    for body in OverlayBody.allCases {
        for style in FocusStyle.allCases {
            for hex in hexes {
                let lit = SettingsPalette.make(body: body, focusHex: hex, style: style, glow: true)
                let dark = SettingsPalette.make(body: body, focusHex: hex, style: style, glow: false)
                check(lit.swatches == dark.swatches, "불빛 끔에도 색 필드가 같다(\(body.rawValue)/\(style.rawValue)/\(hex))")
                check(lit.isNeon == dark.isNeon && lit.isNeon == (style == .neon), "불빛 끔에도 스타일 판별이 유지된다(\(body.rawValue)/\(style.rawValue))")
                check(lit.glow && !dark.glow, "palette.glow 가 인자를 따른다")
            }
        }
    }
    check(SettingsPalette.make(body: .darkGray, focusHex: FocusColors.defaultHex, style: .neon).glow, "make 기본은 불빛 켬")
    let neonLit = SettingsPalette.make(body: .darkGray, focusHex: "#FFD60A", style: .neon, glow: true)
    let neonDark = SettingsPalette.make(body: .darkGray, focusHex: "#FFD60A", style: .neon, glow: false)
    let flatLit = SettingsPalette.make(body: .darkGray, focusHex: "#FFD60A", style: .flat, glow: true)
    check(neonLit.halo(0.5) != .clear, "네온+불빛 켬은 번짐 색이 있다")
    check(neonDark.halo(0.5) == .clear, "네온+불빛 끔은 번짐이 투명")
    check(flatLit.halo(0.5) == .clear, "플랫은 설정 창 번짐이 없다")

    MainActor.assumeIsolated {
        let model = SettingsModel(store: FeedbackStore(), catalog: FeedbackCatalog(), save: { _ in .success }, checkForUpdates: {}, versionText: { "t" })
        check(model.palette.glow, "모델 팔레트 기본 켬")
        model.draft.overlay.focusStyle = .neon
        model.draft.overlay.focusGlow = false
        check(model.isDirty, "모델: 불빛 끔은 dirty")
        check(!model.palette.glow, "모델 팔레트가 draft 끔을 따른다")
        check(model.palette.isNeon, "불빛을 꺼도 설정 창은 네온 스타일")
        model.draft.overlay.focusGlow = true
        check(model.palette.glow, "모델 팔레트가 draft 켬을 따른다")
        check(!model.isDirty, "원래 값으로 돌아오면 깨끗")
        model.draft.overlay.focusGlow = false
        model.revert()
        check(model.draft.overlay.focusGlow && model.palette.glow, "되돌리기 → 켬")
        model.draft.overlay.focusGlow = false
        model.resetToDefaults()
        check(model.draft.overlay.focusGlow && model.palette.glow, "초기화 → 기본(켬)")
    }
}
