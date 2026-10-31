import Foundation

/// 옛 Electron 판(userData = `~/Library/Application Support/<productName>`)의 설정을 새 설정으로 가져온다.
/// 원본은 읽기만 한다. 알 수 없는 키(예: matchApps)는 디코딩에서 무시돼 다음 저장 때 사라진다.
enum SettingsMigration {
    /// Electron 판 productName(package.json). 앞이 실제 폴더명이고 뒤는 표기가 흔들린 경우의 대비.
    static let legacyFolderNames = ["퀵스트림", "퀘스트림"]

    static var defaultAppSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// `appSupport` 아래에서 옛 설정 파일을 찾는다. 한글 폴더명은 NFC/NFD 가 파일 시스템·도구마다 달라서
    /// 경로를 조립하지 않고 목록의 이름을 정규화해서 비교한다.
    static func legacySettingsURL(in appSupport: URL) -> URL? {
        let wanted = Set(legacyFolderNames.map { $0.precomposedStringWithCanonicalMapping })
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: appSupport.path) else { return nil }
        for name in names where wanted.contains(name.precomposedStringWithCanonicalMapping) {
            let file = appSupport.appendingPathComponent(name, isDirectory: true).appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    /// 옛 설정이 있고 검증을 통과하면 돌려준다. 없거나 깨졌으면 nil(호출 측이 기본값으로 시작한다).
    static func load(from appSupport: URL) -> Settings? {
        guard let file = legacySettingsURL(in: appSupport),
              let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data),
              SettingsValidator.validate(settings).isEmpty else { return nil }
        return settings
    }
}
