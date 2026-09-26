import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionCenter {
    static var accessibility: Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    static var screenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func summaryLine() -> String {
        "辅助功能:\(accessibility ? "已授权" : "未授权") · 屏幕录制:\(screenRecording ? "已授权" : "未授权")"
    }

    static func logStatus() {
        GlossLog.info("permissions accessibility=\(accessibility) screenRecording=\(screenRecording)")
    }
}
