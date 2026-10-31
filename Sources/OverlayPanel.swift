import AppKit

/// 테두리 없는 투명 패널. 키 입력은 first responder 를 거치지 않고 sendEvent 에서 먼저 가로챈다.
/// (SwiftUI 호스팅 뷰가 Tab 을 포커스 이동에 쓰거나 키를 삼키는 일을 막고, 한글 입력 상태에서도 물리 키코드로 받기 위해)
final class OverlayPanel: NSPanel {
    var onKeyDown: ((OverlayKeyEvent) -> Bool)?
    var onKeyUp: ((UInt16) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 디스플레이 전체를 덮어야 하므로 AppKit 이 메뉴바 아래로 밀어 넣지 않게 한다(링 위치는 visibleFrame 기준으로 따로 계산).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // 조각 모양이 불규칙하고 투명하므로 창 그림자는 쓰지 않는다. 조각이 SwiftUI 그림자를 직접 그린다.
        hasShadow = false
        // 마우스 이벤트는 항상 받는다(기본값이지만 조각 밖 클릭 의미를 코드에 명시). 투명 픽셀 통과 여부는 이 값과 별개다.
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            let key = OverlayKeyEvent(
                keyCode: event.keyCode,
                isRepeat: event.isARepeat,
                option: event.modifierFlags.contains(.option),
                command: event.modifierFlags.contains(.command),
                control: event.modifierFlags.contains(.control),
                shift: event.modifierFlags.contains(.shift)
            )
            if onKeyDown?(key) == true { return }
        case .keyUp:
            if onKeyUp?(event.keyCode) == true { return }
        default:
            break
        }
        super.sendEvent(event)
    }
}
