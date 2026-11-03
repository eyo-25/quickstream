import SwiftUI

/// 설정 창의 화면 상태. 편집 대상(draft)은 저장될 때까지 store 와 분리돼 있다.
@MainActor
final class SettingsModel: ObservableObject {
    enum Selection: Equatable {
        case general
        /// 패널 모양(모양/색상/표시 탭): 일반과 분리된 한 화면
        case panel
        case tab(String)
        case about
    }

    let store: SettingsStoring
    let catalog: AppCatalog
    private let saveHandler: (Settings) -> ActionResult
    let checkForUpdates: () -> Void
    let versionText: () -> String
    /// 단축키 녹화 시작(true)/종료(false). 녹화 중에는 전역 단축키를 풀어야 현재 조합을 누를 수 있다.
    private let onRecordingChange: (Bool) -> Void

    @Published private(set) var baseline: Settings
    @Published var draft: Settings {
        didSet {
            guard draft != oldValue else { return }
            saveError = nil
            // 프리셋 칩·되돌리기·초기화로 포커스 색이 바뀌면 입력 칸도 따라간다. 사용자가 치는 중인 값(이미 같은 색으로 정규화됨)이나
            // 무관한 편집(잘못 친 글자를 지우지 않는다)에서는 건드리지 않는다.
            if draft.overlay.focusHex != oldValue.overlay.focusHex, FocusColors.normalized(focusHexInput) != draft.overlay.focusHex {
                focusHexInput = draft.overlay.focusHex
            }
            if draft.overlay.glassTintHex != oldValue.overlay.glassTintHex, GlassTints.normalized(glassTintInput) != draft.overlay.glassTintHex {
                glassTintInput = draft.overlay.glassTintHex
            }
            refreshDerived()
        }
    }
    /// 패널 모양 섹션에서 보고 있는 탭
    @Published var panelTab: PanelTab = .shape
    /// 사용자 지정 포커스 색 입력 칸의 글자. 유효할 때만 draft 에 반영되므로 잘못된 입력은 이 칸에만 남는다.
    @Published var focusHexInput: String
    /// 글라스 틴트 직접 입력 칸의 글자(포커스 색 입력 칸과 같은 규칙)
    @Published var glassTintInput: String
    @Published var selection: Selection = .general {
        didSet {
            if selection != oldValue { selectedSlot = 0 }
        }
    }
    @Published private(set) var issues: [ValidationIssue] = []
    @Published private(set) var isDirty = false
    @Published private(set) var saveError: String?
    @Published private(set) var warning: String?
    @Published private(set) var apps: [InstalledApp] = []
    /// 오류 피드백(흔들림) 트리거. 저장 실패·검증에 막힌 저장 시도 때만(draft 편집은 절대 건드리지 않는다) 늘어난다. 표현 전용이라 저장 결과나 draft 에는 관여하지 않는다.
    @Published private(set) var errorFeedback = 0
    /// 탭 편집 패널에서 고른 슬롯 번호(탭을 바꾸면 처음으로). SwiftUI 의 @State 매크로를 쓰지 않으려고(명령줄 도구만 있는 빌드 환경에는 플러그인이 없다) 화면 상태도 모델이 쥔다.
    @Published var selectedSlot = 0
    /// 사이드바에서 탭을 끌어 놓을 때 지금 올려 둔 대상 탭 id(놓을 자리 표시선용). 화면 상태라 모델이 쥔다.
    @Published var tabDropTarget: String?
    /// 슬롯 목록에서 슬롯을 끌어 놓을 때 지금 올려 둔 칸 번호(놓을 자리 표시용). 화면 상태라 모델이 쥔다.
    @Published var slotDropTarget: Int?
    /// 단축키 녹화 중 안내 문구
    @Published var recorderHint: String?
    private(set) var isRecordingShortcut = false
    /// 저장이 성공했을 때만 불린다(실패·검증에 막힌 저장·변경 없는 저장에서는 부르지 않는다). 설정 창은 이걸로 스스로 닫는다.
    var onSaved: () -> Void = {}
    private var appsGeneration = 0

    init(store: SettingsStoring,
         catalog: AppCatalog,
         save: @escaping (Settings) -> ActionResult,
         checkForUpdates: @escaping () -> Void,
         versionText: @escaping () -> String,
         onRecordingChange: @escaping (Bool) -> Void = { _ in }) {
        self.store = store
        self.catalog = catalog
        self.saveHandler = save
        self.checkForUpdates = checkForUpdates
        self.versionText = versionText
        self.onRecordingChange = onRecordingChange
        baseline = store.current
        draft = store.current
        focusHexInput = store.current.overlay.focusHex
        glassTintInput = store.current.overlay.glassTintHex
        warning = store.warning
        refreshDerived()
    }

    private func refreshDerived() {
        issues = SettingsValidator.validate(draft)
        isDirty = SettingsDraft.isDirty(baseline: baseline, draft: draft)
    }

    /// 창을 다시 열 때: 디스크 상태 기준으로 편집을 새로 시작한다(설치 앱 목록도 다시 읽는다)
    func resetFromStore() {
        baseline = store.current
        draft = store.current
        focusHexInput = draft.overlay.focusHex
        glassTintInput = draft.overlay.glassTintHex
        panelTab = .shape
        warning = store.warning
        saveError = nil
        selection = .general
        refreshDerived()
        refreshApps()
    }

    /// 설정 창 색: 선택한 본체 색·포커스 색을 따른다(draft 가 바뀌면 곧바로 바뀐다).
    var palette: SettingsPalette {
        SettingsPalette.make(body: draft.overlay.bodyTheme, focusHex: draft.overlay.focusHex, style: draft.overlay.focusStyle, glassTint: draft.overlay.glassTintHex, glow: draft.overlay.focusGlow)
    }

    /// 설치 앱 목록을 백그라운드에서 다시 읽는다. 더 늦게 시작한 읽기가 있으면 먼저 시작한 읽기의 늦은 결과는 버린다.
    private func refreshApps() {
        appsGeneration += 1
        let generation = appsGeneration
        Task { [weak self, catalog] in
            let list = await catalog.installedApps()
            guard let self, generation == self.appsGeneration else { return }
            self.apps = list
        }
    }

    /// 단축키 녹화 시작/종료. 상태가 바뀔 때만 알려, 녹화 종료가 포커스 이탈·창 닫기 등으로 겹쳐 와도 전역 단축키 재등록이 한 번만 일어난다.
    func setShortcutRecording(_ recording: Bool) {
        guard recording != isRecordingShortcut else { return }
        isRecordingShortcut = recording
        onRecordingChange(recording)
    }

    var tabIndex: Int? {
        if case let .tab(id) = selection { return draft.tabs.firstIndex { $0.id == id } }
        return nil
    }

    var canSave: Bool { isDirty && issues.isEmpty }

    /// 하단 상태 문구의 종류(우선순위: 저장 오류 > 검증 문제 > 변경됨 > 깨끗). 종류가 바뀔 때만 문구를 튀어 오르게 하려고 값으로 분리했다.
    enum StatusKind: Equatable {
        case saveError
        case issue
        case dirty
        case clean
    }

    var statusKind: StatusKind {
        if saveError != nil { return .saveError }
        if !issues.isEmpty { return .issue }
        return isDirty ? .dirty : .clean
    }

    func revert() {
        draft = baseline
    }

    func save() {
        guard canSave else {
            // 검증 문제에 막힌 저장 시도(⌘S)는 오류 피드백만 낸다. 저장 동작 자체는 그대로 무시한다.
            if !issues.isEmpty { errorFeedback += 1 }
            return
        }
        let toSave = SettingsDraft.normalized(draft)
        let result = saveHandler(toSave)
        if result.ok {
            baseline = toSave
            draft = toSave
            warning = nil
            saveError = nil
            refreshDerived()
            onSaved()
        } else {
            saveError = result.error ?? "알 수 없는 오류"
            errorFeedback += 1
        }
    }

    func resetToDefaults() {
        draft = Settings.defaults
    }

    func addTab(_ type: TabKind) {
        let next = SettingsDraft.addTab(draft, type)
        guard next != draft else { return }
        draft = next
        if let id = next.tabs.last?.id { selection = .tab(id) }
    }

    func moveSelectedTab(by delta: Int) {
        guard let i = tabIndex else { return }
        draft = SettingsDraft.moveTab(draft, at: i, by: delta)
    }

    func duplicateSelectedTab() {
        guard let i = tabIndex else { return }
        let next = SettingsDraft.duplicateTab(draft, at: i)
        guard next != draft else { return }
        draft = next
        selection = .tab(next.tabs[i + 1].id)
    }

    func removeSelectedTab() {
        guard let i = tabIndex else { return }
        let next = SettingsDraft.removeTab(draft, at: i)
        guard next != draft else { return }
        draft = next
        // 지운 자리의 이웃 탭으로 선택을 옮긴다
        selection = .tab(next.tabs[min(i, next.tabs.count - 1)].id)
    }

    /// 드래그로 탭 순서를 바꾼다: `id` 탭이 `targetId` 탭이 있던 자리로 가고 사이의 탭이 한 칸씩 밀린다. 선택은 id 로 쥐고 있어 그대로 따라간다.
    func moveTab(id: String, onto targetId: String) {
        guard id != targetId,
              let from = draft.tabs.firstIndex(where: { $0.id == id }),
              let to = draft.tabs.firstIndex(where: { $0.id == targetId }) else { return }
        draft = SettingsDraft.moveTab(draft, at: from, by: to - from)
    }
}

/// 패널 모양 섹션의 탭. 선택 상태는 모델이 쥔다(@State 매크로를 쓸 수 없는 빌드 환경).
enum PanelTab: String, CaseIterable, Equatable {
    case shape
    case color
    case display

    var title: String {
        switch self {
        case .shape: return "모양"
        case .color: return "색상"
        case .display: return "표시"
        }
    }
}
