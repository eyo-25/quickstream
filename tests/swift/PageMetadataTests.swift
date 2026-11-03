import AppKit
import Foundation

// URL 슬롯의 제목·파비콘: HTML 파싱, 파비콘 보관소, 가져오기(네트워크는 URLProtocol 스텁, 파일은 임시 폴더에만).

private final class PMStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (status: Int, type: String, body: Data)] = [:]
    nonisolated(unsafe) static var requested: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requested.append(url.absoluteString)
        let route = Self.routes[url.absoluteString] ?? (404, "text/plain", Data())
        let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": route.type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func samplePNG(side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

private func pixelWidth(_ png: Data?) -> Int? {
    png.flatMap { NSBitmapImageRep(data: $0)?.pixelsWide }
}

func runPageMetadataTests() {
    section("PageMetadata/title")
    checkEqual(PageMetadata.title(fromHTML: "<html><head><TITLE>\n  Hello &amp; World\n  &#39;x&#39; &#x1F600;</title></head>"), "Hello & World 'x' 😀", "제목: 엔티티·공백 정리")
    checkEqual(PageMetadata.title(fromHTML: #"<title lang="ko">한글 제목</title>"#), "한글 제목", "제목: 속성이 있는 태그")
    checkEqual(PageMetadata.title(fromHTML: "<title>AT&T &foo; &nbsp;Home</title>"), "AT&T &foo; Home", "제목: 모르는 엔티티는 그대로")
    checkEqual(PageMetadata.title(fromHTML: "<title>   </title>"), nil, "제목: 빈 제목은 nil")
    checkEqual(PageMetadata.title(fromHTML: "<html><body>no title</body></html>"), nil, "제목: 태그 없음은 nil")
    checkEqual(PageMetadata.title(fromHTML: "<titlex>nope</titlex>"), nil, "제목: 다른 태그 이름은 무시")

    section("PageMetadata/icons")
    let html = """
    <link rel="stylesheet" href="/s.css">
    <link rel="shortcut icon" href="/fav.ico">
    <link rel='icon' type='image/png' href='icons/32.png'>
    <link href="/touch.png" rel="apple-touch-icon">
    <link rel="icon" href="data:image/png;base64,AAA">
    <link rel="icon" href="https://cdn.example.com/x.png">
    <LINK REL="ICON" HREF="/fav.ico">
    <link rel="icon" href="javascript:alert(1)">
    """
    checkEqual(PageMetadata.iconURLs(fromHTML: html, base: URL(string: "https://example.com/dir/page")!).map(\.absoluteString), [
        "https://example.com/touch.png",
        "https://example.com/fav.ico",
        "https://example.com/dir/icons/32.png",
        "https://cdn.example.com/x.png",
        "https://example.com/favicon.ico",
    ], "아이콘 후보: touch → icon(문서 순서) → favicon.ico, 상대 주소 해석·중복 제거, data:/javascript: 제외")
    checkEqual(PageMetadata.iconURLs(fromHTML: "", base: URL(string: "https://a.com/x/y")!).map(\.absoluteString), ["https://a.com/favicon.ico"], "링크가 없으면 /favicon.ico 만")
    checkEqual(PageMetadata.iconURLs(fromHTML: #"<link rel="icon" href="/a.png?x=1&amp;y=2">"#, base: URL(string: "https://a.com")!).first?.absoluteString,
               "https://a.com/a.png?x=1&y=2", "href 의 엔티티도 푼다")

    section("PageMetadata/store")
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qs-favicon-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    checkEqual(FaviconStore.fileName(forHost: "Example.COM"), "example.com.png", "파일 이름은 소문자 호스트")
    checkEqual(FaviconStore.fileName(forHost: "a/b..\\c"), "a_b.._c.png", "경로 문자는 _ 로 바꾼다")
    checkEqual(FaviconStore.fileName(forHost: ""), nil, "빈 호스트는 저장 불가")
    checkEqual(FaviconStore.fileName(forHost: String(repeating: "a", count: 101)), nil, "너무 긴 호스트는 저장 불가")
    let store = FaviconStore(directory: temp)
    checkEqual(store.pngData(forHost: "a.com"), nil, "없으면 nil")
    checkEqual(store.revision(forHost: "a.com"), 0, "없으면 수정 시각 0")
    let png = samplePNG(side: 32)
    check(store.save(png: png, forHost: "a.com"), "저장")
    checkEqual(store.pngData(forHost: "A.com"), png, "대소문자 무관하게 읽는다")
    check(store.revision(forHost: "a.com") > 0, "저장하면 수정 시각이 생긴다")
    checkEqual(pixelWidth(FaviconStore.renderPNG(from: png, pixels: 128)), 128, "정사각 PNG 로 그린다")
    checkEqual(pixelWidth(FaviconStore.renderPNG(from: png, pixels: 40)), 40, "필요한 크기로 줄인다")
    checkEqual(FaviconStore.renderPNG(from: Data("not an image".utf8), pixels: 128), nil, "이미지가 아니면 nil")
    checkEqual(FaviconStore.renderPNG(from: samplePNG(side: 2), pixels: 128), nil, "너무 작은 이미지는 거른다")

    section("PageMetadata/fetch")
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PMStubProtocol.self]
    let session = URLSession(configuration: config)
    let fetchStore = FaviconStore(directory: temp.appendingPathComponent("fetch", isDirectory: true))
    let fetcher = WebPageMetadataFetcher(store: fetchStore, session: session)
    let page = """
    <html><head><title>Hello &amp; World</title>
    <link rel="icon" href="/broken.png"><link rel="icon" href="/good.png"></head><body></body></html>
    """
    PMStubProtocol.routes = [
        "https://stub.test/": (200, "text/html; charset=utf-8", Data(page.utf8)),
        "https://stub.test/broken.png": (200, "image/png", Data("garbage".utf8)),
        "https://stub.test/good.png": (200, "image/png", samplePNG(side: 48)),
    ]
    PMStubProtocol.requested = []
    runAsync {
        let info = await fetcher.fetch(URL(string: "https://stub.test/")!)
        checkEqual(info, PageInfo(title: "Hello & World", hasIcon: true), "제목과 아이콘을 읽는다")
        checkEqual(pixelWidth(fetchStore.pngData(forHost: "stub.test")), FaviconStore.storedPixels, "깨진 첫 후보는 건너뛰고 다음 후보를 128px PNG 로 저장")
        checkEqual(PMStubProtocol.requested, ["https://stub.test/", "https://stub.test/broken.png", "https://stub.test/good.png"], "요청 순서")

        PMStubProtocol.routes = ["https://down.test/": (503, "text/html", Data("<title>x</title>".utf8)),
                                 "https://down.test/favicon.ico": (200, "image/x-icon", samplePNG(side: 16))]
        let down = await fetcher.fetch(URL(string: "https://down.test/")!)
        checkEqual(down, PageInfo(title: nil, hasIcon: true), "페이지가 오류여도 제목은 비우고 /favicon.ico 는 시도")

        PMStubProtocol.routes = [:]
        let none = await fetcher.fetch(URL(string: "https://none.test/")!)
        checkEqual(none, PageInfo(title: nil, hasIcon: false), "아무것도 못 읽으면 빈 결과")
        check(fetchStore.pngData(forHost: "none.test") == nil, "못 읽으면 아이콘 파일을 만들지 않는다")

        PMStubProtocol.requested = []
        let ftp = await fetcher.fetch(URL(string: "ftp://x.test/")!)
        checkEqual(ftp, PageInfo(title: nil, hasIcon: false), "http/https 가 아니면 요청하지 않는다")
        checkEqual(PMStubProtocol.requested, [], "요청 없음")
    }

    section("PageMetadata/encoding")
    let euc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
    let eucData = "<title>한글 제목</title>".data(using: euc)!
    checkEqual(WebPageMetadataFetcher.decodeHTML(eucData, encodingName: "euc-kr"), "<title>한글 제목</title>", "응답 charset(EUC-KR)으로 읽는다")
    checkEqual(WebPageMetadataFetcher.decodeHTML(Data("<title>한글</title>".utf8), encodingName: nil), "<title>한글</title>", "charset 이 없으면 UTF-8")
    checkEqual(WebPageMetadataFetcher.decodeHTML(Data("<title>한글</title>".utf8), encodingName: "no-such-charset"), "<title>한글</title>", "모르는 charset 은 UTF-8")
    let meta = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=EUC-KR\"><title>한글 제목</title>".data(using: euc)!
    checkEqual(WebPageMetadataFetcher.sniffedCharset(meta), "EUC-KR", "헤더에 charset 이 없으면 <meta> 에서 읽는다")
    checkEqual(WebPageMetadataFetcher.decodeHTML(meta, encodingName: nil).contains("한글 제목"), true, "<meta> charset(EUC-KR)으로 디코딩")
    var cut = "<title>한글</title>".data(using: euc)!
    cut.append(contentsOf: "가".data(using: euc)!.prefix(1)) // 본문 중간에서 멀티바이트 문자의 반쪽만 받은 경우
    checkEqual(WebPageMetadataFetcher.decodeHTML(cut, encodingName: "euc-kr"), "<title>한글</title>", "끝이 잘려도 앞부분은 정상으로 읽는다")
    let headCut = WebPageMetadataFetcher.truncatedAfterHead(Data("<HEAD><title>a</title></HEAD><body>한".utf8))
    checkEqual(String(decoding: headCut, as: UTF8.self), "<HEAD><title>a</title></HEAD>", "</head> 끝까지만 남긴다(대소문자 무시)")
    checkEqual(WebPageMetadataFetcher.truncatedAfterHead(Data("no head".utf8)), Data("no head".utf8), "</head> 가 없으면 그대로")

    section("PageMetadata/hardening")
    // 닫히지 않은 태그가 가득한 큰 문서도 빨리 끝난다(선형 시간이 아니면 여기서 멈춘다)
    let hostile = String(repeating: "<title ", count: 70_000) + String(repeating: "<link ", count: 70_000)
    checkEqual(PageMetadata.title(fromHTML: hostile), nil, "닫히지 않은 <title 이 가득해도 nil")
    checkEqual(PageMetadata.iconURLs(fromHTML: hostile, base: URL(string: "https://a.com")!).map(\.absoluteString), ["https://a.com/favicon.ico"], "닫히지 않은 <link 가 가득해도 /favicon.ico 만")
    checkEqual(PageMetadata.title(fromHTML: "<title>" + String(repeating: "가", count: 5000) + "</title>")?.count, 2000, "제목 원문은 2000자까지만 읽는다")

    for local in ["localhost", "a.localhost", "printer.local", "127.0.0.1", "10.1.2.3", "192.168.0.5", "172.16.0.1", "172.31.255.1", "169.254.1.1", "0.0.0.0", "[::1]", "fd00::1", "fe80::1"] {
        check(PageMetadata.isLocalNetworkHost(local), "\(local) 은 로컬 호스트")
    }
    for remote in ["example.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.0.1", "11.0.0.1", "localhost.example.com"] {
        check(!PageMetadata.isLocalNetworkHost(remote), "\(remote) 은 로컬 호스트 아님")
    }
    let crossHost = """
    <link rel="icon" href="http://192.168.0.7/x.png"><link rel="icon" href="http://localhost:8080/y.png"><link rel="icon" href="https://cdn.a.net/z.png">
    """
    checkEqual(PageMetadata.iconURLs(fromHTML: crossHost, base: URL(string: "https://a.com/")!).map(\.absoluteString),
               ["https://cdn.a.net/z.png", "https://a.com/favicon.ico"], "다른 호스트의 로컬·사설 주소 아이콘은 뺀다")
    checkEqual(PageMetadata.iconURLs(fromHTML: #"<link rel="icon" href="/x.png">"#, base: URL(string: "http://192.168.0.7/")!).first?.absoluteString,
               "http://192.168.0.7/x.png", "페이지 자신이 로컬 호스트이면 같은 호스트의 아이콘은 허용")

    let wide = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 5000, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }()
    checkEqual(FaviconStore.renderPNG(from: wide, pixels: 128), nil, "한 변이 4096px 를 넘는 이미지는 디코딩하지 않고 거른다")
    checkEqual(PageMetadata.title(fromHTML: "<title>a&#0;b\u{7}c\t d&#7;</title>"), "abc d", "제목의 제어 문자는 뺀다")

    func redirect(_ from: String, _ to: String) -> Bool { WebPageMetadataFetcher.allowsRedirect(from: URL(string: from), to: URL(string: to)) }
    check(redirect("https://a.com/", "https://www.a.com/x"), "공개 주소끼리 리다이렉트는 따라간다")
    check(!redirect("https://a.com/", "http://127.0.0.1/x"), "공개 주소 → 루프백은 막는다")
    check(!redirect("https://a.com/", "http://192.168.0.1/"), "공개 주소 → 사설 IP 는 막는다")
    check(!redirect("https://a.com/", "http://printer.local/"), "공개 주소 → .local 은 막는다")
    check(redirect("http://192.168.0.7/a", "http://192.168.0.7/b"), "로컬 호스트 안에서의 이동은 허용")
    check(!redirect("https://a.com/", "ftp://b.com/"), "http/https 가 아니면 막는다")

    for local in ["127.1", "2130706433", "0x7f.0.0.1", "0177.0.0.1", "localhost.", "foo.local.", "[::ffff:127.0.0.1]", "[::ffff:7f00:1]", "::ffff:10.0.0.1",
                  "100.64.0.1", "fec0::1", "[::]", "::7f00:1", "64:ff9b::7f00:1", "64:ff9b::a00:1"] {
        check(PageMetadata.isLocalNetworkHost(local), "\(local) 도 로컬 호스트(시스템이 해석하는 표기)")
    }
    for remote in ["[::ffff:8.8.8.8]", "100.63.0.1", "100.128.0.1", "2001:db8::1", "[2606:4700::1111]", "1.1.1.1", "64:ff9b::808:808", "::808:808"] {
        check(!PageMetadata.isLocalNetworkHost(remote), "\(remote) 은 로컬 호스트 아님")
    }
    let withSVG = """
    <link rel="icon" type="image/svg+xml" href="/icon.svg"><link rel="icon" href="/vector.SVG?v=1"><link rel="icon" href="/real.png">
    """
    checkEqual(PageMetadata.iconURLs(fromHTML: withSVG, base: URL(string: "https://a.com/")!).map(\.absoluteString),
               ["https://a.com/real.png", "https://a.com/favicon.ico"], "SVG 아이콘은 후보에서 뺀다")
    check(!WebPageMetadataFetcher.decodeHTML(Data("<meta charset=utf-16><title>한글</title>".utf8), encodingName: nil).contains("\u{FFFD}")
          && WebPageMetadataFetcher.decodeHTML(Data("<meta charset=utf-16><title>한글</title>".utf8), encodingName: nil).contains("한글"), "UTF-16 <meta> 선언은 무시하고 UTF-8 로 읽는다")
    checkEqual(PageMetadata.title(fromHTML: "<title>a\u{202E}b</title>"), "ab", "글자 방향 바꾸는 문자는 뺀다")
}
