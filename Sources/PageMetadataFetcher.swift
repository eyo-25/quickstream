import Foundation

/// 슬롯 URL 의 페이지에서 읽어 온 정보. 못 읽은 것은 nil/false.
struct PageInfo: Equatable, Sendable {
    var title: String?
    /// 파비콘을 받아 보관소(`FaviconStore`)에 저장했나
    var hasIcon: Bool
}

/// 페이지 제목을 읽고 파비콘을 받아 저장한다. 설정 창이 슬롯에 URL 을 넣을 때 부른다(시험에서는 가짜로 바꾼다).
protocol PageMetadataFetching: Sendable {
    func fetch(_ url: URL) async -> PageInfo
}

/// 실제 가져오기: 그 URL 에 GET 요청을 보내 HTML 앞부분에서 제목과 아이콘 주소를 읽고, 아이콘을 받아 PNG 로 저장한다.
/// 사용자가 설정에서 URL 을 넣었을 때만 부르고(오버레이를 열 때는 부르지 않는다), 쿠키·캐시 없이 짧은 시간 제한과 크기 제한 안에서 한다.
struct WebPageMetadataFetcher: PageMetadataFetching {
    let store: FaviconStore
    let session: URLSession

    static let maxHTMLBytes = 512 * 1024
    static let maxIconBytes = 512 * 1024
    /// 한 번에 받아 볼 아이콘 후보 수(앞에서부터, 먼저 읽히는 것을 쓴다)
    static let maxIconAttempts = 4

    init(store: FaviconStore = .standard, session: URLSession = WebPageMetadataFetcher.makeSession()) {
        self.store = store
        self.session = session
    }

    /// 리다이렉트를 따라가도 되는지: http/https 이고, 사내망·로컬 주소로는 같은 호스트 안에서만 간다(공개 주소가 `http://127.0.0.1/…` 로 돌리는 경로를 막는다).
    /// DNS 가 사설 IP 로 풀리는 공개 이름까지는 막지 못한다.
    static func allowsRedirect(from current: URL?, to target: URL?) -> Bool {
        guard let target, let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = target.host else { return false }
        return host.lowercased() == current?.host?.lowercased() || !PageMetadata.isLocalNetworkHost(host)
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(WebPageMetadataFetcher.allowsRedirect(from: response.url, to: request.url) ? request : nil)
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }

    func fetch(_ url: URL) async -> PageInfo {
        guard isHttpURL(url.absoluteString), let host = url.host else { return PageInfo(title: nil, hasIcon: false) }

        var title: String?
        var iconCandidates: [URL] = []
        if let page = await download(url, maxBytes: Self.maxHTMLBytes, stopAfter: "</head>") {
            let html = Self.decodeHTML(Self.truncatedAfterHead(page.data), encodingName: page.encodingName)
            title = PageMetadata.title(fromHTML: html)
            iconCandidates = PageMetadata.iconURLs(fromHTML: html, base: page.finalURL)
        } else if let fallback = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL {
            // 페이지를 못 읽어도(차단·시간 초과) 사이트 루트의 favicon.ico 는 시도해 본다
            iconCandidates = [fallback]
        }

        var hasIcon = false
        for candidate in iconCandidates.prefix(Self.maxIconAttempts) {
            guard let icon = await download(candidate, maxBytes: Self.maxIconBytes, stopAfter: nil),
                  let png = FaviconStore.renderPNG(from: icon.data, pixels: FaviconStore.storedPixels) else { continue }
            hasIcon = store.save(png: png, forHost: host)
            if hasIcon { break }
        }
        return PageInfo(title: title, hasIcon: hasIcon)
    }

    // MARK: - 내부

    private struct Download {
        var data: Data
        var finalURL: URL
        var encodingName: String?
    }

    /// 2xx 응답의 앞 `maxBytes` 바이트까지 받는다. `stopAfter` 가 있으면 그 글자(대소문자 무시)가 나온 시점에 멈춘다.
    private func download(_ url: URL, maxBytes: Int, stopAfter marker: String?) async -> Download? {
        guard isHttpURL(url.absoluteString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) QuickStream/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            var data = Data()
            let needle = marker?.lowercased()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
                if let needle, data.count % 2048 == 0, String(decoding: data.suffix(2048 + needle.utf8.count), as: UTF8.self).lowercased().contains(needle) { break }
            }
            return Download(data: data, finalURL: http.url ?? url, encodingName: http.textEncodingName)
        } catch {
            return nil
        }
    }

    /// `</head>` 끝까지만 남긴다(대소문자 무시). 다운로드가 본문 중간에서 끊긴 바이트(멀티바이트 문자의 반쪽)를 디코딩에서 빼려는 것이다. 없으면 그대로.
    static func truncatedAfterHead(_ data: Data) -> Data {
        let marker = Array("</head>".utf8)
        let lowered = data.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        guard lowered.count >= marker.count else { return data }
        for start in 0...(lowered.count - marker.count) where lowered[start] == marker[0] && Array(lowered[start..<start + marker.count]) == marker {
            return data.prefix(start + marker.count)
        }
        return data
    }

    /// 문자 인코딩 이름(IANA)으로 `String.Encoding`. 모르는 이름은 nil.
    private static func stringEncoding(ianaName name: String) -> String.Encoding? {
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    /// 응답 헤더에 charset 이 없을 때 HTML 앞 2KB 의 `<meta charset=…>` / `http-equiv` 에서 읽는다.
    /// UTF-16/32 선언은 무시한다(ASCII 로 읽히는 `<meta>` 가 UTF-16 일 수는 없다. HTML 표준도 같게 다룬다).
    static func sniffedCharset(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"charset\s*=\s*["']?([A-Za-z0-9_.:\-]+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        let name = (head as NSString).substring(with: match.range(at: 1))
        return name.lowercased().hasPrefix("utf-16") || name.lowercased().hasPrefix("utf-32") ? nil : name
    }

    /// 응답 헤더나 `<meta>` 가 알려 준 문자 인코딩(EUC-KR 등)으로 읽고, 모르면 UTF-8 로 읽는다(잘못된 바이트는 대체 문자로).
    /// 끝이 문자 중간에서 잘려 해석이 실패하면 끝 바이트를 최대 4개까지 덜어 내고 다시 읽는다.
    static func decodeHTML(_ data: Data, encodingName: String?) -> String {
        if let name = encodingName ?? sniffedCharset(data), let encoding = stringEncoding(ianaName: name) {
            for trim in 0...4 where data.count > trim {
                if let text = String(data: data.dropLast(trim), encoding: encoding) { return text }
            }
        }
        return String(decoding: data, as: UTF8.self)
    }
}
