import Foundation

/// `settings.json` 저장소. 읽기 실패·검증 실패는 크래시 대신 기본값 + warning 으로 동작하고,
/// 사용자가 고칠 수 있도록 깨진 파일은 저장 전까지 건드리지 않는다.
final class SettingsStore: SettingsStoring, @unchecked Sendable {
    let fileURL: URL
    private let directory: URL
    private let legacyAppSupport: URL?
    private let lock = NSLock()
    private var _current = Settings.defaults
    private var _warning: String?

    /// - Parameter legacyAppSupport: 옛 Electron 설정을 찾을 `Application Support` 폴더. nil 이면 가져오기를 건너뛴다.
    init(directory: URL = AppInfo.supportDirectory, legacyAppSupport: URL? = SettingsMigration.defaultAppSupport) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("settings.json")
        self.legacyAppSupport = legacyAppSupport
        reload()
    }

    var current: Settings { lock.withLock { _current } }
    var warning: String? { lock.withLock { _warning } }

    private func set(_ settings: Settings, warning: String?) {
        lock.withLock {
            _current = settings
            _warning = warning
        }
    }

    @discardableResult
    func reload() -> Settings {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return createInitialFile()
        } catch {
            set(.defaults, warning: "설정 파일을 읽을 수 없습니다: \(error.localizedDescription)")
            return current
        }

        let settings: Settings
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch let error as DecodingError {
            set(.defaults, warning: "설정 파일 형식 오류: \(Self.describe(error))")
            return current
        } catch {
            set(.defaults, warning: "설정 JSON 문법 오류: \(error.localizedDescription)")
            return current
        }
        let issues = SettingsValidator.validate(settings)
        if !issues.isEmpty {
            set(.defaults, warning: "설정 검증 실패 — 기본값 사용\n" + issues.map(\.text).joined(separator: "\n"))
            return current
        }
        set(settings, warning: nil)
        return settings
    }

    /// 새 설정 파일이 없을 때: 옛 Electron 설정이 있으면 가져오고, 없으면 기본값. 둘 다 파일로 써 둔다.
    private func createInitialFile() -> Settings {
        let initial = legacyAppSupport.flatMap(SettingsMigration.load(from:)) ?? .defaults
        do {
            try Self.writeAtomically(initial, to: fileURL)
            set(initial, warning: nil)
        } catch {
            set(initial, warning: "기본 설정 파일을 만들 수 없습니다: \(error.localizedDescription)")
        }
        return initial
    }

    func save(_ settings: Settings) -> ActionResult {
        if let first = SettingsValidator.validate(settings).first { return .failure(first.text) }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: fileURL.path) {
                // 깨진 파일도 그대로 .bak 으로 남겨, 덮어쓴 뒤에도 사용자가 되살릴 수 있게 한다
                let backup = URL(fileURLWithPath: fileURL.path + ".bak")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: fileURL, to: backup)
            }
            try Self.writeAtomically(settings, to: fileURL)
        } catch {
            return .failure("설정을 저장할 수 없습니다: \(error.localizedDescription)")
        }
        set(settings, warning: nil)
        return .success
    }

    private static func writeAtomically(_ settings: Settings, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(settings)
        data.append(0x0A)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = URL(fileURLWithPath: url.path + ".\(ProcessInfo.processInfo.processIdentifier).tmp")
        do {
            try data.write(to: temp)
            // rename(2) 는 같은 볼륨에서 원자적이고, 대상이 없어도 동작한다
            guard rename(temp.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        } catch {
            try? fm.removeItem(at: temp) // 실패한 임시파일이 남지 않게 한다
            throw error
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context): return "\(path(context).isEmpty ? "" : path(context) + ".")\(key.stringValue) 가 없습니다"
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return "\(path(context)): \(context.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }
}
