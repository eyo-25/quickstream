import Foundation

// 모듈 사이의 계약. UI(오버레이·설정 창)는 구체 구현이 아니라 이 프로토콜과 값 타입에만 의존한다.

struct ActionResult: Equatable {
    var ok: Bool
    var error: String?
    static let success = ActionResult(ok: true, error: nil)
    static func failure(_ message: String) -> ActionResult { ActionResult(ok: false, error: message) }
}

struct RunningApp: Equatable, Hashable {
    var bundleId: String
    var pid: Int32
    var name: String
}

struct InstalledApp: Equatable, Hashable, Identifiable {
    var bundleId: String
    /// 사용자 언어에 맞춘 이름(예: "계산기")
    var name: String
    /// 파일 이름 등 지역화 전 이름(예: "Calculator"). name 과 같으면 nil. 검색에만 쓴다.
    var altName: String?
    var appPath: String
    var id: String { bundleId }
}

/// 아이콘을 얻을 대상
enum IconTarget: Hashable {
    case bundleId(String)
    case appPath(String)
}

/// 앱 실행/전환/조회 (NSWorkspace). 구현: Core
protocol AppCatalog: AnyObject {
    /// 지금 가장 앞에 있는 일반(Dock 에 보이는) 앱. 퀵스트림 자신이 앞이면 nil
    func frontmostApp() -> RunningApp?
    /// 실행 중인 앱을 앞으로. 꺼져 있으면 실패
    func activate(bundleId: String, pid: Int32?) async -> ActionResult
    /// 이전 앱 복원 전용: 실행 중인 앱을 reopen 이벤트 없이 앞으로. 앞으로 가져왔으면 true, 꺼져 있거나 실패면 false(새로 실행하지 않는다)
    func refocus(bundleId: String, pid: Int32?) -> Bool
    /// 실행 중이면 앞으로, 꺼져 있으면 실행. bundleId 또는 appPath 중 정확히 하나
    func open(bundleId: String?, appPath: String?) async -> ActionResult
    /// /Applications, /System/Applications, ~/Applications(+1단계 하위 폴더)와 Finder. 이름순. 호출할 때마다 새로 훑는다(설정 창을 열 때 최신 목록을 보이려고).
    func installedApps() async -> [InstalledApp]
    /// 앱 아이콘 PNG(투명 배경, pixels × pixels). 못 얻으면 nil. 호출 비용이 작도록 구현이 캐시한다.
    func iconPNG(for target: IconTarget, pixels: Int) -> Data?
}

struct ValidationIssue: Equatable {
    /// nil 이면 일반(단축키·모양) 항목
    var tabIndex: Int?
    var slotIndex: Int?
    /// 사용자에게 보이는 위치 + 사유. 예: `탭 "고정 앱" > 슬롯 3 > URL: http/https URL 만 허용됩니다`
    var text: String
}

/// 설정 파일 저장소. 구현: Core
protocol SettingsStoring: AnyObject {
    var current: Settings { get }
    /// 파일이 깨져 기본값으로 동작 중일 때의 사유(없으면 nil). 이 상태에서 저장하면 깨진 파일이 .bak 으로 보존된다.
    var warning: String? { get }
    var fileURL: URL { get }
    /// 디스크에서 다시 읽는다(첫 실행이면 기본값 파일을 만든다). 읽을 수 없으면 기본값 + warning.
    @discardableResult func reload() -> Settings
    /// 검증 → 기존 파일을 .bak 으로 백업 → 원자적 저장. 실패하면 파일과 current 는 그대로. 성공하면 current 를 갱신한다.
    func save(_ settings: Settings) -> ActionResult
}

/// 오버레이에 보내는 화면용 상태
struct SlotView: Equatable {
    var id: String
    var name: String
    /// 타일 약어(최대 3자)
    var label: String
    /// 허브 동사: SWITCH / LAUNCH / OPEN / COPY / RUN
    var verb: String
    /// 앱 슬롯의 아이콘 PNG. 없으면 약어를 그린다.
    var iconPNG: Data?
}

struct TabView: Equatable {
    var id: String
    var name: String
    /// 허브 캡션: PINNED / CUSTOM
    var caption: String
    /// 길이 항상 8. 빈 슬롯은 nil
    var slots: [SlotView?]
    /// 이 탭에서 키·방향키가 어느 칸을 고르는지(슬롯별 지정 반영)와 타일 배지에 쓸 키 표기
    var keymap: TabKeymap = .standard
}

struct OverlayState: Equatable {
    var tabs: [TabView]
    var activeTab: Int
    var alpha: Double
    var radius: Int
    /// 링 바깥 반지름과 중앙 원 반지름(pt). 이 구조체의 기본값은 테스트 편의용이며 설정 기본값과 무관하다(`Deck` 이 항상 설정 값을 명시해 넘긴다).
    var ringRadius: Int = 250
    var centerRadius: Int = 112
    /// 중앙 원 테두리 굵기(pt)
    var centerBorder: Int = 4
    /// 오버레이를 닫는 키(설정의 닫기 키)의 물리 키코드. Esc 는 늘 닫는다.
    var closeKeyCodes: Set<UInt16> = [KeyCode.q]
    /// 오버레이 테마
    var theme: OverlayTheme = .pie
    /// 파이 테마의 선택된 앱 이름 표시 위치
    var namePlacement: OverlayNamePlacement = .top
    /// 1~8 숫자(오비트는 번호 배지) 표시 여부
    var showNumbers: Bool = true
    /// 본체 색 테마 / 포커스 표현 방식 / 포커스 색(`#RRGGBB`)
    var bodyTheme: OverlayBody = .darkGray
    var focusStyle: FocusStyle = .flat
    var focusHex: String = FocusColors.defaultHex
    /// 오비트 타일 아래 앱 이름 라벨 표시 여부
    var showTileLabels: Bool = true
    /// 앱 박스·중앙 원 뒤에 불투명한 바닥판을 깔지 여부
    var solidBacking: Bool = true
    /// 중앙 원 안 이름의 글자 굵기와 크기(pt; 0 = 자동)
    var centerNameWeight: NameWeight = .medium
    var centerNameSize: Int = 0
    /// 클리어 글라스 본체의 틴트 색 `#RRGGBB`
    var glassTintHex: String = GlassTints.defaultHex
    /// 포커스 색 불빛(글로우) 표시 여부
    var focusGlow: Bool = true
}

/// 설정 + 런타임 데이터(아이콘)를 오버레이 상태로 풀고, 슬롯을 실행한다. 구현: Core
protocol DeckProviding: AnyObject {
    /// 표시 직전에 부른다. 이 상태를 보낸 뒤에야 execute 가 그 상태 기준으로 동작한다(commit 의미).
    func buildState() async -> OverlayState
    /// 마지막으로 buildState 가 돌려준 상태 기준으로 (tabId, slotIndex) 의 액션을 실행한다.
    func execute(tabId: String, slotIndex: Int) async -> ActionResult
    /// 그 슬롯이 실행하는 액션(실행 뒤 이전 앱 복귀 여부 판단용). 빈 슬롯이면 nil
    func action(tabId: String, slotIndex: Int) -> Action?
}

/// 전역 단축키. 구현: Core (Carbon RegisterEventHotKey)
protocol ShortcutRegistering: AnyObject {
    /// 등록하고 성공 여부를 돌려준다. 잘못된 가속키 문자열이면 실패. 이전 등록은 먼저 해제한다.
    func register(_ accelerator: String, handler: @escaping () -> Void) -> ActionResult
    func unregister()
    /// 현재 등록된 가속키(없으면 nil)
    var registered: String? { get }
}
