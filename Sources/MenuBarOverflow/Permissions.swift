import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

enum Permissions {
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func requestScreenCaptureAccess() {
        guard !hasScreenCaptureAccess else {
            return
        }

        if #available(macOS 15.0, *) {
            SCShareableContent.getWithCompletionHandler { _, _ in
                DispatchQueue.main.async {
                    guard !hasScreenCaptureAccess else {
                        return
                    }
                    openPrivacyPane("Privacy_ScreenCapture")
                }
            }
            return
        }

        CGRequestScreenCaptureAccess()
    }

    private static func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
