import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: - 테스트 도구

/// 호출을 기록하는 가짜 AppCatalog
private final class FakeCatalog: AppCatalog, @unchecked Sendable {
    var running: [RunningApp] = []
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _iconRequests: [IconTarget] = []
    /// 앱별로 실패시킬 bundleId
    var failing: Set<String> = []
    /// 아이콘 요청을 막거나 돌려줄 훅. nil 이면 bundleId/경로 바이트를 돌려준다.
    var iconHook: ((IconTarget) -> Data?)?

    var calls: [String] { lock.withLock { _calls } }
    var iconRequests: [IconTarget] { lock.withLock { _iconRequests } }

    func frontmostApp() -> RunningApp? { running.first }

    func activate(bundleId: String, pid: Int32?) async -> ActionResult {
        lock.withLock { _calls.append("activate:\(bundleId):\(pid.map(String.init) ?? "-")") }
        return failing.contains(bundleId) ? .failure("실행 중이 아닙니다: \(bundleId)") : .success
    }

    func refocus(bundleId: String, pid: Int32?) -> Bool {
        lock.withLock { _calls.append("refocus:\(bundleId):\(pid.map(String.init) ?? "-")") }
        return !failing.contains(bundleId)
    }

    func open(bundleId: String?, appPath: String?) async -> ActionResult {
        let key = bundleId ?? appPath ?? ""
        lock.withLock { _calls.append("open:\(key)") }
        return failing.contains(key) ? .failure("설치된 앱을 찾을 수 없습니다: \(key)") : .success
    }

    func installedApps() async -> [InstalledApp] { [] }

    func iconPNG(for target: IconTarget, pixels: Int) -> Data? {
        lock.withLock { _iconRequests.append(target) }
        if let iconHook { return iconHook(target) }
        switch target {
        case let .bundleId(id): return Data("png:\(id)".utf8)
        case let .appPath(path): return Data("png:\(path)".utf8)
        }
    }
}

/// 등록 성공/실패를 정할 수 있는 가짜 단축키 레지스트리
private final class FakeShortcuts: ShortcutRegistering {
    var registered: String?
    var rejects: Set<String> = []
    var log: [String] = []

    func register(_ accelerator: String, handler: @escaping () -> Void) -> ActionResult {
        log.append("register:\(accelerator)")
        registered = nil
        if rejects.contains(accelerator) { return .failure("거부: \(accelerator)") }
        registered = accelerator
        return .success
    }

    func unregister() {
        log.append("unregister")
        registered = nil
    }
}

private final class FakeLoginItem: LoginItemControlling {
    var enabled: Bool
    /// true 면 set 이 throw 하지 않고 조용히 무시한다(macOS 가 거부하는 경우)
    var ignoresChanges = false
    var throwsOnSet = false
    struct Boom: LocalizedError { var errorDescription: String? { "boom" } }

    init(enabled: Bool) { self.enabled = enabled }
    var isEnabled: Bool { enabled }

    func setEnabled(_ value: Bool) throws {
        if throwsOnSet { throw Boom() }
        if !ignoresChanges { enabled = value }
    }
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qs-core-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func slot(_ id: String, _ action: Action = .openURL("https://example.com"), name: String = "슬롯", label: String? = nil) -> Slot {
    Slot(id: id, name: name, label: label, action: action)
}

/// 고정 앱 탭 하나를 가진 설정
private func settings(slots: [Slot?]) -> Settings {
    var s = Settings.defaults
    s.tabs[0].slots = slots
    return s
}

private func issues(_ s: Settings) -> [String] { SettingsValidator.validate(s).map(\.text) }

private func hasIssue(_ s: Settings, containing text: String) -> Bool { issues(s).contains { $0.contains(text) } }

private func running(_ id: String, name: String, pid: Int32) -> RunningApp {
    RunningApp(bundleId: id, pid: pid, name: name)
}

/// Electron 판이 실제로 쓰던 형태(알 수 없는 matchApps 키 포함)
private let legacyJSON = """
{
  "schemaVersion": 4, "platform": "darwin", "shortcut": "Alt+Q", "launchAtLogin": false,
  "overlay": { "alpha": 0.77, "radius": 28, "slotCount": 8, "showIcons": true },
  "tabs": [
    { "id": "pinned", "name": "고정 앱", "type": "pinned-apps", "slots": [
      { "id": "memo", "name": "memo", "label": "mem", "action": { "type": "launch_app", "bundleId": "com.apple.Notes" } },
      { "id": "site", "name": "사이트", "action": { "type": "open_url", "url": "https://example.com" } },
      { "id": "macro", "name": "매크로", "action": { "type": "macro_sequence", "steps": [
          { "type": "launch_app", "appPath": "/Applications/Safari.app" }, { "type": "clipboard_text", "text": "hi" } ] } }
    ], "matchApps": ["com.apple.Notes"] },
    { "id": "recent", "name": "최근 앱", "type": "recent-apps" }
  ]
}
"""

// MARK: - 진입점

func runCoreTests() {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    testValidator()
    testActionJSON(root)
    testStore(root)
    testMigration(root)

    runAsync {
        await testActionExecutor()
        await testDeck(root)
    }
    testShortcutSwap()
    testLoginItem()
    testAccelerator()
    testOverlaySizes()
    testThemeSizesAndBodyDecode()
    testCenterNameDecode()
    testFocusRestore()
}

// MARK: - 검증

private func testValidator() {
    section("Core/Validator")
    checkEqual(issues(.defaults), [], "기본 설정은 유효")

    // 탭
    var s = Settings.defaults
    s.tabs = []
    check(hasIssue(s, containing: "탭: 항목이 부족합니다"), "탭 0개")
    s = .defaults
    s.tabs = (0..<9).map { Tab(id: "t\($0)", name: "탭", type: .custom) }
    check(hasIssue(s, containing: "탭: 항목이 너무 많습니다"), "탭 9개")
    s.tabs.removeLast()
    checkEqual(issues(s), [], "탭 8개는 허용")

    s = .defaults
    s.tabs[0].id = "BAD ID"
    check(hasIssue(s, containing: "식별자: 탭 id 는 영문/숫자/-/_ 1~32자"), "탭 id 공백 불가")
    s.tabs[0].id = String(repeating: "a", count: 33)
    check(!issues(s).isEmpty, "탭 id 33자 불가")
    s.tabs[0].id = String(repeating: "A", count: 32)
    checkEqual(issues(s), [], "탭 id 32자·대문자 허용")
    s.tabs[0].id = "한글"
    check(!issues(s).isEmpty, "탭 id 한글 불가")

    s = .defaults
    s.tabs.append(Tab(id: "pinned", name: "둘째", type: .custom))
    check(hasIssue(s, containing: "탭 id 중복: pinned"), "탭 id 중복")
    s = .defaults
    s.tabs = []
    check(!issues(s).isEmpty, "탭이 하나도 없으면 불가")
    s = .defaults
    s.tabs[0].name = String(repeating: "가", count: 21)
    check(hasIssue(s, containing: "이름: 너무 깁니다"), "탭 이름 21자")
    s.tabs[0].name = ""
    check(hasIssue(s, containing: "이름: 비워 둘 수 없습니다"), "탭 이름 빈 값")

    // 슬롯
    s = settings(slots: (0..<8).map { slot("s\($0)") })
    checkEqual(issues(s), [], "슬롯 8개 허용")
    s = settings(slots: (0..<9).map { slot("s\($0)") })
    let tooMany = SettingsValidator.validate(s).first { $0.text.contains("슬롯: 항목이 너무 많습니다") }
    checkEqual(tooMany?.tabIndex, 0, "슬롯 9개 → 탭 위치")
    checkEqual(tooMany?.slotIndex, nil, "슬롯 9개 → 슬롯 위치 없음")
    // 끝의 빈 칸(null)은 저장 때 떨어지므로 슬롯 수로 세지 않는다. 8번째 이후에 슬롯이 있을 때만 거부한다.
    s = settings(slots: (0..<8).map { slot("s\($0)") } + [nil, nil])
    checkEqual(issues(s), [], "끝의 빈 칸 null 은 슬롯 수에 넣지 않는다")
    s = settings(slots: [slot("a")] + [Slot?](repeating: nil, count: 8) + [slot("b")])
    check(hasIssue(s, containing: "슬롯: 항목이 너무 많습니다"), "9번째 칸 이후의 슬롯은 거부")

    s = settings(slots: [slot("a"), slot("a")])
    let dup = SettingsValidator.validate(s).first
    checkEqual(dup?.text, "탭 \"고정 앱\" > 슬롯 2 > 식별자: 슬롯 id 중복: a", "슬롯 id 중복 문구")
    checkEqual(dup?.slotIndex, 1, "슬롯 id 중복 위치")
    // 빈 칸이 있어도 이슈의 슬롯 위치는 링 위치(0부터)다: 12시, 비어 있음 ×2, 슬롯 4번 칸의 id 중복
    s = settings(slots: [slot("a"), nil, nil, slot("a")])
    let gapDup = SettingsValidator.validate(s).first
    checkEqual(gapDup?.text, "탭 \"고정 앱\" > 슬롯 4 > 식별자: 슬롯 id 중복: a", "빈 칸 뒤 슬롯의 번호는 링 위치")
    checkEqual(gapDup?.slotIndex, 3, "빈 칸 뒤 슬롯의 이슈 위치")
    // 다른 탭이면 같은 슬롯 id 허용
    s = .defaults
    s.tabs[0].slots = [slot("a")]
    s.tabs.append(Tab(id: "c", name: "커스텀", type: .custom, slots: [slot("a")]))
    checkEqual(issues(s), [], "슬롯 id 는 탭 안에서만 유일")

    s = settings(slots: [slot("a", name: "")])
    check(hasIssue(s, containing: "슬롯 1 > 이름: 비워 둘 수 없습니다"), "슬롯 이름 빈 값")
    s = settings(slots: [slot("a", name: String(repeating: "x", count: 41))])
    check(hasIssue(s, containing: "슬롯 1 > 이름: 너무 깁니다"), "슬롯 이름 41자")
    s = settings(slots: [slot("a", name: String(repeating: "x", count: 40), label: "abc")])
    checkEqual(issues(s), [], "이름 40자·라벨 3자 허용")
    s = settings(slots: [slot("a", label: "abcd")])
    check(hasIssue(s, containing: "라벨: 너무 깁니다"), "라벨 4자")
    s = settings(slots: [slot("a", label: "")])
    check(hasIssue(s, containing: "라벨: 비워 둘 수 없습니다"), "라벨 빈 값")
    s = settings(slots: [slot("")])
    check(hasIssue(s, containing: "식별자: 비워 둘 수 없습니다"), "슬롯 id 빈 값")

    // 액션
    s = settings(slots: [slot("a"), slot("b"), slot("c", .openURL("ftp://example.com"), name: "x")])
    let urlIssue = SettingsValidator.validate(s).first
    checkEqual(urlIssue?.text, "탭 \"고정 앱\" > 슬롯 3 > URL: http/https URL 만 허용됩니다", "잘못된 URL 문구")
    checkEqual(urlIssue?.slotIndex, 2, "잘못된 URL 슬롯 위치")
    for bad in ["javascript:alert(1)", "not a url", "", "https://", "file:///etc/passwd"] {
        check(hasIssue(settings(slots: [slot("a", .openURL(bad))]), containing: "URL"), "URL 거부: \(bad)")
    }
    for good in ["http://a.com", "https://a.com/path?q=1#x", "HTTPS://A.COM"] {
        checkEqual(issues(settings(slots: [slot("a", .openURL(good))])), [], "URL 허용: \(good)")
    }

    s = settings(slots: [slot("a", .launchApp(bundleId: nil, appPath: nil))])
    check(hasIssue(s, containing: "정확히 하나"), "launch_app 대상 없음")
    s = settings(slots: [slot("a", .launchApp(bundleId: "a.b", appPath: "/A.app"))])
    check(hasIssue(s, containing: "정확히 하나"), "launch_app 대상 둘")
    s = settings(slots: [slot("a", .launchApp(bundleId: nil, appPath: "/Applications/Foo"))])
    check(hasIssue(s, containing: "앱 경로"), "appPath 는 .app 으로 끝나야 함")
    s = settings(slots: [slot("a", .launchApp(bundleId: nil, appPath: "/Applications/Foo.app"))])
    checkEqual(issues(s), [], "appPath 허용")
    s = settings(slots: [slot("a", .launchApp(bundleId: String(repeating: "a", count: 256), appPath: nil))])
    check(hasIssue(s, containing: "번들 ID: 너무 깁니다"), "bundleId 256자")
    s = settings(slots: [slot("a", .launchApp(bundleId: String(repeating: "a", count: 255), appPath: nil))])
    checkEqual(issues(s), [], "bundleId 255자 허용")
    s = settings(slots: [slot("a", .activateApp(bundleId: "", pid: nil))])
    check(hasIssue(s, containing: "번들 ID: 비워 둘 수 없습니다"), "activate bundleId 빈 값")

    s = settings(slots: [slot("a", .clipboardText(String(repeating: "가", count: 10_000)))])
    checkEqual(issues(s), [], "클립보드 10000자 허용")
    s = settings(slots: [slot("a", .clipboardText(String(repeating: "가", count: 10_001)))])
    check(hasIssue(s, containing: "텍스트: 너무 깁니다"), "클립보드 10001자")

    // 매크로
    let step = Action.clipboardText("x")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: true, steps: []))])
    check(hasIssue(s, containing: "단계: 항목이 부족합니다"), "매크로 단계 0개")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: true, steps: Array(repeating: step, count: 17)))])
    check(hasIssue(s, containing: "단계: 항목이 너무 많습니다"), "매크로 단계 17개")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: true, steps: Array(repeating: step, count: 16)))])
    checkEqual(issues(s), [], "매크로 단계 16개 허용")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: true, steps: [step, .macroSequence(stopOnError: true, steps: [step])]))])
    let nested = SettingsValidator.validate(s).first
    checkEqual(nested?.text, "탭 \"고정 앱\" > 슬롯 1 > 매크로 단계 2 > 종류: 매크로 안에 매크로를 넣을 수 없습니다", "중첩 매크로 금지")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: false, steps: [step, .openURL("ftp://x")]))])
    checkEqual(SettingsValidator.validate(s).first?.text, "탭 \"고정 앱\" > 슬롯 1 > 매크로 단계 2 > URL: http/https URL 만 허용됩니다", "매크로 단계 안의 URL 검증")
    s = settings(slots: [slot("a", .macroSequence(stopOnError: true, steps: [.activateApp(bundleId: "a.b", pid: nil)]))])
    check(hasIssue(s, containing: "매크로 단계 1 > 종류: 매크로 단계에는 앱 전환"), "매크로 단계에 activate_app 금지")

    // 모양/단축키/버전
    func overlay(_ edit: (inout OverlaySettings) -> Void) -> Settings {
        var s = Settings.defaults
        edit(&s.overlay)
        return s
    }
    checkEqual(issues(overlay { $0.alpha = 0.4 }), [], "alpha 하한")
    checkEqual(issues(overlay { $0.alpha = 0.95 }), [], "alpha 상한")
    check(hasIssue(overlay { $0.alpha = 0.39 }, containing: "패널 투명도"), "alpha 미만")
    check(hasIssue(overlay { $0.alpha = 0.96 }, containing: "패널 투명도"), "alpha 초과")
    checkEqual(issues(overlay { $0.radius = 24 }), [], "radius 하한")
    checkEqual(issues(overlay { $0.radius = 56 }), [], "radius 상한")
    check(hasIssue(overlay { $0.radius = 23 }, containing: "모서리"), "radius 미만")
    check(hasIssue(overlay { $0.radius = 57 }, containing: "모서리"), "radius 초과")
    check(!issues(overlay { $0.slotCount = 7 }).isEmpty, "slotCount 는 8 만")

    s = .defaults
    s.shortcut = ""
    check(hasIssue(s, containing: "단축키: 비워 둘 수 없습니다"), "단축키 빈 값")
    s.shortcut = "Q"
    check(hasIssue(s, containing: "단축키"), "수정키 없는 단축키")
    s.shortcut = "Alt+Bogus"
    check(hasIssue(s, containing: "단축키"), "알 수 없는 키")
    s.shortcut = "Command+Shift+Space"
    checkEqual(issues(s), [], "정상 단축키")
    s = .defaults
    s.schemaVersion = 3
    check(!issues(s).isEmpty, "schemaVersion 3 불가")
    let general = SettingsValidator.validate(s).first
    check(general?.tabIndex == nil && general?.slotIndex == nil, "일반 항목은 위치 없음")
}

// MARK: - Action JSON 호환

private func testActionJSON(_ root: URL) {
    section("Core/ActionJSON")
    let decoder = JSONDecoder()
    func decode(_ json: String) -> Action? { try? decoder.decode(Action.self, from: Data(json.utf8)) }
    checkEqual(decode(#"{"type":"launch_app","bundleId":"com.apple.Notes"}"#), .launchApp(bundleId: "com.apple.Notes", appPath: nil), "launch_app bundleId")
    checkEqual(decode(#"{"type":"macro_sequence","steps":[{"type":"clipboard_text","text":"a"}]}"#), .macroSequence(stopOnError: true, steps: [.clipboardText("a")]), "stopOnError 기본 true")
    checkEqual(decode(#"{"type":"activate_app","bundleId":"a.b","pid":42}"#), .activateApp(bundleId: "a.b", pid: 42), "activate_app pid")
    check(decode(#"{"type":"nope"}"#) == nil, "알 수 없는 종류는 디코드 실패")

    let action = Action.macroSequence(stopOnError: false, steps: [.openURL("https://a.com"), .launchApp(bundleId: nil, appPath: "/A.app")])
    let roundTrip = try? decoder.decode(Action.self, from: JSONEncoder().encode(action))
    checkEqual(roundTrip, action, "Action 인코딩 왕복")

    // 실제 사용자 파일 형태
    let samplePath = electronSettingsFixturePath
    let sampleData = FileManager.default.contents(atPath: samplePath)
    check(sampleData != nil, "Electron 샘플 파일이 있어야 한다: \(samplePath)")
    if let data = sampleData {
        let parsed = try? decoder.decode(Settings.self, from: data)
        check(parsed != nil, "Electron 샘플 디코드")
        if let parsed {
            checkEqual(SettingsValidator.validate(parsed).map(\.text), [], "Electron 샘플은 유효")
            check(parsed.tabs.contains { !$0.slots.isEmpty }, "Electron 샘플 슬롯을 읽음")
        }
    }
    if let parsed = try? decoder.decode(Settings.self, from: Data(legacyJSON.utf8)) {
        checkEqual(parsed.tabs.map(\.id), ["pinned"], "옛 recent-apps 탭은 읽을 때 버림")
        checkEqual(parsed.tabs[0].slots.count, 3, "옛 형식 슬롯 수")
        checkEqual(parsed.tabs[0].slots[2]?.action, .macroSequence(stopOnError: true, steps: [.launchApp(bundleId: nil, appPath: "/Applications/Safari.app"), .clipboardText("hi")]), "옛 형식 매크로")
    } else {
        check(false, "옛 형식 JSON 디코드")
    }
    // 옛 최근 앱 탭만 있던 파일은 기본 탭으로 되돌려 탭이 항상 하나 이상 있다. 탭이 원래 비어 있던 파일은 그대로(검증이 거부한다).
    func decodeTabs(_ tabsJSON: String) -> [Tab]? {
        try? decoder.decode(Settings.self, from: Data(#"{"schemaVersion":4,"platform":"darwin","shortcut":"Alt+Q","overlay":{},"tabs":\#(tabsJSON)}"#.utf8)).tabs
    }
    checkEqual(decodeTabs(#"[{"id":"recent","name":"최근 앱","type":"recent-apps"}]"#), Settings.defaults.tabs, "최근 앱 탭만 있던 파일은 기본 탭으로")
    checkEqual(decodeTabs("[]"), [], "원래 빈 탭 목록은 그대로")
    check(decodeTabs(#"[{"id":"x","name":"x","type":"nope"}]"#) == nil, "알 수 없는 탭 종류는 여전히 디코드 실패")
}

// MARK: - SettingsStore

private func testStore(_ root: URL) {
    section("Core/SettingsStore")
    let fm = FileManager.default
    func fresh() -> URL { root.appendingPathComponent(UUID().uuidString, isDirectory: true) }

    // 첫 실행: 기본값 파일 생성
    var dir = fresh()
    var store = SettingsStore(directory: dir, legacyAppSupport: nil)
    checkEqual(store.current, .defaults, "첫 실행은 기본값")
    checkEqual(store.warning, nil, "첫 실행은 경고 없음")
    let text = (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? ""
    check(text.hasSuffix("}\n"), "끝 개행")
    check(text.hasPrefix("{\n  \"launchAtLogin\""), "prettyPrinted + sortedKeys")
    check(!text.contains("\\/"), "슬래시를 이스케이프하지 않음")

    // 저장 왕복 + 백업
    var edited = Settings.defaults
    edited.shortcut = "Command+Shift+Space"
    edited.tabs[0].slots = [slot("a", name: "사이트 A", label: "SA")]
    let before = try? Data(contentsOf: store.fileURL)
    checkEqual(store.save(edited), .success, "저장 성공")
    checkEqual(store.current, edited, "저장하면 current 갱신")
    checkEqual(SettingsStore(directory: dir, legacyAppSupport: nil).current, edited, "저장→재로드 왕복")
    checkEqual(try? Data(contentsOf: URL(fileURLWithPath: store.fileURL.path + ".bak")), before, "이전 파일이 .bak 으로 보존")
    let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    checkEqual(names, ["settings.json", "settings.json.bak"], "임시파일이 남지 않음")

    // .bak 은 저장할 때마다 최신 이전본으로 덮어쓴다
    let beforeSecond = try? Data(contentsOf: store.fileURL)
    var second = edited
    second.overlay.alpha = 0.5
    _ = store.save(second)
    checkEqual(try? Data(contentsOf: URL(fileURLWithPath: store.fileURL.path + ".bak")), beforeSecond, "기존 .bak 덮어쓰기")

    // 검증 실패: 파일·current 불변
    let onDisk = try? Data(contentsOf: store.fileURL)
    let backupBefore = try? Data(contentsOf: URL(fileURLWithPath: store.fileURL.path + ".bak"))
    var invalid = second
    invalid.tabs[0].slots = [slot("a", .openURL("ftp://x"))]
    let failed = store.save(invalid)
    check(!failed.ok, "검증 실패는 저장 실패")
    check(failed.error?.contains("URL: http/https URL 만 허용됩니다") == true, "실패 사유는 첫 문제 텍스트")
    checkEqual(try? Data(contentsOf: store.fileURL), onDisk, "검증 실패 시 파일 불변")
    checkEqual(try? Data(contentsOf: URL(fileURLWithPath: store.fileURL.path + ".bak")), backupBefore, "검증 실패 시 .bak 불변")
    checkEqual(store.current, second, "검증 실패 시 current 불변")

    // 깨진 JSON: 덮어쓰지 않고 기본값 + warning, 저장하면 .bak 으로 보존
    dir = fresh()
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let broken = Data("{ not json".utf8)
    try? broken.write(to: dir.appendingPathComponent("settings.json"))
    store = SettingsStore(directory: dir, legacyAppSupport: nil)
    checkEqual(store.current, .defaults, "깨진 파일은 기본값으로 동작")
    check(store.warning?.isEmpty == false, "깨진 파일은 warning")
    checkEqual(try? Data(contentsOf: store.fileURL), broken, "깨진 파일을 덮어쓰지 않음")
    checkEqual(store.save(edited), .success, "깨진 상태에서도 저장 가능")
    checkEqual(try? Data(contentsOf: URL(fileURLWithPath: store.fileURL.path + ".bak")), broken, "깨진 파일이 .bak 으로 보존")
    checkEqual(store.warning, nil, "저장 성공 시 warning 해제")

    // 검증 실패 파일(schemaVersion 3): 사유가 warning 에 들어간다
    dir = fresh()
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let oldVersion = Data(legacyJSON.replacingOccurrences(of: "\"schemaVersion\": 4", with: "\"schemaVersion\": 3").utf8)
    try? oldVersion.write(to: dir.appendingPathComponent("settings.json"))
    store = SettingsStore(directory: dir, legacyAppSupport: nil)
    checkEqual(store.current, .defaults, "검증 실패 파일은 기본값으로 동작")
    check(store.warning?.contains("스키마 버전") == true, "warning 에 사유 포함")
    checkEqual(try? Data(contentsOf: store.fileURL), oldVersion, "검증 실패 파일 보존")

    // matchApps 가 든 옛 파일은 유효, 다음 저장에서 사라진다
    dir = fresh()
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try? Data(legacyJSON.utf8).write(to: dir.appendingPathComponent("settings.json"))
    store = SettingsStore(directory: dir, legacyAppSupport: nil)
    checkEqual(store.warning, nil, "matchApps 가 있어도 유효")
    checkEqual(store.current.tabs[0].slots.count, 3, "옛 파일 내용을 그대로 사용")
    _ = store.save(store.current)
    check(!((try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "").contains("matchApps"), "다음 저장에서 matchApps 제거")

    // 만들 수 없는 위치: 크래시 없이 기본값 + warning
    let blocker = root.appendingPathComponent("blocker-\(UUID().uuidString)")
    try? Data().write(to: blocker)
    store = SettingsStore(directory: blocker, legacyAppSupport: nil)
    checkEqual(store.current, .defaults, "쓸 수 없는 위치도 기본값")
    check(store.warning != nil, "쓰기 실패는 warning")
    check(!store.save(.defaults).ok, "쓸 수 없으면 저장 실패")
}

// MARK: - 마이그레이션

private func testMigration(_ root: URL) {
    section("Core/Migration")
    let fm = FileManager.default

    func makeLegacy(folder: String, json: String) -> URL {
        let appSupport = root.appendingPathComponent("support-\(UUID().uuidString)", isDirectory: true)
        let folderURL = appSupport.appendingPathComponent(folder, isDirectory: true)
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: folderURL.appendingPathComponent("settings.json"))
        return appSupport
    }

    // NFC/NFD 어느 쪽 폴더명이든 찾는다
    for (label, folder) in [("NFC", "퀵스트림".precomposedStringWithCanonicalMapping), ("NFD", "퀵스트림".decomposedStringWithCanonicalMapping)] {
        let appSupport = makeLegacy(folder: folder, json: legacyJSON)
        let original = try? Data(contentsOf: appSupport.appendingPathComponent(folder).appendingPathComponent("settings.json"))
        let newDir = root.appendingPathComponent("new-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsStore(directory: newDir, legacyAppSupport: appSupport)
        checkEqual(store.warning, nil, "\(label): 가져오기 경고 없음")
        checkEqual(store.current.tabs[0].slots.compactMap { $0?.id }, ["memo", "site", "macro"], "\(label): 옛 설정을 가져옴")
        checkEqual(store.current.overlay.radius, 28, "\(label): 옛 모양 값을 가져옴")
        check(fm.fileExists(atPath: store.fileURL.path), "\(label): 새 파일로 저장")
        checkEqual(SettingsStore(directory: newDir, legacyAppSupport: nil).current, store.current, "\(label): 새 파일에서 다시 읽힘")
        checkEqual(try? Data(contentsOf: appSupport.appendingPathComponent(folder).appendingPathComponent("settings.json")), original, "\(label): 원본은 수정하지 않음")
    }

    // 새 파일이 이미 있으면 옛 설정은 보지 않는다
    let appSupport = makeLegacy(folder: "퀵스트림", json: legacyJSON)
    let existing = root.appendingPathComponent("existing-\(UUID().uuidString)", isDirectory: true)
    _ = SettingsStore(directory: existing, legacyAppSupport: nil)
    checkEqual(SettingsStore(directory: existing, legacyAppSupport: appSupport).current, .defaults, "새 파일이 있으면 가져오지 않음")

    // 깨졌거나 검증 실패한 옛 파일은 무시하고 기본값
    for (label, json) in [("깨진 JSON", "{ nope"), ("검증 실패", legacyJSON.replacingOccurrences(of: "\"alpha\": 0.77", with: "\"alpha\": 5"))] {
        let bad = makeLegacy(folder: "퀵스트림", json: json)
        let store = SettingsStore(directory: root.appendingPathComponent("n-\(UUID().uuidString)", isDirectory: true), legacyAppSupport: bad)
        checkEqual(store.current, .defaults, "\(label) 옛 파일은 기본값으로 시작")
    }

    // 옛 폴더가 없으면 기본값
    let none = root.appendingPathComponent("empty-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: none, withIntermediateDirectories: true)
    checkEqual(SettingsStore(directory: root.appendingPathComponent("n-\(UUID().uuidString)"), legacyAppSupport: none).current, .defaults, "옛 폴더 없음")

    // 실제 사용자 파일 형태 샘플
    let migrationSample = FileManager.default.contents(atPath: electronSettingsFixturePath)
    check(migrationSample != nil, "Electron 샘플 파일이 있어야 한다")
    if let sample = migrationSample, let json = String(data: sample, encoding: .utf8) {
        let appSupport = makeLegacy(folder: "퀵스트림", json: json)
        let store = SettingsStore(directory: root.appendingPathComponent("s-\(UUID().uuidString)"), legacyAppSupport: appSupport)
        checkEqual(store.warning, nil, "Electron 샘플 마이그레이션 경고 없음")
        check(store.current != .defaults, "Electron 샘플 마이그레이션 내용 반영")
    }
}


// MARK: - ActionExecutor

private final class Effects: @unchecked Sendable {
    var opened: [URL] = []
    var clipboard: [String] = []
    var openError: Error?
    struct Failure: LocalizedError { var errorDescription: String? { "열기 실패" } }
}

private func testActionExecutor() async {
    section("Core/ActionExecutor")
    let catalog = FakeCatalog()
    let fx = Effects()
    func run(_ action: Action) async -> ActionResult {
        await ActionExecutor.execute(action, catalog: catalog, openURL: { url in
            if let error = fx.openError { throw error }
            fx.opened.append(url)
        }, writeClipboard: { fx.clipboard.append($0) })
    }

    let activated = await run(.activateApp(bundleId: "a.b", pid: 7))
    checkEqual(activated, .success, "activate 성공")
    checkEqual(catalog.calls, ["activate:a.b:7"], "activate 호출 인자")
    let launchedById = await run(.launchApp(bundleId: "c.d", appPath: nil))
    let launchedByPath = await run(.launchApp(bundleId: nil, appPath: "/A.app"))
    checkEqual(launchedById, .success, "launch bundleId")
    checkEqual(launchedByPath, .success, "launch appPath")
    checkEqual(Array(catalog.calls.suffix(2)), ["open:c.d", "open:/A.app"], "launch 대상 전달")

    let opened = await run(.openURL("https://example.com/x"))
    checkEqual(opened, .success, "URL 열기")
    checkEqual(fx.opened.map(\.absoluteString), ["https://example.com/x"], "열린 URL")
    let rejected = await run(.openURL("file:///etc/passwd"))
    check(!rejected.ok && rejected.error?.contains("허용되지 않는 URL") == true, "실행 시점에도 http/https 만")
    checkEqual(fx.opened.count, 1, "거부된 URL 은 열지 않음")
    fx.openError = Effects.Failure()
    let openFailed = await run(.openURL("https://a.com"))
    checkEqual(openFailed, .failure("열기 실패"), "URL 열기 오류 전달")
    fx.openError = nil

    let copied = await run(.clipboardText("복사"))
    checkEqual(copied, .success, "클립보드")
    checkEqual(fx.clipboard, ["복사"], "클립보드 내용")

    // 매크로: 순서 / 중단 / 계속
    fx.clipboard = []
    let before = catalog.calls.count
    let order = await run(.macroSequence(stopOnError: true, steps: [.clipboardText("1"), .launchApp(bundleId: "x.y", appPath: nil), .clipboardText("2")]))
    checkEqual(order, .success, "매크로 성공")
    checkEqual(fx.clipboard, ["1", "2"], "매크로 단계 순서")
    checkEqual(Array(catalog.calls.dropFirst(before)), ["open:x.y"], "매크로 단계 호출")

    catalog.failing = ["bad.one", "bad.two"]
    fx.clipboard = []
    let stopped = await run(.macroSequence(stopOnError: true, steps: [.clipboardText("1"), .launchApp(bundleId: "bad.one", appPath: nil), .clipboardText("2")]))
    checkEqual(stopped, .failure("2단계: 설치된 앱을 찾을 수 없습니다: bad.one"), "stopOnError 는 첫 실패에서 중단")
    checkEqual(fx.clipboard, ["1"], "중단 뒤 단계는 실행하지 않음")

    fx.clipboard = []
    let continued = await run(.macroSequence(stopOnError: false, steps: [.launchApp(bundleId: "bad.one", appPath: nil), .clipboardText("2"), .launchApp(bundleId: "bad.two", appPath: nil)]))
    checkEqual(continued, .failure("1단계: 설치된 앱을 찾을 수 없습니다: bad.one / 3단계: 설치된 앱을 찾을 수 없습니다: bad.two"), "실패를 ` / ` 로 연결")
    checkEqual(fx.clipboard, ["2"], "stopOnError=false 는 계속 실행")

    let badURLStep = await run(.macroSequence(stopOnError: true, steps: [.openURL("ftp://x")]))
    check(badURLStep.error?.hasPrefix("1단계: 허용되지 않는 URL") == true, "매크로 안 URL 도 거부")
}

// MARK: - Deck

private func testDeck(_ root: URL) async {
    section("Core/Deck")
    func makeStore(_ s: Settings) -> SettingsStore {
        let store = SettingsStore(directory: root.appendingPathComponent("deck-\(UUID().uuidString)", isDirectory: true), legacyAppSupport: nil)
        check(store.save(s).ok, "Deck 테스트 설정 저장")
        return store
    }

    // 기본값: 빈 고정 탭 하나
    do {
        let catalog = FakeCatalog()
        let store = SettingsStore(directory: root.appendingPathComponent("deck-\(UUID().uuidString)"), legacyAppSupport: nil)
        let deck = Deck(store: store, catalog: catalog)
        let state = await deck.buildState()
        checkEqual(state.activeTab, 0, "activeTab 0")
        checkEqual(state.tabs.map(\.caption), ["PINNED"], "캡션")
        check(state.tabs.allSatisfy { $0.slots.count == 8 }, "슬롯 배열은 항상 8")
        check(state.tabs[0].slots.allSatisfy { $0 == nil }, "빈 고정 탭은 슬롯 전부 비어 있음")
        checkEqual(state.alpha, OverlaySettings().alpha, "alpha 전달(설정 기본값)")
        checkEqual(state.radius, OverlaySettings().radius, "radius 전달(설정 기본값)")
        check(deck.action(tabId: "pinned", slotIndex: 0) == nil, "빈 슬롯은 nil")
        check(deck.action(tabId: "pinned", slotIndex: 8) == nil && deck.action(tabId: "pinned", slotIndex: -1) == nil, "범위 밖은 nil")
        let emptyRun = await deck.execute(tabId: "pinned", slotIndex: 6)
        check(!emptyRun.ok, "빈 슬롯 실행은 실패")
        checkEqual(catalog.calls, [], "빈 슬롯 실행은 아무 것도 호출하지 않음")
    }

    // 고정/커스텀 슬롯 매핑: 라벨/약어/동사
    do {
        var s = Settings.defaults
        s.tabs[0].slots = [
            slot("n", .launchApp(bundleId: "com.apple.Notes", appPath: nil), name: "memo pad", label: "mp"),
            slot("w", .openURL("https://a.com"), name: "웹"),
            slot("c", .clipboardText("t"), name: "복사"),
            slot("m", .macroSequence(stopOnError: true, steps: [.launchApp(bundleId: "m.app", appPath: nil)]), name: "매크로"),
        ]
        s.tabs.append(Tab(id: "mine", name: "내 탭", type: .custom, slots: [slot("x", .launchApp(bundleId: nil, appPath: "/Applications/X.app"), name: "Xylophone")]))
        let catalog = FakeCatalog()
        let deck = Deck(store: makeStore(s), catalog: catalog)
        let state = await deck.buildState()
        let pinned = state.tabs[0].slots
        checkEqual(pinned.prefix(4).compactMap { $0?.verb }, ["LAUNCH", "OPEN", "COPY", "RUN"], "동사")
        checkEqual(pinned[0]?.label, "mp", "명시한 라벨 우선")
        checkEqual(pinned[1]?.label, "웹", "라벨이 없으면 약어 생성")
        checkEqual(state.tabs[1].caption, "CUSTOM", "커스텀 캡션")
        checkEqual(state.tabs[1].slots[0]?.label, "XY", "한 단어 이름 약어")
        checkEqual(deck.action(tabId: "mine", slotIndex: 0), .launchApp(bundleId: nil, appPath: "/Applications/X.app"), "커스텀 탭 액션")
        let launched = await deck.execute(tabId: "pinned", slotIndex: 0)
        checkEqual(launched, .success, "고정 슬롯 실행")
        checkEqual(catalog.calls, ["open:com.apple.Notes"], "고정 슬롯 launch")
    }

    // 아이콘: 표시를 기다리지 않고, 캐시되면 다음 표시부터 붙는다
    do {
        var s = Settings.defaults
        s.tabs[0].slots = [
            slot("n", .launchApp(bundleId: "com.apple.Notes", appPath: nil)),
            slot("p", .launchApp(bundleId: nil, appPath: "/Applications/P.app")),
            slot("m", .macroSequence(stopOnError: true, steps: [.launchApp(bundleId: "macro.step", appPath: nil)])),
            slot("u", .openURL("https://a.com")),
        ]
        let catalog = FakeCatalog()
        let gate = DispatchSemaphore(value: 0)
        catalog.iconHook = { target in
            _ = gate.wait(timeout: .now() + 10) // 풀어 주기 전까지 아이콘 렌더가 끝나지 않는다
            if case let .bundleId(id) = target { return Data("png:\(id)".utf8) }
            if case let .appPath(path) = target { return Data("png:\(path)".utf8) }
            return nil
        }
        let store = makeStore(s)
        let deck = Deck(store: store, catalog: catalog)
        let first = await deck.buildState() // 렌더가 막혀 있어도 돌아와야 한다(막히면 10초 뒤에야 돌아와 아래 검사가 실패한다)
        check(first.tabs.flatMap { $0.slots }.allSatisfy { $0?.iconPNG == nil }, "아이콘이 없어도 buildState 는 기다리지 않고 약어로 표시")
        for _ in 0..<10 { gate.signal() }
        await deck.waitForIconWork()

        let second = await deck.buildState()
        checkEqual(second.tabs[0].slots[0]?.iconPNG, Data("png:com.apple.Notes".utf8), "launch bundleId 아이콘")
        checkEqual(second.tabs[0].slots[1]?.iconPNG, Data("png:/Applications/P.app".utf8), "launch appPath 아이콘")
        checkEqual(second.tabs[0].slots[2]?.iconPNG, nil, "매크로 슬롯은 아이콘 없음")
        checkEqual(second.tabs[0].slots[3]?.iconPNG, nil, "URL 슬롯은 아이콘 없음")
        check(!catalog.iconRequests.contains(.bundleId("macro.step")), "매크로 단계는 아이콘을 요청하지 않음")

        let requested = catalog.iconRequests.count
        _ = await deck.buildState()
        _ = await deck.buildState()
        await deck.waitForIconWork()
        checkEqual(catalog.iconRequests.count, requested, "캐시된 아이콘은 다시 요청하지 않음")
        checkEqual(Set(catalog.iconRequests).count, catalog.iconRequests.count, "같은 대상을 중복 요청하지 않음")

        // prewarm 은 설정에 새로 생긴 앱의 아이콘을 미리 채운다
        var s2 = s
        s2.tabs[0].slots.append(slot("later", .launchApp(bundleId: "later", appPath: nil)))
        check(store.save(s2).ok, "슬롯 추가 저장")
        deck.prewarm()
        await deck.waitForIconWork()
        check(catalog.iconRequests.contains(.bundleId("later")), "prewarm 이 설정의 새 앱 아이콘을 요청")
    }

    // 아이콘 표시를 끄면 요청하지 않는다
    do {
        var s = Settings.defaults
        s.overlay.showIcons = false
        s.tabs[0].slots = [slot("n", .launchApp(bundleId: "com.apple.Notes", appPath: nil))]
        let catalog = FakeCatalog()
        let deck = Deck(store: makeStore(s), catalog: catalog)
        deck.prewarm()
        let state = await deck.buildState()
        await deck.waitForIconWork()
        checkEqual(catalog.iconRequests, [], "showIcons=false 면 아이콘을 요청하지 않음")
        check(state.tabs.flatMap { $0.slots }.allSatisfy { $0?.iconPNG == nil }, "showIcons=false 면 아이콘 없음")
    }

    // 빈 칸이 있는 탭: 슬롯은 자기 링 위치에 있고(뒤 슬롯이 당겨지지 않는다), 실행도 그 위치로 간다
    do {
        var s = Settings.defaults
        s.tabs[0].slots = [slot("a", .clipboardText("12시")), nil, nil, nil, slot("b", .clipboardText("6시"))]
        let fx = Effects()
        let deck = Deck(store: makeStore(s), catalog: FakeCatalog(), openURL: { fx.opened.append($0) }, writeClipboard: { fx.clipboard.append($0) })
        let state = await deck.buildState()
        checkEqual(state.tabs[0].slots.map { $0?.id }, ["a", nil, nil, nil, "b", nil, nil, nil], "빈 칸은 nil 로 남고 슬롯은 자기 링 위치에 선다")
        checkEqual(deck.action(tabId: "pinned", slotIndex: 4), .clipboardText("6시"), "6시 칸의 동작")
        check(deck.action(tabId: "pinned", slotIndex: 1) == nil, "빈 칸은 동작이 없다")
        _ = await deck.execute(tabId: "pinned", slotIndex: 4)
        checkEqual(fx.clipboard, ["6시"], "5번 칸 실행은 6시 슬롯의 동작")
        let emptyRun = await deck.execute(tabId: "pinned", slotIndex: 1)
        check(!emptyRun.ok, "빈 칸 실행은 실패")
    }

    // commit 의미: 이미 보낸 상태의 실행 조회표는 설정이 바뀌어도 그대로
    do {
        var s1 = Settings.defaults
        s1.tabs[0].slots = [slot("a", .clipboardText("첫번째"))]
        let store = makeStore(s1)
        let fx = Effects()
        let deck = Deck(store: store, catalog: FakeCatalog(), openURL: { fx.opened.append($0) }, writeClipboard: { fx.clipboard.append($0) })
        _ = await deck.buildState()

        var s2 = s1
        s2.tabs[0].slots = [slot("a", .clipboardText("두번째")), slot("b", .clipboardText("추가"))]
        check(store.save(s2).ok, "설정 변경 저장")
        checkEqual(deck.action(tabId: "pinned", slotIndex: 0), .clipboardText("첫번째"), "새 설정이 저장돼도 보낸 상태의 조회표 유지")
        check(deck.action(tabId: "pinned", slotIndex: 1) == nil, "보낸 상태에 없던 슬롯은 실행 불가")
        _ = await deck.execute(tabId: "pinned", slotIndex: 0)
        checkEqual(fx.clipboard, ["첫번째"], "실행은 보낸 상태 기준")

        _ = await deck.buildState()
        checkEqual(deck.action(tabId: "pinned", slotIndex: 0), .clipboardText("두번째"), "다음 buildState 부터 새 설정")
        _ = await deck.execute(tabId: "pinned", slotIndex: 1)
        checkEqual(fx.clipboard, ["첫번째", "추가"], "새 상태 기준 실행")
    }
}

// MARK: - 단축키 교체 / 로그인 항목 / 가속키

private func testShortcutSwap() {
    section("Core/ShortcutSwap")
    let handler = {}

    // 성공: 이전 해제 후 새로 등록, rollback 은 이전으로 복구
    let ok = FakeShortcuts()
    _ = ok.register("Alt+Q", handler: handler)
    let rollback = GlobalShortcut.swap(registry: ok, previous: "Alt+Q", next: "Command+Shift+Space", handler: handler)
    checkEqual(ok.registered, "Command+Shift+Space", "교체 성공")
    check(rollback != nil, "성공하면 rollback 반환")
    rollback?()
    checkEqual(ok.registered, "Alt+Q", "rollback 은 이전 단축키를 복구")

    // 새 등록 실패: 이전 복구 + nil
    let bad = FakeShortcuts()
    _ = bad.register("Alt+Q", handler: handler)
    bad.rejects = ["Command+Space"]
    let failed = GlobalShortcut.swap(registry: bad, previous: "Alt+Q", next: "Command+Space", handler: handler)
    check(failed == nil, "새 등록 실패는 nil")
    checkEqual(bad.registered, "Alt+Q", "실패하면 이전 단축키 복구")

    // 이전이 없었으면 복구할 것도 없다
    let none = FakeShortcuts()
    none.rejects = ["Alt+X"]
    check(GlobalShortcut.swap(registry: none, previous: nil, next: "Alt+X", handler: handler) == nil, "이전 없이 실패")
    checkEqual(none.registered, nil, "이전이 없으면 아무것도 등록되지 않음")
    let created = FakeShortcuts()
    let undo = GlobalShortcut.swap(registry: created, previous: nil, next: "Alt+Y", handler: handler)
    undo?()
    checkEqual(created.registered, nil, "이전이 없던 교체의 rollback 은 해제")
}

private func testLoginItem() {
    section("Core/LoginItem")
    let same = FakeLoginItem(enabled: true)
    if case .success = applyLoginItem(same, wanted: true) {} else { check(false, "이미 같은 상태면 성공") }

    let api = FakeLoginItem(enabled: false)
    if case let .success(rollback) = applyLoginItem(api, wanted: true) {
        check(api.enabled, "켜기 반영")
        rollback()
        check(!api.enabled, "rollback 은 이전 상태로")
    } else {
        check(false, "켜기 성공")
    }

    // macOS 가 조용히 거부: 복구 + 오류(서명 안내)
    let ignoring = FakeLoginItem(enabled: false)
    ignoring.ignoresChanges = true
    if case let .failure(message) = applyLoginItem(ignoring, wanted: true) {
        check(message.contains("서명되지 않은 앱은 macOS 가 거부할 수 있습니다"), "서명 힌트")
    } else {
        check(false, "반영되지 않으면 실패")
    }
    check(!ignoring.enabled, "반영되지 않으면 이전 상태")

    // throw: 복구 + 오류에 원인 포함
    let throwing = FakeLoginItem(enabled: false)
    throwing.throwsOnSet = true
    if case let .failure(message) = applyLoginItem(throwing, wanted: true) {
        check(message.contains("boom") && message.contains("서명되지 않은 앱은 macOS 가 거부할 수 있습니다"), "원인과 힌트")
    } else {
        check(false, "throw 는 실패")
    }
    check(!throwing.enabled, "throw 뒤 이전 상태")

    // 끄기 실패는 켜진 상태로 복구
    let stuck = FakeLoginItem(enabled: true)
    stuck.ignoresChanges = true
    if case .failure = applyLoginItem(stuck, wanted: false) {} else { check(false, "끄기가 반영되지 않으면 실패") }
    check(stuck.enabled, "끄기 실패는 켜진 상태 유지")
}

private func testAccelerator() {
    section("Core/Accelerator")
    for accelerator in ["Alt+Q", "Command+Shift+Space", "Control+Alt+Shift+F5", "Command+1", "Command+Alt+Left"] {
        guard let parsed = Accelerator.parse(accelerator) else {
            check(false, "해석 가능: \(accelerator)")
            continue
        }
        var flags: NSEvent.ModifierFlags = []
        if parsed.carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if parsed.carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if parsed.carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if parsed.carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        let back = Accelerator.string(keyCode: UInt16(parsed.keyCode), modifierFlags: flags)
        checkEqual(back.flatMap(Accelerator.parse), parsed, "문자열 왕복: \(accelerator)")
    }
    checkEqual(Accelerator.string(keyCode: 12, modifierFlags: [.shift, .command]), "Command+Shift+Q", "출력 순서는 Command, Control, Alt, Shift")
    checkEqual(Accelerator.display("Alt+Q"), "⌥Q", "표시")
    checkEqual(Accelerator.display("Command+Shift+Space"), "⇧⌘Space", "표시(수정키 순서)")
    check(Accelerator.parse("Q") == nil, "수정키 없음")
    check(Accelerator.parse("Alt+") == nil, "키 없음")
    check(Accelerator.parse("Alt+Q+W") == nil, "키 둘")
    check(Accelerator.parse("alt+q") != nil, "대소문자 무관")

    // Electron 이 허용하는 문자열은 Swift 가 거부해 설정 파일 전체가 기본값이 되면 안 된다
    let cmd = Accelerator.parse("Command+Q")
    for alias in ["CommandOrControl", "CmdOrCtrl", "Meta"] {
        checkEqual(Accelerator.parse("\(alias)+Q"), cmd, "\(alias) 는 macOS 에서 ⌘")
    }
    checkEqual(Accelerator.parse("Alt+Insert")?.keyCode, UInt32(kVK_Help), "Insert → Help 키코드")
    checkEqual(Accelerator.display("Alt+Insert"), "⌥Insert", "Insert 표시")
    checkEqual(Accelerator.display("CmdOrCtrl+Shift+Q"), "⇧⌘Q", "별칭 표시")
    for n in 1...24 {
        let name = "F\(n)"
        check(Accelerator.isWellFormed("Alt+\(name)"), "\(name) 는 형식상 유효")
        if n <= 20 {
            check(Accelerator.parse("Alt+\(name)") != nil, "\(name) 등록 가능")
        } else {
            check(Accelerator.parse("Alt+\(name)") == nil, "\(name) 는 Carbon 키코드가 없어 등록 불가")
            checkEqual(Accelerator.display("alt+f\(n)"), "⌥\(name)", "\(name) 표시")
        }
    }
    var electronSettings = Settings.defaults
    for accelerator in ["CommandOrControl+Shift+Space", "Meta+Insert", "Alt+F24"] {
        electronSettings.shortcut = accelerator
        check(SettingsValidator.validate(electronSettings).isEmpty, "검증 통과: \(accelerator)")
    }
    let f24 = GlobalShortcut().register("Alt+F24") {}
    check(!f24.ok && (f24.error ?? "").contains("쓸 수 없는"), "F24 는 등록 단계에서 경고로 처리(Carbon 호출 전에 실패)")
    for bad in ["Alt+F25", "Alt+F0", "Hyper+Q", "CommandOrControl", "Alt+Foo"] {
        check(Accelerator.parse(bad) == nil && !Accelerator.isWellFormed(bad), "여전히 거부: \(bad)")
        electronSettings.shortcut = bad
        check(!SettingsValidator.validate(electronSettings).isEmpty, "검증 실패: \(bad)")
    }
}

private func testOverlaySizes() {
    section("Core/패널 크기")
    let decoder = JSONDecoder()
    let none = try? decoder.decode(OverlaySettings.self, from: Data(#"{"alpha":0.5}"#.utf8))
    checkEqual(none?.ringSize, 258, "키 없으면 바깥 크기 기본값(기본 테마 오비트 258)")
    checkEqual(none?.centerSize, 78, "키 없으면 중앙 원 기본값(오비트 78)")
    var custom = Settings.defaults
    custom.overlay.ringSize = 200
    custom.overlay.centerSize = 90
    let back = (try? JSONEncoder().encode(custom)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(back?.overlay.ringSize, 200, "바깥 크기 왕복")
    checkEqual(back?.overlay.centerSize, 90, "중앙 원 크기 왕복")
    checkEqual(none?.centerBorder, 4, "키 없으면 테두리 굵기 기본값(오비트 4)")
    checkEqual(none?.theme, .orbit, "theme 키 없으면 기본 테마 orbit")
    checkEqual([none?.pieSizes, none?.orbitSizes], [OverlayTheme.pie.defaultSizes, OverlayTheme.orbit.defaultSizes], "크기 기본값은 테마별(pie 250/112/4, orbit 258/78/4)")
    checkEqual(none?.namePlacement, .center, "namePlacement 키 없으면 center(기본)")
    checkEqual(none?.showNumbers, true, "showNumbers 키 없으면 true")
    for (raw, expected) in [("center", OverlayNamePlacement.center), ("hidden", .hidden), ("top", .top)] {
        var np = Settings.defaults
        np.overlay.namePlacement = expected
        np.overlay.showNumbers = false
        let nb = (try? JSONEncoder().encode(np)).flatMap { try? decoder.decode(Settings.self, from: $0) }
        checkEqual(nb?.overlay.namePlacement, expected, "namePlacement 왕복: \(raw)")
        checkEqual(nb?.overlay.showNumbers, false, "showNumbers 왕복(\(raw))")
        checkEqual(expected.rawValue, raw, "namePlacement raw id: \(raw)")
    }
    for bad in [#"{"namePlacement":"floating","showNumbers":"yes"}"#, #"{"namePlacement":3,"showNumbers":7}"#] {
        let doc = #"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":\#(bad),"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#
        let loaded = try? decoder.decode(Settings.self, from: Data(doc.utf8))
        check(loaded != nil, "잘못된 이름 위치/숫자 값이어도 설정을 버리지 않는다")
        checkEqual(loaded?.overlay.namePlacement, OverlaySettings().namePlacement, "잘못된 namePlacement → 기본(center)")
        checkEqual(loaded?.overlay.showNumbers, true, "잘못된 showNumbers → true")
        checkEqual(loaded?.shortcut, "Alt+W", "shortcut 유지")
        checkEqual(loaded?.tabs.count, 1, "tabs 유지")
        if let loaded { checkEqual(issues(loaded), [], "검증 이슈 없음") }
    }
    // 이전 방식 키(palette/focusColor)는 알 수 없는 키로 무시되고 로드에 영향이 없다
    for legacy in [#""palette":"dracula","focusColor":"nord""#, #""palette":"neon","focusColor":7"#, #""palette":[1],"focusColor":{}"#] {
        let doc = #"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{\#(legacy)},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#
        let loaded = try? decoder.decode(Settings.self, from: Data(doc.utf8))
        check(loaded != nil, "이전 palette/focusColor 키가 있어도 파일을 읽는다(\(legacy))")
        checkEqual(loaded?.overlay, OverlaySettings(), "이전 키는 무시되고 기본값(\(legacy))")
        checkEqual(loaded?.shortcut, "Alt+W", "이전 키가 있어도 shortcut 유지(\(legacy))")
        checkEqual(loaded?.tabs.count, 1, "이전 키가 있어도 tabs 유지(\(legacy))")
        if let loaded { checkEqual(issues(loaded), [], "이전 키는 검증 이슈가 아니다(\(legacy))") }
    }
    let legacyJSON = (try? JSONEncoder().encode(Settings.defaults)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check(!legacyJSON.contains("\"palette\"") && !legacyJSON.contains("focusColor"), "이전 키는 저장하지 않는다")
    let orbit = try? decoder.decode(OverlaySettings.self, from: Data(#"{"theme":"orbit"}"#.utf8))
    checkEqual(orbit?.theme, .orbit, "orbit 디코드")
    var orbitSettings = Settings.defaults
    orbitSettings.overlay.theme = .orbit
    let orbitBack = (try? JSONEncoder().encode(orbitSettings)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(orbitBack?.overlay.theme, .orbit, "orbit 왕복")
    // 알 수 없는 테마 이름이어도 설정 전체를 버리지 않는다
    let galaxy = try? decoder.decode(Settings.self, from: Data(#"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{"theme":"galaxy"},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#.utf8))
    checkEqual(galaxy?.overlay.theme, .orbit, "알 수 없는 테마는 기본(orbit)")
    checkEqual(galaxy?.shortcut, "Alt+W", "나머지 설정은 유지")
    if let galaxy { checkEqual(issues(galaxy).filter { $0.contains("테마") }, [], "테마 때문에 검증 이슈가 생기지 않는다") }
    custom.overlay.centerBorder = 9
    let back2 = (try? JSONEncoder().encode(custom)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(back2?.overlay.centerBorder, 9, "테두리 굵기 왕복")
    for (v, ok) in [(0, false), (13, false), (1, true), (12, true)] {
        var b = Settings.defaults
        b.overlay.centerBorder = v
        if ok { checkEqual(issues(b), [], "테두리 \(v) 허용") } else { check(hasIssue(b, containing: "중앙 원 테두리"), "테두리 \(v) 거부") }
    }

    func with(_ ring: Int, _ center: Int) -> Settings {
        var s = Settings.defaults
        s.overlay.ringSize = ring
        s.overlay.centerSize = center
        return s
    }
    check(hasIssue(with(159, 112), containing: "바깥 크기"), "ring<160 거부")
    check(hasIssue(with(321, 112), containing: "바깥 크기"), "ring>320 거부")
    check(hasIssue(with(250, 39), containing: "중앙 원 크기"), "center<40 거부")
    check(hasIssue(with(250, 249), containing: "중앙 원 크기"), "center>248(절대 상한) 거부")
    // 조합이 어긋나도(예: 250 에서 179~248) 파일 전체를 버리지 않는다. 그릴 때 보정한다.
    checkEqual(issues(with(250, 200)), [], "ring 대비 큰 center 도 파일은 유효")
    for (r, c) in [(160, 40), (320, 248), (250, 178), (160, 200)] {
        checkEqual(issues(with(r, c)), [], "허용: \(r)/\(c)")
    }
    checkEqual(PieGeometry(ringRadius: 160, centerRadius: 200).hubRadius, 88, "그릴 때 중앙 원은 바깥-72 로 보정")
    checkEqual(PieGeometry(ringRadius: 250, centerRadius: 200).hubRadius, 178, "그릴 때 중앙 원 보정(250)")
}

// MARK: - 이전 앱 복원

private func testFocusRestore() {
    section("Core/FocusRestore")
    let catalog = FakeCatalog()
    let kakao = running("com.kakao.KakaoTalk", name: "KakaoTalk", pid: 77)
    check(FocusRestore.restore(kakao, catalog: catalog), "복원 성공")
    checkEqual(catalog.calls, ["refocus:com.kakao.KakaoTalk:77"], "복원은 refocus 만 부르고 activate/open(reopen 계열)은 부르지 않음")

    catalog.failing = [kakao.bundleId]
    check(!FocusRestore.restore(kakao, catalog: catalog), "refocus 실패는 false")
    check(!catalog.calls.contains { $0.hasPrefix("open:") || $0.hasPrefix("activate:") }, "실패해도 앱을 새로 열거나 activate 하지 않음")

    let before = catalog.calls.count
    check(!FocusRestore.restore(nil, catalog: catalog), "이전 앱이 없으면 false")
    checkEqual(catalog.calls.count, before, "이전 앱이 없으면 아무 호출도 없음")

    // 실제 구현: 실행 중이 아닌 앱은 실행하지 않고 false (GUI 없이 확인 가능)
    check(!SystemAppCatalog().refocus(bundleId: "com.quickstream.tests.not-running", pid: nil), "실행 중이 아닌 앱은 false")
    check(!SystemAppCatalog().refocus(bundleId: "com.quickstream.tests.not-running", pid: 999_999), "없는 pid 도 false")
}

private func testThemeSizesAndBodyDecode() {
    section("Core/테마별 크기·본체·포커스 디코드")
    let decoder = JSONDecoder()
    func overlay(_ json: String) -> OverlaySettings? { try? decoder.decode(OverlaySettings.self, from: Data(json.utf8)) }

    // 예전 단일 크기 키 → '지금 테마'의 크기, 다른 테마는 기본값
    let legacyPie = overlay(#"{"theme":"pie","ringSize":200,"centerSize":90,"centerBorder":6}"#)
    checkEqual(legacyPie?.pieSizes, ThemeSizes(ring: 200, center: 90, border: 6), "pie 예전 키 → pieSizes")
    checkEqual(legacyPie?.orbitSizes, OverlayTheme.orbit.defaultSizes, "pie 예전 키는 orbit 기본값을 건드리지 않음")
    let legacyOrbit = overlay(#"{"theme":"orbit","ringSize":310,"centerSize":100,"centerBorder":2}"#)
    checkEqual(legacyOrbit?.orbitSizes, ThemeSizes(ring: 310, center: 100, border: 2), "orbit 예전 키 → orbitSizes")
    checkEqual(legacyOrbit?.pieSizes, OverlayTheme.pie.defaultSizes, "orbit 예전 키는 pie 기본값을 건드리지 않음")
    let legacyNoTheme = overlay(#"{"ringSize":210}"#)
    checkEqual(legacyNoTheme?.pieSizes.ring, 210, "theme 없으면 pie 로 가져옴")
    // 키는 있는데 값을 읽을 수 없으면(오타·null) '키 없음'(→ 파이)과 달리 기본 테마가 그대로 현재 테마다: 사용자가 보는 화면의 크기로 이관된다
    for bad in [#""x""#, "null", "7"] {
        let legacyBadTheme = overlay(#"{"theme":\#(bad),"ringSize":300,"centerSize":90,"centerBorder":5}"#)
        checkEqual(legacyBadTheme?.theme, OverlaySettings().theme, "theme \(bad) 는 기본 테마")
        checkEqual(legacyBadTheme?.orbitSizes, ThemeSizes(ring: 300, center: 90, border: 5), "theme \(bad) 이어도 예전 크기는 현재(기본) 테마 크기로")
        checkEqual(legacyBadTheme?.pieSizes, OverlayTheme.pie.defaultSizes, "theme \(bad) 의 예전 크기는 pie 를 건드리지 않음")
    }

    // 저장은 테마별 키만 기록한다
    var migrated = Settings.defaults
    migrated.overlay = legacyOrbit ?? OverlaySettings()
    let json = (try? JSONEncoder().encode(migrated)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check(json.contains("\"orbitSizes\"") && json.contains("\"pieSizes\""), "테마별 키로 저장")
    check(!json.contains("\"ringSize\"") && !json.contains("\"centerSize\"") && !json.contains("\"centerBorder\""), "예전 단일 키는 기록하지 않는다")
    let reread = (try? JSONEncoder().encode(migrated)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(reread?.overlay.orbitSizes, ThemeSizes(ring: 310, center: 100, border: 2), "저장→재로드 왕복")

    // 새 키가 있으면 예전 키보다 우선
    let both = overlay(#"{"theme":"pie","ringSize":200,"pieSizes":{"ring":260,"center":100,"border":5}}"#)
    checkEqual(both?.pieSizes, ThemeSizes(ring: 260, center: 100, border: 5), "pieSizes 가 예전 키보다 우선")

    // 알 수 없는 값·타입 오류는 기본값, 파일 전체를 버리지 않는다
    for bad in [#""neon-pink""#, "7", "null", "[]", "{}"] {
        let doc = #"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{"bodyTheme":\#(bad),"focusStyle":\#(bad),"focusHex":\#(bad),"showTileLabels":\#(bad)},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#
        let loaded = try? decoder.decode(Settings.self, from: Data(doc.utf8))
        check(loaded != nil, "잘못된 본체/스타일/색(\(bad))에도 파일을 읽는다")
        checkEqual(loaded?.overlay.bodyTheme, OverlaySettings().bodyTheme, "bodyTheme 오류 → 기본(다크 글라스)(\(bad))")
        checkEqual(loaded?.overlay.focusStyle, .neon, "focusStyle 오류 → 네온(기본)(\(bad))")
        checkEqual(loaded?.overlay.focusHex, FocusColors.defaultHex, "focusHex 오류 → 기본 민트(\(bad))")
        checkEqual(loaded?.overlay.showTileLabels, true, "showTileLabels 오류 → true(\(bad))")
        checkEqual(loaded?.shortcut, "Alt+W", "오류에도 shortcut 유지(\(bad))")
        checkEqual(loaded?.tabs.count, 1, "오류에도 tabs 유지(\(bad))")
        if let loaded { checkEqual(issues(loaded), [], "오류는 검증 이슈가 아니다(\(bad))") }
    }
    let valid = overlay(#"{"bodyTheme":"dark-glass","focusStyle":"neon","focusHex":"ff7edb","showTileLabels":false}"#)
    checkEqual(valid?.bodyTheme, .darkGlass, "dark-glass 로드")
    checkEqual(valid?.focusStyle, .neon, "neon 로드")
    checkEqual(valid?.focusHex, "#FF7EDB", "focusHex 는 정규화되어 로드")
    checkEqual(valid?.showTileLabels, false, "showTileLabels false 로드")
    // 불투명 바닥: 키 없음 → true, false 왕복, 타입 오류는 true 로 로드(파일 전체를 버리지 않는다)
    checkEqual(overlay("{}")?.solidBacking, true, "solidBacking 키 없으면 true")
    checkEqual(overlay(#"{"solidBacking":false}"#)?.solidBacking, false, "solidBacking false 로드")
    var solidOff = Settings.defaults
    solidOff.overlay.solidBacking = false
    let solidBack = (try? JSONEncoder().encode(solidOff)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(solidBack?.overlay.solidBacking, false, "solidBacking false 왕복")
    for bad in [#""yes""#, "1", "null", "[]"] {
        let doc = #"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{"solidBacking":\#(bad)},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#
        let loaded = try? decoder.decode(Settings.self, from: Data(doc.utf8))
        check(loaded != nil, "잘못된 solidBacking(\(bad))에도 파일을 읽는다")
        checkEqual(loaded?.overlay.solidBacking, true, "solidBacking 오류 → true(\(bad))")
        checkEqual(loaded?.tabs.count, 1, "solidBacking 오류에도 tabs 유지(\(bad))")
    }
    let defaults = overlay("{}")
    checkEqual([defaults?.bodyTheme == .darkGlass, defaults?.focusStyle == .neon, defaults?.focusHex == FocusColors.defaultHex], [true, true, true], "키 없으면 기본값")
    // 새 기본값은 선언부와 디코드 폴백이 항상 같다: 키가 전혀 없는 문서 = 기본 생성자, 그리고 값 자체도 고정한다
    checkEqual(defaults, OverlaySettings(), "키 없는 overlay 는 OverlaySettings() 와 같다")
    checkEqual(FocusColors.defaultHex, "#19F9D8", "기본 포커스 색은 민트")
    let d = OverlaySettings()
    checkEqual([d.alpha, Double(d.radius)], [0.4, 28], "기본 투명도 0.4 · 모서리 28")
    checkEqual(d.theme, .orbit, "기본 테마는 오비트")
    checkEqual(d.centerNameWeight, .regular, "기본 중앙 이름 굵기는 보통")
    checkEqual(d.orbitSizes, ThemeSizes(ring: 258, center: 78, border: 4), "오비트 기본 크기 258/78/4")
    checkEqual(d.pieSizes, ThemeSizes(ring: 250, center: 112, border: 4), "파이 기본 크기 250/112/4")
    check(Limits.alphaRange.contains(d.alpha) && Limits.radiusRange.contains(d.radius) && Limits.ringRange.contains(d.orbitSizes.ring), "새 기본값은 허용 범위 안")
    var round = Settings.defaults
    round.overlay.bodyTheme = .darkGlass
    round.overlay.focusStyle = .neon
    round.overlay.focusHex = "#19F9D8"
    let roundBack = (try? JSONEncoder().encode(round)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(roundBack, round, "본체·스타일·색 왕복")

    // 클리어 글라스 본체와 틴트
    checkEqual(overlay(#"{"bodyTheme":"clear-glass"}"#)?.bodyTheme, .clearGlass, "clear-glass 로드")
    checkEqual(OverlayBody.clearGlass.rawValue, "clear-glass", "clearGlass 저장 키")
    checkEqual(overlay(#"{"bodyTheme":"frosted-glass"}"#)?.bodyTheme, OverlaySettings().bodyTheme, "알 수 없는 본체 → 기본(다크 글라스)")
    checkEqual(overlay("{}")?.glassTintHex, GlassTints.defaultHex, "glassTintHex 키 없으면 기본(하늘)")
    checkEqual(GlassTints.defaultHex, "#6FB1FF", "기본 틴트 값")
    checkEqual(overlay(##"{"glassTintHex":"#ff8fc7"}"##)?.glassTintHex, "#FF8FC7", "소문자 틴트는 대문자로 정규화")
    for bad in ["7", "null", ##""nope""##, ##""#12""##, "[]", "{}"] {
        let loaded = try? decoder.decode(Settings.self, from: Data(#"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{"bodyTheme":"clear-glass","glassTintHex":\#(bad)},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#.utf8))
        check(loaded != nil, "잘못된 틴트(\(bad))에도 파일을 읽는다")
        checkEqual(loaded?.overlay.glassTintHex, GlassTints.defaultHex, "glassTintHex 오류 → 기본(\(bad))")
        checkEqual(loaded?.overlay.bodyTheme, .clearGlass, "틴트 오류가 본체를 바꾸지 않는다(\(bad))")
        checkEqual(loaded?.tabs.count, 1, "틴트 오류에도 tabs 유지(\(bad))")
    }
    var tinted = Settings.defaults
    tinted.overlay.bodyTheme = .clearGlass
    tinted.overlay.glassTintHex = "#FF8FC7"
    let tintedBack = (try? JSONEncoder().encode(tinted)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(tintedBack, tinted, "클리어 글라스 + 틴트 왕복")
    checkEqual(tintedBack?.overlay.glassTintHex, "#FF8FC7", "틴트 왕복 값")
    let encoded = (try? JSONEncoder().encode(tinted)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check(encoded.contains(##""glassTintHex":"#FF8FC7""##) && encoded.contains(##""bodyTheme":"clear-glass""##), "저장 JSON 에 본체·틴트 키가 있다")

    // 포커스 불빛 토글: 키 없음·잘못된 값은 켬, false 는 왕복
    checkEqual(overlay("{}")?.focusGlow, true, "focusGlow 키 없으면 켬")
    checkEqual(Settings.defaults.overlay.focusGlow, true, "focusGlow 기본은 켬")
    checkEqual(overlay(#"{"focusGlow":false}"#)?.focusGlow, false, "focusGlow false 로드")
    checkEqual(overlay(#"{"focusGlow":true}"#)?.focusGlow, true, "focusGlow true 로드")
    for bad in [##""no""##, "0", "1", "null", "{}", "[]"] {
        let loaded = try? decoder.decode(Settings.self, from: Data(#"{"schemaVersion":\#(Limits.schemaVersion),"platform":"darwin","shortcut":"Alt+W","overlay":{"bodyTheme":"dark-glass","focusGlow":\#(bad)},"tabs":[{"id":"t","name":"탭","type":"custom","slots":[]}]}"#.utf8))
        check(loaded != nil, "잘못된 focusGlow(\(bad))에도 파일을 읽는다")
        checkEqual(loaded?.overlay.focusGlow, true, "focusGlow 오류 → 켬(\(bad))")
        checkEqual(loaded?.overlay.bodyTheme, .darkGlass, "focusGlow 오류가 본체를 바꾸지 않는다(\(bad))")
    }
    var unlit = Settings.defaults
    unlit.overlay.focusGlow = false
    let unlitBack = (try? JSONEncoder().encode(unlit)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(unlitBack, unlit, "focusGlow 끔 왕복")
    checkEqual(unlitBack?.overlay.focusGlow, false, "focusGlow 끔 왕복 값")
    let unlitJSON = (try? JSONEncoder().encode(unlit)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check(unlitJSON.contains(#""focusGlow":false"#), "저장 JSON 에 focusGlow 키가 쓰인다")
}

private func testCenterNameDecode() {
    section("Core/중앙 원 글자 디코드")
    let decoder = JSONDecoder()
    func overlay(_ json: String) -> OverlaySettings? { try? decoder.decode(OverlaySettings.self, from: Data(json.utf8)) }
    let none = overlay("{}")
    checkEqual(none?.centerNameWeight, .regular, "키 없으면 굵기 regular(기본)")
    checkEqual(none?.centerNameSize, 0, "키 없으면 크기 자동(0)")
    checkEqual(overlay(#"{"centerNameSize":99}"#)?.centerNameSize, Limits.centerNameSizeRange.upperBound, "범위 위는 clamp")
    checkEqual(overlay(#"{"centerNameSize":4}"#)?.centerNameSize, Limits.centerNameSizeRange.lowerBound, "범위 아래는 clamp")
    checkEqual(overlay(#"{"centerNameSize":0}"#)?.centerNameSize, 0, "0 은 자동")
    checkEqual(overlay(#"{"centerNameSize":-3}"#)?.centerNameSize, 0, "음수는 자동")
    for bad in [#""big""#, "true", "null", "[]"] {
        checkEqual(overlay("{\"centerNameSize\":\(bad)}")?.centerNameSize, 0, "크기 타입 오류 → 자동(\(bad))")
    }
    for bad in [#""heavy""#, "3", "null", "[]"] {
        let o = overlay("{\"centerNameWeight\":\(bad)}")
        check(o != nil, "굵기 오류에도 설정을 읽는다(\(bad))")
        checkEqual(o?.centerNameWeight, .regular, "잘못된 굵기 → regular(기본)(\(bad))")
    }
    for weight in NameWeight.allCases {
        checkEqual(overlay("{\"centerNameWeight\":\"\(weight.rawValue)\"}")?.centerNameWeight, weight, "굵기 로드: \(weight.rawValue)")
    }
    var s = Settings.defaults
    s.overlay.centerNameWeight = .bold
    s.overlay.centerNameSize = 24
    let back = (try? JSONEncoder().encode(s)).flatMap { try? decoder.decode(Settings.self, from: $0) }
    checkEqual(back?.overlay.centerNameWeight, .bold, "굵기 왕복")
    checkEqual(back?.overlay.centerNameSize, 24, "크기 왕복")
}
