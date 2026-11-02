import AppKit
import SwiftUI

// README 용 스크린샷 생성기. 화면·창을 캡처하지 않고, 앱의 실제 SwiftUI 뷰를 오프스크린으로 그려 PNG 로 쓴다.
//  - 오버레이: OverlayView(+OrbitScene) 에 OverlayModel/OverlayState 를 직접 주입해 ImageRenderer 로 그린다.
//  - 설정 창: SettingsRootView 를 화면에 올리지 않은 NSHostingView 로 그려(AppKit 컨트롤이 정상 렌더되도록) 창 틀 위에 합성한다.
// 모든 슬롯·탭·이름은 아래 데모 데이터다. 사용자 설정 파일·최근 앱·클립보드는 읽지 않는다.
// 사용법: qs-shots <출력 폴더> <Info.plist 경로>

// MARK: - 데모 데이터

struct DemoApp {
    let id: String
    let name: String
    let bundleId: String
    /// 아이콘을 읽을 후보 경로(먼저 존재하는 것)
    let paths: [String]
}

let demoApps: [DemoApp] = [
    DemoApp(id: "demo-safari", name: "Safari", bundleId: "com.apple.Safari",
            paths: ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"]),
    DemoApp(id: "demo-notes", name: "메모", bundleId: "com.apple.Notes", paths: ["/System/Applications/Notes.app"]),
    DemoApp(id: "demo-mail", name: "Mail", bundleId: "com.apple.mail", paths: ["/System/Applications/Mail.app"]),
    DemoApp(id: "demo-calendar", name: "캘린더", bundleId: "com.apple.iCal", paths: ["/System/Applications/Calendar.app"]),
    DemoApp(id: "demo-finder", name: "Finder", bundleId: "com.apple.finder", paths: ["/System/Library/CoreServices/Finder.app"]),
    DemoApp(id: "demo-terminal", name: "터미널", bundleId: "com.apple.Terminal", paths: ["/System/Applications/Utilities/Terminal.app"]),
    DemoApp(id: "demo-music", name: "음악", bundleId: "com.apple.Music", paths: ["/System/Applications/Music.app"]),
    DemoApp(id: "demo-photos", name: "사진", bundleId: "com.apple.Photos", paths: ["/System/Applications/Photos.app"]),
]

/// 설치 앱 선택기에 보일 추가 후보(데모)
let extraApps: [DemoApp] = [
    DemoApp(id: "x-calc", name: "계산기", bundleId: "com.apple.calculator", paths: ["/System/Applications/Calculator.app"]),
    DemoApp(id: "x-maps", name: "지도", bundleId: "com.apple.Maps", paths: ["/System/Applications/Maps.app"]),
    DemoApp(id: "x-msg", name: "메시지", bundleId: "com.apple.MobileSMS", paths: ["/System/Applications/Messages.app"]),
    DemoApp(id: "x-rem", name: "미리 알림", bundleId: "com.apple.reminders", paths: ["/System/Applications/Reminders.app"]),
]

func firstExistingPath(_ app: DemoApp) -> String? {
    app.paths.first { FileManager.default.fileExists(atPath: $0) }
}

var missingIcons: [String] = []

/// 시스템 앱 번들의 아이콘을 PNG 로. 없으면 nil(약어 타일로 남는다).
func demoIconPNG(_ app: DemoApp, pixels: Int) -> Data? {
    guard let path = firstExistingPath(app) else {
        if !missingIcons.contains(app.name) { missingIcons.append(app.name) }
        return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: path)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func demoSlots() -> [Slot] {
    demoApps.map { Slot(id: $0.id, name: $0.name, label: nil, action: .launchApp(bundleId: $0.bundleId, appPath: nil)) }
}

func demoSettings(_ edit: (inout OverlaySettings) -> Void = { _ in }) -> Settings {
    var s = Settings.defaults
    s.shortcut = "Alt+Q"
    s.tabs[0].slots = demoSlots()
    edit(&s.overlay)
    return s
}

/// 설정 파일을 읽지도 쓰지도 않는 메모리 저장소. 상태줄에는 일반 표기 경로만 보이게 한다.
final class DemoStore: SettingsStoring {
    var current: Settings
    var warning: String? { nil }
    /// `URL(string:)` 의 상대 URL 은 `.path` 가 입력 문자열 그대로라 사용자 홈 경로가 섞이지 않는다.
    let fileURL = URL(string: "~/Library/Application Support/QuickStream/settings.json")!
    init(_ settings: Settings) { current = settings }
    func reload() -> Settings { current }
    func save(_ settings: Settings) -> ActionResult { current = settings; return .success }
}

/// 실제 앱을 실행·조회하지 않는 카탈로그. 아이콘은 시스템 번들에서만 읽는다.
final class DemoCatalog: AppCatalog {
    var onAppActivated: ((RunningApp) -> Void)?
    private var cache: [String: Data] = [:]
    func runningApps() -> [RunningApp] { [] }
    func frontmostApp() -> RunningApp? { nil }
    func activate(bundleId: String, pid: Int32?) async -> ActionResult { .success }
    func refocus(bundleId: String, pid: Int32?) -> Bool { false }
    func open(bundleId: String?, appPath: String?) async -> ActionResult { .success }
    func installedApps() async -> [InstalledApp] {
        (demoApps + extraApps).compactMap { app in
            guard let path = firstExistingPath(app) else { return nil }
            return InstalledApp(bundleId: app.bundleId, name: app.name, altName: nil, appPath: path)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func iconPNG(for target: IconTarget, pixels: Int) -> Data? {
        guard case let .bundleId(id) = target, let app = (demoApps + extraApps).first(where: { $0.bundleId == id }) else { return nil }
        let key = "\(id)#\(pixels)"
        if let data = cache[key] { return data }
        let data = demoIconPNG(app, pixels: pixels)
        if let data { cache[key] = data }
        return data
    }
}

// MARK: - 오버레이 상태

func overlayState(_ o: OverlaySettings, selected: Int = 0) -> OverlayState {
    let slotViews: [SlotView?] = demoApps.map { app in
        SlotView(id: app.id, name: app.name, label: slotInitials(app.name), verb: "LAUNCH", iconPNG: demoIconPNG(app, pixels: 160))
    }
    let tabs = [
        TabView(id: "pinned", name: "고정 앱", caption: "PINNED", slots: slotViews),
        TabView(id: "recent", name: "최근 앱", caption: "RECENT", slots: slotViews.reversed()),
    ]
    return OverlayState(tabs: tabs, activeTab: 0, alpha: o.alpha, radius: o.radius,
                        ringRadius: o.ringSize, centerRadius: o.centerSize, centerBorder: o.centerBorder,
                        theme: o.theme, namePlacement: o.namePlacement, showNumbers: o.showNumbers,
                        bodyTheme: o.bodyTheme, focusStyle: o.focusStyle, focusHex: o.focusHex,
                        showTileLabels: o.showTileLabels, solidBacking: o.solidBacking,
                        centerNameWeight: o.centerNameWeight, centerNameSize: o.centerNameSize,
                        glassTintHex: o.glassTintHex, focusGlow: o.focusGlow)
}

// MARK: - 가상 배경

func demoColor(_ hex: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
}

enum BackdropStyle { case night, pastel, sunset }

/// 데스크톱 느낌의 가상 배경: 다색 그라데이션 + 흐릿한 창 모형 + 글라스 뒤로 비치는 대비 있는 도형·큰 글자.
/// 위치는 캔버스 비율로 정해 크기가 달라도 같은 구도가 된다. 실제 배경화면·창은 전혀 쓰지 않는다.
struct Backdrop: View {
    let style: BackdropStyle
    let size: CGSize
    /// true 면 링 뒤의 큰 글자·코드 줄을 빼고 도형도 중앙에서 비껴 둔다(대문 이미지용)
    var calm = false

    private var base: [Color] {
        switch style {
        case .night: return [demoColor(0x17123a), demoColor(0x2c1d6a), demoColor(0x0e2a5c)]
        case .pastel: return [demoColor(0xffdff0), demoColor(0xdbe7ff), demoColor(0xd6fbea)]
        case .sunset: return [demoColor(0xff9a5a), demoColor(0xff5c7c), demoColor(0x512a86)]
        }
    }
    private var blobs: [Color] {
        switch style {
        case .night: return [demoColor(0x7a4dff), demoColor(0x20b8ff), demoColor(0xff4fa0)]
        case .pastel: return [demoColor(0xffa6d2), demoColor(0xa8cbff), demoColor(0xb9ffd2)]
        case .sunset: return [demoColor(0xffd166), demoColor(0xff6a8d), demoColor(0x7b3fe4)]
        }
    }
    private var dark: Bool { style != .pastel }
    private var windowFill: Color {
        switch style {
        case .night: return demoColor(0x120f2c, 0.82)
        case .pastel: return Color.white.opacity(0.82)
        case .sunset: return demoColor(0x2a1238, 0.62)
        }
    }
    private var ink: Color { dark ? Color.white.opacity(0.55) : demoColor(0x3a3f55, 0.55) }
    private var hot: Color {
        switch style {
        case .night: return demoColor(0x27e0ff)
        case .pastel: return demoColor(0xff5a7a)
        case .sunset: return demoColor(0xffe066)
        }
    }
    private var cool: Color {
        switch style {
        case .night: return demoColor(0xff4fa0)
        case .pastel: return demoColor(0x3a6bff)
        case .sunset: return demoColor(0x22d3c5)
        }
    }

    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }

    var body: some View {
        let u = min(size.width, size.height)
        return ZStack {
            LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(blobs[0].opacity(0.55)).frame(width: u * 0.9).blur(radius: u * 0.12).position(at(0.18, 0.22))
            Circle().fill(blobs[1].opacity(0.5)).frame(width: u * 0.8).blur(radius: u * 0.12).position(at(0.85, 0.3))
            Circle().fill(blobs[2].opacity(0.5)).frame(width: u * 0.9).blur(radius: u * 0.14).position(at(0.6, 0.95))

            // 창 모형(흐릿)
            window(title: "Draft", w: u * 0.62, h: u * 0.42, accent: hot, seed: 1).position(at(0.16, 0.30)).rotationEffect(.degrees(-3))
            window(title: "Preview", w: u * 0.58, h: u * 0.40, accent: cool, seed: 2).position(at(0.86, 0.68)).rotationEffect(.degrees(2.5))
            window(title: "Notes", w: u * 0.5, h: u * 0.34, accent: hot, seed: 3).position(at(0.80, 0.14)).rotationEffect(.degrees(-1.5))

            // 글라스 뒤로 비치는 도형·글자(대비)
            if calm {
                Circle().fill(hot.opacity(0.9)).frame(width: u * 0.26).position(at(0.36, 0.40))
                RoundedRectangle(cornerRadius: u * 0.03, style: .continuous).fill(cool.opacity(0.9))
                    .frame(width: u * 0.5, height: u * 0.06).rotationEffect(.degrees(-18)).position(at(0.64, 0.62))
                Circle().stroke(Color.white.opacity(0.7), lineWidth: u * 0.012).frame(width: u * 0.18).position(at(0.68, 0.32))
            } else {
                Circle().fill(hot).frame(width: u * 0.34).position(at(0.40, 0.46))
                RoundedRectangle(cornerRadius: u * 0.03, style: .continuous).fill(cool)
                    .frame(width: u * 0.66, height: u * 0.075).rotationEffect(.degrees(-18)).position(at(0.52, 0.56))
                Circle().stroke(Color.white.opacity(dark ? 0.85 : 0.95), lineWidth: u * 0.02).frame(width: u * 0.24).position(at(0.66, 0.42))
                // 글자는 중앙 원(이름이 뜨는 곳)을 피해 위·아래 빈틈에 둔다
                Text("Aa 12:30").font(.system(size: u * 0.07, weight: .heavy, design: .rounded))
                    .foregroundStyle(dark ? Color.white : demoColor(0x232842)).position(at(0.50, 0.335))
                Text("draw(tiles)").font(.system(size: u * 0.028, weight: .bold, design: .monospaced))
                    .foregroundStyle(dark ? hot : demoColor(0x1f2a5a)).position(at(0.5, 0.715))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 제목 줄 + 글줄 모형이 있는 둥근 사각형(살짝 흐리게)
    private func window(title: String, w: CGFloat, h: CGFloat, accent: Color, seed: Int) -> some View {
        let rows = max(3, Int(h / 30))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(windowFill)
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1)
            HStack(spacing: 6) {
                Circle().fill(demoColor(0xff5f57)).frame(width: 10, height: 10)
                Circle().fill(demoColor(0xfebc2e)).frame(width: 10, height: 10)
                Circle().fill(demoColor(0x28c840)).frame(width: 10, height: 10)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink).padding(.leading, 8)
            }
            .padding(14)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<rows, id: \.self) { i in
                    let width = w * (0.35 + 0.5 * CGFloat(((i * 37 + seed * 53) % 100)) / 100)
                    Capsule().fill(i % 3 == 0 ? accent.opacity(0.7) : ink.opacity(0.5)).frame(width: width, height: 9)
                }
            }
            .padding(.horizontal, 20).padding(.top, 52)
        }
        .frame(width: w, height: h)
        .blur(radius: 1.6)
    }
}

// MARK: - 렌더 도구

/// 그라데이션·블러의 미세한 디더 잡음이 PNG 압축을 망치므로, 채널 하위 비트를 잘라(`mask`) 용량을 줄인다. 눈에 띄는 띠는 생기지 않는 수준만 쓴다.
func quantized(_ image: CGImage, mask: UInt8) -> CGImage {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return image }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    for i in 0..<(w * h) {
        bytes[i * 4] &= mask; bytes[i * 4 + 1] &= mask; bytes[i * 4 + 2] &= mask
    }
    return ctx.makeImage() ?? image
}

/// 렌더·쓰기 실패 횟수와 실제로 만든 파일 이름. 하나라도 실패하면 종료 코드를 0 이 아니게 해, 일부만 갱신된 채 성공처럼 보이지 않게 한다.
var shotFailures = 0
var shotWritten = Set<String>()

@MainActor
func pngData(cgImage: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: quantized(cgImage, mask: 0xF8)).representation(using: .png, properties: [:])
}

@MainActor
func writePNG(_ view: some View, size: CGSize, scale: CGFloat = 1, to url: URL) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage, let data = pngData(cgImage: cg) else {
        FileHandle.standardError.write(Data("렌더 실패: \(url.lastPathComponent)\n".utf8))
        shotFailures += 1
        return
    }
    do {
        try data.write(to: url)
    } catch {
        FileHandle.standardError.write(Data("쓰기 실패: \(url.lastPathComponent): \(error.localizedDescription)\n".utf8))
        shotFailures += 1
        return
    }
    shotWritten.insert(url.lastPathComponent)
    print("\(url.lastPathComponent): \(cg.width)x\(cg.height) \(data.count / 1024)KB")
}

/// 오버레이 한 장면: 가상 배경 위에 실제 OverlayView 를 놓는다. 링 중심은 `center`(기본: 캔버스 중앙).
/// 모델은 뷰가 살아 있는 동안 유지돼야 하므로 호출 측이 `keep` 에 보관한다.
@MainActor
final class ModelKeeper {
    static var models: [OverlayModel] = []
}

@MainActor
func overlayScene(_ o: OverlaySettings, backdrop: BackdropStyle, size: CGSize, center: CGPoint? = nil, selected: Int = 0, backdropSize: CGSize? = nil, calm: Bool = true) -> some View {
    let model = OverlayModel()
    model.present(overlayState(o))
    // 등장 모션을 건너뛴 정지 상태로 그린다
    model.appeared = true
    model.selected = selected
    model.ringCenter = center ?? CGPoint(x: size.width / 2, y: size.height / 2)
    ModelKeeper.models.append(model)
    return ZStack {
        Backdrop(style: backdrop, size: backdropSize ?? size, calm: calm)
        OverlayView(model: model)
    }
    .frame(width: size.width, height: size.height)
    .clipped()
}

/// 라벨(캡션) 한 줄을 셀 위/아래에 덧그리는 알약
struct CaptionPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - 설정 창

/// 화면에 올리지 않은 NSHostingView 로 설정 창 내용을 그린다(AppKit 컨트롤도 실제로 그려진다). 배율 `scale` 의 비트맵으로 돌려준다.
@MainActor
func renderSettingsContent(_ model: SettingsModel, size: CGSize, scale: CGFloat) -> NSImage? {
    let host = NSHostingView(rootView: SettingsRootView(model: model))
    host.frame = NSRect(origin: .zero, size: size)
    // 표시하지 않는 창: 오프스크린 렌더에서 레이아웃·appearance 가 창 없이 어긋나지 않게 하는 용도다.
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    // onAppear·Task·GeometryReader 환경값이 한 번씩 돌도록 런루프를 잠깐 돌린다
    for _ in 0..<6 {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
        host.layoutSubtreeIfNeeded()
    }
    let pixelsW = Int(size.width * scale), pixelsH = Int(size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsW, pixelsHigh: pixelsH, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    window.contentView = nil
    return image
}

/// 설정 창 틀(제목줄·신호등·그림자)을 코드로 그려 배경 위에 얹는다
struct WindowFrame: View {
    let content: NSImage
    let title: String
    let canvas: CGSize
    static let margin = CGSize(width: 44, height: 40)
    static let titleBar: CGFloat = 32

    var body: some View {
        let w = content.size.width, h = content.size.height
        return ZStack {
            Backdrop(style: .night, size: canvas)
            VStack(spacing: 0) {
                ZStack {
                    demoColor(0x2b2b30)
                    HStack(spacing: 8) {
                        Circle().fill(demoColor(0xff5f57)).frame(width: 12, height: 12)
                        Circle().fill(demoColor(0xfebc2e)).frame(width: 12, height: 12)
                        Circle().fill(demoColor(0x28c840)).frame(width: 12, height: 12)
                        Spacer()
                    }.padding(.leading, 14)
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                }
                .frame(width: w, height: Self.titleBar)
                Image(nsImage: content).resizable().frame(width: w, height: h)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.45), radius: 24, y: 12)
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

@MainActor
func settingsShot(_ name: String, settings: Settings, height: CGFloat = 680, to dir: URL, versionText: String,
                  configure: (SettingsModel) -> Void) {
    let catalog = DemoCatalog()
    let model = SettingsModel(store: DemoStore(settings), catalog: catalog, save: { _ in .success },
                              checkForUpdates: {}, versionText: { versionText })
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        model.resetFromStore()
        configure(model)
    }
    // 설치 앱 목록(비동기)이 채워질 때까지 기다린다
    for _ in 0..<10 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
    // resetFromStore 가 선택을 되돌릴 수 있어 목록이 채워진 뒤 한 번 더 적용한다
    withTransaction(transaction) { configure(model) }
    let size = CGSize(width: 960, height: height)
    guard let content = renderSettingsContent(model, size: size, scale: 1.5) else {
        FileHandle.standardError.write(Data("설정 렌더 실패: \(name)\n".utf8))
        shotFailures += 1
        return
    }
    let canvas = CGSize(width: size.width + WindowFrame.margin.width * 2, height: size.height + WindowFrame.titleBar + WindowFrame.margin.height * 2)
    writePNG(WindowFrame(content: content, title: "퀵스트림 설정", canvas: canvas), size: canvas, scale: 1.5, to: dir.appendingPathComponent(name))
}

// MARK: - 진입

@MainActor
func runAll() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        FileHandle.standardError.write(Data("usage: qs-shots <출력 폴더> <Info.plist>\n".utf8))
        exit(2)
    }
    let out = URL(fileURLWithPath: args[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let version = (NSDictionary(contentsOfFile: args[2])?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    let only = Set(args.dropFirst(3))
    func want(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
    func url(_ name: String) -> URL { out.appendingPathComponent(name) }

    let mint = "#19F9D8"
    let canvas = CGSize(width: 1200, height: 780)

    // 장면 기본(이미지 의미 고정): 다크 그레이 · 노랑 · 투명도 0.74 · 모서리 40 · 이름 위 · 중간 굵기 · 오비트 300/96/3.
    // 앱의 설정 기본값이 바뀌어도 README 가 말하는 장면이 달라지지 않게 값을 여기서 명시한다. (앱 기본 모양은 theme-*.png·settings-*.png 가 보여 준다.)
    func scene(_ theme: OverlayTheme, _ edit: (inout OverlaySettings) -> Void) -> OverlaySettings {
        var o = OverlaySettings()
        o.alpha = 0.74; o.radius = 40
        o.bodyTheme = .darkGray; o.focusStyle = .neon; o.focusHex = "#FAE32E"
        o.namePlacement = .top; o.centerNameWeight = .medium
        o.orbitSizes = ThemeSizes(ring: 300, center: 96, border: 3)
        o.theme = theme
        edit(&o)
        return o
    }
    func orbit(_ edit: (inout OverlaySettings) -> Void = { _ in }) -> OverlaySettings { scene(.orbit, edit) }
    func pie(_ edit: (inout OverlaySettings) -> Void = { _ in }) -> OverlaySettings { scene(.pie, edit) }
    // 앱 기본 모양(오비트 · 다크 글라스 · 네온 민트 · 투명도 0.4 …)에서 테마만 고른다
    func appDefault(_ theme: OverlayTheme) -> OverlaySettings { var o = OverlaySettings(); o.theme = theme; return o }

    // 테마 비교: 같은 본체·같은 배경, 테마만 다르다
    for (name, theme) in [("theme-orbit.png", OverlayTheme.orbit), ("theme-pie.png", .pie)] where want(name) {
        writePNG(overlayScene(appDefault(theme), backdrop: .night, size: canvas), size: canvas, to: url(name))
    }

    // 1. 대문 이미지
    if want("hero-orbit.png") {
        let o = orbit { $0.bodyTheme = .darkGlass; $0.focusStyle = .neon; $0.focusHex = mint; $0.orbitSizes.ring = 320; $0.orbitSizes.center = 104 }
        let size = CGSize(width: 1440, height: 880)
        writePNG(overlayScene(o, backdrop: .night, size: size), size: size, to: url("hero-orbit.png"))
    }

    // 2. 테마 × 스타일
    if want("overlay-orbit-neon.png") {
        writePNG(overlayScene(orbit { $0.focusStyle = .neon }, backdrop: .sunset, size: canvas), size: canvas, to: url("overlay-orbit-neon.png"))
    }
    if want("overlay-orbit-flat.png") {
        writePNG(overlayScene(orbit { $0.focusStyle = .flat }, backdrop: .sunset, size: canvas), size: canvas, to: url("overlay-orbit-flat.png"))
    }
    if want("overlay-pie-neon.png") {
        writePNG(overlayScene(pie { $0.focusStyle = .neon }, backdrop: .night, size: canvas), size: canvas, to: url("overlay-pie-neon.png"))
    }
    if want("overlay-pie-flat.png") {
        writePNG(overlayScene(pie { $0.focusStyle = .flat }, backdrop: .night, size: canvas), size: canvas, to: url("overlay-pie-flat.png"))
    }

    // 3. 본체 비교(같은 오비트·같은 배경)
    let bodies: [(String, OverlayBody, String)] = [
        ("body-dark-gray.png", .darkGray, GlassTints.defaultHex),
        ("body-dark-glass.png", .darkGlass, GlassTints.defaultHex),
        ("body-clear-glass-sky.png", .clearGlass, "#6FB1FF"),
        ("body-clear-glass-pink.png", .clearGlass, "#FF8FC7"),
    ]
    for (name, body, tint) in bodies where want(name) {
        let o = orbit { $0.bodyTheme = body; $0.glassTintHex = tint; $0.focusStyle = .neon; $0.focusHex = mint }
        // 글라스 비침이 보이도록 대비 있는 배경(calm 끔)을 쓴다
        writePNG(overlayScene(o, backdrop: .pastel, size: canvas, calm: false), size: canvas, to: url(name))
    }

    // 4. 포커스 색 6가지(2×3 격자)
    if want("focus-colors.png") {
        let colors: [(String, String)] = [("노랑", "#FAE32E"), ("민트", "#19F9D8"), ("핑크", "#FF7EDB"),
                                          ("파랑", "#7AA2F7"), ("보라", "#BD93F9"), ("코랄", "#E95378")]
        let cell = CGSize(width: 460, height: 490)
        let gap: CGFloat = 4
        let gridSize = CGSize(width: cell.width * 3 + gap * 2, height: cell.height * 2 + gap)
        let grid = VStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { c in
                        let (label, hex) = colors[r * 3 + c]
                        let o = orbit {
                            $0.bodyTheme = .darkGlass; $0.focusStyle = .neon; $0.focusHex = hex
                            $0.showTileLabels = false; $0.orbitSizes.ring = 184; $0.orbitSizes.center = 64
                        }
                        overlayScene(o, backdrop: .night, size: cell, center: CGPoint(x: cell.width / 2, y: cell.height / 2 - 14), backdropSize: cell)
                            .overlay(alignment: .bottom) { CaptionPill(text: label).padding(.bottom, 16) }
                    }
                }
            }
        }
        writePNG(grid.background(Color.black), size: gridSize, to: url("focus-colors.png"))
    }

    // 5. 불빛 켬/끔
    if want("glow-on-off.png") {
        let cell = CGSize(width: 700, height: 760)
        func one(_ glow: Bool, _ label: String) -> some View {
            let o = orbit { $0.bodyTheme = .darkGlass; $0.focusStyle = .neon; $0.focusHex = mint; $0.focusGlow = glow; $0.orbitSizes.ring = 250; $0.orbitSizes.center = 84 }
            return overlayScene(o, backdrop: .night, size: cell, center: CGPoint(x: cell.width / 2, y: cell.height / 2 + 14))
                .overlay(alignment: .top) { CaptionPill(text: label).padding(.top, 22) }
        }
        let size = CGSize(width: cell.width * 2, height: cell.height)
        writePNG(HStack(spacing: 0) { one(true, "불빛 켬"); one(false, "불빛 끔") }, size: size, to: url("glow-on-off.png"))
    }

    // 6. 파이 이름 위치
    if want("pie-name-center.png") {
        writePNG(overlayScene(pie { $0.namePlacement = .center; $0.focusStyle = .neon; $0.focusHex = mint }, backdrop: .night, size: canvas), size: canvas, to: url("pie-name-center.png"))
    }
    if want("pie-name-top.png") {
        writePNG(overlayScene(pie { $0.namePlacement = .top; $0.focusStyle = .neon; $0.focusHex = mint }, backdrop: .night, size: canvas), size: canvas, to: url("pie-name-top.png"))
    }

    // 7. 번호·타일 이름 숨김
    if want("orbit-no-labels.png") {
        writePNG(overlayScene(orbit { $0.showNumbers = false; $0.showTileLabels = false; $0.bodyTheme = .darkGlass; $0.focusStyle = .neon; $0.focusHex = mint }, backdrop: .sunset, size: canvas),
                 size: canvas, to: url("orbit-no-labels.png"))
    }

    // 8·9. 설정 창
    let base = demoSettings()
    if want("settings-general.png") {
        settingsShot("settings-general.png", settings: base, to: out, versionText: version) { $0.selection = .general }
    }
    if want("settings-panel-shape.png") {
        settingsShot("settings-panel-shape.png", settings: base, height: 1470, to: out, versionText: version) { $0.selection = .panel; $0.panelTab = .shape }
    }
    if want("settings-panel-color.png") {
        settingsShot("settings-panel-color.png", settings: base, height: 1360, to: out, versionText: version) { $0.selection = .panel; $0.panelTab = .color }
    }
    if want("settings-panel-display.png") {
        settingsShot("settings-panel-display.png", settings: base, height: 1345, to: out, versionText: version) { $0.selection = .panel; $0.panelTab = .display }
    }
    if want("settings-tabs.png") {
        settingsShot("settings-tabs.png", settings: base, height: 1232, to: out, versionText: version) { $0.selection = .tab("pinned"); $0.selectedSlot = 0 }
    }
    if want("settings-slot-editor.png") {
        settingsShot("settings-slot-editor.png", settings: base, height: 1905, to: out, versionText: version) { $0.selection = .tab("pinned"); $0.selectedSlot = 1 }
    }
    if want("settings-about.png") {
        settingsShot("settings-about.png", settings: base, to: out, versionText: version) { $0.selection = .about }
    }
    if want("settings-glass-neon.png") {
        let glass = demoSettings { $0.bodyTheme = .clearGlass; $0.glassTintHex = "#6FB1FF"; $0.focusStyle = .neon; $0.focusHex = mint }
        settingsShot("settings-glass-neon.png", settings: glass, height: 1650, to: out, versionText: version) { $0.selection = .panel; $0.panelTab = .color }
    }

    if !missingIcons.isEmpty { print("아이콘 없음(약어 타일): \(missingIcons.joined(separator: ", "))") }

    // 이름을 지정해 돌렸는데 만들지 못한 것(오타 포함)이 있으면 실패로 끝낸다
    let notMade = only.filter { !shotWritten.contains($0) }
    if !notMade.isEmpty {
        FileHandle.standardError.write(Data("만들지 못한 이미지: \(notMade.sorted().joined(separator: ", "))\n".utf8))
        shotFailures += notMade.count
    }
    if shotFailures > 0 {
        FileHandle.standardError.write(Data("실패 \(shotFailures)건\n".utf8))
        exit(1)
    }
}

// 창을 띄우지 않는다: NSApp 을 만들기만 하고 run 하지 않으며 Dock 에도 나타나지 않게 한다
MainActor.assumeIsolated {
    let shotsApp = NSApplication.shared
    shotsApp.setActivationPolicy(.prohibited)
    runAll()
}
