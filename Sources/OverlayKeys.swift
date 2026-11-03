import Foundation

// 오버레이 키 해석(순수 로직). Electron 판 overlayKeys.ts 를 옮긴 것으로, AppKit 에 의존하지 않아 단위 테스트한다.
// 한글 입력 상태에서는 문자(characters)가 'ㅂ' 등으로 바뀌므로 모든 키를 물리 키코드(kVK_*)로만 판단한다.

struct OverlayKeyEvent: Equatable {
    var keyCode: UInt16
    var isRepeat: Bool = false
    var option: Bool = false
    var command: Bool = false
    var control: Bool = false
    var shift: Bool = false
}

enum ArrowDirection: Hashable {
    case up, down, left, right
}

enum OverlayKeyAction: Equatable {
    case close
    case tab(delta: Int)
    case arrow(ArrowDirection, isRepeat: Bool)
    case run
    /// 영문자·숫자 키(키패드 숫자 포함): 어느 칸인지는 탭의 키 배정(`TabKeymap`)으로 정한다
    case key(keyCode: UInt16)
    /// 처리하지 않지만 기본 동작(포커스 이동·경고음)은 막는다
    case swallow
}

enum KeyCode {
    static let q: UInt16 = 12
    static let bracketLeft: UInt16 = 33
    static let bracketRight: UInt16 = 30
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    /// 숫자 1~8 (윗줄). 인덱스 = 슬롯 번호 - 1
    static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28]
    /// 숫자 1~8 (키패드)
    static let keypadDigits: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91]
}

func arrowDirection(keyCode: UInt16) -> ArrowDirection? {
    switch keyCode {
    case KeyCode.up: return .up
    case KeyCode.down: return .down
    case KeyCode.left: return .left
    case KeyCode.right: return .right
    default: return nil
    }
}

/// 지금 눌려 있는 방향키 → 링의 슬롯 인덱스(0 기반, 12시부터 시계 방향). 눌린 키가 없으면 nil.
/// 반대 방향(↑↓, ←→)을 함께 누르면 서로 상쇄된다.
///
///     ↖ 8   ↑ 1   ↗ 2
///     ← 7         → 3
///     ↙ 6   ↓ 5   ↘ 4
func slotForArrows(_ held: Set<ArrowDirection>) -> Int? {
    let vertical = (held.contains(.down) ? 1 : 0) - (held.contains(.up) ? 1 : 0)
    let horizontal = (held.contains(.right) ? 1 : 0) - (held.contains(.left) ? 1 : 0)
    switch (horizontal, vertical) {
    case (0, -1): return 0
    case (1, -1): return 1
    case (1, 0): return 2
    case (1, 1): return 3
    case (0, 1): return 4
    case (-1, 1): return 5
    case (-1, 0): return 6
    case (-1, -1): return 7
    default: return nil
    }
}

/// 눌려 있는 방향키를 기억하고 "이미 포커스된 슬롯의 방향이면 한 번만 눌러도 실행"을 판정한다.
/// - 제스처 = 방향키를 하나도 안 누른 상태에서 시작해 다시 모두 뗄 때까지. 선택은 누를 때마다 즉시 바뀐다.
/// - 실행 여부는 제스처가 끝날 때 한 번만 정한다: 마지막으로 가리킨 슬롯 == 제스처 시작 때 포커스돼 있던 슬롯.
///   대각선을 누르는 도중 거치는 중간 슬롯과 키 간격은 판정에 영향이 없다(끝 슬롯만 본다).
/// - 숨겨진 동안 뗀 키는 keyup 이 오지 않으므로 clear() 로 비운다.
struct ArrowTracker {
    private var held = Set<ArrowDirection>()
    private var focusedAtStart: Int?
    private var lastSlot: Int?

    /// 눌렀다. 지금 눌린 키 전체로 정한 슬롯을 돌려준다(서로 상쇄되거나 배정이 없으면 nil).
    /// focused 는 지금 포커스된 슬롯이며, 제스처의 첫 키를 누를 때의 값만 판정에 쓰인다.
    /// `resolve` 는 눌린 방향키 조합 → 링 위치. 기본은 링 위치의 방향(`slotForArrows`)이고, 슬롯마다 방향을 바꾼 탭은 그 배정을 넘긴다.
    mutating func press(_ direction: ArrowDirection, focused: Int, resolve: (Set<ArrowDirection>) -> Int? = slotForArrows) -> Int? {
        if held.isEmpty { focusedAtStart = focused }
        held.insert(direction)
        let slot = resolve(held)
        if let slot { lastSlot = slot }
        return slot
    }

    /// 뗐다. 마지막 키까지 모두 뗐고 끝 슬롯이 시작 포커스와 같을 때만 그 슬롯(= 실행할 슬롯)을 돌려준다.
    mutating func release(_ direction: ArrowDirection) -> Int? {
        held.remove(direction)
        guard held.isEmpty, let slot = lastSlot else { return nil }
        lastSlot = nil
        return slot == focusedAtStart ? slot : nil
    }

    /// 오버레이를 다시 열었거나, 포커스를 잃었거나, 탭이 바뀌었다: 진행 중인 제스처를 버린다
    mutating func clear() {
        held.removeAll()
        focusedAtStart = nil
        lastSlot = nil
    }
}

/// 키 입력 → 동작. 처리할 키가 아니면 nil(기본 동작을 그대로 둔다).
/// Esc/Enter/Tab/방향키는 수정키와 무관하게, 닫기 키·[ ]·영문자/숫자 키는 ⌥⌘⌃ 없이 눌렀을 때만 처리한다(앱 단축키·전역 호출 키와 충돌 방지).
/// `closeKeyCodes` 는 설정의 닫기 키(기본 Q)의 물리 키코드. Esc 는 늘 닫는다.
func overlayKeyAction(_ event: OverlayKeyEvent, closeKeyCodes: Set<UInt16> = [KeyCode.q]) -> OverlayKeyAction? {
    let plain = !event.option && !event.command && !event.control

    if event.keyCode == KeyCode.escape || (closeKeyCodes.contains(event.keyCode) && plain) { return .close }

    if plain {
        if event.keyCode == KeyCode.bracketLeft { return .tab(delta: -1) }
        if event.keyCode == KeyCode.bracketRight { return .tab(delta: 1) }
    }

    if let direction = arrowDirection(keyCode: event.keyCode) {
        return .arrow(direction, isRepeat: event.isRepeat)
    }

    if event.keyCode == KeyCode.tab { return .tab(delta: event.shift ? -1 : 1) }

    // 꾹 눌러 반복되는 입력으로 앱이 여러 번 실행되면 안 된다
    if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter {
        return event.isRepeat ? .swallow : .run
    }
    if plain, SlotKey.character(forKeyCode: event.keyCode) != nil {
        return event.isRepeat ? .swallow : .key(keyCode: event.keyCode)
    }

    return nil
}
