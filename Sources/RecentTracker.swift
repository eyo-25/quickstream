import Foundation

/// 최근 앱(MRU) 순서 추적. `NSWorkspace.runningApplications` 는 MRU 순서가 아니라서
/// 활성화 알림을 받을 때마다 따로 기록한다. 메모리에만 보관한다.
final class RecentTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivated: [String: Date] = [:]

    func noteActivated(_ bundleId: String, at date: Date = Date()) {
        lock.withLock { lastActivated[bundleId] = date }
    }

    /// 실행 중인 앱만 대상으로 최근 활성화 순 → (기록 없으면) 실행 시각 최신순 → 이름순.
    /// 활성화 기록이 있는 앱이 없는 앱보다 앞선다. bundleId 중복(다중 인스턴스)은 앞의 것만 남긴다.
    func order(_ running: [RunningApp], limit: Int) -> [RunningApp] {
        let times = lock.withLock { lastActivated }
        var seen = Set<String>()
        let unique = running.filter { seen.insert($0.bundleId).inserted }

        let sorted = unique.sorted { a, b in
            let ta = times[a.bundleId], tb = times[b.bundleId]
            switch (ta, tb) {
            case let (ta?, tb?) where ta != tb: return ta > tb
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let la = a.launchedAt ?? .distantPast, lb = b.launchedAt ?? .distantPast
            if la != lb { return la > lb }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
