import Foundation

/// 앱 식별·배포 정보. 단일 출처는 Info.plist 이고(빌드·릴리스 스크립트도 같은 값을 읽는다), 번들이 없는 테스트 실행에서는 기본값을 쓴다.
enum AppInfo {
    static let defaultRepo = "eyo-25/quickstream"

    private static func plist(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// "owner/repo" — 릴리스 페이지 링크에 쓴다
    static var repo: String { plist("QSGitHubRepo") ?? defaultRepo }
    static var bundleId: String { Bundle.main.bundleIdentifier ?? "io.github.eyo-25.quickstream" }
    static var displayName: String { plist("CFBundleDisplayName") ?? "퀵스트림" }
    static var version: String { plist("CFBundleShortVersionString") ?? "0.0.0" }
    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    /// 사용자 설정·로그 폴더: ~/Library/Application Support/QuickStream.
    /// 시험·격리 실행용으로 `--support-dir=<경로>` 인자 또는 QUICKSTREAM_SUPPORT_DIR 환경변수가 있으면 그 폴더를 쓴다.
    static var supportDirectory: URL {
        if let override = supportDirectoryOverride { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickStream", isDirectory: true)
    }
    static var supportDirectoryOverride: String? {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--support-dir=") }) { return String(arg.dropFirst("--support-dir=".count)) }
        if let env = ProcessInfo.processInfo.environment["QUICKSTREAM_SUPPORT_DIR"], !env.isEmpty { return env }
        return nil
    }
    static var logDirectory: URL { supportDirectory.appendingPathComponent("logs", isDirectory: true) }
}
