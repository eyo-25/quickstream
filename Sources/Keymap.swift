import Foundation

// 슬롯을 고르는 키 배정(순수 로직). 설정 창(보기·편집·충돌 검사)과 오버레이(키 → 칸)가 같은 규칙을 쓴다.
// 한글 입력 상태에서도 되도록 문자가 아니라 물리 키코드(ANSI 배열 기준)로만 다룬다.

/// 슬롯을 방향키로 고르는 8방향. 대각선은 방향키 두 개를 함께 눌러 만든다. `off` 는 방향키로 고르지 않는다.
enum SlotDirection: String, Codable, CaseIterable, Equatable {
    case up
    case upRight = "up-right"
    case right
    case downRight = "down-right"
    case down
    case downLeft = "down-left"
    case left
    case upLeft = "up-left"
    case off

    /// 링 위치(0 = 12시, 시계 방향)의 기본 방향
    static func ring(_ position: Int) -> SlotDirection {
        let order: [SlotDirection] = [.up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft]
        return order.indices.contains(position) ? order[position] : .off
    }

    /// 지금 눌려 있는 방향키 조합이 가리키는 방향. 눌린 키가 없거나 서로 상쇄되면 nil.
    static func held(_ held: Set<ArrowDirection>) -> SlotDirection? {
        slotForArrows(held).map(ring)
    }

    /// 화살표 표기(`off` 는 "없음")
    var label: String {
        switch self {
        case .up: return "↑"
        case .upRight: return "↗"
        case .right: return "→"
        case .downRight: return "↘"
        case .down: return "↓"
        case .downLeft: return "↙"
        case .left: return "←"
        case .upLeft: return "↖"
        case .off: return "없음"
        }
    }
}

/// 슬롯·닫기에 쓸 수 있는 키: 영문자와 숫자(저장은 소문자 한 글자)
enum SlotKey {
    private static let codes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    /// 키패드 숫자 0~9
    private static let keypadCodes: [String: UInt16] = [
        "0": 82, "1": 83, "2": 84, "3": 85, "4": 86, "5": 87, "6": 88, "7": 89, "8": 91, "9": 92,
    ]

    /// 한 글자 영문자/숫자면 저장 형태(소문자)로, 아니면 nil
    static func normalize(_ text: String) -> String? {
        let lowered = text.lowercased()
        return lowered.count == 1 && codes[lowered] != nil ? lowered : nil
    }

    /// 이 키로 인식하는 물리 키코드(숫자는 키패드 포함)
    static func keyCodes(for key: String) -> [UInt16] {
        guard let main = codes[key] else { return [] }
        return [main] + (keypadCodes[key].map { [$0] } ?? [])
    }

    /// 눌린 물리 키코드의 글자(영문자·숫자 윗줄·키패드 숫자). 해당 없으면 nil.
    static func character(forKeyCode code: UInt16) -> String? {
        codes.first { $0.value == code }?.key ?? keypadCodes.first { $0.value == code }?.key
    }

    /// 링 위치(0~7)의 기본 키: 숫자 1~8. 칸에 슬롯이 있든 없든 늘 그 칸을 고른다.
    static func defaultKey(position: Int) -> String { String(position + 1) }

    /// 칸 번호 키(숫자 1~8)인가. 슬롯에 추가로 지정하는 키는 이 숫자를 쓸 수 없다.
    static func isPositionDigit(_ key: String) -> Bool {
        (0..<Limits.slots).contains { defaultKey(position: $0) == key }
    }

    /// 화면 표기(대문자)
    static func display(_ key: String) -> String { key.uppercased() }
}

/// 한 탭에서 실제로 통하는 키 배정. 오버레이가 키 입력을 칸으로 바꾸고 타일 배지를 그리는 데 쓴다.
struct TabKeymap: Equatable {
    /// 물리 키코드 → 링 위치
    var keys: [UInt16: Int]
    /// 방향 → 링 위치
    var directions: [SlotDirection: Int]
    /// 링 위치별 키 표기(대문자). 키가 없으면 빈 문자열. 길이 8.
    var keyLabels: [String]

    /// 아무것도 지정하지 않았을 때(숫자 1~8, 링 위치 방향)
    static let standard = Keymap.build(slots: [], closeKey: "q")
}

enum Keymap {
    /// 슬롯 배열(인덱스 = 링 위치, nil = 빈 칸)과 닫기 키로 실제 배정을 정한다.
    /// 키: 칸 번호 숫자(1~8)는 늘 그 칸을 고르고(빈 칸이면 선택만), 슬롯에 추가로 지정한 키(`Slot.key`)가 그 슬롯을 하나 더 고른다.
    /// 닫기 키는 어떤 칸도 가져가지 못한다(닫기 키가 숫자면 그 칸은 번호 키를 잃는다). 겹치면 앞선 것이 이긴다: 번호 키 → 추가 키(앞 칸 먼저).
    /// 방향: ① 사용자가 지정한 방향 ② 칸에 슬롯이 있으면 링 방향 ③ 빈 칸의 링 방향(선택만 하게). 먼저 가져간 쪽이 이긴다.
    /// 설정 검증이 겹침을 막으므로 정상 설정에서는 부딪히지 않는다(그래도 결과가 일정하게 정해 둔다).
    static func build(slots: [Slot?], closeKey: String) -> TabKeymap {
        let cells = (0..<Limits.slots).map { $0 < slots.count ? slots[$0] : nil }

        var takenKeys: Set<String> = [closeKey]
        var positionOfKey: [String: Int] = [:]
        var digitOf: [Int: String] = [:]
        for p in 0..<Limits.slots {
            let digit = SlotKey.defaultKey(position: p)
            if takenKeys.insert(digit).inserted { positionOfKey[digit] = p; digitOf[p] = digit }
        }
        for p in 0..<Limits.slots {
            if let extra = cells[p]?.key.flatMap(SlotKey.normalize), takenKeys.insert(extra).inserted { positionOfKey[extra] = p }
        }

        var directionOf: [Int: SlotDirection] = [:]
        var takenDirections = Set<SlotDirection>()
        func claimDirection(_ position: Int, _ direction: SlotDirection) {
            if direction != .off, takenDirections.insert(direction).inserted { directionOf[position] = direction }
        }
        for p in 0..<Limits.slots {
            if let direction = cells[p]?.direction { claimDirection(p, direction) }
        }
        // 방향을 `off` 로 끈 슬롯은 기본 방향도 가져가지 않는다
        for p in 0..<Limits.slots where cells[p] != nil && cells[p]?.direction == nil {
            claimDirection(p, SlotDirection.ring(p))
        }
        for p in 0..<Limits.slots where cells[p] == nil {
            claimDirection(p, SlotDirection.ring(p))
        }

        var keys: [UInt16: Int] = [:]
        for (key, position) in positionOfKey {
            for code in SlotKey.keyCodes(for: key) { keys[code] = position }
        }
        var directions: [SlotDirection: Int] = [:]
        for (position, direction) in directionOf { directions[direction] = position }
        // 타일 배지에는 칸 번호 키(숫자)를 보인다. 닫기 키로 번호를 잃은 칸은 배지가 없다.
        return TabKeymap(keys: keys, directions: directions, keyLabels: (0..<Limits.slots).map { digitOf[$0].map(SlotKey.display) ?? "" })
    }


    /// 칸에 추가로 지정한 키(없으면 nil). 형식이 틀린 값은 지정 없음으로 본다.
    static func extraKey(_ slot: Slot) -> String? {
        slot.key.flatMap(SlotKey.normalize)
    }

    /// 칸이 지금 쓰는 방향(지정값, 없으면 링 방향). `off` 면 방향키로 고르지 않는다.
    static func effectiveDirection(_ slot: Slot, position: Int) -> SlotDirection {
        slot.direction ?? SlotDirection.ring(position)
    }
}
