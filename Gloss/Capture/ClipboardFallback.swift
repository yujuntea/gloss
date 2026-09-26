import AppKit
import CoreGraphics
import Foundation

/// ⌘C 兜底取词 + 剪贴板快照恢复。主线程外调用。
enum ClipboardFallback {
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func take() -> Snapshot? {
            guard let items = NSPasteboard.general.pasteboardItems, !items.isEmpty else { return nil }
            let out = items.map { item -> [NSPasteboard.PasteboardType: Data] in
                var d: [NSPasteboard.PasteboardType: Data] = [:]
                for t in item.types {
                    if let data = item.data(forType: t) { d[t] = data }
                }
                return d
            }
            return Snapshot(items: out)
        }

        func restore() {
            let pb = NSPasteboard.general
            pb.clearContents()
            for dict in items {
                let item = NSPasteboardItem()
                for (t, data) in dict { item.setData(data, forType: t) }
                pb.writeObjects([item])
            }
        }
    }

    /// 模拟 ⌘C → 轮询剪贴板 → 读取 → 恢复（尽力而为）。
    static func fetchWithBudget(_ seconds: Double = 0.3) -> CaptureResult? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pb = NSPasteboard.general
        let snapshot = Snapshot.take()
        let before = pb.changeCount
        postCopy(pid: app.processIdentifier)
        let deadline = DispatchTime.now() + seconds
        var text: String?
        while DispatchTime.now() < deadline {
            usleep(50_000)
            if pb.changeCount != before {
                text = pb.string(forType: .string)
                break
            }
        }
        if let snapshot {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { snapshot.restore() }
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return CaptureResult(text: t, context: nil, selectionBounds: nil, origin: .hotkeyClipboard)
    }

    private static func postCopy(pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        down?.flags = .maskCommand
        down?.postToPid(pid)
        usleep(20_000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        up?.flags = .maskCommand
        up?.postToPid(pid)
    }
}
