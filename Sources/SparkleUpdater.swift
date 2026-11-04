import AppKit
import Sparkle

/// 앱 업데이트. Sparkle 이 Info.plist 의 `SUFeedURL` 피드를 확인하고, 새 zip 을 받아 `SUPublicEDKey` 로 EdDSA 서명을 검증한 뒤
/// 앱 번들을 바꾸고 다시 연다. 서명이 맞지 않는 업데이트는 설치하지 않는다.
///
/// 메뉴바 앱이라 스케줄된(자동) 확인이 찾은 새 버전을 갑자기 창으로 띄우면 방해된다. 그래서 앱이 앞에 있지 않을 때는 창 없이
/// `pendingVersion` 으로만 알리고(메뉴에 '새 버전 …' 항목), 사용자가 그 항목을 누르거나 직접 확인하면 Sparkle 이 창을 보여 준다.
final class SparkleUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    /// 창 없이 알린 새 버전(메뉴 표시용). 사용자가 업데이트 창을 보거나 세션이 끝나면 비운다.
    private(set) var pendingVersion: String?
    /// `pendingVersion` 이 바뀔 때 부른다(메인 스레드)
    var onChange: () -> Void = {}
    /// 업데이트 설치를 마치고 다시 열기 전에 종료해도 되는지 묻는다(저장하지 않은 설정이 있으면 사용자에게 확인). nil 이면 바로 진행한다.
    var confirmQuit: (() -> Bool)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// 자동 확인 일정을 시작한다. 번들 설정(피드·공개키)이 잘못되면 Sparkle 이 로그를 남기고 사용자에게 알린다.
    func start() { controller.startUpdater() }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// 일정에 따라 새 버전을 자동으로 확인할지(Sparkle 이 사용자 설정으로 저장한다. 기본은 Info.plist 의 `SUEnableAutomaticChecks`)
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - SPUUpdaterDelegate

    /// 설치를 마친 뒤 다시 열기 전에 저장하지 않은 설정을 확인한다(`confirmQuit`). 사용자가 취소하면 재시작은 하지 않고,
    /// 받아 둔 업데이트는 다음에 앱을 직접 종료할 때 설치된다.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let confirmQuit else { return false }
        DispatchQueue.main.async {
            if confirmQuit() { installHandler() }
        }
        return true
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 자동 확인이 찾았을 때: 앱이 앞에 있을 때만 창을 띄운다. 아니면 메뉴 항목으로 알린다.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        setPending(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { setPending(nil) }

    func standardUserDriverWillFinishUpdateSession() { setPending(nil) }

    private func setPending(_ version: String?) {
        guard pendingVersion != version else { return }
        pendingVersion = version
        onChange()
    }
}
