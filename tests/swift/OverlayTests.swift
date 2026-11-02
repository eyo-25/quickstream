import AppKit
import SwiftUI
import Foundation

// 오버레이 키 라우터·방향키 제스처·모델(창 없이) 테스트. 시나리오는 Electron 판 overlayKeys.test.ts 와 같은 수준이다.

private func key(_ code: UInt16, repeat isRepeat: Bool = false, option: Bool = false, command: Bool = false, control: Bool = false, shift: Bool = false) -> OverlayKeyEvent {
    OverlayKeyEvent(keyCode: code, isRepeat: isRepeat, option: option, command: command, control: control, shift: shift)
}

/// Overlay 처럼 포커스(selected)를 들고 있는 호출 측. 방향키를 누르면 선택이 바뀐다.
private struct FakeOverlay {
    var tracker = ArrowTracker()
    var focus: Int
    init(focus: Int = 0) { self.focus = focus }

    mutating func press(_ direction: ArrowDirection) -> Int? {
        let slot = tracker.press(direction, focused: focus)
        if let slot { focus = slot }
        return slot
    }
    mutating func release(_ direction: ArrowDirection) -> Int? { tracker.release(direction) }
    /// 방향키 하나를 톡 친다: (선택된 슬롯, 뗄 때 실행하라는 슬롯)
    mutating func tap(_ direction: ArrowDirection) -> (selected: Int?, run: Int?) {
        let selected = press(direction)
        return (selected, release(direction))
    }
}

private func sampleState(tabs: Int = 3, activeTab: Int = 0, emptyAt: Set<Int> = [7]) -> OverlayState {
    let views = (0..<tabs).map { t in
        TabView(
            id: "tab\(t)", name: "탭\(t)", caption: "PINNED",
            slots: (0..<8).map { i in
                emptyAt.contains(i) ? nil : SlotView(id: "t\(t)s\(i)", name: "앱\(i)", label: "A\(i)", verb: "LAUNCH", iconPNG: nil)
            }
        )
    }
    return OverlayState(tabs: views, activeTab: activeTab, alpha: 0.74, radius: 40)
}

private final class RunLog {
    var runs: [String] = []
    var closes: [Bool] = []
}

private func makeModel(_ state: OverlayState = sampleState()) -> (OverlayModel, RunLog) {
    let model = OverlayModel()
    let log = RunLog()
    model.onRun = { tab, index in log.runs.append("\(tab):\(index)") }
    model.onClose = { log.closes.append($0) }
    model.present(state)
    return (model, log)
}

private extension CGRect {
    var corners: [CGPoint] { [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)] }
}

func runOverlayTests() {
    section("Overlay keys: 닫기·탭·숫자·Enter")
    checkEqual(overlayKeyAction(key(KeyCode.escape)), .close, "Esc 는 닫기")
    checkEqual(overlayKeyAction(key(KeyCode.q)), .close, "Q 는 닫기(문자가 아니라 물리 키라 한글 입력 상태에서도 같다)")
    checkEqual(overlayKeyAction(key(KeyCode.bracketLeft)), .tab(delta: -1), "[ 는 이전 탭")
    checkEqual(overlayKeyAction(key(KeyCode.bracketRight)), .tab(delta: 1), "] 는 다음 탭")
    checkEqual(overlayKeyAction(key(KeyCode.tab)), .tab(delta: 1), "Tab 은 다음 탭")
    checkEqual(overlayKeyAction(key(KeyCode.tab, shift: true)), .tab(delta: -1), "Shift+Tab 은 이전 탭")
    checkEqual(overlayKeyAction(key(KeyCode.bracketLeft, shift: true)), .tab(delta: -1), "Shift 만 더해진 [ 는 그대로 탭 이동")

    check(overlayKeyAction(key(KeyCode.q, command: true)) == nil, "⌘Q 는 앱 종료 단축키에 맡긴다")
    check(overlayKeyAction(key(KeyCode.q, option: true)) == nil, "⌥Q(전역 호출 키)는 무시")
    check(overlayKeyAction(key(KeyCode.bracketRight, command: true)) == nil, "⌘] 는 무시")
    check(overlayKeyAction(key(KeyCode.digits[2], control: true)) == nil, "⌃3 은 무시")
    checkEqual(overlayKeyAction(key(KeyCode.escape, command: true)), .close, "Esc 는 수정키와 무관하게 닫는다")

    for i in 0..<8 {
        checkEqual(overlayKeyAction(key(KeyCode.digits[i])), .digit(index: i), "숫자 \(i + 1)")
        checkEqual(overlayKeyAction(key(KeyCode.keypadDigits[i])), .digit(index: i), "키패드 숫자 \(i + 1)")
    }
    check(overlayKeyAction(key(25)) == nil, "9 는 무시")
    check(overlayKeyAction(key(29)) == nil, "0 은 무시")

    checkEqual(overlayKeyAction(key(KeyCode.returnKey)), .run, "Enter 는 실행")
    checkEqual(overlayKeyAction(key(KeyCode.keypadEnter)), .run, "키패드 Enter 도 실행")
    checkEqual(overlayKeyAction(key(KeyCode.returnKey, repeat: true)), .swallow, "꾹 누른 Enter 는 실행하지 않는다")
    checkEqual(overlayKeyAction(key(KeyCode.digits[1], repeat: true)), .swallow, "꾹 누른 숫자는 실행하지 않는다")
    check(overlayKeyAction(key(0)) == nil, "관련 없는 키(A)는 기본 동작을 건드리지 않는다")
    check(overlayKeyAction(key(49)) == nil, "Space 는 무시")

    section("Overlay keys: 방향키 → 슬롯")
    checkEqual(overlayKeyAction(key(KeyCode.up)), .arrow(.up, isRepeat: false), "↑")
    checkEqual(overlayKeyAction(key(KeyCode.left, repeat: true)), .arrow(.left, isRepeat: true), "반복 입력은 repeat 로 구분")
    for code in [KeyCode.up, KeyCode.down, KeyCode.left, KeyCode.right] {
        if case .tab? = overlayKeyAction(key(code)) { check(false, "방향키는 탭을 바꾸지 않는다") }
    }
    checkEqual(slotForArrows([.up]), 0, "↑ = 1번")
    checkEqual(slotForArrows([.right]), 2, "→ = 3번")
    checkEqual(slotForArrows([.down]), 4, "↓ = 5번")
    checkEqual(slotForArrows([.left]), 6, "← = 7번")
    checkEqual(slotForArrows([.up, .right]), 1, "↑→ = 2번")
    checkEqual(slotForArrows([.right, .down]), 3, "→↓ = 4번")
    checkEqual(slotForArrows([.down, .left]), 5, "↓← = 6번")
    checkEqual(slotForArrows([.left, .up]), 7, "←↑ = 8번")
    check(slotForArrows([]) == nil, "눌린 키 없음")
    check(slotForArrows([.up, .down]) == nil, "↑↓ 상쇄")
    check(slotForArrows([.left, .right]) == nil, "←→ 상쇄")
    checkEqual(slotForArrows([.up, .down, .right]), 2, "세로가 상쇄되면 남은 → ")

    section("Overlay keys: 방향키 제스처")
    do {
        var o = FakeOverlay(focus: 0)
        let r = o.tap(.up)
        checkEqual(r.selected, 0, "막 연 상태(1번 포커스)의 ↑ 는 1번")
        checkEqual(r.run, 0, "막 연 상태의 ↑ 한 번은 실행")
    }
    do {
        var o = FakeOverlay(focus: 0)
        var r = o.tap(.right)
        checkEqual(r.selected, 2, "→ 는 3번 선택")
        check(r.run == nil, "포커스가 다른 슬롯이면 선택만")
        r = o.tap(.right)
        checkEqual(r.run, 2, "이미 포커스된 3번 방향을 다시 누르면 실행")
    }
    do {
        var o = FakeOverlay(focus: 0)
        o.focus = 4 // 숫자 키·마우스 등으로 5번을 포커스
        checkEqual(o.tap(.down).run, 4, "포커스를 어떻게 옮겼든 그 슬롯의 방향 한 번이면 실행")
    }
    do {
        var o = FakeOverlay(focus: 0)
        check(o.tap(.right).run == nil && o.tap(.up).run == nil && o.tap(.right).run == nil && o.tap(.up).run == nil, "→↑→↑ 는 한 번도 실행하지 않는다")
    }
    do {
        // 시작 포커스 1번에서 ↑→ 로 2번: 거치는 1번 때문에 실행되면 안 된다
        var o = FakeOverlay(focus: 0)
        _ = o.press(.up)
        checkEqual(o.press(.right), 1, "↑→ = 2번 선택")
        check(o.release(.right) == nil, "→ 먼저 뗌: 아직 ↑ 가 눌려 있다")
        check(o.release(.up) == nil, "중간에 거친 1번은 실행되지 않는다")
        checkEqual(o.focus, 1, "떼도 선택은 바뀌지 않는다")
        // 두 번째 제스처(시작 포커스 2번)
        _ = o.press(.up)
        _ = o.press(.right)
        check(o.release(.up) == nil, "한 키를 뗐을 땐 실행하지 않는다")
        checkEqual(o.release(.right), 1, "끝 슬롯 2번 == 시작 포커스 → 마지막 키를 뗄 때 실행")
    }
    for order in [[ArrowDirection.up, .right], [.right, .up]] {
        var o = FakeOverlay(focus: 1)
        _ = o.press(.up)
        _ = o.press(.right)
        check(o.release(order[0]) == nil, "먼저 뗀 키는 실행하지 않는다")
        checkEqual(o.release(order[1]), 1, "어느 키를 먼저 떼도 결과가 같다")
    }
    do {
        var o = FakeOverlay(focus: 0)
        _ = o.press(.up)
        o.tracker.clear()
        check(o.release(.up) == nil, "clear 뒤 늦게 온 keyup 은 실행하지 않는다")
        check(o.release(.up) == nil, "누른 적 없는 키를 떼도 아무 일 없다")
        _ = o.press(.up)
        o.tracker.clear()
        checkEqual(o.press(.right), 2, "clear 뒤에는 눌려 있던 키가 남지 않는다")
    }
    do {
        var o = FakeOverlay(focus: 0)
        _ = o.press(.up); _ = o.press(.right)
        _ = o.release(.up); _ = o.release(.right)
        checkEqual(o.press(.right), 2, "모두 뗀 뒤 한 키만 누르면 이전 대각선이 남지 않는다")
    }
    do {
        var o = FakeOverlay(focus: 0)
        _ = o.press(.right); _ = o.press(.up); _ = o.release(.up)
        checkEqual(o.press(.down), 3, "아직 눌린 →와 새 ↓ 는 합쳐져 4번")
    }

    section("Overlay model: 키 동작")
    do {
        let (m, log) = makeModel()
        checkEqual(m.selected, 0, "표시 직후 선택은 1번")
        check(m.handleKeyDown(key(KeyCode.up)), "방향키는 처리됨")
        check(log.runs.isEmpty, "누르는 동안은 실행하지 않는다")
        check(m.handleKeyUp(keyCode: KeyCode.up), "방향키 keyup 처리됨")
        checkEqual(log.runs, ["tab0:0"], "표시 직후 ↑ 한 번 → 1번 실행(뗄 때)")
    }
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.right))
        m.handleKeyUp(keyCode: KeyCode.right)
        checkEqual(m.selected, 2, "→ 로 3번 선택")
        check(log.runs.isEmpty, "처음엔 선택만")
        m.handleKeyDown(key(KeyCode.right))
        m.handleKeyUp(keyCode: KeyCode.right)
        checkEqual(log.runs, ["tab0:2"], "다시 → 면 3번 실행")
    }
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.up))
        m.handleKeyDown(key(KeyCode.up, repeat: true))
        m.handleKeyDown(key(KeyCode.right))
        m.handleKeyUp(keyCode: KeyCode.up)
        m.handleKeyUp(keyCode: KeyCode.right)
        check(log.runs.isEmpty, "반복 입력은 무시, ↑→ 는 시작 포커스(1번)와 끝(2번)이 달라 실행하지 않음")
        checkEqual(m.selected, 1, "↑→ = 2번 선택")
    }
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.right))
        m.handleKeyDown(key(KeyCode.tab)) // 누른 채 탭 이동 → 제스처 버림
        checkEqual(m.tabIndex, 1, "Tab 으로 다음 탭")
        m.handleKeyUp(keyCode: KeyCode.right)
        check(log.runs.isEmpty, "탭이 바뀐 뒤 방향키를 떼도 실행하지 않는다")
    }
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.up))
        m.releaseAll() // 포커스 잃음
        m.handleKeyUp(keyCode: KeyCode.up)
        check(log.runs.isEmpty, "포커스를 잃은 뒤에는 실행하지 않는다")
        m.handleKeyDown(key(KeyCode.up))
        m.present(sampleState()) // 다시 표시
        m.handleKeyUp(keyCode: KeyCode.up)
        check(log.runs.isEmpty, "다시 표시하면 진행 중이던 제스처를 버린다")
    }
    do {
        let (m, log) = makeModel(sampleState(tabs: 3, activeTab: 2))
        checkEqual(m.tabIndex, 2, "activeTab 으로 시작")
        m.handleKeyDown(key(KeyCode.bracketRight))
        checkEqual(m.tabIndex, 0, "] 는 끝에서 처음으로 이어진다")
        m.handleKeyDown(key(KeyCode.bracketLeft))
        checkEqual(m.tabIndex, 2, "[ 는 처음에서 끝으로 이어진다")
        m.handleKeyDown(key(KeyCode.tab))
        m.handleKeyDown(key(KeyCode.tab, shift: true))
        checkEqual(m.tabIndex, 2, "Tab, Shift+Tab 왕복은 제자리")
        m.handleKeyDown(key(KeyCode.escape))
        m.handleKeyDown(key(KeyCode.q))
        checkEqual(log.closes, [true, true], "Esc/Q 는 이전 앱 복귀를 요청하며 닫는다")
    }
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.digits[2]))
        checkEqual(log.runs, ["tab0:2"], "3 은 3번 슬롯을 즉시 실행")
        m.handleKeyDown(key(KeyCode.digits[7])) // 8번은 빈 슬롯
        checkEqual(log.runs.count, 1, "빈 슬롯은 실행하지 않는다")
        checkEqual(m.selected, 7, "빈 슬롯은 선택만 한다")
        m.handleKeyDown(key(KeyCode.returnKey))
        checkEqual(log.runs.count, 1, "빈 슬롯 선택 상태의 Enter 는 아무것도 실행하지 않는다")
        m.handleKeyDown(key(KeyCode.digits[0], repeat: true))
        checkEqual(log.runs.count, 1, "꾹 누른 숫자는 실행하지 않는다")
        m.selectTab(1)
        checkEqual(m.selected, 0, "탭을 클릭하면 선택이 1번으로 돌아간다")
        m.handleKeyDown(key(KeyCode.returnKey))
        m.handleKeyDown(key(KeyCode.returnKey, repeat: true))
        checkEqual(log.runs, ["tab0:2", "tab1:0"], "Enter 는 선택 슬롯 실행, 반복은 무시")
    }
    do {
        let (m, _) = makeModel()
        m.selected = 5
        m.present(sampleState())
        checkEqual(m.selected, 0, "표시될 때마다 선택은 1번으로")
        check(!m.handleKeyDown(key(0)), "처리하지 않는 키는 false(기본 동작 유지)")
        check(!m.handleKeyUp(keyCode: KeyCode.returnKey), "방향키가 아닌 keyup 은 처리하지 않는다")
    }

    section("Overlay motion: 스태거·수치 불변식")
    do {
        var previous = -1.0
        for i in 0..<8 {
            let delay = OverlayMotion.appearDelay(index: i, reduced: false)
            check(delay > previous, "스태거 지연은 index 순서대로 증가(\(i))")
            previous = delay
            checkEqual(OverlayMotion.appearDelay(index: i, reduced: true), 0, "동작 줄이기이면 지연 0(\(i))")
        }
        checkEqual(OverlayMotion.appearDelay(index: 0, reduced: false), 0, "첫 타일은 지연이 없다")
        check(OverlayMotion.appearDuration(slots: 8, reduced: false) <= OverlayMotion.maxAppearDuration, "8슬롯 등장은 350ms 이내")
        check(OverlayMotion.appearDuration(slots: 8, reduced: false) > 0, "등장 시간은 0 보다 크다")
        checkEqual(OverlayMotion.appearDuration(slots: 8, reduced: true), 0, "동작 줄이기이면 등장 즉시")
        check(OverlayMotion.tabStep < OverlayMotion.appearStep, "탭 전환 스태거는 등장보다 짧다")
        check(OverlayMotion.confirmHold <= 0.06 + 1e-9, "실행 확인 모션은 60ms 이하")
        check(OverlayMotion.fadeIn <= 0.12 + 1e-9 && OverlayMotion.fadeOut <= 0.11 + 1e-9, "창 페이드 시간 상한")
        checkEqual(OverlayMotion.selectedScale, 1.04, "선택 조각 확대 1.04")
        checkEqual(OverlayMotion.selectedPop, 6, "선택 조각은 바깥으로 6pt")
        checkEqual(OverlayMotion.pressScale, 0.95, "눌림 0.95")
    }

    section("Overlay motion: 페이드 세대 토큰")
    do {
        var gate = OverlayFadeGate()
        let hideToken = gate.begin()
        check(gate.shouldOrderOut(token: hideToken, visible: false), "페이드아웃이 방해받지 않으면 창을 내린다")
        _ = gate.begin() // 페이드 도중 다시 show
        check(!gate.shouldOrderOut(token: hideToken, visible: true), "다시 표시되면 낡은 완료 콜백은 창을 내리지 않는다")
        let second = gate.begin() // 다시 hide
        check(!gate.shouldOrderOut(token: hideToken, visible: false), "그 다음 hide 가 있으면 첫 hide 의 콜백은 무시")
        check(gate.shouldOrderOut(token: second, visible: false), "최신 hide 의 콜백만 창을 내린다")
        check(!gate.shouldOrderOut(token: second, visible: true), "보이는 상태면 내리지 않는다")
    }

    section("Overlay motion: 키보드 실행은 지연 없이")
    do {
        let (m, log) = makeModel()
        m.handleKeyDown(key(KeyCode.digits[2]))
        checkEqual(log.runs, ["tab0:2"], "숫자 키 실행은 확인 모션을 기다리지 않고 즉시 호출")
        checkEqual(m.confirming, 2, "실행된 슬롯이 확인 모션 대상")
        m.setPressed(1, true)
        checkEqual(m.pressedSlot, 1, "눌림 기록")
        m.setPressed(3, false)
        checkEqual(m.pressedSlot, 1, "다른 슬롯의 뗌은 눌림을 지우지 않는다")
        m.setPressed(1, false)
        check(m.pressedSlot == nil, "뗌")
        m.present(sampleState())
        check(m.confirming == nil && !m.leaving, "다시 표시되면 확인·사라짐 상태 초기화")
    }

    section("Overlay 가장 가까운 디스플레이 (getDisplayNearestPoint)")
    do {
        let main = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let right = NSRect(x: 1000, y: 0, width: 600, height: 800)
        let above = NSRect(x: 0, y: 800, width: 1000, height: 500)
        let frames = [main, right, above]
        let nearest = { (x: CGFloat, y: CGFloat, f: [NSRect]) in OverlayController.nearestFrameIndex(to: NSPoint(x: x, y: y), frames: f) }
        checkEqual(nearest(500, 400, frames), 0, "안쪽 점")
        checkEqual(nearest(1200, 400, frames), 1, "오른쪽 화면 안쪽")
        // 단독 화면의 맨 위·맨 오른쪽 점은 NSMouseInRect 에 걸리지 않던 자리
        checkEqual(nearest(1000, 800, [main]), 0, "단독 화면의 오른쪽 위 모서리")
        checkEqual(nearest(500, 800, [main]), 0, "단독 화면의 위 가장자리")
        checkEqual(nearest(1600, 400, frames), 1, "오른쪽 끝 가장자리")
        checkEqual(nearest(1700, 400, frames), 1, "화면 밖 오른쪽은 가장 가까운 화면")
        checkEqual(nearest(300, 5000, [main, right]), 0, "화면 위 먼 곳도 가장 가까운 화면")
        checkEqual(nearest(1990, -50, [main, right]), 1, "아래쪽 바깥은 x 로 가까운 화면")
        checkEqual(nearest(900, 1000, [main, right]), 0, "두 화면 중 거리가 짧은 쪽(main)")
        checkEqual(nearest(1100, 1000, [main, right]), 1, "두 화면 중 거리가 짧은 쪽(right)")
        check(nearest(0, 0, []) == nil, "화면이 없으면 nil")
    }

    section("Overlay hover: 커서가 움직였을 때만 선택")
    do {
        var gate = HoverGate()
        check(!gate.shouldSelect(at: CGPoint(x: 100, y: 100)), "리셋 후 첫 이벤트는 무시")
        check(!gate.shouldSelect(at: CGPoint(x: 100, y: 100)), "같은 좌표 반복은 무시")
        check(!gate.shouldSelect(at: CGPoint(x: 101, y: 100)), "2pt 미만 이동은 무시")
        check(gate.shouldSelect(at: CGPoint(x: 103, y: 100)), "2pt 이상 이동하면 허용")
        check(!gate.shouldSelect(at: CGPoint(x: 103, y: 100)), "허용 뒤 같은 좌표는 다시 무시")
        gate.reset()
        check(!gate.shouldSelect(at: CGPoint(x: 103, y: 100)), "탭 변경 리셋 후 같은 좌표는 다시 무시")
        let (m, _) = makeModel()
        _ = m.hoverGate.shouldSelect(at: .zero)
        m.moveTab(1)
        check(!m.hoverGate.shouldSelect(at: CGPoint(x: 50, y: 50)), "모델의 탭 이동은 게이트를 리셋")
        _ = m.hoverGate.shouldSelect(at: .zero)
        m.present(sampleState())
        check(!m.hoverGate.shouldSelect(at: CGPoint(x: 50, y: 50)), "표시는 게이트를 리셋")
    }

    section("Pie 기하: 슬롯 ↔ 각도")
    do {
        for i in 0..<8 { checkEqual(PieGeometry.centerDegrees(index: i), Double(i) * 45, "슬롯 \(i + 1) 중심각") }
        let top = PieGeometry.offset(index: 0, radius: 100)
        check(abs(top.x) < 1e-6 && abs(top.y + 100) < 1e-6, "슬롯 1 은 12시 정중앙")
        let right = PieGeometry.offset(index: 2, radius: 100)
        check(abs(right.x - 100) < 1e-6 && abs(right.y) < 1e-6, "슬롯 3 은 3시(시계 방향)")
        let bottom = PieGeometry.offset(index: 4, radius: 100)
        check(abs(bottom.x) < 1e-6 && abs(bottom.y - 100) < 1e-6, "슬롯 5 는 6시")
        let left = PieGeometry.offset(index: 6, radius: 100)
        check(abs(left.x + 100) < 1e-6 && abs(left.y) < 1e-6, "슬롯 7 은 9시")
    }

    section("Pie 기하: 링 크기에 따른 치수")
    do {
        for (ring, center) in [(160, 40), (250, 112), (320, 200)] {
            let g = PieGeometry(ringRadius: ring, centerRadius: center)
            checkEqual(g.outerRadius, CGFloat(ring), "링 바깥 반지름 \(ring)")
            checkEqual(g.hubRadius, CGFloat(center), "중앙 원 반지름 \(center)")
            checkEqual(g.innerRadius, CGFloat(center + 16), "조각 안쪽 반지름 = 중앙 + 16")
            check(g.iconSize <= 56 && abs(g.iconSize - min(56, g.thickness * 0.45)) < 1e-9, "아이콘 크기는 두께에 맞춰 줄어든다(\(ring))")
            for i in 0..<8 {
                let p = PieGeometry.offset(index: i, radius: g.midRadius)
                checkEqual(g.clickIndex(dx: p.x, dy: p.y), i, "조각 중심은 자기 슬롯(\(ring)/\(i + 1))")
                checkEqual(g.directionIndex(dx: p.x * 3, dy: p.y * 3), i, "먼 바깥도 같은 방향 슬롯(\(ring)/\(i + 1))")
            }
        }
        let clamped = PieGeometry(ringRadius: 9999, centerRadius: 9999)
        checkEqual(clamped.outerRadius, 320, "링 상한")
        checkEqual(clamped.hubRadius, 248, "중앙 원은 링 - 72 까지")
        checkEqual(PieGeometry(ringRadius: 1, centerRadius: 1).outerRadius, 160, "링 하한")
        checkEqual(PieGeometry(ringRadius: 1, centerRadius: 1).hubRadius, 40, "중앙 원 하한")
    }

    section("Pie 기하: 방향 선택과 클릭 영역")
    do {
        let g = PieGeometry(ringRadius: 250, centerRadius: 112)
        func at(_ degrees: Double, _ radius: CGFloat) -> (CGFloat, CGFloat) {
            let a = degrees * Double.pi / 180
            return (CGFloat(sin(a)) * radius, -CGFloat(cos(a)) * radius)
        }
        let near = at(0, 200)
        checkEqual(g.directionIndex(dx: near.0, dy: near.1), 0, "12시 방향은 슬롯 1")
        let far = at(0, 3000)
        checkEqual(g.directionIndex(dx: far.0, dy: far.1), 0, "링 바깥 아주 먼 점도 방향으로 선택")
        let hub = at(0, 111)
        check(g.directionIndex(dx: hub.0, dy: hub.1) == nil, "중앙 원 안은 nil")
        check(g.directionIndex(dx: 0, dy: 0) == nil, "정중앙은 nil")
        let edge = at(90, 112)
        checkEqual(g.directionIndex(dx: edge.0, dy: edge.1), 2, "중앙 원 경계 위는 선택")
        // 섹터 경계 ±22.5°: 양쪽이 서로 다른 슬롯
        let a = at(22, 200), b = at(23, 200), c = at(-22, 200), d = at(-23, 200)
        checkEqual(g.directionIndex(dx: a.0, dy: a.1), 0, "22° 는 슬롯 1")
        checkEqual(g.directionIndex(dx: b.0, dy: b.1), 1, "23° 는 슬롯 2")
        checkEqual(g.directionIndex(dx: c.0, dy: c.1), 0, "-22° 는 슬롯 1")
        checkEqual(g.directionIndex(dx: d.0, dy: d.1), 7, "-23° 는 슬롯 8")
        let wrap = at(359.9, 200)
        checkEqual(g.directionIndex(dx: wrap.0, dy: wrap.1), 0, "360° 직전은 슬롯 1")
        let gapPoint = at(22.5, 200)
        check(g.directionIndex(dx: gapPoint.0, dy: gapPoint.1) != nil, "조각 사이 틈에서도 가장 가까운 조각")

        // 클릭 가능 영역: 중앙 원 반지름 이상 ~ 링 바깥 반지름 이하
        for (label, radius, expected) in [("중앙 원 안쪽", CGFloat(111), false), ("중앙 원 경계", 112, true), ("링 영역", 180, true),
                                          ("링 바깥 경계", 250, true), ("링 바로 밖", 251, false), ("먼 바깥", 3000, false)] {
            let p = at(0, radius) // 축 위라야 경계 반지름이 부동소수 오차 없이 정확하다
            check((g.clickIndex(dx: p.0, dy: p.1) != nil) == expected, "클릭 영역: \(label)")
        }
    }

    section("Pie 기하: 중앙 원 선택 호")
    do {
        checkEqual(PieGeometry.shortestDelta(from: 315, to: 0), 45, "8→1 은 시계 방향 +45°")
        checkEqual(PieGeometry.shortestDelta(from: 0, to: 315), -45, "1→8 은 반시계 -45°")
        checkEqual(PieGeometry.shortestDelta(from: 0, to: 180), 180, "정반대는 +180")
        checkEqual(PieGeometry.shortestDelta(from: 180, to: 0), 180, "정반대는 어느 쪽에서든 +180")
        checkEqual(PieGeometry.shortestDelta(from: 90, to: 90), 0, "같은 각도는 0")
        checkEqual(PieGeometry.shortestDelta(from: 720, to: 45), 45, "누적 각도가 커도 최단 델타")
        var angle = 0.0
        for index in [7, 6, 0, 1] { angle = PieGeometry.accumulate(angle: angle, toIndex: index) }
        checkEqual(angle, 45, "1→8→7→1→2 를 최단으로 따라가면 -45, -90, 0, 45 를 지나 45°(반대로 한 바퀴 돌지 않음)")
        angle = PieGeometry.accumulate(angle: 315, toIndex: 0)
        checkEqual(angle, 360, "8→1 은 315° → 360° 방향")
        for i in 0..<8 { checkEqual(PieGeometry.centerDegrees(index: i), Double(i) * 45, "슬롯→중심각(\(i + 1))") }
        for (ring, center) in [(160, 40), (250, 112), (320, 200)] {
            for border in [1, 4, 12] {
                let g = PieGeometry(ringRadius: ring, centerRadius: center, centerBorder: border)
                let range = g.arcRange(center: 90)
                check(abs((range.start + range.end) / 2 - 90) < 1e-9, "호는 중심각 대칭(\(center)/\(border))")
                let gapAngle = asin(Double(PieGeometry.gap / 2 / g.hubBorderRadius)) * 180 / Double.pi
                let capAngle = asin(Double(g.hubBorder / 2 / g.hubBorderRadius)) * 180 / Double.pi
                check(g.arcHalfSpan > 0 && g.arcHalfSpan < 22.5, "호 반폭은 양수이고 조각 반폭보다 작다(\(center)/\(border))")
                check(abs(g.arcHalfSpan + capAngle + gapAngle - 22.5) < 1e-9, "둥근 끝까지 그려도 조각 사이 틈을 넘지 않는다(\(center)/\(border))")
                checkEqual(g.hubBorder, CGFloat(border), "테두리 굵기(\(center)/\(border))")
                checkEqual(g.hubBorderRadius + g.hubBorder / 2, CGFloat(center), "테두리·호 바깥 가장자리가 원에 닿는다(\(center)/\(border))")
            }
        }
        checkEqual(PieGeometry(ringRadius: 250, centerRadius: 112).hubBorder, 4, "테두리 기본값 4")
        checkEqual(PieGeometry(ringRadius: 250, centerRadius: 112, centerBorder: 0).hubBorder, 1, "테두리 0 → 1 로 보정")
        checkEqual(PieGeometry(ringRadius: 250, centerRadius: 112, centerBorder: 99).hubBorder, 12, "테두리 99 → 12 로 보정")
    }

    section("Pie 기하: 클릭 대상(중앙 원 / 링 / 링 밖)")
    do {
        for (ring, center) in [(160, 40), (250, 112), (320, 200)] {
            let g = PieGeometry(ringRadius: ring, centerRadius: center)
            let hub = g.hubRadius, outer = g.outerRadius
            // 축(12시) 위의 점은 경계 반지름이 부동소수 오차 없이 정확하다
            checkEqual(g.clickTarget(dx: 0, dy: 0), .close, "정중앙은 닫기(\(ring))")
            checkEqual(g.clickTarget(dx: 0, dy: -(hub - 1)), .close, "중앙 원 안쪽은 닫기(\(ring))")
            checkEqual(g.clickTarget(dx: 0, dy: -hub), .slot(0), "중앙 원 경계 위는 링 영역(\(ring))")
            checkEqual(g.clickTarget(dx: 0, dy: -outer), .slot(0), "링 바깥 경계 위는 링 영역(\(ring))")
            checkEqual(g.clickTarget(dx: 0, dy: -(outer + 1)), .selected, "링 바로 밖은 선택된 조각(\(ring))")
            checkEqual(g.clickTarget(dx: 3000, dy: 0), .selected, "먼 바깥도 선택된 조각(\(ring))")
            checkEqual(g.clickTarget(dx: g.midRadius, dy: 0), .slot(2), "3시 방향 링 영역은 슬롯 3(\(ring))")
            checkEqual(g.clickTarget(dx: 0, dy: g.midRadius), .slot(4), "6시 방향 링 영역은 슬롯 5(\(ring))")
        }
    }

    section("Overlay 포인터 규칙: 닫기·링 실행·링 밖은 선택된 조각")
    do {
        let (m, log) = makeModel() // 슬롯 8(index 7)만 비어 있다
        m.pointerReleased(start: .close, end: .close)
        checkEqual(log.closes, [true], "중앙 원에서 눌러 중앙 원에서 놓으면 Esc 와 같이 닫는다")
        check(log.runs.isEmpty, "중앙 원 클릭은 실행하지 않는다")
        m.pointerReleased(start: .slot(2), end: .slot(2))
        checkEqual(log.runs, ["tab0:2"], "링 영역 클릭은 그 방향 조각을 실행")
        m.selected = 4
        m.pointerReleased(start: .selected, end: .selected)
        checkEqual(log.runs, ["tab0:2", "tab0:4"], "링 밖 클릭은 현재 선택된 조각을 실행")
        m.selected = 7
        m.pointerReleased(start: .selected, end: .selected)
        m.pointerReleased(start: .slot(7), end: .slot(7))
        checkEqual(log.runs.count, 2, "선택된·눌린 슬롯이 비어 있으면 아무 일도 없다")
        m.pointerReleased(start: .close, end: .slot(1))
        m.pointerReleased(start: .slot(1), end: .slot(2))
        m.pointerReleased(start: .selected, end: .slot(1))
        checkEqual(log.runs.count, 2, "다른 영역에서 놓으면 취소")
        checkEqual(log.closes, [true], "중앙 원에서 눌러 링에서 놓아도 닫히지 않는다")

        m.selected = 4
        m.pointerChanged(start: .slot(1), current: .slot(1))
        checkEqual(m.pressedSlot, 1, "링 영역을 누르면 그 조각이 눌림 표시")
        m.pointerChanged(start: .slot(1), current: .slot(2))
        check(m.pressedSlot == nil, "다른 영역으로 벗어나면 눌림 해제")
        m.pointerChanged(start: .selected, current: .selected)
        checkEqual(m.pressedSlot, 4, "링 밖을 누르면 선택된 조각이 눌림 표시")
        m.pointerReleased(start: .selected, end: .selected)
        check(m.pressedSlot == nil, "놓으면 눌림 해제")
        m.pointerChanged(start: .close, current: .close)
        check(m.pressedSlot == nil, "중앙 원은 눌림 표시가 없다")
        m.selected = 7
        m.pointerChanged(start: .selected, current: .selected)
        check(m.pressedSlot == nil, "빈 슬롯은 눌림 표시가 없다")
    }

    section("Overlay 포인터: 누르는 순간 대상 확정")
    do {
        // 규칙: 링 밖을 누르면 그 순간의 선택 슬롯이 대상이다. 놓기 전에 선택이 바뀌어도 누를 때의 슬롯이 실행된다.
        let (m, log) = makeModel()
        m.selected = 4
        m.pointerChanged(start: .selected, current: .selected)
        checkEqual(m.pressedSlot, 4, "링 밖을 누르면 그때의 선택 슬롯이 눌림 표시")
        m.selected = 5 // 방향키·숫자키·hover 로 선택이 바뀜
        m.pointerChanged(start: .selected, current: .selected)
        checkEqual(m.pressedSlot, 4, "눌림 표시는 누를 때 확정한 슬롯을 유지")
        m.pointerReleased(start: .selected, end: .selected)
        checkEqual(log.runs, ["tab0:4"], "놓으면 눌렀을 때 선택이던 슬롯이 실행된다")
        check(m.pressedSlot == nil, "놓으면 눌림 해제")
    }

    section("Overlay 포인터: 탭 전환·표시·숨김이 진행 중인 눌림을 무효화")
    do {
        let (m, log) = makeModel()
        m.pointerChanged(start: .slot(2), current: .slot(2))
        checkEqual(m.pressedSlot, 2, "링을 누름")
        m.moveTab(1)
        check(m.pressedSlot == nil, "탭 이동 후 눌림 상태 없음")
        m.pointerReleased(start: .slot(2), end: .slot(2))
        check(log.runs.isEmpty, "눌린 채 Tab 을 눌러도 새 탭의 같은 번호 슬롯이 실행되지 않는다")
        m.pointerReleased(start: .slot(1), end: .slot(1))
        checkEqual(log.runs, ["tab1:1"], "무효화된 눌림 이후의 새 클릭은 정상 실행")

        m.pointerChanged(start: .slot(3), current: .slot(3))
        m.selectTab(0)
        check(m.pressedSlot == nil, "탭 선택 후 눌림 상태 없음")
        m.pointerReleased(start: .slot(3), end: .slot(3))
        checkEqual(log.runs, ["tab1:1"], "selectTab 도 눌림을 무효화")

        m.pointerChanged(start: .slot(2), current: .slot(2))
        m.releaseAll() // hide() 가 부르는 경로
        check(m.pressedSlot == nil, "숨김 경로 후 눌림 상태 없음")
        m.pointerReleased(start: .slot(2), end: .slot(2))
        checkEqual(log.runs, ["tab1:1"], "숨김 경로로 무효화된 눌림은 실행하지 않는다")

        m.pointerChanged(start: .slot(2), current: .slot(2))
        m.present(sampleState())
        check(m.pressedSlot == nil, "다시 표시되면 눌림 상태 없음")

        // 누른 채 숨김(mouse-up 없이 제스처가 끊김) → 다시 표시: 새 세션의 첫 클릭이 삼켜지지 않아야 한다
        m.pointerChanged(start: .slot(2), current: .slot(2))
        m.releaseAll()
        m.present(sampleState())
        m.pointerChanged(start: .slot(6), current: .slot(6))
        m.pointerReleased(start: .slot(6), end: .slot(6))
        checkEqual(log.runs.last, "tab0:6", "숨김·재표시 뒤 첫 클릭이 정상 실행된다")

        m.pointerReleased(start: .slot(5), end: .slot(5))
        checkEqual(log.runs.last, "tab0:5", "눌림이 없을 때 무효화돼도 다음 클릭에는 영향 없다")
    }

    section("Pie 기하: 링 중심 기준 상대 좌표")
    do {
        let g = PieGeometry(ringRadius: 250, centerRadius: 112)
        for center in [CGPoint(x: 400, y: 300), CGPoint(x: 1234, y: 777)] {
            let rel = PieGeometry.relative(CGPoint(x: center.x + 150, y: center.y), ringCenter: center)
            checkEqual(rel.dx, 150, "링 중심이 \(center) 여도 같은 상대 x")
            checkEqual(rel.dy, 0, "상대 y")
            checkEqual(g.clickTarget(dx: rel.dx, dy: rel.dy), .slot(2), "같은 상대 위치는 같은 판정(3시 방향 링)")
            let outside = PieGeometry.relative(CGPoint(x: center.x, y: center.y - 400), ringCenter: center)
            checkEqual(g.clickTarget(dx: outside.dx, dy: outside.dy), .selected, "링 밖 판정도 동일")
        }
    }

    section("Orbit 기하: 타일·배지·라벨 배치(링 160/250/300/320)")
    do {
        func distanceToOrigin(_ r: CGRect) -> CGFloat {
            hypot(max(r.minX, 0, -r.maxX), max(r.minY, 0, -r.maxY))
        }
        for (ring, center) in [(160, 40), (250, 96), (300, 96), (320, 96)] {
            let g = OrbitGeometry(pie: PieGeometry(ringRadius: ring, centerRadius: center))
            let half = g.pie.boxSize / 2
            let box = CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half)
            check(abs(g.tileSide - CGFloat(ring) * 0.27) < 1e-9, "타일 한 변은 링의 27%(\(ring))")
            check(abs(g.orbitRadius - (CGFloat(ring) - OrbitGeometry.restHalfDiagonal * g.tileSide)) < 1e-9, "타일 중심 궤도는 보통 타일 모서리가 링에 닿는 반지름(\(ring))")
            let selectedRects = (0..<8).map { g.tileRect(index: $0, scale: OrbitGeometry.selectedScale) }
            for i in 0..<8 {
                let c = g.tileCenter(index: i)
                var degrees = atan2(Double(c.x), Double(-c.y)) * 180 / Double.pi
                if degrees < 0 { degrees += 360 }
                check(abs(degrees - PieGeometry.centerDegrees(index: i)) < 1e-6 || abs(degrees - PieGeometry.centerDegrees(index: i) - 360) < 1e-6,
                      "타일 중심각은 pie 와 같다(\(ring)/\(i + 1))")
                check(abs(hypot(c.x, c.y) - g.orbitRadius) < 1e-6, "타일 중심은 궤도 위(\(ring)/\(i + 1))")
                check(box.contains(selectedRects[i]) && box.contains(g.badgeRect(index: i)) && box.contains(g.labelRect(index: i, selected: true)),
                      "타일·배지·라벨이 링 영역 상자 안(\(ring)/\(i + 1))")
                check(distanceToOrigin(selectedRects[i]) > g.hub && distanceToOrigin(g.labelRect(index: i, selected: true)) > g.hub,
                      "타일·라벨은 중앙 원 밖(\(ring)/\(i + 1))")
                // 클릭 가능한 링 영역(링 반지름 이하) 안에 타일 전체가 들어온다(선택 확대 시의 모서리는 둥글어 사실상 안에 있다)
                check(g.tileRect(index: i).corners.allSatisfy { hypot($0.x, $0.y) <= g.ring + 1e-6 }, "타일 전체가 링 영역 안(\(ring)/\(i + 1))")
                for j in 0..<8 where j != i {
                    check(!selectedRects[i].intersects(selectedRects[j]), "타일끼리 겹치지 않는다(\(ring)/\(i + 1),\(j + 1))")
                    check(!g.labelRect(index: i, selected: true).intersects(selectedRects[j]), "라벨이 다른 타일과 겹치지 않는다(\(ring)/\(i + 1),\(j + 1))")
                    check(!g.badgeRect(index: i).intersects(selectedRects[j]), "배지가 다른 타일과 겹치지 않는다(\(ring)/\(i + 1),\(j + 1))")
                    check(!g.labelRect(index: i, selected: true).intersects(g.labelRect(index: j, selected: true)), "라벨끼리 겹치지 않는다(\(ring)/\(i + 1),\(j + 1))")
                }
                check(!g.labelRect(index: i, selected: true).intersects(selectedRects[i]), "라벨은 자기 타일 바로 아래(\(ring)/\(i + 1))")
                check(g.labelCenter(index: i).y > g.tileCenter(index: i).y, "라벨은 타일 아래(\(ring)/\(i + 1))")
                check(g.badgeCenter(index: i).x > g.tileCenter(index: i).x && g.badgeCenter(index: i).y < g.tileCenter(index: i).y, "배지는 타일 오른쪽 위(\(ring)/\(i + 1))")
            }
        }
        let g = OrbitGeometry(pie: PieGeometry(ringRadius: 300, centerRadius: 96))
        check(g.tileCorner(setting: 24) < g.tileCorner(setting: 56), "모서리 설정이 클수록 타일 모서리도 크다")
        check(abs(g.tileCorner(setting: 24) - g.tileSide * 0.20) < 1e-9 && abs(g.tileCorner(setting: 56) - g.tileSide * 0.40) < 1e-9, "모서리는 타일 한 변의 20%~40%")
    }

    section("테마: 판정 기하는 공통, 기본은 pie")
    do {
        var state = sampleState()
        checkEqual(state.theme, .pie, "OverlayState 기본 테마는 pie")
        let pie = PieGeometry(state: state)
        state.theme = .orbit
        checkEqual(PieGeometry(state: state), pie, "두 테마가 같은 방향 섹터·중앙 원·링 영역 기하를 쓴다")
        checkEqual(PieGeometry(state: state).clickTarget(dx: 0, dy: -200), .slot(0), "orbit 에서도 링 영역은 눌린 방향 슬롯")
        checkEqual(PieGeometry(state: state).clickTarget(dx: 0, dy: 0), .close, "orbit 에서도 중앙 원은 닫기")
        check(OverlayMetrics.hairlineWidth >= 0.75 && OverlayMetrics.hairlineWidth <= 1, "글라스 헤어라인은 0.75~1pt")
    }

    section("Orbit 기하: 허용되는 모든 링·중앙 원 조합에서 라벨은 늘 타일 아래이고 중앙 원판·타일·라벨과 겹치지 않는다")
    do {
        func distanceToOrigin(_ r: CGRect) -> CGFloat { hypot(max(r.minX, 0, -r.maxX), max(r.minY, 0, -r.maxY)) }
        let rings = Array(160...320)
        var combos = 0
        var minSide = CGFloat.infinity, minWidth = CGFloat.infinity
        var bad: [String] = []
        for ring in rings {
            let range = Limits.centerRange(ring: ring)
            let hubs = Array(range)
            for hub in hubs {
                let g = OrbitGeometry(pie: PieGeometry(ringRadius: ring, centerRadius: hub))
                let half = g.pie.boxSize / 2
                let box = CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half)
                let tag = "링 \(ring)/중앙 \(hub)"
                combos += 1
                minSide = min(minSide, g.tileSide)
                minWidth = min(minWidth, g.labelWidth)
                var ok = g.labelWidth >= OrbitGeometry.minLabelWidth - 0.01 && g.tileSide >= OrbitGeometry.minTileSide - 0.01
                let tiles = (0..<8).map { g.tileRect(index: $0, scale: OrbitGeometry.selectedScale) }
                for i in 0..<8 {
                    ok = ok && g.tileRect(index: i).corners.allSatisfy { hypot($0.x, $0.y) <= g.ring + 0.01 }
                    ok = ok && distanceToOrigin(tiles[i]) > g.hub
                    for selected in [false, true] {
                        let label = g.labelRect(index: i, selected: selected)
                        ok = ok && g.labelCenter(index: i, selected: selected).y > g.tileCenter(index: i).y
                        ok = ok && distanceToOrigin(label) >= g.hub && box.contains(label)
                        ok = ok && !label.intersects(g.tileRect(index: i, scale: selected ? OrbitGeometry.selectedScale : 1))
                        ok = ok && !g.badgeRect(index: i).intersects(label)
                    }
                    let label = g.labelRect(index: i, selected: true)
                    let badge = g.badgeRect(index: i)
                    ok = ok && box.contains(badge) && distanceToOrigin(badge) >= g.hub
                    for j in 0..<8 where j != i {
                        ok = ok && !tiles[i].intersects(tiles[j]) && !label.intersects(tiles[j]) && !label.intersects(g.labelRect(index: j, selected: true))
                        ok = ok && !badge.intersects(tiles[j]) && !badge.intersects(g.labelRect(index: j, selected: true))
                    }
                }
                if !ok { bad.append(tag) }
            }
        }
        // 허용되는 정수 조합 전부: 링 160…320 × 중앙 40…링−72
        var expected = 0
        for ring in 160...320 { expected += Limits.centerRange(ring: ring).count }
        checkEqual(combos, expected, "전수 조합 수(허용 정수 조합 전부)")
        check(bad.isEmpty, "라벨/타일/배지 겹침·범위 위반 조합: \(bad.prefix(12))")
        check(minSide >= OrbitGeometry.minTileSide - 0.01 && minWidth >= OrbitGeometry.minLabelWidth - 0.01, "최악 조합에서도 타일 ≥ 24pt, 라벨 칸 ≥ 60pt (\(minSide)/\(minWidth))")
        let preset = OrbitGeometry(pie: PieGeometry(ringRadius: 300, centerRadius: 96))
        check(abs(preset.tileSide - 81) < 1e-9, "프리셋 300/96 의 타일은 링의 27%")
        let tight = OrbitGeometry(pie: PieGeometry(ringRadius: 160, centerRadius: 88))
        check(tight.tileSide < 160 * 0.27, "띠가 좁으면 타일이 줄어든다(160/88)")
    }

    section("색 합성: 본체 3종 × 포커스 스타일 2종, 레거시 darkGray 보존")
    do {
        typealias RGB = PaletteColors.RGB
        checkEqual(OverlayBody.allCases.count, 3, "본체는 3종(다크 그레이·다크 글라스·클리어 글라스)")
        let standard = PaletteColors.standard
        check(standard == PaletteColors.make(body: .darkGray, style: .flat, hex: "#FAE32E"), "상태 없을 때의 임시 색 = 다크 그레이 + 플랫 노랑 프리셋(레거시 상수 기준)")
        check(standard.surface == Color(white: 0.20) && standard.surfaceHover == Color(white: 0.28) && standard.ink == .white && standard.capsule == Color(white: 0.1),
              "darkGray 의 면·hover·글자·캡슐은 레거시 상수와 같다")
        check(standard.accent == Color(red: 0.98, green: 0.89, blue: 0.18) && standard.selectedGlyph == Color(white: 0.1), "기본 포커스(플랫 노랑)의 면·글자는 레거시 상수와 같다")
        check(standard.plate == nil, "바닥판은 solid 일 때만 있다")
        for body in OverlayBody.allCases {
            let a = PaletteColors.make(body: body, style: .flat, hex: "#FAE32E")
            let b = PaletteColors.make(body: body, style: .neon, hex: "#19F9D8")
            check(a.surfaceRGB == b.surfaceRGB && a.inkRGB == b.inkRGB && a.surface == b.surface, "\(body.rawValue): 본체 면·글자는 포커스와 무관")
            check(a.glowStrength == 0 && b.glowStrength == 1, "\(body.rawValue): 발광은 네온에서만")
            check(a.rimInk == a.rim && b.rimInk == b.accent, "\(body.rawValue): 중앙 원 테두리 하이라이트는 네온에서만 포커스 색(플랫은 본체 광택 색)")
            check(PaletteColors.make(body: body, style: .flat, hex: "zzz") == PaletteColors.make(body: body, style: .flat, hex: FocusColors.defaultHex), "\(body.rawValue): 해석 못 하는 색은 기본 포커스 색")
            check(PaletteColors.make(body: body, style: .flat, hex: "#fae32e") == a, "\(body.rawValue): 소문자 hex 도 같은 색")
            let solid = PaletteColors.make(body: body, style: .flat, hex: "#FAE32E", solid: true)
            let plated = PaletteColors.usesBackingPlate(body: body, solid: true)
            check(plated ? (solid.plate != nil && solid.plate == PaletteColors.spec(for: body).plateColor) : (solid.plate == nil && !solid.solid),
                  "\(body.rawValue): solid 를 켜면 바닥판 여부는 본체가 정한다(다크 그레이만 있고 글라스는 없다)")
            check(PaletteColors.spec(for: body).plate.luminance < PaletteColors.spec(for: body).surface.luminance, "\(body.rawValue): 바닥판은 면 색보다 어둡다")
        }
        check(PaletteColors.spec(for: .darkGlass).plate.luminance < PaletteColors.spec(for: .darkGray).plate.luminance, "darkGlass 바닥판이 더 어둡다")
        check(PaletteColors.spec(for: .darkGray).surface.luminance >= PaletteColors.minSurfaceLuminance, "darkGray 면 휘도 하한")
        check(PaletteColors.spec(for: .darkGlass).surface.luminance >= 0.035, "darkGlass 면 휘도 하한 0.035")
        for body in OverlayBody.allCases {
            let spec = PaletteColors.spec(for: body)
            check(spec.hairlineFloor >= 0.10 && spec.ink == .white, "\(body.rawValue): 헤어라인 하한 0.10 이상, 글씨는 흰색 100%")
            // 검은 바탕 위 보통 면(alpha 0.74)이 바탕과 구분된다: 위 광택 쪽 / 아래 쪽
            let layers = PaletteColors.wedgeLayers(spec: spec, style: .flat, selectedBase: 0, alpha: 0.74, sel: 0)
            let bottom = RGB.black.mixed(with: .black, layers.underlay).mixed(with: spec.surface, layers.face)
            let top = RGB.black.mixed(with: .black, layers.underlay).mixed(with: spec.surface.mixed(with: spec.rim, spec.sheenTop), layers.face)
            check(PaletteColors.contrast(bottom, .black) >= 1.2, "\(body.rawValue): 검은 바탕에서 조각 아래쪽이 구분된다")
            // 클리어 글라스는 가장 투명하게 둔 대신 면 자체의 구분은 약하고(1.4) 틴트 헤어라인이 윤곽을 맡는다
            check(PaletteColors.contrast(top, .black) >= (body == .clearGlass ? 1.35 : 1.5), "\(body.rawValue): 검은 바탕에서 조각 위쪽이 구분된다")
        }
        check(PaletteColors.spec(for: .darkGlass).faceScale < PaletteColors.spec(for: .darkGray).faceScale, "darkGlass 면이 더 투명하다")
        check(PaletteColors.spec(for: .darkGlass).sheenTop > PaletteColors.spec(for: .darkGray).sheenTop, "darkGlass 광택이 더 강하다")
    }

    section("선택 면 글자 대비: 본체 3 × 스타일 2 × 색 격자 512 + 프리셋·극단·저채도 × alpha × 검정·흰 바탕 × 바닥판 유무")
    do {
        typealias RGB = PaletteColors.RGB
        let extremes = ["#000000", "#101040", "#101010", "#FFFFFF", "#FFFFE0", "#F0F0F0", "#808080", "#7A7F85", "#A08C8C", "#303030"]
        // 리뷰에서 4.5 미달로 재현된 중간 명도 색과 저채도 색
        let midtones = ["#666666", "#707070", "#907090", "#807060", "#606060", "#6A6A6A", "#757575", "#8A7A6A", "#6A7A8A", "#7A6A8A", "#5A6A5A", "#707A70"]
        let grays = stride(from: 0x10, through: 0xF0, by: 0x10).map { String(format: "#%02X%02X%02X", $0, $0, $0) }
        // 격자: R·G·B 각 8단계(0,37,73,110,146,182,219,255)
        let levels = [0, 37, 73, 110, 146, 182, 219, 255]
        var grid: [String] = []
        for r in levels { for g in levels { for b in levels { grid.append(String(format: "#%02X%02X%02X", r, g, b)) } } }
        checkEqual(grid.count, 512, "격자 512색")
        let colors = FocusColors.presets.map(\.hex) + extremes + midtones + grays + grid
        var failures: [String] = []
        var samples = 0
        var corrected = 0
        for body in OverlayBody.allCases {
            for style in FocusStyle.allCases {
                for hex in colors {
                    for solid in [false, true] {
                        let c = PaletteColors.make(body: body, style: style, hex: hex, solid: solid)
                        if style == .flat && c.flatFillRGB != c.accentRGB { corrected += 1 }
                        // 면 채움은 뷰가 읽는 값(flatFillRGB). 네온은 본체 면 + 강조색 층이라 포커스 색 그대로다.
                        let fill = style == .flat ? c.flatFillRGB : c.accentRGB
                        for alpha in PaletteColors.alphaSamples {
                            // 면 합성식은 프로덕션 뷰가 읽는 층(wedgeLayers/tileLayers)에서 나온다. 바닥판이 있으면 바탕은 바닥판 하나다.
                            for backdrop in [RGB.black, RGB.white] {
                                let faces = PaletteColors.selectedFaces(spec: c.spec, style: style, accent: fill, selectedBase: c.selectedBase, solid: c.solid,
                                                                        alphas: [alpha], backdrops: [backdrop])
                                samples += 1
                                let worst = faces.map { PaletteColors.contrast(c.selectedGlyphRGB, $0) }.min() ?? 0
                                if worst < PaletteColors.minTextContrast { failures.append("\(body.rawValue)/\(style.rawValue)/\(hex)/solid \(solid)/alpha \(alpha)/바탕 \(backdrop.r): \(String(format: "%.2f", worst))") }
                            }
                        }
                    }
                }
            }
        }
        checkEqual(samples, OverlayBody.allCases.count * 2 * colors.count * 2 * 3 * 2, "대비 표본 수")
        check(failures.isEmpty, "선택 글자 대비 4.5 미달 \(failures.count)건: \(failures.prefix(8))")
        check(corrected > 0, "중간 명도 색은 플랫 채움 보정이 실제로 일어난다")
        // 보정이 필요 없는 색(프리셋 14·기본 노랑)은 채움이 포커스 색 그대로다
        for body in OverlayBody.allCases {
            for solid in [false, true] {
                for hex in FocusColors.presets.map(\.hex) {
                    let c = PaletteColors.make(body: body, style: .flat, hex: hex, solid: solid)
                    check(c.flatFillRGB == c.accentRGB && c.flatFill == c.accent, "프리셋 \(hex)(\(body.rawValue), solid \(solid))은 면 채움 보정 없음")
                }
            }
        }
        // 보정은 채움만 바꾼다: 중앙 원 호·테두리에 쓰는 accent 는 원래 포커스 색 그대로다
        let mid = PaletteColors.make(body: .darkGlass, style: .flat, hex: "#666666")
        check(mid.flatFillRGB != mid.accentRGB && mid.accent == mid.accentRGB.color, "#666666 darkGlass: 채움만 보정되고 accent 는 원래 색")
        // 플랫: 글자는 본체 글자색/부드러운 어두운 색/순수 흰·검정 중 하나
        for hex in colors.prefix(60) {
            let c = PaletteColors.make(body: .darkGray, style: .flat, hex: hex)
            check([c.inkRGB, PaletteColors.softDarkGlyph, .white, .black].contains(c.selectedGlyphRGB), "플랫 글자색은 후보 중 하나(\(hex))")
            check(c.selectedBase == 0, "플랫은 네온 받침이 없다(\(hex))")
        }
        // 네온은 보정 대상이 아니다
        for hex in colors.prefix(60) {
            let n = PaletteColors.make(body: .darkGray, style: .neon, hex: hex)
            check(n.flatFillRGB == n.accentRGB, "네온은 채움 보정 없음(\(hex))")
        }
        let neon = PaletteColors.make(body: .darkGray, style: .neon, hex: "#19F9D8")
        check(neon.selectedBase >= PaletteColors.neonSelectedBase && neon.selectedBase <= PaletteColors.neonSelectedBaseMax, "네온 받침은 0.55~0.95")
        // 층 모델: 네온 선택 받침은 alpha 와 무관, 선택 안 한 면은 alpha 를 따른다. 플랫 선택은 포커스 색 면(0.94)
        let spec = PaletteColors.spec(for: .darkGray)
        let nLow = PaletteColors.wedgeLayers(spec: spec, style: .neon, selectedBase: 0.8, alpha: 0.4, sel: 1)
        let nHigh = PaletteColors.wedgeLayers(spec: spec, style: .neon, selectedBase: 0.8, alpha: 0.95, sel: 1)
        check(abs(nLow.underlay - 0.8) < 1e-12 && abs(nHigh.underlay - 0.8) < 1e-12, "네온 선택 받침은 alpha 와 무관")
        check(nLow.accentTop >= 0.12 && nLow.accentTop <= 0.20 && nLow.accentBottom >= 0.12 && nLow.accentBottom <= 0.20, "네온 pie 강조색은 0.12~0.20 로 아주 옅게")
        let tileNeon = PaletteColors.tileLayers(spec: spec, style: .neon, selectedBase: 0.8, alpha: 0.74, hovered: false, sel: 1)
        check(tileNeon.accentTop >= 0.12 && tileNeon.accentTop <= 0.20 && tileNeon.solid == 0, "네온 orbit 타일: 강조색 옅게, 솔리드 면 없음")
        let flatSel = PaletteColors.wedgeLayers(spec: spec, style: .flat, selectedBase: 0, alpha: 0.4, sel: 1)
        check(abs(flatSel.face - PaletteColors.flatFaceOpacity) < 1e-12, "플랫 선택 조각은 alpha 와 무관하게 포커스 색 면")
        let flatTile = PaletteColors.tileLayers(spec: spec, style: .flat, selectedBase: 0, alpha: 0.74, hovered: false, sel: 1)
        check(abs(flatTile.solid - PaletteColors.flatFaceOpacity) < 1e-12 && flatTile.base == 0 && flatTile.tintTop == 0, "플랫 선택 타일: 유리 층이 빠지고 포커스 색 면")
        let idleTile = PaletteColors.tileLayers(spec: spec, style: .flat, selectedBase: 0, alpha: 0.74, hovered: false, sel: 0)
        check(idleTile.solid == 0 && abs(idleTile.base - 0.38) < 1e-12 && abs(idleTile.tintTop - 0.24) < 1e-12, "darkGray 보통 타일은 레거시 값(받침 0.38·색조 0.24)")
        // 바닥판: 켜면 바탕 표본이 바닥판 하나(대비 모델이 단순해짐)
        let one = PaletteColors.selectedFaces(spec: spec, style: .flat, accent: PaletteColors.RGB(r: 1, g: 0, b: 0), selectedBase: 0, solid: true, alphas: [0.74])
        let two = PaletteColors.selectedFaces(spec: spec, style: .flat, accent: PaletteColors.RGB(r: 1, g: 0, b: 0), selectedBase: 0, solid: false, alphas: [0.74])
        checkEqual(two.count, 2 * one.count, "solid 면 바탕 표본이 검정·흰 두 개에서 바닥판 하나로 줄어든다")
    }

    section("글라스 본체: 바닥판 없는 투명 · 클리어 글라스 틴트 · 글자 대비 4.5(기본 alpha 0.74)")
    do {
        typealias RGB = PaletteColors.RGB
        let glass: [OverlayBody] = [.darkGlass, .clearGlass]
        // 공개 API: 바닥판 여부는 본체가 정한다
        for body in OverlayBody.allCases {
            for solid in [false, true] {
                checkEqual(PaletteColors.usesBackingPlate(body: body, solid: solid), body == .darkGray && solid, "usesBackingPlate(\(body.rawValue), solid \(solid))")
            }
        }
        for body in glass {
            let on = PaletteColors.make(body: body, style: .neon, hex: "#19F9D8", solid: true)
            let off = PaletteColors.make(body: body, style: .neon, hex: "#19F9D8", solid: false)
            check(on == off && on.plate == nil && !on.solid, "\(body.rawValue): solidBacking 과 무관하게 같은 색 합성·바닥판 없음")
        }
        check(PaletteColors.spec(for: .clearGlass) == PaletteColors.spec(for: .clearGlass, glassTint: GlassTints.defaultHex), "틴트 기본 인자는 기본 틴트")
        // 다크 그레이는 틴트·바닥판 변경에 영향받지 않고, 층 상수는 이전 값 그대로다
        let gray = PaletteColors.spec(for: .darkGray)
        check(gray == PaletteColors.spec(for: .darkGray, glassTint: "#FF0000") && gray.rim == gray.ink && gray.rimColor == gray.inkColor, "다크 그레이는 틴트와 무관, 광택·헤어라인 색은 글자색 그대로")
        let grayHub = PaletteColors.orbitHubLayers(spec: gray, alpha: 0.74)
        check(grayHub.base == 0.45 && grayHub.surface == 0 && grayHub.tint == 0.10, "다크 그레이 orbit 중앙 원판 층은 레거시 값(0.45·0·0.10)")
        let grayBadge = PaletteColors.badgeLayers(alpha: 0.74)
        check(grayBadge.base == 0.35 && grayBadge.tint == 0.10, "번호 배지 층은 레거시 값(0.35·0.10)")
        check(PaletteColors.make(body: .darkGray, style: .flat, hex: "#FAE32E", glassTint: "#FF0000") == PaletteColors.standard, "다크 그레이 합성은 틴트를 읽지 않는다")
        check(PaletteColors.make(body: .darkGlass, style: .neon, hex: "#19F9D8", glassTint: "#FF0000") == PaletteColors.make(body: .darkGlass, style: .neon, hex: "#19F9D8"), "다크 글라스 합성도 틴트를 읽지 않는다")

        // 클리어 글라스 틴트: 면은 휘도 상한 아래로 눌리고, 광택·헤어라인(rim)은 틴트를 머금는다
        var faceColors = Set<String>()
        for preset in GlassTints.presets {
            let s = PaletteColors.spec(for: .clearGlass, glassTint: preset.hex)
            check(s.surface.luminance <= PaletteColors.clearSurfaceLuminance + 1e-9 && s.hover.luminance <= PaletteColors.clearHoverLuminance + 1e-9
                  && s.glassTint.luminance <= PaletteColors.clearTintLuminance + 1e-9, "\(preset.label): 면·hover·유리 색조 휘도 상한")
            check(s.hover.luminance >= s.surface.luminance - 1e-9 && s.rim.luminance > s.hover.luminance, "\(preset.label): 면 < hover < 광택 색")
            check(s.ink == .white && s.inkColor == .white, "\(preset.label): 글자는 흰색")
            check(s.surface.luminance > 0.004, "\(preset.label): 면에 색이 남는다(검정으로 죽지 않는다)")
            faceColors.insert(String(describing: s.surface))
        }
        checkEqual(faceColors.count, GlassTints.presets.count, "프리셋 8개는 서로 다른 면 색")
        let sky = PaletteColors.spec(for: .clearGlass, glassTint: "#6FB1FF")
        check(sky.surface.b > sky.surface.r && sky.rim.b > sky.rim.r && sky.rim != .white, "하늘 틴트: 면과 광택 모두 푸른기")
        let pink = PaletteColors.spec(for: .clearGlass, glassTint: "#FF8FC7")
        check(pink.surface.r > pink.surface.g && pink.rim.r > pink.rim.g, "분홍 틴트: 면과 광택 모두 붉은기")
        check(PaletteColors.spec(for: .clearGlass).faceScale < PaletteColors.spec(for: .darkGlass).faceScale, "클리어 글라스 면이 다크 글라스보다 더 투명")
        let a = PaletteColors.make(body: .clearGlass, style: .flat, hex: "#FAE32E", glassTint: "#6FB1FF")
        let b = PaletteColors.make(body: .clearGlass, style: .flat, hex: "#FAE32E", glassTint: "#FF8FC7")
        check(a != b && a.surfaceRGB != b.surfaceRGB && a.glassTint != b.glassTint, "틴트가 다르면 합성 색이 다르다(캐시 키에 틴트 포함)")
        check(PaletteColors.make(body: .clearGlass, style: .flat, hex: "#FAE32E", glassTint: "#6fb1ff") == a, "소문자 틴트도 같은 색")
        check(PaletteColors.make(body: .clearGlass, style: .flat, hex: "#FAE32E", glassTint: "zzz") == a, "해석 못 하는 틴트는 기본 틴트")

        // 글자 대비 격자
        let levels = [0, 128, 255]
        var tintGrid: [String] = []
        for r in levels { for g in levels { for b in levels { tintGrid.append(String(format: "#%02X%02X%02X", r, g, b)) } } }
        let tints = GlassTints.presets.map(\.hex) + ["#202020", "#808080", "#E0E0E0", "#FFFF00", "#FFFF80", "#80FFFF", "#B8F26B", "#E8EEF5"] + tintGrid
        let focusExtremes = ["#000000", "#101040", "#FFFFFF", "#FFFFE0", "#808080", "#7A7F85", "#A08C8C", "#666666", "#907090", "#8A7A6A"]
        let focusColors = FocusColors.presets.map(\.hex) + focusExtremes + tintGrid

        // 선택되지 않은 면: 조각(평소·hover·광택)·중앙 원판·타일·번호 배지·orbit 중앙 원판 위 흰 글자. 알파 0.74 와 상한 0.95 는 검정·흰 바탕 모두 4.5 이상(명시 표본: 설정 기본 알파 0.4 는 아래 어두운 바탕만 보장한다).
        var restFailures: [String] = []
        var restSamples = 0
        for body in glass {
            for hex in (body == .clearGlass ? tints : [GlassTints.defaultHex]) {
                let spec = PaletteColors.spec(for: body, glassTint: hex)
                for alpha in [0.74, Limits.alphaRange.upperBound] {
                    for backdrop in [RGB.black, RGB.white] {
                        let faces = PaletteColors.restFaces(spec: spec, alphas: [alpha], backdrops: [backdrop])
                        restSamples += faces.count
                        let worst = faces.map { PaletteColors.contrast(spec.ink, $0) }.min() ?? 0
                        if worst < PaletteColors.minTextContrast { restFailures.append("\(body.rawValue)/\(hex)/alpha \(alpha)/바탕 \(backdrop.r): \(String(format: "%.2f", worst))") }
                    }
                }
                // 가장 투명한 설정(0.4)도 어두운 바탕에서는 읽힌다(흰 바탕은 수학적으로 한계가 있다: 보고서 참고)
                let dark = PaletteColors.restFaces(spec: spec, alphas: [Limits.alphaRange.lowerBound], backdrops: [.black])
                if (dark.map { PaletteColors.contrast(spec.ink, $0) }.min() ?? 0) < PaletteColors.minTextContrast { restFailures.append("\(body.rawValue)/\(hex)/alpha 0.4/검정") }
            }
        }
        check(restSamples > 1000, "비선택 면 표본이 충분하다")
        check(restFailures.isEmpty, "비선택 면 글자 대비 4.5 미달 \(restFailures.count)건: \(restFailures.prefix(8))")

        // 선택 면: 글라스 2종 × 틴트 × 플랫/네온 × 포커스 색(프리셋 14 + 극단 + 격자) × alpha 3 × 검정·흰 바탕. 프로덕션 selectedFaces/selectionFields 를 그대로 쓴다.
        var selFailures: [String] = []
        var selSamples = 0
        var correctedFlat = 0
        for body in glass {
            for tint in (body == .clearGlass ? tints : [GlassTints.defaultHex]) {
                for style in FocusStyle.allCases {
                    for hex in focusColors {
                        let c = PaletteColors.make(body: body, style: style, hex: hex, solid: true, glassTint: tint)
                        if style == .flat && c.flatFillRGB != c.accentRGB { correctedFlat += 1 }
                        let fill = style == .flat ? c.flatFillRGB : c.accentRGB
                        for alpha in PaletteColors.alphaSamples {
                            for backdrop in [RGB.black, RGB.white] {
                                let faces = PaletteColors.selectedFaces(spec: c.spec, style: style, accent: fill, selectedBase: c.selectedBase, solid: c.solid,
                                                                        alphas: [alpha], backdrops: [backdrop])
                                selSamples += 1
                                let worst = faces.map { PaletteColors.contrast(c.selectedGlyphRGB, $0) }.min() ?? 0
                                if worst < PaletteColors.minTextContrast { selFailures.append("\(body.rawValue)/\(tint)/\(style.rawValue)/\(hex)/alpha \(alpha)/바탕 \(backdrop.r): \(String(format: "%.2f", worst))") }
                            }
                        }
                    }
                }
            }
        }
        check(selSamples > 5000, "선택 면 표본이 충분하다(\(selSamples))")
        check(selFailures.isEmpty, "글라스 선택 글자 대비 4.5 미달 \(selFailures.count)건: \(selFailures.prefix(8))")
        check(correctedFlat > 0, "글라스에서도 중간 명도 색의 플랫 채움 보정이 일어난다")
        // 보정 없는 프리셋 14 는 글라스에서도 채움이 포커스 색 그대로
        for body in glass {
            for hex in FocusColors.presets.map(\.hex) {
                let c = PaletteColors.make(body: body, style: .flat, hex: hex, glassTint: "#B8F26B")
                check(c.flatFillRGB == c.accentRGB, "프리셋 \(hex)(\(body.rawValue))은 면 채움 보정 없음")
            }
        }
        let neonClear = PaletteColors.make(body: .clearGlass, style: .neon, hex: "#19F9D8", glassTint: "#E8EEF5")
        check(neonClear.selectedBase >= PaletteColors.neonSelectedBase && neonClear.selectedBase <= PaletteColors.neonSelectedBaseMax, "클리어 글라스 네온 받침도 0.55~0.95")

        // 미리보기 스타일은 설정의 틴트를 읽어 오버레이와 같은 합성 색을 쓴다
        var o = OverlaySettings()
        o.bodyTheme = .clearGlass
        o.glassTintHex = "#FF8FC7"
        let preview = PiePreviewStyle(o)
        checkEqual(preview.glassTintHex, "#FF8FC7", "미리보기 스타일이 틴트를 읽는다")
        check(preview.colors == PaletteColors.make(body: .clearGlass, style: o.focusStyle, hex: o.focusHex, solid: o.solidBacking, glassTint: "#FF8FC7"), "미리보기 합성 색은 틴트를 포함한 같은 함수")
        var state = sampleState()
        state.bodyTheme = .clearGlass
        state.focusStyle = o.focusStyle
        state.focusHex = o.focusHex
        state.glassTintHex = "#FF8FC7"
        check(state.colors == preview.colors, "오버레이 상태와 미리보기가 같은 색을 읽는다")
    }

    section("이름 위치·미리보기 스타일·제목 글꼴·번호")
    do {
        var state = sampleState()
        state.bodyTheme = .darkGray
        state.focusStyle = .neon
        state.focusHex = "#FF7EDB"
        checkEqual(state.colors.glowStrength, 1, "OverlayState.colors 는 포커스 스타일을 합성한다")
        check(state.colors.body == .darkGray && state.colors.plate != nil, "OverlayState 기본은 solidBacking 켬 → 바닥판이 있다")
        state.bodyTheme = .darkGlass
        check(state.colors.plate == nil && !state.colors.solid, "글라스 본체는 solidBacking 이 켜져 있어도 바닥판이 없다")
        state.bodyTheme = .clearGlass
        check(state.colors.plate == nil && !state.colors.solid, "클리어 글라스도 바닥판이 없다")
        state.bodyTheme = .darkGray
        state.solidBacking = false
        check(state.colors.plate == nil, "OverlayState.solidBacking 을 끄면 바닥판이 없다")
        state.solidBacking = true
        check(state.colors.plate != nil, "OverlayState.solidBacking 이 바닥판을 켠다")
        check(OverlayNameLayout.showsTopName(theme: .pie, placement: .top) && !OverlayNameLayout.showsTopName(theme: .pie, placement: .center)
              && !OverlayNameLayout.showsTopName(theme: .pie, placement: .hidden), "pie 위쪽 이름은 top 일 때만")
        check(OverlayNameLayout.showsCenterName(theme: .pie, placement: .center) && !OverlayNameLayout.showsCenterName(theme: .pie, placement: .top)
              && !OverlayNameLayout.showsCenterName(theme: .pie, placement: .hidden), "pie 중앙 이름은 center 일 때만")
        check(OverlayNameLayout.showsCenterName(theme: .orbit, placement: .top) && !OverlayNameLayout.showsTopName(theme: .orbit, placement: .top)
              && OverlayNameLayout.showsCenterName(theme: .orbit, placement: .hidden), "orbit 은 설정과 무관하게 이름이 허브에")
        for hub in [40, 96, 112, 200] {
            let h = CGFloat(hub)
            let size = OverlayMetrics.centerNameSize(hub: h)
            for border in [0, 4, 12] as [CGFloat] {
                let inner = 2 * (h - border)
                check(OverlayMetrics.centerNameWidth(hub: h, border: border) <= inner && size * 2.6 <= inner, "중앙 이름이 허브 \(hub)/테두리 \(border) 안에 들어간다")
            }
        }

        section("Overlay: 중앙 이름 글자 굵기·크기")
        for hub in stride(from: 40, through: 200, by: 4) {
            let h = CGFloat(hub)
            for border in [0, 4, 12] as [CGFloat] {
                checkEqual(OverlayMetrics.centerNameFontSize(hub: h, border: border, setting: 0), OverlayMetrics.centerNameSize(hub: h), "자동(0)은 기존 값 그대로: 허브 \(hub)/테두리 \(border)")
                for setting in [10, 14, 24, 32] {
                    let size = OverlayMetrics.centerNameFontSize(hub: h, border: border, setting: setting)
                    check(size * 2.6 <= 2 * (h - border) - 4 + 0.0001 && size <= CGFloat(setting) && size > 0, "유효 크기는 원 안: 허브 \(hub)/테두리 \(border)/설정 \(setting)")
                }
            }
        }
        checkEqual(OverlayMetrics.centerNameFontSize(hub: 130, border: 4, setting: 24), 24, "큰 원에서는 설정값이 그대로 쓰인다")
        checkEqual(OverlayMetrics.centerNameFontSize(hub: 130, border: 4, setting: 14), 14, "자동(30pt 상한)보다 작게도 고를 수 있다")
        check(OverlayMetrics.centerNameFontSize(hub: 40, border: 4, setting: 32) < 32, "작은 원에서는 상한이 걸린다")
        checkEqual(OverlayMetrics.centerNameFontSize(hub: 40, border: 4, setting: 32), (2 * 36 - 4) / 2.6, "상한은 (안쪽 지름 − 4) / 2.6")
        let weights = NameWeight.allCases.map(\.fontWeight)
        checkEqual(Set(weights.map { String(describing: $0) }).count, NameWeight.allCases.count, "굵기 5개가 서로 다른 Font.Weight")
        checkEqual(NameWeight.allCases, [.light, .regular, .medium, .semibold, .bold], "NameWeight 선언 순서가 가는 것 → 굵은 것")
        check(weights == [.light, .regular, .medium, .semibold, .bold], "굵기 매핑이 순서대로 굵어진다")
        checkEqual(NameWeight.medium.fontWeight, OverlayMetrics.titleWeight, "기본 굵기(medium)는 기존 titleWeight")

        section("Overlay: 선택 변경 중앙 원 빛")
        let peak = 0.3
        checkEqual(OverlayMetrics.hubPulseOpacity(elapsed: 0, peak: peak), 0, "시작 순간은 0")
        checkEqual(OverlayMetrics.hubPulseOpacity(elapsed: -0.1, peak: peak), 0, "시작 전은 0")
        checkEqual(OverlayMetrics.hubPulseOpacity(elapsed: OverlayMetrics.hubPulseRise, peak: peak), peak, "올라가는 구간 끝이 피크")
        checkEqual(OverlayMetrics.hubPulseOpacity(elapsed: OverlayMetrics.hubPulseDuration, peak: peak), 0, "끝나면 0")
        checkEqual(OverlayMetrics.hubPulseOpacity(elapsed: 5, peak: peak), 0, "끝난 뒤도 0")
        var previous = 0.0
        var rising = true
        var monotone = true
        var inRange = true
        for step in 1..<500 {
            let v = OverlayMetrics.hubPulseOpacity(elapsed: Double(step) * 0.001, peak: peak)
            if v < 0 || v > peak { inRange = false }
            if rising { if v < previous { rising = false; if v > previous + 1e-12 { monotone = false } } }
            else if v > previous + 1e-12 { monotone = false }
            previous = v
        }
        check(inRange && monotone, "곡선은 [0, peak] 안에서 올라갔다 내려가기만 한다")
        check(OverlayMetrics.hubPulseRise < OverlayMetrics.hubPulseDuration - OverlayMetrics.hubPulseRise, "올라가는 구간이 내려가는 구간보다 짧다")
        do {
            let (m, _) = makeModel()
            checkEqual(m.hubPulse, 0, "처음 표시는 반짝이지 않는다")
            m.selected = 0
            checkEqual(m.hubPulse, 0, "같은 값 재설정은 카운터를 올리지 않는다")
            m.handleKeyDown(key(KeyCode.right))
            checkEqual(m.hubPulse, 1, "방향키로 선택이 바뀌면 +1")
            m.handleKeyDown(key(KeyCode.digits[7])) // 빈 슬롯: 선택만 바뀐다
            checkEqual(m.hubPulse, 2, "숫자 키로 선택이 바뀌면 +1")
            m.selected = 3 // hover 와 같은 설정 지점
            checkEqual(m.hubPulse, 3, "hover 처럼 직접 바꿔도 +1")
            m.selected = 3
            checkEqual(m.hubPulse, 3, "같은 슬롯 hover 는 올리지 않는다")
            m.selectTab(1)
            checkEqual(m.hubPulse, 3, "탭 전환 직후 초기 선택(1번)은 올리지 않는다")
            m.selected = 5
            checkEqual(m.hubPulse, 4, "선택을 5로 바꾸면 +1")
            m.present(sampleState())
            checkEqual(m.selected, 0, "다시 표시하면 선택은 1번")
            checkEqual(m.hubPulse, 4, "다시 표시할 때 5→0 초기 설정은 올리지 않는다")
            m.handleKeyDown(key(KeyCode.right))
            checkEqual(m.hubPulse, 5, "초기 설정 뒤 첫 이동은 다시 올린다(억제 플래그가 남지 않는다)")
        }

        var settings = OverlaySettings()
        settings.bodyTheme = .darkGlass
        settings.focusStyle = .neon
        settings.focusHex = "#19F9D8"
        settings.namePlacement = .center
        settings.showNumbers = false
        settings.showTileLabels = false
        settings.solidBacking = true
        let style = PiePreviewStyle(settings)
        check(style.bodyTheme == .darkGlass && style.focusStyle == .neon && style.focusHex == "#19F9D8" && style.namePlacement == .center
              && !style.showNumbers && !style.showTileLabels && style.solidBacking, "미리보기 스타일이 본체·포커스·이름 위치·번호·라벨·바닥판을 읽는다")
        check(style.colors == PaletteColors.make(body: .darkGlass, style: .neon, hex: "#19F9D8", solid: true), "미리보기 합성 색은 오버레이와 같은 함수")
        let defaultStyle = PiePreviewStyle(OverlaySettings())
        check(defaultStyle.colors == PaletteColors.make(body: .darkGlass, style: .neon, hex: "#19F9D8", solid: true), "기본 미리보기 색은 다크 글라스 + 네온 민트(바닥판 켬)")
        // 크기는 테마별로 각자: 미리보기는 현재 테마의 값을 읽는다
        var sizes = OverlaySettings()
        sizes.pieSizes = ThemeSizes(ring: 200, center: 80, border: 5)
        sizes.orbitSizes = ThemeSizes(ring: 290, center: 100, border: 2)
        sizes.theme = .pie
        checkEqual(PiePreviewStyle(sizes).ringSize, 200, "pie 미리보기는 pie 크기")
        sizes.theme = .orbit
        checkEqual(PiePreviewStyle(sizes).ringSize, 290, "orbit 미리보기는 orbit 크기")

        // 제목 글꼴: 가볍게(regular~medium), 약한 자간, 라벨은 regular
        check(OverlayMetrics.titleWeight == .regular || OverlayMetrics.titleWeight == .medium, "제목은 regular~medium")
        check(OverlayMetrics.labelWeight == .regular, "타일 아래 라벨은 regular")
        check(OverlayMetrics.titleTracking >= 0.2 && OverlayMetrics.titleTracking <= 0.4, "제목 자간 0.2~0.4pt")
    }

    section("중앙 원 글로우: 은은함·네온은 한 단계 더 강함")
    do {
        let flat = PaletteColors.standard
        let neon = PaletteColors.make(body: .darkGray, style: .neon, hex: "#19F9D8")
        checkEqual(OverlayMetrics.hubGlowStrength(flat), 1, "플랫 중앙 글로우 배율 1")
        checkEqual(OverlayMetrics.hubGlowStrength(neon), OverlayMetrics.hubGlowNeonBoost, "네온 중앙 글로우는 한 단계 강하다")
        check(OverlayMetrics.hubGlowNeonBoost > 1 && OverlayMetrics.hubGlowNeonBoost <= 2, "네온 배율은 1~2")
        check(OverlayMetrics.hubGlowNear <= 0.2 && OverlayMetrics.hubGlowFar < OverlayMetrics.hubGlowNear && OverlayMetrics.hubInnerGlow <= 0.12, "중앙 글로우는 살짝(가까운 ≤0.2, 넓은 < 가까운, 안쪽 ≤0.12)")
        check(OverlayMetrics.hubGlowFarRadius > OverlayMetrics.hubGlowNearRadius, "넓은 번짐 반경이 더 크다")
    }

    section("이름 라벨 캡슐: 패딩·링과의 간격")
    do {
        check(GlassCapsuleText.horizontalPadding == 10 && GlassCapsuleText.verticalPadding == 4, "캡슐 패딩은 가로 10·세로 4")
        for ring in [160, 250, 300, 320] {
            // pie 위쪽 이름: 글자 크기·위치는 뷰와 같은 식(링 반지름 기준). 캡슐 아래 끝이 링 위(선택 조각이 6pt 튀어나온 것까지)보다 위에 있어야 한다.
            let nameSize = min(34, max(22, CGFloat(ring) * 0.12))
            let offset = max(30, nameSize * 1.4)
            let capsuleHalfHeight = (nameSize * 1.2 + 2 * GlassCapsuleText.verticalPadding) / 2
            check(offset - capsuleHalfHeight > OverlayMotion.selectedPop, "pie 이름 캡슐이 링과 겹치지 않는다(\(ring))")
            // orbit 타일 라벨: 칸 높이(24) 안에 글자+세로 패딩이 들어간다
            let g = OrbitGeometry(pie: PieGeometry(ringRadius: ring, centerRadius: 96))
            check(g.labelFontSize * 1.25 + 2 * GlassCapsuleText.verticalPadding <= OrbitGeometry.labelHeight, "라벨 캡슐 높이 추정이 글자+패딩을 덮는다(\(ring))")
            check(g.labelWidth > 2 * GlassCapsuleText.horizontalPadding + 30, "라벨 캡슐 최대 폭은 패딩 외에 글자 폭을 남긴다(\(ring))")
        }
    }
    section("Overlay 창 배치: 디스플레이 전체 + 링 중심은 visibleFrame 중앙")
    do {
        let screen = NSRect(x: 1440, y: -200, width: 1920, height: 1080)
        let visible = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
        let placed = OverlayController.placement(screen: screen, visible: visible)
        checkEqual(placed.frame, screen, "창 frame 은 디스플레이 전체")
        checkEqual(placed.ringCenter.x, 960, "링 중심 x = visibleFrame 중앙(창 기준)")
        checkEqual(placed.ringCenter.y, (screen.maxY - visible.midY).rounded(), "링 중심 y 는 위에서부터 잰 visibleFrame 중앙")
        let full = OverlayController.placement(screen: screen, visible: screen)
        checkEqual(full.ringCenter, CGPoint(x: 960, y: 540), "visibleFrame 이 같으면 창 한가운데")
    }

    section("Pie 기하: 모서리 반지름 대응")
    do {
        checkEqual(PieGeometry.cornerRadius(setting: Limits.radiusRange.lowerBound), 2, "최소 설정은 2pt")
        checkEqual(PieGeometry.cornerRadius(setting: Limits.radiusRange.upperBound), 18, "최대 설정은 18pt")
        check(PieGeometry.cornerRadius(setting: 40) > 2 && PieGeometry.cornerRadius(setting: 40) < 18, "기본값은 중간")
        checkEqual(PieGeometry.cornerRadius(setting: 0), 2, "범위 밖은 하한으로")
        checkEqual(PieGeometry.cornerRadius(setting: 999), 18, "범위 밖은 상한으로")
    }

    section("Overlay 컨트롤러: 숨김 상태의 입력 차단")
    do {
        // 창을 띄우지 않는다: isVisible == false 인 컨트롤러(= 페이드아웃 중과 같은 상태)로 키 경로를 태운다
        _ = NSApplication.shared
        let c = OverlayController()
        var runs: [String] = []
        var closes = 0
        var resigns = 0
        c.onRun = { tab, index in runs.append("\(tab):\(index)") }
        c.onClose = { _ in closes += 1 }
        c.onResignKey = { resigns += 1 }
        c.model.present(sampleState())
        c.sendTestKey(keyCode: KeyCode.right, down: true)
        c.sendTestKey(keyCode: KeyCode.right, down: false)
        checkEqual(c.model.selected, 0, "숨김 상태의 방향키는 선택을 바꾸지 않는다(onKeyDown 가드)")
        c.sendTestKey(keyCode: KeyCode.digits[2], down: true)
        c.sendTestKey(keyCode: KeyCode.q, down: true)
        check(runs.isEmpty && closes == 0, "숨김 상태의 숫자·Q 는 실행·닫기로 새지 않는다")
        c.model.handleKeyDown(key(KeyCode.digits[1]))
        c.model.handleKeyDown(key(KeyCode.escape))
        check(runs.isEmpty && closes == 0, "모델이 직접 불러도 숨김 상태면 onRun/onClose 를 무시(콜백 가드)")
        c.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        checkEqual(resigns, 0, "숨김 상태의 resign 은 onResignKey 를 중복 호출하지 않는다")
    }

    section("Overlay 컨트롤러: 시험 키 경로 양성 대조")
    do {
        // 위 숨김 검사가 '이벤트가 아예 안 닿아서' 통과하는 것이 아님을 보이는 대조: 같은 방식으로 만든 이벤트가 패널의 onKeyDown 까지 닿는다
        _ = NSApplication.shared
        let panel = OverlayPanel(size: NSSize(width: 100, height: 100))
        var seen: [UInt16] = []
        panel.onKeyDown = { seen.append($0.keyCode); return true }
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: KeyCode.right
        )
        check(event != nil, "시험 키 이벤트가 만들어진다")
        if let event { panel.sendEvent(event) }
        checkEqual(seen, [KeyCode.right], "보이지 않는 패널에서도 sendEvent 가 onKeyDown 에 닿는다")
    }

    section("Overlay: 작은 화면에서 링 맞춤")
    let small = NSRect(x: 0, y: 0, width: 1366, height: 700)   // 메뉴바·Dock 을 뺀 높이 700 → 링 상한 350-56=294
    checkEqual(OverlayController.fittingRing(320, visible: small), 294, "작은 화면에선 링을 줄여 이름이 잘리지 않게 한다")
    checkEqual(OverlayController.fittingRing(250, visible: small), 250, "이미 들어가면 그대로")
    checkEqual(OverlayController.fittingRing(320, visible: NSRect(x: 0, y: 0, width: 1728, height: 1050)), 320, "큰 화면에선 설정 그대로")
    checkEqual(OverlayController.fittingRing(250, visible: NSRect(x: 0, y: 0, width: 400, height: 300)), 160, "아주 작아도 링 하한 아래로는 줄이지 않는다")

    section("Overlay: 중앙 원 클릭으로 닫기")
    let geo = PieGeometry(ringRadius: 250, centerRadius: 112)
    check(geo.isCenter(dx: 0, dy: 0), "정중앙은 중앙 원")
    check(geo.isCenter(dx: 111, dy: 0), "반지름 안쪽은 중앙 원")
    check(!geo.isCenter(dx: 112, dy: 0), "반지름 위(경계)는 중앙 원이 아니다")
    check(!geo.isCenter(dx: 0, dy: -200), "링 영역은 중앙 원이 아니다")
    check(geo.directionIndex(dx: 0, dy: 0) == nil && geo.directionIndex(dx: 0, dy: -200) == 0, "방향 선택은 중앙 원 안에서만 nil")
    for (ring, center) in [(160, 40), (320, 200)] {
        let g = PieGeometry(ringRadius: ring, centerRadius: center)
        check(g.isCenter(dx: g.hubRadius - 1, dy: 0) && !g.isCenter(dx: g.hubRadius, dy: 0), "크기 \(ring)/\(center) 에서도 경계가 hubRadius")
    }
    MainActor.assumeIsolated {
        let (model, _) = makeModel()
        var closed: [Bool] = []
        model.onClose = { closed.append($0) }
        model.closeFromCenter()
        checkEqual(closed, [true], "중앙 닫기는 Esc 와 같이 이전 앱 복원을 요청한다")
    }

    section("Overlay: 포커스 불빛 토글")
    MainActor.assumeIsolated {
        for body in OverlayBody.allCases {
            for style in FocusStyle.allCases {
                for hex in ["#FAE32E", "#19F9D8"] {
                    let on = PaletteColors.make(body: body, style: style, hex: hex)
                    let off = PaletteColors.make(body: body, style: style, hex: hex, glow: false)
                    let label = "\(body.rawValue)/\(style.rawValue)/\(hex)"
                    check(on.glow && !off.glow, "\(label): glow 기본은 켬, glow:false 는 끔")
                    checkEqual(off.glowStrength, 0, "\(label): 끄면 불빛 세기 0")
                    checkEqual(on.glowStrength, style == .neon ? 1 : 0, "\(label): 켜면 네온만 불빛 세기 1(기존 의미)")
                    check(on != off, "\(label): 캐시 키가 glow 를 구분한다(켬/끔은 서로 다른 값)")
                    check(on == PaletteColors.make(body: body, style: style, hex: hex, glow: true), "\(label): 같은 입력은 같은 값")
                    // 대비 보장은 불빛 토글로 흔들리지 않는다
                    check(on.style == off.style && on.selectedGlyphRGB == off.selectedGlyphRGB && on.flatFillRGB == off.flatFillRGB
                          && on.selectedBase == off.selectedBase && on.accentRGB == off.accentRGB && on.solid == off.solid && on.spec == off.spec,
                          "\(label): 스타일·글자색·플랫 채움·네온 받침·강조색은 불빛 켬/끔에서 같다")
                    check(on.rimInk == off.rimInk, "\(label): 중앙 원 테두리 색도 같다")
                    checkEqual(on.wedgeLayers(alpha: 0.6, sel: 1), off.wedgeLayers(alpha: 0.6, sel: 1), "\(label): 조각 층 불투명도는 같다")
                    checkEqual(on.tileLayers(alpha: 0.6, hovered: false, sel: 1), off.tileLayers(alpha: 0.6, hovered: false, sel: 1), "\(label): 타일 층 불투명도는 같다")
                    checkEqual(OverlayMetrics.hubPulsePeak(on), OverlayMetrics.hubPulsePeak(off), "\(label): 펄스 정점의 네온/플랫 구분은 불빛과 무관")
                    checkEqual(OverlayMetrics.hubGlowStrength(off), 0, "\(label): 끄면 중앙 원 번짐 세기 0")
                    check(OverlayMetrics.hubGlowStrength(on) > 0, "\(label): 켜면 중앙 원 번짐 세기 > 0")
                    check(off.tileHalo == Color.clear, "\(label): 끄면 플랫 타일 halo 도 없다")
                    check(on.tileHalo == (style == .neon ? Color.clear : on.accent), "\(label): 켠 halo 는 기존과 같다(플랫만 포커스 색)")
                }
            }
        }
        // 중앙 원 빛(펄스)은 불빛이 꺼지면 층을 그리지 않는다
        let neonOn = PaletteColors.make(body: .darkGray, style: .neon, hex: "#FAE32E")
        let neonOff = PaletteColors.make(body: .darkGray, style: .neon, hex: "#FAE32E", glow: false)
        let flatOn = PaletteColors.make(body: .darkGray, style: .flat, hex: "#FAE32E")
        let flatOff = PaletteColors.make(body: .darkGray, style: .flat, hex: "#FAE32E", glow: false)
        check(HubPulseGlow.isActive(palette: neonOn, reduced: false) && HubPulseGlow.isActive(palette: flatOn, reduced: false), "불빛이 켜지면 펄스를 그린다")
        check(!HubPulseGlow.isActive(palette: neonOff, reduced: false) && !HubPulseGlow.isActive(palette: flatOff, reduced: false), "불빛이 꺼지면 펄스를 그리지 않는다")
        check(!HubPulseGlow.isActive(palette: neonOn, reduced: true), "동작 줄이기면 불빛이 켜져도 펄스를 그리지 않는다")
        // 설정 → 미리보기·오버레이 상태가 같은 값을 읽는다
        var o = OverlaySettings()
        check(PiePreviewStyle(o).focusGlow && PiePreviewStyle(o).colors.glow, "기본 미리보기는 불빛 켬")
        o.focusGlow = false
        check(!PiePreviewStyle(o).focusGlow && !PiePreviewStyle(o).colors.glow, "미리보기가 focusGlow 를 읽는다")
        check(PiePreviewStyle(o).colors == PaletteColors.make(body: o.bodyTheme, style: o.focusStyle, hex: o.focusHex, solid: o.solidBacking, glassTint: o.glassTintHex, glow: false), "미리보기 색은 glow:false 합성과 같다")
        check(PiePreviewStyle(o) != PiePreviewStyle(OverlaySettings()), "불빛 토글은 미리보기 스타일 값을 바꾼다(다시 그려진다)")
        var state = sampleState()
        check(state.colors.glow, "오버레이 상태 기본은 불빛 켬")
        state.focusGlow = false
        check(!state.colors.glow, "오버레이 상태가 focusGlow 를 읽는다")
    }
}
