import AppKit
import SwiftUI

/// 图片放大窗视图（§4.3）：原图 fit 满窗 + 十字准星与坐标读数 + 整图点词回调 + ESC 关闭。
///
/// 前提（§4.4，勿破坏）：图片**恒 fit 满窗**，不引入 ScrollView / magnification / 缩放手势——
/// `ImageGeometry.normalizedPoint` 的换算公式只在「无滚动无缩放」下成立。
/// 放大手段就是拉大窗口（窗口样式自带最大化按钮）。
struct ImageZoomView: View {
    /// 最近一次点击：只存**归一化**坐标，显示区坐标按当前 bounds 实时反解——
    /// 存显示区快照会在窗口 resize 后漂移，而归一化点与发给模型的坐标同口径，永不漂移。
    private struct Crosshair {
        let normalized: CGPoint
    }

    let image: NSImage
    /// (归一化点 0…1, 点击点 Cocoa 全局屏幕坐标 rect)
    let onTap: (CGPoint, CGRect) -> Void
    @State private var crosshair: Crosshair?

    var body: some View {
        ZoomImageView(image: image,
                      onTap: { point, screenRect in
                          crosshair = Crosshair(normalized: point)
                          onTap(point, screenRect)
                      })
            // 准星与读数叠加在图上，不参与布局也不吃鼠标事件（点穿到图 → 可继续点下一个词）
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    if let c = crosshair { marks(c, in: geo.size) }
                }
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private func marks(_ c: Crosshair, in size: CGSize) -> some View {
        // 归一化 → 当前显示区坐标：用与绘制/换算同一份 fitRect，resize 后自动重算不漂移
        let r = ImageGeometry.fitRect(imageSize: image.size, container: size)
        let p = CGPoint(x: r.origin.x + c.normalized.x * r.width, y: r.origin.y + c.normalized.y * r.height)
        // 十字线：两条 1pt 线跨满显示区
        Path { path in
            path.move(to: CGPoint(x: 0, y: p.y))
            path.addLine(to: CGPoint(x: size.width, y: p.y))
            path.move(to: CGPoint(x: p.x, y: 0))
            path.addLine(to: CGPoint(x: p.x, y: size.height))
        }
        .stroke(Color.red.opacity(0.85), lineWidth: 1)

        Circle()
            .stroke(Color.red, lineWidth: 1.5)
            .frame(width: 18, height: 18)
            .position(p)

        Text(String(format: "x %.0f%%　y %.0f%%", c.normalized.x * 100, c.normalized.y * 100))
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            // 读数跟随光标但不出窗：x 就近左移、y 触底上移
            .position(x: min(max(60, p.x), max(60, size.width - 60)),
                      y: min(max(14, p.y - 18), max(14, size.height - 14)))
    }
}

/// 图片显示区：用 `NSViewRepresentable` 承载 AppKit 视图而非纯 SwiftUI 实现，原因有二：
/// ① 屏幕坐标换算按规格钉死为 `NSView.convert(_:to: nil)` → `window.convertToScreen(_:)`
///    （多屏各自 frame、y 向上由系统保证；手搓 `NSScreen.main.frame.height - y` 单屏公式多屏即错），
///    拿得到真实 NSView 才能走这条路径；
/// ② 点击落在 fit 后的空白（letterbox）时直接丢弃，与缩略图路径的 0…1 守卫同源，
///    不会把窗内空白处算成图上坐标。
/// 准星/读数留在 SwiftUI 侧叠加（`allowsHitTesting(false)` 不吃事件），AppKit 侧只负责图与坐标。
private struct ZoomImageView: NSViewRepresentable {
    let image: NSImage
    /// (归一化点 0…1, 点击点 Cocoa 全局屏幕坐标 rect)
    let onTap: (CGPoint, CGRect) -> Void

    func makeNSView(context: Context) -> ZoomImageNSView {
        let v = ZoomImageNSView()
        v.image = image
        v.onTap = { point, screenRect in
            MainActor.assumeIsolated { self.onTap(point, screenRect) }
        }
        return v
    }

    func updateNSView(_ nsView: ZoomImageNSView, context: Context) {
        nsView.image = image
    }
}

private final class ZoomImageNSView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    /// (归一化点 0…1, 点击点 Cocoa 全局屏幕坐标 rect)
    var onTap: ((CGPoint, CGRect) -> Void)?

    /// 与缩略图路径同口径（视图局部 y 向下），准星才能直接叠在同一组坐标上
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // 图片恒 fit 满窗：与坐标换算共用 ImageGeometry.fitRect，绘制与换算必须同源（否则二者会漂移）
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard let image else { return }
        image.draw(in: ImageGeometry.fitRect(imageSize: image.size, container: bounds.size))
    }

    // 接管 first responder，否则 ESC 落在 NSHostingView 上、图片窗的 keyDown 收不到（开窗即接管，不等用户点一下）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil) // 视图局部坐标（与缩略图路径同向，y 向下）
        guard let p = ImageGeometry.normalizedPoint(viewSize: bounds.size, imagePixelSize: image?.size ?? .zero, click: local),
              let win = window else { return }
        // 屏幕坐标两段契约（§4.4）：视图→窗口（NSView.convert(to: nil)）→Cocoa 全局屏幕（y 向上、多屏各自 frame）
        let winPoint = convert(local, to: nil)
        // convertToScreen 只收 rect，用零尺寸 rect 取 origin（等价于取点，多屏由系统按所在屏换算）
        let screenPoint = win.convertToScreen(NSRect(origin: winPoint, size: .zero)).origin
        onTap?(p, CGRect(origin: screenPoint, size: .zero))
    }

    /// ESC 关图片窗；面板可见时 ESC 已被 Carbon 热键消费为「藏面板」，两级各按一次（§4.3）
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // kVK_Escape
            WindowManager.shared.closeImageWindow()
            return
        }
        super.keyDown(with: event)
    }
}
