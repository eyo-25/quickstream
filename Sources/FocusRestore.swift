import Foundation

/// 오버레이를 닫은 뒤 원래 작업 앱으로 포커스를 돌려주는 로직. AppController 를 창 없이 구동하기 어려워 따로 뗐다.
enum FocusRestore {
    /// 복원은 사용자가 앱을 "열라"고 한 게 아니므로 `activate`/`open`(reopen 이벤트를 보내 닫힌 창을 되살린다)이 아니라
    /// `refocus` 만 쓴다. 앱이 이미 종료됐으면 false 이고 새로 실행하지 않는다.
    @discardableResult
    static func restore(_ previous: RunningApp?, catalog: AppCatalog) -> Bool {
        guard let previous else { return false }
        return catalog.refocus(bundleId: previous.bundleId, pid: previous.pid)
    }
}
