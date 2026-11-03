import Foundation

/// 웹 페이지 HTML 에서 제목과 아이콘(파비콘) 후보를 읽는다. 순수 로직이라 단위 테스트한다.
/// 슬롯에 URL 을 넣을 때 그 페이지의 제목을 이름·약어로, 파비콘을 아이콘으로 쓰는 데 쓴다.
enum PageMetadata {
    /// `<title>` 글자. 엔티티를 풀고 연속 공백·줄바꿈을 한 칸으로 줄인다. 없거나 비면 nil.
    /// 정규식 대신 앞에서부터 한 번 훑는다(닫히지 않은 `<title` 이 많은 악의적인 페이지에서도 선형 시간).
    static func title(fromHTML html: String) -> String? {
        let ns = html as NSString
        var from = 0
        while from < ns.length {
            let open = ns.range(of: "<title", options: .caseInsensitive, range: NSRange(location: from, length: ns.length - from))
            guard open.location != NSNotFound else { return nil }
            let after = open.location + open.length
            // `<titlex` 같은 다른 태그 이름은 건너뛴다
            guard after < ns.length, let next = Unicode.Scalar(ns.character(at: after)),
                  next == ">" || next == "/" || CharacterSet.whitespacesAndNewlines.contains(next) else { from = after; continue }
            // 여는 태그의 `>` 나 닫는 태그가 없으면 뒤에도 없으므로 끝낸다
            let close = ns.range(of: ">", range: NSRange(location: after, length: ns.length - after))
            guard close.location != NSNotFound else { return nil }
            let start = close.location + 1
            let end = ns.range(of: "</title", options: .caseInsensitive, range: NSRange(location: start, length: ns.length - start))
            guard end.location != NSNotFound else { return nil }
            let raw = ns.substring(with: NSRange(location: start, length: min(end.location - start, maxTitleLength)))
            // 공백류로 나눈 뒤 남은 제어 문자(`&#0;` 등)와 글자 방향을 바꾸는 문자(U+202A–202E, U+2066–2069)는 뺀다
            func unwanted(_ scalar: Unicode.Scalar) -> Bool {
                scalar.properties.generalCategory == .control || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
            }
            let text = decodeEntities(raw).split(whereSeparator: { $0.isWhitespace })
                .map { String(String.UnicodeScalarView($0.unicodeScalars.filter { !unwanted($0) })) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// 제목으로 읽는 원문의 최대 길이(UTF-16 유닛). 슬롯 이름 상한(40)보다 훨씬 넉넉하다.
    private static let maxTitleLength = 2000

    /// 아이콘 후보 주소를 쓸 만한 순서로 돌려준다: `apple-touch-icon`(크고 선명) → `icon`/`shortcut icon` → 사이트 루트의 `/favicon.ico`.
    /// 상대 주소는 `base`(응답을 받은 최종 주소) 기준으로 풀고, http/https 가 아닌 것(`data:` 등)은 뺀다. 중복은 한 번만.
    /// 페이지가 다른 호스트의 사내망·로컬 주소(localhost, `.local`, 사설 IP)를 가리키는 링크는 뺀다.
    static func iconURLs(fromHTML html: String, base: URL) -> [URL] {
        var touch: [URL] = []
        var plain: [URL] = []
        for tag in allMatches(#"<link\b[^>]{0,2000}>"#, in: html) {
            guard let rel = attribute("rel", in: tag)?.lowercased(), let href = attribute("href", in: tag), !href.isEmpty else { continue }
            let tokens = rel.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let isTouch = tokens.contains { $0.hasPrefix("apple-touch-icon") }
            guard isTouch || tokens.contains("icon"), let url = URL(string: decodeEntities(href), relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.host?.lowercased() == base.host?.lowercased() || !isLocalNetworkHost(url.host ?? "") else { continue }
            // SVG 는 ImageIO 가 읽지 못해 시도 횟수만 쓰므로 후보에서 뺀다
            if attribute("type", in: tag)?.lowercased().contains("svg") == true || url.path.lowercased().hasSuffix(".svg") { continue }
            if isTouch { touch.append(url) } else { plain.append(url) }
        }
        var result: [URL] = []
        for url in touch + plain + [URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL].compactMap({ $0 }) where !result.contains(url) {
            result.append(url)
        }
        return result
    }

    /// localhost · `.local` 이름, 또는 사설·루프백·링크로컬·CGNAT 주소면 true. 주소는 시스템이 해석하는 방식대로 읽는다
    /// (`127.1` · `2130706433` · `0x7f.0.0.1` 같은 축약·16진·8진 IPv4, IPv6 와 `::ffff:a.b.c.d`, 끝의 `.`).
    static func isLocalNetworkHost(_ host: String) -> Bool {
        var h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        while h.hasSuffix(".") { h.removeLast() }
        if h.isEmpty || h == "localhost" || h.hasSuffix(".localhost") || h.hasSuffix(".local") { return true }
        func privateV4(_ a: UInt8, _ b: UInt8) -> Bool {
            a == 0 || a == 10 || a == 127 || (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254)
                || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, h, &v6) == 1 {
            let b = withUnsafeBytes(of: v6) { Array($0) }
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return privateV4(b[12], b[13]) }
            if b[0..<12].allSatisfy({ $0 == 0 }) { return privateV4(b[12], b[13]) } // ::a.b.c.d(IPv4 호환), ::, ::1
            if b[0] == 0, b[1] == 0x64, b[2] == 0xff, b[3] == 0x9b, b[4..<12].allSatisfy({ $0 == 0 }) { return privateV4(b[12], b[13]) } // NAT64 64:ff9b::/96
            return b[0] & 0xfe == 0xfc || (b[0] == 0xfe && b[1] & 0x80 == 0x80) // fc00::/7, fe80::/10 과 fec0::/10
        }
        var v4 = in_addr()
        if inet_aton(h, &v4) == 1 {
            let address = UInt32(bigEndian: v4.s_addr)
            return privateV4(UInt8(address >> 24), UInt8((address >> 16) & 0xff))
        }
        return false
    }

    // MARK: - 내부

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = regex(pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// 태그 문자열에서 속성값을 읽는다("…", '…', 따옴표 없는 값). 이름은 대소문자를 가리지 않는다.
    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = regex(#"(?:^|[\s"'/])"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return nil
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "middot": "·", "hellip": "…",
        "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©",
    ]

    /// `&amp;` `&#39;` `&#x1F600;` 같은 흔한 HTML 엔티티를 푼다. 모르는 이름은 그대로 둔다.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = regex(#"&(#[0-9]{1,7}|#x[0-9a-f]{1,6}|[a-z]{2,8});"#) else { return text }
        let ns = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let body = ns.substring(with: match.range(at: 1))
            let replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[body.lowercased()]
            }
            guard let replacement, let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
