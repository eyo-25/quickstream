import AppKit
import SwiftUI

/// 오버레이 창 수명 관리. 화면 상태·키 동작은 OverlayModel, 그리기는 OverlayView.
final class OverlayController: NSObject, NSWindowDelegate {
    /// 첫 생성 때의 임시 크기. 표시할 때마다 디스플레이 전체로 다시 맞춘다.
    private static let initialSize = NSSize(width: 800, height: 600)

    var onRun: ((_ tabId: String, _ slotIndex: Int) -> Void)?
    var onClose: ((_ restorePrevious: Bool) -> Void)?
    var onResignKey: (() -> Void)?

    /// 시험이 컨트롤러 수준 가드(숨김 상태 입력 차단)를 모델 쪽에서 직접 두드릴 수 있게 internal 로 둔다
    let model = OverlayModel()
    private let panel: OverlayPanel
    private(set) var isVisible = false
    /// show/hide 마다 새 토큰을 받아, 페이드아웃이 끝나기 전에 다시 표시되면 낡은 완료 콜백이 창을 내리지 못하게 한다
    private var fadeGate = OverlayFadeGate()
    /// 다른 앱으로 포커스가 넘어가면 스스로 숨는다. 시험(`--keep-open`)에서만 끈다 — 자동화 환경은 포커스를 계속 빼앗는다.
    var hidesOnResign = true

    override init() {
        panel = OverlayPanel(size: Self.initialSize)
        super.init()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        // 페이드아웃 중에는 창이 아직 키이므로, 숨김 상태의 입력(키·클릭)은 실행으로 새지 않게 막는다
        panel.onKeyDown = { [weak self, model] in self?.isVisible == true ? model.handleKeyDown($0) : true }
        panel.onKeyUp = { [weak self, model] in self?.isVisible == true ? model.handleKeyUp(keyCode: $0) : true }
        model.onRun = { [weak self] tabId, index in
            guard self?.isVisible == true else { return }
            self?.onRun?(tabId, index)
        }
        model.onClose = { [weak self] restore in
            guard self?.isVisible == true else { return }
            self?.onClose?(restore)
        }
        // 표시 중에 디스플레이 구성(모니터 연결·해상도·메뉴바)이 바뀌면 창 프레임과 링 중심이 낡으므로 조용히 내린다.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.hide(fade: false)
            self.onResignKey?()
        }
    }

    /// 시험 전용: 시스템 입력 합성(접근성 권한 필요)이 막힌 환경에서 패널의 sendEvent → 키 라우터 경로를 그대로 태운다.
    /// `--keep-open` 실행에서만 AppController 가 연결한다.
    func sendTestKey(keyCode: UInt16, down: Bool, shift: Bool = false) {
        guard let event = NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        ) else { return }
        panel.sendEvent(event)
    }

    /// 점에서 가장 가까운 frame 의 인덱스. 가장자리(위·오른쪽 포함)는 거리 0 이라 "안"으로 본다.
    /// 어느 frame 에도 없으면 frame 까지 거리가 가장 짧은 것, 동률이면 앞선 것. frames 가 비면 nil.
    static func nearestFrameIndex(to point: NSPoint, frames: [NSRect]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, frame) in frames.enumerated() {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// 창은 디스플레이 전체(`screen`)를 덮고, 링 중심은 그 디스플레이 visibleFrame 의 중앙이다.
    /// 링 중심은 SwiftUI 좌표(좌상단 원점, 창 기준)로 돌려준다.
    static func placement(screen: NSRect, visible: NSRect) -> (frame: NSRect, ringCenter: CGPoint) {
        (screen, CGPoint(x: (visible.midX - screen.minX).rounded(), y: (screen.maxY - visible.midY).rounded()))
    }

    /// 작은 화면에서 큰 링과 위쪽 이름이 화면 밖으로 잘리지 않게 링 반지름을 visibleFrame 에 맞춰 줄인다(이름 자리 56pt 확보).
    /// 링 하한보다 작게는 줄이지 않는다.
    static func fittingRing(_ ring: Int, visible: NSRect) -> Int {
        let limit = Int(min(visible.height, visible.width) / 2) - 56
        return min(ring, max(limit, Limits.ringRange.lowerBound))
    }

    /// 마우스가 있는 디스플레이 전체를 덮는 키 윈도우로 표시한다. 링은 그 디스플레이 visibleFrame 중앙에 그린다.
    func show(_ state: OverlayState) {
        let mouse = NSEvent.mouseLocation
        let frames = NSScreen.screens.map(\.frame)
        // Electron 의 getDisplayNearestPoint 와 같게: 커서가 위·오른쪽 가장자리에 있어도 가장 가까운 화면을 고른다
        let screen = Self.nearestFrameIndex(to: mouse, frames: frames).map { NSScreen.screens[$0] } ?? NSScreen.main ?? NSScreen.screens.first
        var state = state
        if let screen {
            state.ringRadius = Self.fittingRing(state.ringRadius, visible: screen.visibleFrame)
        }
        model.present(state)
        if let screen {
            let placed = Self.placement(screen: screen.frame, visible: screen.visibleFrame)
            model.ringCenter = placed.ringCenter
            panel.setFrame(placed.frame, display: false)
        }

        isVisible = true
        // 진행 중인 페이드아웃은 토큰이 낡아져 완료 콜백이 창을 내리지 못한다
        _ = fadeGate.begin()
        let animate = !Motion.reduced
        // 페이드아웃 도중 다시 오면 현재 투명도에서 이어서 올라온다
        let startAlpha: CGFloat = panel.isVisible ? panel.alphaValue : 0
        if animate {
            panel.alphaValue = startAlpha
        } else {
            // 직접 대입은 진행 중인 페이드아웃 애니메이터를 취소하지 못해 투명한 채 입력만 가로채는 창이 남을 수 있다. 길이 0 의 애니메이터로 덮는다.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        }
        // 앱 전체를 활성화하지 않는다: `activate` 는 이 앱의 모든 창을 앞으로 올려, 다른 앱 뒤에 있던 설정 창이 오버레이와 함께 올라온다.
        // 패널이 nonactivatingPanel 이라 활성화 없이도 키 창이 되어 키 입력을 받고, 앞에 있던 앱은 앞에 그대로 남는다.
        panel.makeKeyAndOrderFront(nil)
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayMotion.fadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// `fade == false` 는 다른 앱이 앞에 온 경우처럼 즉시 내려야 할 때. 호출 즉시 isVisible 는 false 가 된다.
    func hide(fade: Bool = true) {
        // orderOut 이 windowDidResignKey 를 부르므로 먼저 내려서 onResignKey 가 중복 호출되지 않게 한다
        guard isVisible else { return }
        isVisible = false
        model.releaseAll()
        let token = fadeGate.begin()
        guard fade else {
            model.leaving = false
            panel.orderOut(nil)
            return
        }
        // 동작 줄이기에서는 축소 없이 투명도 페이드만
        model.leaving = !Motion.reduced
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = OverlayMotion.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.fadeGate.shouldOrderOut(token: token, visible: self.isVisible) else { return }
            self.panel.orderOut(nil)
            self.model.leaving = false
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, hidesOnResign else { return }
        hide(fade: false)
        onResignKey?()
    }
}
