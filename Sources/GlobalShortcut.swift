import Carbon.HIToolbox
import Foundation

/// 전역 단축키(Carbon RegisterEventHotKey). 접근성 권한이 필요 없다.
final class GlobalShortcut: ShortcutRegistering {
    private(set) var registered: String?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// 'QSTR'
    private static let signature: OSType = 0x5153_5452

    deinit {
        unregister()
        // 콜백이 해제된 self 를 가리키지 않도록 핸들러도 제거한다
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ accelerator: String, handler: @escaping () -> Void) -> ActionResult {
        unregister()
        guard let parsed = Accelerator.parse(accelerator) else {
            // F21~F24 처럼 형식은 맞지만 macOS 에 키코드가 없는 경우를 구분해 알린다
            if Accelerator.isWellFormed(accelerator) { return .failure("macOS 에서는 전역 단축키로 쓸 수 없는 키입니다: \(Accelerator.display(accelerator))") }
            return .failure("해석할 수 없는 단축키입니다: \(accelerator)")
        }
        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(parsed.keyCode, parsed.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            return .failure("단축키를 등록하지 못했습니다(다른 앱이 쓰고 있을 수 있습니다): \(Accelerator.display(accelerator))")
        }
        hotKeyRef = ref
        self.handler = handler
        registered = accelerator
        return .success
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        handler = nil
        registered = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // 콜백은 C 함수라 클로저를 캡처할 수 없어, 인스턴스를 userData 로 넘긴다
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalShortcut.signature else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue().handler?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}

extension GlobalShortcut {
    /// 단축키를 previous → next 로 교체한다. next 등록에 실패하면 previous 를 되살리고 nil 을 돌려준다.
    /// 성공하면 이후 단계(설정 파일 저장)가 실패했을 때 이전 상태로 되돌리는 rollback 을 돌려준다.
    static func swap(
        registry: ShortcutRegistering,
        previous: String?,
        next: String,
        handler: @escaping () -> Void
    ) -> (() -> Void)? {
        let restore = {
            registry.unregister()
            if let previous { _ = registry.register(previous, handler: handler) }
        }
        registry.unregister()
        guard registry.register(next, handler: handler).ok else {
            restore()
            return nil
        }
        return restore
    }
}
