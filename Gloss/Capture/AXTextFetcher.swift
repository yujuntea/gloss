import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// AX 取词（辅助功能权限）。主线程外调用。
enum AXTextFetcher {
    private static let kFocusedApp = "AXFocusedApplication" as CFString
    private static let kFocusedUI = "AXFocusedUIElement" as CFString
    private static let kSelectedText = "AXSelectedText" as CFString
    private static let kSelectedRange = "AXSelectedTextRange" as CFString
    private static let kBoundsForRange = "AXBoundsForRange" as CFString
    private static let kStringForRange = "AXStringForRange" as CFString
    private static let kChildren = "AXChildren" as CFString
    private static let kNumberOfChars = "AXNumberOfCharacters" as CFString

    private static let rangeType = AXValueType(rawValue: kAXValueCFRangeType)!
    private static let rectType = AXValueType(rawValue: kAXValueCGRectType)!

    /// 主线程外调用。预算 ~150ms，超时返回 nil。primaryHeight=主屏 Cocoa 高度（主线程预取注入——NSScreen 非主线程访问不安全，K3-P2-10）
    static func fetchWithBudget(_ seconds: Double = 0.15, primaryHeight: CGFloat?) -> CaptureResult? {
        let deadline = DispatchTime.now() + seconds
        guard let app = copyElement(AXUIElementCreateSystemWide(), kFocusedApp),
              let focused = copyElement(app, kFocusedUI) else { return nil }
        if let t = copyString(focused, kSelectedText), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CaptureResult(text: t, context: contextAround(focused), selectionBounds: selectionBounds(focused, primaryHeight: primaryHeight), origin: .hotkeyAX)
        }
        if let (el, text) = searchSelection(root: focused, deadline: deadline) {
            return CaptureResult(text: text, context: contextAround(el), selectionBounds: selectionBounds(el, primaryHeight: primaryHeight), origin: .hotkeyAX)
        }
        return nil
    }

    // MARK: - 基础读取

    private static func copyElement(_ el: AXUIElement, _ attr: CFString) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let raw = v else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    private static func copyString(_ el: AXUIElement, _ attr: CFString) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
        return v as? String
    }

    private static func copyNumber(_ el: AXUIElement, _ attr: CFString) -> Int? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let n = v as? NSNumber else { return nil }
        return n.intValue
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kChildren, &v) == .success, let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    // MARK: - 受限搜索（聚焦元素自身无选区时向下找，深度≤6 / 元素≤200 / 预算内）

    private static func searchSelection(root: AXUIElement, deadline: DispatchTime) -> (AXUIElement, String)? {
        struct Node { let el: AXUIElement; let depth: Int }
        var queue = [Node(el: root, depth: 0)]
        var head = 0
        var visited = 0
        while head < queue.count {
            if DispatchTime.now() > deadline || visited > 200 { return nil }
            let node = queue[head]
            head += 1
            visited += 1
            if node.depth > 6 { continue }
            if let t = copyString(node.el, kSelectedText), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (node.el, t)
            }
            for kid in children(of: node.el) {
                queue.append(Node(el: kid, depth: node.depth + 1))
            }
        }
        return nil
    }

    // MARK: - 选区 bounds / 上下文

    private static func selectedRange(_ el: AXUIElement) -> CFRange? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kSelectedRange, &v) == .success, let raw = v else { return nil }
        let rv = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(rv) == rangeType else { return nil }
        var r = CFRange()
        guard AXValueGetValue(rv, rangeType, &r) else { return nil }
        return r
    }

    static func selectionBounds(_ el: AXUIElement, primaryHeight: CGFloat? = nil) -> CGRect? {
        guard let range = selectedRange(el) else { return nil }
        var param = range
        guard let paramVal = AXValueCreate(rangeType, &param) else { return nil }
        var bv: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kBoundsForRange, paramVal, &bv) == .success,
              let braw = bv else { return nil }
        let bVal = unsafeDowncast(braw, to: AXValue.self)
        guard AXValueGetType(bVal) == rectType else { return nil }
        var axRect = CGRect()
        guard AXValueGetValue(bVal, rectType, &axRect) else { return nil }
        return cocoaRect(fromAX: axRect, primaryHeight: primaryHeight)
    }

    /// AX 坐标（主屏左上原点）→ Cocoa 全局坐标（主屏左下原点）
    static func cocoaRect(fromAX axRect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
        let h = primaryHeight ?? NSScreen.screens.first?.frame.height ?? axRect.maxY
        guard axRect.height > 0, h > 0 else { return axRect }
        return CGRect(x: axRect.minX, y: h - axRect.maxY, width: axRect.width, height: axRect.height)
    }

    private static func contextAround(_ el: AXUIElement) -> String? {
        guard let sel = selectedRange(el) else { return nil }
        let total = copyNumber(el, kNumberOfChars) ?? (sel.location + sel.length + 200)
        let loc = max(0, sel.location - 100)
        let len = min(total - loc, sel.length + 200)
        guard len > 0 else { return nil }
        var ctx = CFRange(location: loc, length: len)
        guard let p = AXValueCreate(rangeType, &ctx) else { return nil }
        var cv: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kStringForRange, p, &cv) == .success else { return nil }
        return cv as? String
    }
}
