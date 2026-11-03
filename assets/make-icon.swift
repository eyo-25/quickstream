import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 앱 아이콘 생성: 오비트 · 다크 글라스 · 네온 라벤더 모양을 CoreGraphics 로 직접 그린다(브라우저·Electron 불필요). 아이콘 색은 앱의 기본 포커스 색(민트)과 별개다.
// 사용: swift make-icon.swift <출력 .iconset 폴더>   — make-icon.sh 가 iconutil 로 icns 까지 만든다.
// 기하: 1024 캔버스, 824px 둥근 사각형, 반지름 262 궤도 위 92px 유리 타일 8개(12시가 선택), 가운데 원판.

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 1024 좌표계(y 아래로 증가, SVG 와 같음)로 그린다. `scale` 은 목표 픽셀/1024 이다:
/// CoreGraphics 의 그림자 블러는 CTM 배율의 영향을 받지 않는 장치 픽셀 단위라, 작은 크기에서 번짐이 과해지지 않도록 직접 곱해 준다.
func draw(_ ctx: CGContext, scale: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let lavender: UInt32 = 0xa277ff      // 아이콘 강조색(앱 기본 포커스 색과는 별개)
    let lavenderLight: UInt32 = 0xd2bfff // 같은 색을 흰색 쪽으로 밝힌 선(헤어라인)
    let panel = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), 185)

    // 배경 패널: 어두운 유리(위가 아주 약간 밝은 남보라 → 아래 거의 검정)
    ctx.saveGState()
    ctx.addPath(panel)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [rgb(0x1d1a3a), rgb(0x08070f)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    // 가운데에서 번지는 라벤더 기운(네온 불빛이 유리 안쪽을 물들이는 느낌)
    let ambience = CGGradient(colorsSpace: space, colors: [rgb(lavender, 0.30), rgb(lavender, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(ambience, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 430, options: [])
    // 위쪽 유리 광택
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xffffff, 0.12), rgb(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 480), options: [])
    ctx.restoreGState()

    // 패널 테두리: 빛이 닿는 위쪽은 밝고 아래로 갈수록 옅은 헤어라인
    ctx.saveGState()
    ctx.addPath(roundedRect(CGRect(x: 102, y: 102, width: 820, height: 820), 183))
    ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rim = CGGradient(colorsSpace: space, colors: [rgb(0xffffff, 0.42), rgb(0xffffff, 0.06)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // 타일이 놓이는 궤도
    ctx.setStrokeColor(rgb(lavender, 0.42)); ctx.setLineWidth(4)
    ctx.strokeEllipse(in: CGRect(x: 512 - 262, y: 512 - 262, width: 524, height: 524))

    // 가운데 원판 바깥 글로우(그림자로 번지게 한다)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46 * scale, color: rgb(lavender, 0.75))
    ctx.setFillColor(rgb(lavender, 0.5))
    ctx.fillEllipse(in: CGRect(x: 512 - 122, y: 512 - 122, width: 244, height: 244))
    ctx.restoreGState()

    // 가운데 원판: 어두운 면 + 안쪽의 라벤더 빛
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: 512 - 118, y: 512 - 118, width: 236, height: 236))
    ctx.clip()
    let hub = CGGradient(colorsSpace: space, colors: [rgb(0x6a4bc4), rgb(0x15122b)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(hub, startCenter: CGPoint(x: 512, y: 512 - 118 * 0.15), startRadius: 0, endCenter: CGPoint(x: 512, y: 512 - 118 * 0.15), endRadius: 118 * 1.15, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(lavenderLight)); ctx.setLineWidth(6)
    ctx.strokeEllipse(in: CGRect(x: 512 - 118, y: 512 - 118, width: 236, height: 236))

    // 8개 유리 타일. 12시 방향(1번)이 선택 상태: 면은 투명하게 두고 밝은 가장자리선과 이중 글로우로 빛난다(네온).
    let glass = CGGradient(colorsSpace: space, colors: [rgb(0xffffff, 0.20), rgb(0xffffff, 0.05)] as CFArray, locations: [0, 1])!
    for i in 0..<8 {
        let angle = Double.pi * 2 * Double(i) / 8
        let x = 512 + CGFloat(sin(angle)) * 262
        let y = 512 - CGFloat(cos(angle)) * 262
        let selected = i == 0
        let rect = CGRect(x: x - 46, y: y - 46, width: 92, height: 92)
        let tile = roundedRect(rect, 26)

        if selected {
            // 바깥 이중 글로우(가까운 것 + 넓은 것). 면 아래로 비치지 않게 어두운 받침 위에 그리고, 작은 크기에서도 읽히도록 각각 두 번 겹친다.
            for (blur, alpha) in [(28, 1.0), (28, 1.0), (84, 0.85), (84, 0.85)] as [(CGFloat, CGFloat)] {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: blur * scale, color: rgb(lavender, alpha))
                ctx.addPath(tile); ctx.setFillColor(rgb(0x0b0a18)); ctx.fillPath()
                ctx.restoreGState()
            }
        }

        // 유리 면(위가 더 밝다). 선택 타일은 라벤더 틴트를 얹는다.
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        ctx.drawLinearGradient(glass, start: CGPoint(x: x, y: rect.minY), end: CGPoint(x: x, y: rect.maxY), options: [])
        if selected {
            let tint = CGGradient(colorsSpace: space, colors: [rgb(lavender, 0.85), rgb(lavender, 0.42)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(tint, start: CGPoint(x: x, y: rect.minY), end: CGPoint(x: x, y: rect.maxY), options: [])
        }
        ctx.restoreGState()

        ctx.addPath(tile)
        ctx.setStrokeColor(selected ? rgb(lavenderLight) : rgb(0xffffff, 0.34))
        ctx.setLineWidth(selected ? 6 : 3)
        ctx.strokePath()
    }
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // 1024 좌표계를 목표 크기로 줄이고 y 를 뒤집는다
    let scale = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    draw(ctx, scale: scale)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG 를 쓸 수 없습니다: \(url.path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("사용: swift make-icon.swift <출력 .iconset 폴더>\n".utf8))
    exit(1)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(pixels: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
