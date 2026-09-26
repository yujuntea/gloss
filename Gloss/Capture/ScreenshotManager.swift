import AppKit

/// ⌥S 交互框选截图（screencapture -i -c 子进程），截图进剪贴板后恢复用户原剪贴板。
enum ScreenshotManager {
    static func captureInteractive() async -> NSImage? {
        let before = NSPasteboard.general.changeCount
        let snapshot = ClipboardFallback.Snapshot.take()
        let exitedOK: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                proc.arguments = ["-i", "-c"]
                do {
                    try proc.run()
                } catch {
                    GlossLog.error("screencapture spawn failed: \(error)")
                    cont.resume(returning: false)
                    return
                }
                proc.waitUntilExit()
                cont.resume(returning: proc.terminationStatus == 0)
            }
        }
        guard exitedOK else {
            if let snapshot {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { snapshot.restore() }
            }
            return nil
        }
        let pb = NSPasteboard.general
        let changed = pb.changeCount != before
        let image = changed ? NSImage(pasteboard: pb) : nil
        if let snapshot {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { snapshot.restore() }
        }
        guard let image, let tiff = image.tiffRepresentation, !tiff.isEmpty else { return nil }
        return image
    }
}
