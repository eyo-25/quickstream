import AppKit
import SwiftUI

/// 앱 전체가 같은 "쫀득한" 움직임을 쓰도록 모은 값. 빠르게 붙고 살짝 튕겼다가 가라앉는 스프링이 기본이다.
/// 시스템의 "동작 줄이기"(Reduce Motion)가 켜져 있으면 움직임을 모두 끈다(nil) — 호출 측은 반드시 `Motion.animation(_:)` 을 거친다.
enum Motion {
    /// 시스템 설정을 매번 읽는다(앱 실행 중에 바꿀 수 있다)
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 쫀득: 등장·선택 강조처럼 눈에 띄는 움직임. 살짝 튕긴다.
    static let chewy = Animation.spring(response: 0.30, dampingFraction: 0.58)
    /// 짧고 단단한 반응: 눌림·hover·작은 전환
    static let snap = Animation.spring(response: 0.20, dampingFraction: 0.72)
    /// 부드럽게 가라앉는 큰 이동: 탭 전환·패널 이동
    static let soft = Animation.spring(response: 0.42, dampingFraction: 0.80)
    /// 사라질 때: 튕기지 않고 빠르게
    static let exit = Animation.easeIn(duration: 0.12)

    /// 동작 줄이기가 켜져 있으면 nil(= 애니메이션 없음), 아니면 그대로
    static func animation(_ animation: Animation) -> Animation? { reduced ? nil : animation }

    /// 순서대로 살짝 늦게 시작하는 스프링(타일이 차례로 튀어 오르는 등장). index 0 은 지연이 없다.
    static func staggered(_ base: Animation, index: Int, step: Double = 0.022) -> Animation {
        base.delay(Double(max(index, 0)) * step)
    }

    /// 지연 계산만 따로 노출(테스트용): 동작 줄이기이면 0
    static func staggerDelay(index: Int, step: Double = 0.022, reduced: Bool = Motion.reduced) -> Double {
        reduced ? 0 : Double(max(index, 0)) * step
    }
}
