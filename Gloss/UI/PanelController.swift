import AppKit
import SwiftUI

/// 不抢焦点浮窗（NSPanel nonactivating + floating + canJoinAllSpaces/fullScreenAuxiliary）。
/// ESC=Carbon 消费式热键随显隐装拆；外点=全局鼠标监听（免权限）；定位=选区优先/鼠标兜底+边缘钳制。
/// 用户手动拖放过面板后，位置被记忆并在后续 ⌥D 复用（拖放位置失效时回退选区跟随）。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResultPanelView>?
    private var monitors: [Any] = []
    private var maxContentHeight: CGFloat = 500
    private var anchoredTop = false
    /// 程序化 setFrame 期间置位：windowDidMove 据此区分"程序定位"与"用户拖动"。
    /// 警告：勿引入 setFrame(display:animate:true) 等动画路径——动画下 windowDidMove 异步发出，会绕过该标志误存。
    private var isProgrammaticMove = false
    private static let dragXKey = "panel.customTopX"
    private static let dragTopYKey = "panel.customTopY"
    /// 验收/演示钩子：指定浮窗位置（Cocoa 全局坐标）
    var positionOverride: CGPoint?

    var isVisible: Bool { panel?.isVisible ?? false }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                        styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.delegate = self
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.backgroundColor = NSColor.windowBackgroundColor
        let hv = NSHostingView(rootView: ResultPanelView())
        p.contentView = hv
        hostingView = hv
        return p
    }

    func show(near bounds: CGRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        maxContentHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.65
        if let p = positionOverride {
            anchoredTop = false
            move(p, panel: panel)
        } else if let saved = restoredOrigin(panelSize: panel.frame.size) {
            // 尊重用户上次手动拖放的位置；顶边固定，内容增高向下延伸
            anchoredTop = true
            move(saved, panel: panel)
        } else {
            let mouse = NSEvent.mouseLocation
            if let b = bounds {
                anchoredTop = positionBySelection(panel, sel: b, mouse: mouse)
            } else {
                anchoredTop = positionByMouse(panel, mouse: mouse)
            }
        }
        installMonitors()
        HotkeyManager.shared.registerEscape { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.resizeToContent() }
        GlossLog.info("panel shown")
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        removeMonitors()
        HotkeyManager.shared.unregisterEscape()
        SessionCoordinator.shared.panelDidHide()
    }

    func resizeToContent() {
        guard let panel, panel.isVisible else { return }
        applyHeight(panel)
        // 切卡（返回/换卡）时本轮 SwiftUI 布局尚未完成，fittingSize 可能读到上一张卡的中间值而算出
        // 偏小高度，且此后 revision 不再变化、不会自愈（实机验收实证：点 chips 进词卡再返回，卡停在
        // 120pt 下限、正文被压扁）。下一轮 runloop 布局完成后再量一次即可收敛。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.applyHeight(panel)
        }
    }

    private func applyHeight(_ panel: NSPanel) {
        guard let hv = hostingView else { return }
        let h = max(120, min(maxContentHeight, hv.fittingSize.height))
        guard abs(h - panel.frame.height) > 1 else { return }
        var f = panel.frame
        let dy = h - panel.frame.height
        if anchoredTop { f.origin.y -= dy }
        f.size.height = h
        isProgrammaticMove = true
        panel.setFrame(f, display: false)
        isProgrammaticMove = false
    }

    // MARK: - 定位

    /// 程序化移动统一入口：置位屏蔽标志，防止 windowDidMove 把程序定位误存为用户拖放位置
    private func move(_ origin: CGPoint, panel: NSPanel) {
        isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        isProgrammaticMove = false
    }

    /// 用户上次手动拖放的浮窗位置；仅当该位置仍落在任一屏幕可见范围内时返回（否则回退选区跟随）。
    /// 存档语义=顶边（maxY）+左边缘：恢复时 y=记忆顶边−当前高度，与 anchoredTop"顶边固定向下延伸"自洽，免疫内容高度变化。
    private func restoredOrigin(panelSize: CGSize) -> CGPoint? {
        let ud = UserDefaults.standard
        guard let x = ud.object(forKey: Self.dragXKey) as? Double,
              let topY = ud.object(forKey: Self.dragTopYKey) as? Double else { return nil }
        var origin = CGPoint(x: CGFloat(x), y: CGFloat(topY) - panelSize.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(CGRect(origin: origin, size: panelSize)) }) else { return nil }
        let vf = screen.visibleFrame
        origin.x = min(max(vf.minX + 8, origin.x), vf.maxX - panelSize.width - 8)
        origin.y = min(max(vf.minY + 8, origin.y), vf.maxY - panelSize.height - 8)
        return origin
    }

    // MARK: - 用户拖动记录

    nonisolated func windowDidMove(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !isProgrammaticMove, let panel, panel.isVisible else { return }
            let ud = UserDefaults.standard
            ud.set(Double(panel.frame.origin.x), forKey: Self.dragXKey)
            ud.set(Double(panel.frame.maxY), forKey: Self.dragTopYKey)
        }
    }

    /// 返回是否为上方锚定（true=顶部固定，高度增长向下延伸）
    @discardableResult
    private func positionBySelection(_ panel: NSPanel, sel: CGRect, mouse: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return positionByMouse(panel, mouse: mouse)
        }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let cocoaSel = sel // CaptureResult 侧已完成 AX→Cocoa 转换
        var origin = CGPoint(x: cocoaSel.minX, y: cocoaSel.minY - 12 - size.height)
        var topAnchor = false
        if origin.y < vf.minY + 8 {
            origin = CGPoint(x: cocoaSel.minX, y: cocoaSel.maxY + 12)
            topAnchor = true
        }
        origin.x = min(max(vf.minX + 8, origin.x), vf.maxX - size.width - 8)
        if topAnchor { origin.y = min(origin.y, vf.maxY - size.height - 8) }
        move(origin, panel: panel)
        return topAnchor
    }

    @discardableResult
    private func positionByMouse(_ panel: NSPanel, mouse: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            isProgrammaticMove = true
            panel.center()
            isProgrammaticMove = false
            return false
        }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        var origin = CGPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        var topAnchor = false
        if origin.y < vf.minY + 8 {
            origin.y = mouse.y + 12
            topAnchor = true
        }
        origin.x = min(max(vf.minX + 8, origin.x), vf.maxX - size.width - 8)
        if topAnchor { origin.y = min(origin.y, vf.maxY - size.height - 8) }
        move(origin, panel: panel)
        return topAnchor
    }

    // MARK: - 外部事件

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if SessionCoordinator.shared.pinned { return }
                let loc = NSEvent.mouseLocation
                if !panel.frame.insetBy(dx: -2, dy: -2).contains(loc) {
                    self.hide()
                }
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: handler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] ev in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return ev }
                if SessionCoordinator.shared.pinned { return ev }
                // 图片窗内的点击是「连续点词」，不是「点浮窗外关窗」——排除掉，否则每次图内点击
                // 都会藏面板一次（面板闪隐 + ESC 热键拆装 + 旧流式卡被打成已取消）
                if WindowManager.shared.isImageWindow(ev.window) { return ev }
                if !panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) {
                    self.hide()
                }
                return ev
            }
        }) {
            monitors.append(m)
        }
    }

    private func removeMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }
}
