import Foundation

/// 설정(탭/슬롯) + 런타임 데이터(아이콘)를 화면용 OverlayState 로 풀고, 슬롯을 실행한다.
/// 실행할 Action 본문은 여기에만 두고 오버레이는 (tabId, slotIndex) 만 돌려보낸다.
final class Deck: DeckProviding, @unchecked Sendable {
    private static let iconPixels = 80
    private static let iconCacheLimit = 256

    private let store: SettingsStoring
    private let catalog: AppCatalog
    private let openURL: (URL) async throws -> Void
    private let writeClipboard: (String) -> Void

    private let lock = NSLock()
    /// 마지막으로 buildState 가 돌려준 상태의 실행 조회표. 설정이 다시 로드돼도 이미 보낸 화면과 어긋나지 않게 이 표만 본다.
    private var resolved: [String: [Action?]] = [:]
    private var icons: [IconTarget: Data] = [:]
    /// 오래 안 쓴 순서(앞이 가장 오래됨)
    private var iconOrder: [IconTarget] = []
    private var inFlight = Set<IconTarget>()
    /// 아이콘 렌더는 디스크를 읽으므로 표시 경로 밖의 직렬 큐에서 한다
    private let iconQueue = DispatchQueue(label: "quickstream.deck.icons", qos: .utility)

    init(
        store: SettingsStoring,
        catalog: AppCatalog,
        openURL: @escaping (URL) async throws -> Void = ActionExecutor.systemOpenURL,
        writeClipboard: @escaping (String) -> Void = ActionExecutor.systemWriteClipboard
    ) {
        self.store = store
        self.catalog = catalog
        self.openURL = openURL
        self.writeClipboard = writeClipboard
    }

    /// 슬롯 대상 앱의 식별자. 매크로 안의 단계는 슬롯 자체가 앱이 아니므로 제외한다.
    static func iconTarget(for action: Action) -> IconTarget? {
        switch action {
        case let .activateApp(bundleId, _): return .bundleId(bundleId)
        case let .launchApp(bundleId, appPath):
            if let appPath { return .appPath(appPath) }
            return bundleId.map(IconTarget.bundleId)
        default: return nil
        }
    }

    func buildState() async -> OverlayState {
        let settings = store.current
        var resolvedNow: [String: [Action?]] = [:]
        var tabs: [TabView] = []
        var iconSlots: [(tab: Int, slot: Int, target: IconTarget)] = []

        for (tabIndex, tab) in settings.tabs.enumerated() {
            var views = [SlotView?](repeating: nil, count: Limits.slots)
            var actions = [Action?](repeating: nil, count: Limits.slots)

            for (i, entry) in tab.slots.prefix(Limits.slots).enumerated() {
                guard let slot = entry else { continue } // 빈 칸
                actions[i] = slot.action
                views[i] = SlotView(id: slot.id, name: slot.name, label: slot.label ?? slotInitials(slot.name), verb: slot.action.verb)
                if let target = Self.iconTarget(for: slot.action) { iconSlots.append((tabIndex, i, target)) }
            }
            resolvedNow[tab.id] = actions
            tabs.append(TabView(id: tab.id, name: tab.name, caption: tab.type.caption, slots: views, keymap: Keymap.build(slots: tab.slots, closeKey: settings.closeKey)))
        }

        if settings.overlay.showIcons {
            // 캐시에 있는 아이콘만 즉시 붙인다. 없는 앱은 기다리지 않고 백그라운드로 채워 다음 표시부터 쓴다.
            fetchIcons(iconSlots.map(\.target))
            let cached = lock.withLock { icons }
            for entry in iconSlots {
                if let png = cached[entry.target] { tabs[entry.tab].slots[entry.slot]?.iconPNG = png }
            }
            touch(iconSlots.map(\.target))
        }

        // 보낸 상태를 확정한다: 이 반환값을 그대로 오버레이에 보낸다는 계약
        lock.withLock { resolved = resolvedNow }
        return OverlayState(tabs: tabs, activeTab: 0, alpha: settings.overlay.alpha, radius: settings.overlay.radius,
                            ringRadius: settings.overlay.ringSize, centerRadius: settings.overlay.centerSize, centerBorder: settings.overlay.centerBorder,
                            closeKeyCodes: Set(SlotKey.keyCodes(for: settings.closeKey).isEmpty ? [KeyCode.q] : SlotKey.keyCodes(for: settings.closeKey)),
                            theme: settings.overlay.theme,
                            namePlacement: settings.overlay.namePlacement, showNumbers: settings.overlay.showNumbers,
                            bodyTheme: settings.overlay.bodyTheme, focusStyle: settings.overlay.focusStyle, focusHex: settings.overlay.focusHex,
                            showTileLabels: settings.overlay.showTileLabels, solidBacking: settings.overlay.solidBacking,
                            centerNameWeight: settings.overlay.centerNameWeight, centerNameSize: settings.overlay.centerNameSize,
                            glassTintHex: settings.overlay.glassTintHex, focusGlow: settings.overlay.focusGlow)
    }

    /// 아이콘 캐시를 미리 채운다(표시를 막지 않는다). 설정의 슬롯 대상 앱 아이콘을 받아 둔다.
    func prewarm() {
        let settings = store.current
        guard settings.overlay.showIcons else { return }
        fetchIcons(settings.tabs.flatMap { $0.slots.compactMap { $0.flatMap { Self.iconTarget(for: $0.action) } } })
    }

    /// 지금까지 요청한 아이콘 작업이 모두 끝날 때까지 기다린다(종료 정리와 테스트용)
    func waitForIconWork() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            iconQueue.async { continuation.resume() }
        }
    }

    /// 캐시에 없고 진행 중도 아닌 대상만 요청한다. 못 얻으면 약어로 남기고, 다음 표시에서 다시 시도한다.
    private func fetchIcons(_ targets: [IconTarget]) {
        let missing = lock.withLock { () -> [IconTarget] in
            var out: [IconTarget] = []
            for target in targets where icons[target] == nil && !inFlight.contains(target) {
                inFlight.insert(target)
                out.append(target)
            }
            return out
        }
        guard !missing.isEmpty else { return }
        iconQueue.async { [self] in
            for target in missing {
                let png = catalog.iconPNG(for: target, pixels: Self.iconPixels)
                lock.withLock {
                    inFlight.remove(target)
                    if let png { remember(target, png) }
                }
            }
        }
    }

    /// lock 을 잡은 상태에서 부른다
    private func remember(_ target: IconTarget, _ png: Data) {
        icons[target] = png
        iconOrder.removeAll { $0 == target }
        iconOrder.append(target)
        while iconOrder.count > Self.iconCacheLimit { icons[iconOrder.removeFirst()] = nil }
    }

    /// 방금 표시에 쓴 아이콘을 최근 사용으로 올려, 가득 찼을 때 쓰는 중인 것이 먼저 밀려나지 않게 한다
    private func touch(_ targets: [IconTarget]) {
        lock.withLock {
            for target in targets where icons[target] != nil {
                iconOrder.removeAll { $0 == target }
                iconOrder.append(target)
            }
        }
    }

    func action(tabId: String, slotIndex: Int) -> Action? {
        guard (0..<Limits.slots).contains(slotIndex) else { return nil }
        return lock.withLock { resolved[tabId]?[slotIndex] ?? nil }
    }

    func execute(tabId: String, slotIndex: Int) async -> ActionResult {
        guard let action = action(tabId: tabId, slotIndex: slotIndex) else { return .failure("비어 있는 슬롯입니다") }
        return await ActionExecutor.execute(action, catalog: catalog, openURL: openURL, writeClipboard: writeClipboard)
    }
}
