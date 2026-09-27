import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var readerWindow: NSWindow?
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

    /// 关窗必须走这里取消跑批：实测关窗/最小化不触发 onDisappear（视图仍在窗层级里），
    /// 只靠 ReaderView 的 onDisappear 会让任务在关窗后继续发请求写缓存。
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === readerWindow else { return }
        currentReaderVM?.cancel()
        currentReaderVM = nil
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
