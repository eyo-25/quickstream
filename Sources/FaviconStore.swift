import AppKit
import Foundation

/// URL 슬롯의 파비콘 보관소: 호스트마다 PNG 파일 하나(`<호스트>.png`)를 설정 폴더 아래에 둔다.
/// 가져오기(`WebPageMetadataFetcher`)가 쓰고, 아이콘을 그리는 쪽(`SystemAppCatalog`)이 읽는다.
final class FaviconStore: @unchecked Sendable {
    /// 앱이 쓰는 기본 보관소(설정 폴더/favicons). `--support-dir` 로 설정 폴더를 바꾸면 따라간다.
    static let standard = FaviconStore(directory: AppInfo.supportDirectory.appendingPathComponent("favicons", isDirectory: true))

    /// 저장하는 아이콘 한 변(px). 타일에 그릴 때는 필요한 크기로 줄여 쓴다.
    static let storedPixels = 128

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// 호스트를 파일 이름으로: 소문자 영문자·숫자·`.`·`-` 만 남기고 나머지는 `_`. 비었거나 너무 길면 nil.
    static func fileName(forHost host: String) -> String? {
        let lowered = host.lowercased()
        guard !lowered.isEmpty, lowered.count <= 100 else { return nil }
        let safe = lowered.map { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" ? $0 : "_" }
        return String(safe) + ".png"
    }

    private func fileURL(forHost host: String) -> URL? {
        Self.fileName(forHost: host).map { directory.appendingPathComponent($0) }
    }

    /// 저장된 파비콘 PNG(없으면 nil)
    func pngData(forHost host: String) -> Data? {
        guard let url = fileURL(forHost: host) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 파일 수정 시각(없으면 0). 아이콘이 바뀌면 그리는 쪽의 캐시가 새로 만들어지게 하는 열쇠다.
    func revision(forHost host: String) -> TimeInterval {
        guard let url = fileURL(forHost: host),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return 0 }
        return date.timeIntervalSince1970
    }

    @discardableResult
    func save(png: Data, forHost host: String) -> Bool {
        guard let url = fileURL(forHost: host) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 원본 이미지 한 변의 허용 범위(px). 이보다 작거나 큰 이미지는 거른다(작은 파일이 거대한 캔버스를 선언해 메모리를 먹는 것을 막는다).
    static let sourceSideRange = 4...4096

    /// 이미지 데이터(PNG·ICO·JPEG·GIF 등 ImageIO 가 읽는 형식)를 `pixels` × `pixels` 투명 배경 PNG 로 그린다. 비율은 유지하고 가운데에 둔다.
    /// 여러 장이 든 파일(ICO)은 허용 범위 안에서 가장 큰 장을 쓴다. 읽을 수 없거나 모든 장이 허용 범위를 벗어나면 nil.
    /// 디코딩 전에 크기를 확인하고 `pixels` 이하 썸네일로 디코딩한다.
    static func renderPNG(from data: Data, pixels: Int) -> Data? {
        guard pixels > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: (index: Int, side: Int)?
        for index in 0..<min(CGImageSourceGetCount(source), 16) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
                  sourceSideRange.contains(width), sourceSideRange.contains(height) else { continue }
            if best == nil || max(width, height) > best!.side { best = (index, max(width, height)) }
        }
        guard let best,
              let image = CGImageSourceCreateThumbnailAtIndex(source, best.index, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixels,
              ] as CFDictionary),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let scale = min(CGFloat(pixels) / CGFloat(image.width), CGFloat(pixels) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2, width: width, height: height))
        guard let rendered = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
    }
}
