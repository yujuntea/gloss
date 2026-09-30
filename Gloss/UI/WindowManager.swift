import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var readerWindow: NSWindow?
    private var imageWindow: NSWindow? // 图片放大窗：生命周期绑定栈根会话（换根即关，D-f）
    private var currentReaderVM: ReaderViewModel? // 旧精读任务的生命周期锚点

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        activate()
        let w = settingsWindow ?? makeWindow(title: "Gloss 设置", size: NSSize(width: 700, height: 540))
        settingsWindow = w
        w.contentView = NSHostingView(rootView: SettingsView())
        w.makeKeyAndOrderFront(nil)
    }

    func showHistory() {
        activate()
        let w = historyWindow ?? makeWindow(title: "Gloss 历史记录", size: NSSize(width: 600, height: 520))
        historyWindow = w
        w.contentView = NSHostingView(rootView: HistoryView())
        w.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        activate()
        let w = onboardingWindow ?? makeWindow(title: "欢迎使用 Gloss", size: NSSize(width: 600, height: 490))
        onboardingWindow = w
        w.contentView = NSHostingView(rootView: OnboardingView())
        w.makeKeyAndOrderFront(nil)
    }

    func closeOnboarding() {
        onboardingWindow?.orderOut(nil)
    }

    func showReader(text: String) {
        activate()
        // 替换内容前取消旧精读任务（防止强捕获的 Task 继续发请求——L2a P1-6）
        currentReaderVM?.cancel()
        currentReaderVM = nil
        let w = readerWindow ?? makeWindow(title: "Gloss 精读", size: NSSize(width: 1100, height: 720))
        readerWindow = w
        w.delegate = self
        let vm = ReaderViewModel(text: text)
        currentReaderVM = vm
        // 每次都装全新 NSHostingView，不能复用后换 rootView：往已有 hosting view 上赋值 rootView
        // 不会触发 onAppear/onDisappear（实测静默跳过），视图里的 @State 选中的 tab 还会跨内容残留
        w.contentView = NSHostingView(rootView: ReaderView(vm: vm))
        w.makeKeyAndOrderFront(nil)
        vm.start() // 显式启动：任务归 WindowManager 所有，不依赖视图生命周期回调
        GlossLog.info("reader opened chars=\(text.count)")
    }

    /// 图片放大窗（§4.3）：原图 fit 满窗的独立窗口，供密集截图上「看得清地点词」。
    /// onTap 收 (归一化点 0…1, 点击点 Cocoa 屏幕坐标 rect)。
    func showImage(image: NSImage, onTap: @escaping (CGPoint, CGRect) -> Void) {
        activate()
        let w = imageWindow ?? makeWindow(title: "Gloss 图片", size: NSSize(width: 1000, height: 700))
        imageWindow = w
        w.delegate = self
        // 与 showReader 同理：每次装全新 NSHostingView，复用 hosting view 换 rootView 不触发 onAppear
        w.contentView = NSHostingView(rootView: ImageZoomView(image: image) { point, screenRect in
            MainActor.assumeIsolated { onTap(point, screenRect) }
        })
        // 每次开窗都重新落到**鼠标所在屏**的可见区正中：makeWindow 的 center() 在多屏且副屏
        // visibleFrame 异常时会落到屏幕外（实机验收实证：窗口开到 y=-988 完全不可见）。跟随鼠标屏
        // 与面板定位惯例一致（用户点的是面板里的缩略图，鼠标通常就在那块屏上）。
        if let screen = screenUnderMouse() ?? NSScreen.main {
            let vf = screen.visibleFrame
            let size = w.frame.size
            // 屏比窗口还矮时（罕见的多屏布局）按可见高度收缩，避免又顶出屏外
            w.setContentSize(NSSize(width: min(size.width, vf.width), height: min(size.height, vf.height)))
            let fitted = w.frame.size
            w.setFrameOrigin(CGPoint(x: vf.midX - fitted.width / 2, y: vf.midY - fitted.height / 2))
        }
        w.makeKeyAndOrderFront(nil)
        GlossLog.info("image window opened \(Int(image.size.width))x\(Int(image.size.height)) frame=\(w.frame)")
    }

    private func screenUnderMouse() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    /// 换栈根即关图（D-f）：否则旧图点词卡会压在新根上（跨会话混栈），换根为文本卡后窗内点击又是静默死路
    func closeImageWindow() {
        imageWindow?.orderOut(nil)
        imageWindow = nil
    }

    /// 图片窗的跨类型判同：PanelController 的 local monitor 要排除图内点击，不能直接读 private 属性
    func isImageWindow(_ w: NSWindow?) -> Bool {
        guard let w, let imageWindow else { return false }
        return w === imageWindow
    }

    /// 关窗必须走这里取消跑批：实测关窗/最小化不触发 onDisappear（视图仍在窗层级里），
    /// 只靠 ReaderView 的 onDisappear 会让任务在关窗后继续发请求写缓存。
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === readerWindow {
            currentReaderVM?.cancel()
            currentReaderVM = nil
            return
        }
        // 图片窗没有归窗管理的可取消任务（点词请求归 SessionCoordinator），断开引用即可
        if w === imageWindow { imageWindow = nil }
    }

    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }
}
