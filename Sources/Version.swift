import Foundation

/// X.Y.Z 형태의 버전. 릴리스 태그(`v0.2.0`)와 Info.plist 값을 같은 규칙으로 읽고 비교한다.
/// 프리릴리스(`-beta`)·빌드 메타데이터·자리 수가 다른 문자열은 배포 규칙에 없으므로 nil 로 거른다.
struct Version: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("v") || body.hasPrefix("V") { body.removeFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            // 9자리 제한: Int 오버플로를 막고, 비정상적으로 긴 숫자를 버전으로 받지 않는다
            guard (1...9).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: Version, b: Version) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

/// GitHub `releases/latest` 응답에서 업데이트 판단에 필요한 부분
struct ReleaseInfo: Equatable {
    var version: Version
    var url: URL

    /// draft/prerelease 이거나 필수 값이 비정상이면 nil. `releases/latest` 가 이미 걸러 주지만 응답 형태에 기대지 않고 한 번 더 막는다.
    static func parseLatest(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            var tag_name: String
            var html_url: String
            var draft: Bool?
            var prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = Version(payload.tag_name),
              let url = URL(string: payload.html_url), url.scheme == "https", url.host != nil
        else { return nil }
        return ReleaseInfo(version: version, url: url)
    }
}

/// 확인 주기 스로틀. 마지막 확인 시각이 미래(시계 조정)이면 믿지 않고 바로 확인한다.
enum UpdateThrottle {
    static let interval: TimeInterval = 6 * 60 * 60

    static func shouldCheck(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed < 0 || elapsed >= interval
    }
}
