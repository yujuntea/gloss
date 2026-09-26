import AppKit

/// Services 右键通道（Info.plist NSServices / NSMessage doQueryService）。
final class ServicesBridge: NSObject {
    @objc func doQueryService(_ pboard: NSPasteboard?, userData: String?, error: NSErrorPointer) {
        guard let pboard,
              let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let enabled = MainActor.assumeIsolated { SettingsStore.shared.channelServiceEnabled }
        guard enabled else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SessionCoordinator.shared.beginTextQuery(text: text, context: nil, selectionBounds: nil, origin: .service)
            }
        }
    }
}
