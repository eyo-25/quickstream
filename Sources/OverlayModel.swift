import AppKit
import Combine

/// 오버레이 움직임의 수치와 순수 계산. 뷰·컨트롤러가 같은 값을 쓰고, 창 없이도 불변식을 테스트할 수 있다.
enum OverlayMotion {
    /// 링 타일이 12시부터 차례로 튀어 오르는 간격(8슬롯 마지막 타일 지연 ≈ 98ms)
    static let appearStep = 0.014
    /// 탭 전환 때 새 타일이 차례로 오르는 간격(등장보다 짧게)
    static let tabStep = 0.010
    /// `Motion.chewy` 의 스프링 상수(Motion.swift 의 값과 같아야 한다 — 거기서 숫자를 노출하지 않아 복제)
    static let chewyResponse = 0.30
    static let chewyDamping = 0.58
    /// chewy 가 목표의 5% 이내로 들어오는 시간 = ln(20) / (ζ·ω), ω = 2π / response. 눈에 띄게 가라앉았다고 보는 기준.
    static let settle = log(20.0) / (chewyDamping * 2 * Double.pi / chewyResponse)
    /// 등장 전체 시간 상한
    static let maxAppearDuration = 0.35
    static let panelLeaving: CGFloat = 0.96
    static let tileFrom: CGFloat = 0.6
    static let hubFrom: CGFloat = 0.85
    /// 선택 조각이 바깥으로 튀어나오는 거리(pt)와 확대 배율
    static let selectedPop: CGFloat = 6
    static let selectedScale: CGFloat = 1.04
    static let pressScale: CGFloat = 0.95
    /// 키보드 실행 확인 모션이 눌려 있는 시간. 실행(onRun)은 이 시간을 기다리지 않는다.
    static let confirmHold = 0.06
    static let fadeIn = 0.12
    static let fadeOut = 0.11

    /// 등장 때 타일 index 의 시작 지연. 동작 줄이기이면 0
    static func appearDelay(index: Int, reduced: Bool = Motion.reduced) -> Double {
        Motion.staggerDelay(index: index, step: appearStep, reduced: reduced)
    }

    /// 슬롯 `count` 개가 모두 자리잡는 시간. 동작 줄이기이면 0(즉시)
    static func appearDuration(slots count: Int, reduced: Bool = Motion.reduced) -> Double {
        guard !reduced, count > 0 else { return 0 }
        return appearDelay(index: count - 1, reduced: false) + settle
    }
}

/// 커서가 실제로 움직였을 때만 hover 로 선택을 바꾸게 하는 판정. 표시·탭 전환 직후에는 기준 좌표가 없어,
/// 커서가 가만히 있는데 뷰가 다시 만들어져 발화하는 hover 이벤트가 키보드 선택을 덮어쓰지 못한다.
struct HoverGate {
    static let minMove: CGFloat = 2
    private var last: CGPoint?

    mutating func reset() { last = nil }

    /// 첫 이벤트는 기준만 기록하고 false. 이후 기준에서 minMove 이상 벗어났을 때만 true(기준 갱신).
    mutating func shouldSelect(at point: CGPoint) -> Bool {
        guard let base = last else {
            last = point
            return false
        }
        guard hypot(point.x - base.x, point.y - base.y) >= Self.minMove else { return false }
        last = point
        return true
    }
}

/// 페이드아웃 도중 다시 표시되는 경쟁 상태를 막는 세대 토큰. show/hide 마다 새 토큰을 받고,
/// 지난 페이드의 완료 콜백은 토큰이 낡았으면 아무것도 하지 않는다.
struct OverlayFadeGate {
    private(set) var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    /// 페이드아웃이 끝났을 때 창을 내려도 되는가: 그 사이 새 show/hide 가 없었고 여전히 숨김 상태여야 한다
    func shouldOrderOut(token: Int, visible: Bool) -> Bool { token == generation && !visible }
}

/// 오버레이의 화면 상태와 키 동작. 창·뷰와 분리해 두어 창 없이도 키 시나리오를 테스트할 수 있다.
final class OverlayModel: ObservableObject {
    @Published private(set) var state: OverlayState?
    @Published private(set) var tabIndex = 0
    @Published var selected = 0 {
        didSet {
            // 호는 가장 짧은 방향으로 도는 연속 각도를 따라간다(8→1 이 반대로 한 바퀴 도는 일이 없게)
            arcAngle = PieGeometry.accumulate(angle: arcAngle, toIndex: selected)
            // 키·숫자·hover 가 전부 이 지점을 거친다. 실제로 다른 값일 때만 중앙 원을 한 번 반짝이고,
            // 표시·탭 전환 직후의 초기 설정(`resetSelection`)은 반짝이지 않게 건너뛴다.
            if selected != oldValue, !settingInitialSelection { hubPulse += 1 }
        }
    }
    /// 선택이 실제로 바뀔 때마다 1씩 오르는 단조 카운터. 뷰가 이 값이 바뀔 때마다 중앙 원의 빛을 처음부터 다시 재생한다.
    @Published private(set) var hubPulse = 0
    private var settingInitialSelection = false
    /// 중앙 원 호의 중심각(도, 12시=0, 시계 방향 +). 누적값이라 0~360 으로 접히지 않는다.
    @Published private(set) var arcAngle = 0.0
    /// 등장 애니메이션 상태. present() 가 내려 두고 뷰가 올린다. Reduce Motion 이면 항상 true
    @Published var appeared = true
    /// 사라지는 중(살짝 축소). 호출 즉시 isVisible=false 가 되므로 입력은 컨트롤러가 막는다
    @Published var leaving = false
    @Published var hovered: Int?
    /// 마우스로 누르고 있는 슬롯
    @Published private(set) var pressedSlot: Int?
    private struct Press {
        let start: ClickTarget
        let target: ClickTarget
        let tabId: String
    }
    private var press: Press?
    /// 진행 중이던 눌림이 무효화됐다. 그 눌림의 마우스 업에서 해제한다.
    private var pressCancelled = false
    /// 키보드로 실행한 슬롯의 짧은 확인 모션(≈60ms)
    @Published private(set) var confirming: Int?
    private var confirmToken = 0

    /// 표시될 때마다 증가 → 뷰가 등장 애니메이션을 다시 재생한다
    @Published private(set) var epoch = 0
    /// 디코딩해 둔 아이콘. 키: 슬롯 id. 디코딩 실패·아이콘 없음은 약어로 그린다. 늦게 바뀌면 뷰가 크로스페이드한다.
    @Published private(set) var icons: [String: NSImage] = [:]

    var onRun: ((_ tabId: String, _ slotIndex: Int) -> Void)?
    var onClose: ((_ restorePrevious: Bool) -> Void)?

    /// 링 중심(창 좌표, 좌상단 원점). 창이 디스플레이 전체라 컨트롤러가 표시할 때마다 visibleFrame 중앙으로 맞춘다.
    @Published var ringCenter = CGPoint(x: 400, y: 300)
    private var arrows = ArrowTracker()
    /// 뷰가 hover 이벤트마다 묻는다. 뷰가 다시 만들어질 때 커서가 가만히 있어도 이벤트가 오므로 움직임만 걸러 낸다.
    var hoverGate = HoverGate()

    var tabs: [TabView] { state?.tabs ?? [] }
    var tab: TabView? { tabs.indices.contains(tabIndex) ? tabs[tabIndex] : nil }

    func present(_ next: OverlayState) {
        state = next
        tabIndex = next.tabs.indices.contains(next.activeTab) ? next.activeTab : 0
        resetSelection()
        arrows.clear() // 숨겨진 사이에 뗀 키의 keyup 은 오지 않는다
        hoverGate.reset()
        icons = [:]
        for tab in next.tabs {
            for case let slot? in tab.slots {
                if let data = slot.iconPNG, let image = NSImage(data: data) { icons[slot.id] = image }
            }
        }
        appeared = Motion.reduced
        leaving = false
        hovered = nil
        // 숨겨진 사이 이전 세션의 제스처는 mouse-up 없이 끊기므로 취소 표시도 남기지 않는다(새 세션의 첫 클릭이 삼켜지지 않게)
        press = nil
        pressCancelled = false
        pressedSlot = nil
        confirming = nil
        epoch += 1
    }

    func moveTab(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        arrows.clear() // 방향키를 누른 채 탭이 바뀌면, 떼는 순간 새 탭의 슬롯이 실행되지 않게 제스처를 버린다
        hoverGate.reset()
        invalidatePress()
        tabIndex = ((tabIndex + delta) % tabs.count + tabs.count) % tabs.count
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabIndex = index
        resetSelection()
        arrows.clear()
        hoverGate.reset()
        invalidatePress()
    }

    /// 표시·탭 전환 때 선택을 1번으로 되돌린다(반짝임 없이).
    private func resetSelection() {
        settingInitialSelection = true
        selected = 0
        settingInitialSelection = false
    }

    /// 중앙 원을 클릭해 닫는다. Esc 와 같이 이전 앱으로 포커스를 돌려준다.
    func closeFromCenter() {
        onClose?(true)
    }

    /// 클릭 결과를 수행한다: 중앙 원 → 닫기, 링 영역 → 그 조각 실행, 링 밖 → 현재 선택된 조각 실행. 빈 슬롯은 `run` 이 걸러 아무 일도 없다.
    func click(_ target: ClickTarget) {
        switch target {
        case .close: closeFromCenter()
        case .slot(let index): run(index)
        case .selected: run(selected)
        }
    }

    /// 눌림 표시 대상: 내용이 있는 조각만. 중앙 원·빈 슬롯은 nil.
    private func pressIndex(for target: ClickTarget) -> Int? {
        guard case .slot(let index) = target, let tab, tab.slots.indices.contains(index), tab.slots[index] != nil else { return nil }
        return index
    }

    /// 누르는 순간 대상을 확정한다: 링 밖(`.selected`)은 그때의 선택 슬롯로 풀어 두어, 누른 뒤 놓기 전에 키·hover 로 선택이 바뀌어도
    /// 눌림 표시와 실행 대상이 어긋나지 않는다. 눌린 탭 id 도 함께 기억한다.
    private func beginPress(_ start: ClickTarget) -> Press {
        let resolved: ClickTarget = start == .selected ? .slot(selected) : start
        let next = Press(start: start, target: resolved, tabId: tab?.id ?? "")
        press = next
        return next
    }

    /// 탭 전환·표시·숨김 때 진행 중인 눌림을 버린다. 그 눌림의 마우스 업은 실행하지 않는다
    /// (링을 누른 채 Tab 을 눌렀을 때 새 탭의 같은 번호 슬롯이 실행되는 일 방지). 눌림이 없었다면 다음 클릭에 영향이 없다.
    private func invalidatePress() {
        if press != nil { pressCancelled = true }
        press = nil
        pressedSlot = nil
    }

    /// 포인터를 누른 채 움직일 때: 처음 누른 영역에 그대로 있는 동안만 확정된 조각이 눌림 표시(쪼그라듦)된다.
    func pointerChanged(start: ClickTarget, current: ClickTarget) {
        if pressCancelled { return }
        let active = press?.start == start ? press! : beginPress(start)
        if let index = pressIndex(for: active.target), current == start, active.tabId == tab?.id {
            if pressedSlot != index { pressedSlot = index }
        } else if pressedSlot != nil {
            pressedSlot = nil
        }
    }

    /// 포인터를 놓을 때: 누른 곳과 놓은 곳이 같은 영역이고 눌림이 무효화되지 않았을 때만, 누를 때 확정한 대상을 실행한다.
    func pointerReleased(start: ClickTarget, end: ClickTarget) {
        defer { press = nil; pressedSlot = nil }
        if pressCancelled {
            pressCancelled = false
            return
        }
        let active = press?.start == start ? press! : beginPress(start)
        guard end == start, active.tabId == (tab?.id ?? "") else { return }
        click(active.target)
    }

    func setPressed(_ index: Int, _ down: Bool) {
        if down { pressedSlot = index } else if pressedSlot == index { pressedSlot = nil }
    }

    func run(_ index: Int) {
        guard let tab, tab.slots.indices.contains(index), tab.slots[index] != nil else { return }
        // 확인 모션은 표시만: onRun 은 바로 부르고, 숨길지는 호출 측이 정한다
        confirming = index
        confirmToken += 1
        let token = confirmToken
        DispatchQueue.main.asyncAfter(deadline: .now() + OverlayMotion.confirmHold) { [weak self] in
            if let self, self.confirmToken == token { self.confirming = nil }
        }
        onRun?(tab.id, index)
    }

    /// 포커스를 잃었다. 실행은 keyup 에서만 일어나므로 포커스를 잃은 뒤 앱이 실행되는 일은 없다.
    func releaseAll() {
        arrows.clear()
        invalidatePress()
    }

    /// 처리한 키면 true(호출 측이 기본 동작을 막는다)
    @discardableResult
    func handleKeyDown(_ event: OverlayKeyEvent) -> Bool {
        guard tab != nil, let action = overlayKeyAction(event) else { return false }
        switch action {
        case .close:
            onClose?(true)
        case .tab(let delta):
            moveTab(delta)
        case .arrow(let direction, let isRepeat):
            // 꾹 눌러 반복되는 입력은 "한 번 더 누름"이 아니다
            if isRepeat { break }
            // 방향키를 함께 누르면 대각선이 된다. 누른 순서와 상관없이 지금 눌린 키 전체로 위치를 정한다.
            if let slot = arrows.press(direction, focused: selected) { selected = slot }
        case .run:
            run(selected)
        case .digit(let index):
            if tab?.slots[index] != nil { run(index) } else { selected = index } // 빈 슬롯: 선택만 해서 허브에 안내
        case .swallow:
            break
        }
        return true
    }

    /// 뗄 때는 선택을 바꾸지 않는다: 두 키를 거의 동시에 떼면 먼저 뗀 쪽 때문에 엉뚱한 슬롯으로 튀기 때문
    @discardableResult
    func handleKeyUp(keyCode: UInt16) -> Bool {
        guard let direction = arrowDirection(keyCode: keyCode) else { return false }
        if let slot = arrows.release(direction) { run(slot) }
        return true
    }
}
