import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var readerWindow: NSWindow?
    private var readerHosting: NSHostingView<ReaderView>?
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
        let vm = ReaderViewModel(text: text)
        currentReaderVM = vm
        let view = ReaderView(text: text, externalVM: vm)
        if let hv = readerHosting {
            hv.rootView = view
        } else {
            let hv = NSHostingView(rootView: view)
            readerHosting = hv
            w.contentView = hv
        }
        w.makeKeyAndOrderFront(nil)
        GlossLog.info("reader opened chars=\(text.count)")
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
