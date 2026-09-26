import AppKit
import SwiftUI

/// 不抢焦点浮窗（NSPanel nonactivating + floating + canJoinAllSpaces/fullScreenAuxiliary）。
/// ESC=Carbon 消费式热键随显隐装拆；外点=全局鼠标监听（免权限）；定位=选区优先/鼠标兜底+边缘钳制。
@MainActor
final class PanelController {
    static let shared = PanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResultPanelView>?
    private var monitors: [Any] = []
    private var maxContentHeight: CGFloat = 500
    private var anchoredTop = false
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
            panel.setFrameOrigin(p)
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
        guard let panel, let hv = hostingView, panel.isVisible else { return }
        let ideal = hv.fittingSize.height
        let h = max(120, min(maxContentHeight, ideal))
        let old = panel.frame.height
        guard abs(h - old) > 1 else { return }
        var f = panel.frame
        let dy = h - old
        if anchoredTop { f.origin.y -= dy }
        f.size.height = h
        panel.setFrame(f, display: false)
    }

    // MARK: - 定位

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
        panel.setFrameOrigin(origin)
        return topAnchor
    }

    @discardableResult
    private func positionByMouse(_ panel: NSPanel, mouse: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            panel.center()
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
        panel.setFrameOrigin(origin)
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
