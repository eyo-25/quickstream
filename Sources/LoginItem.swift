import ServiceManagement

/// 로그인 항목 API. 테스트에서 가짜로 바꿔 끼운다.
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService.mainApp`. 서명되지 않은 앱은 macOS 가 거부하거나 사용자 승인을 요구할 수 있다.
struct SystemLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LoginItemResult {
    /// rollback: 이후 단계(설정 파일 저장)가 실패했을 때 이전 상태로 되돌린다
    case success(rollback: () -> Void)
    case failure(String)
}

private let loginItemFailureMessage = "로그인 시 자동 시작을 설정하지 못했습니다. 서명되지 않은 앱은 macOS 가 거부할 수 있습니다."

/// 로그인 항목을 wanted 로 맞춘다. macOS 는 거부해도 throw 하지 않을 수 있어, 설정 후 다시 읽어 실제 반영 여부를 확인한다.
/// 반영되지 않으면 이전 상태로 되돌리고 오류를 돌려준다.
func applyLoginItem(_ api: LoginItemControlling, wanted: Bool) -> LoginItemResult {
    let previous = api.isEnabled
    if previous == wanted { return .success(rollback: {}) }

    let restore = {
        // 복구 실패는 더 할 수 있는 일이 없다. 원래 오류를 가리지 않도록 삼킨다.
        try? api.setEnabled(previous)
    }

    do {
        try api.setEnabled(wanted)
    } catch {
        restore()
        return .failure("\(loginItemFailureMessage) (\(error.localizedDescription))")
    }
    if api.isEnabled != wanted {
        restore()
        return .failure(loginItemFailureMessage)
    }
    return .success(rollback: { restore() })
}
