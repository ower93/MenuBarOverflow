import AppKit
import ApplicationServices

final class MenuExtraItem: NSObject {
    let id: String
    let title: String
    let applicationName: String
    let bundleIdentifier: String?
    let ownerPID: pid_t
    let frame: CGRect?
    let isWindowServerOnScreen: Bool?
    let menuBarVisibleRegions: [CGRect]
    let icon: NSImage?
    private let element: AXUIElement

    init(
        id: String,
        title: String,
        applicationName: String,
        bundleIdentifier: String?,
        ownerPID: pid_t,
        frame: CGRect?,
        isWindowServerOnScreen: Bool?,
        menuBarVisibleRegions: [CGRect],
        icon: NSImage?,
        element: AXUIElement
    ) {
        self.id = id
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.ownerPID = ownerPID
        self.frame = frame
        self.isWindowServerOnScreen = isWindowServerOnScreen
        self.menuBarVisibleRegions = menuBarVisibleRegions
        self.icon = icon
        self.element = element
    }

    var menuTitle: String {
        if title.localizedCaseInsensitiveCompare(applicationName) == .orderedSame {
            return isLikelyHidden ? "\(applicationName) (hidden)" : applicationName
        }

        let base = "\(title) - \(applicationName)"
        return isLikelyHidden ? "\(base) (hidden)" : base
    }

    var tooltip: String {
        var parts = [applicationName]
        if let bundleIdentifier {
            parts.append(bundleIdentifier)
        }
        if let frame {
            parts.append("x:\(Int(frame.minX)) y:\(Int(frame.minY))")
        }
        if let isWindowServerOnScreen {
            parts.append(isWindowServerOnScreen ? "visible in menu bar" : "not visible in menu bar")
        }
        return parts.joined(separator: "\n")
    }

    var isLikelyHidden: Bool {
        !isVisibleInMenuBar
    }

    var shouldShowInOverflow: Bool {
        MenuExtraVisibility.shouldShowInOverflow(
            frame: frame,
            windowServerOnScreen: isWindowServerOnScreen,
            visibleRegions: menuBarVisibleRegions,
            bundleIdentifier: bundleIdentifier,
            title: title,
            applicationName: applicationName
        )
    }

    private var isVisibleInMenuBar: Bool {
        MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: isWindowServerOnScreen,
            visibleRegions: menuBarVisibleRegions
        )
    }

    func press() -> AXError {
        // Scanning uses a very short timeout to keep the dropdown responsive,
        // but opening an item can legitimately take longer to acknowledge.
        AXUIElementSetMessagingTimeout(element, 1.5)
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

struct MenuExtraVisibility {
    static func isVisible(
        frame: CGRect?,
        windowServerOnScreen: Bool?,
        visibleRegions: [CGRect]
    ) -> Bool {
        guard let frame, !frame.isEffectivelyEmpty else {
            return false
        }

        // A WindowServer on-screen flag alone is not sufficient: macOS can
        // report a clipped menu extra as on-screen. The complete AX frame must
        // fit within one visible menu-bar region.
        guard visibleRegions.isEmpty || visibleRegions.contains(where: { $0.contains(frame) }) else {
            return false
        }

        // An exact window match remains authoritative when it says the item is
        // off-screen. If there is no match, containment is the conservative
        // fallback that keeps existing visible items out of the overflow menu.
        return windowServerOnScreen != false
    }

    static func shouldShowInOverflow(
        frame: CGRect?,
        windowServerOnScreen: Bool?,
        visibleRegions: [CGRect],
        bundleIdentifier: String?,
        title: String,
        applicationName: String
    ) -> Bool {
        guard let frame, !frame.isEffectivelyEmpty else {
            return false
        }

        return !isVisible(
            frame: frame,
            windowServerOnScreen: windowServerOnScreen,
            visibleRegions: visibleRegions
        ) && !isSystemPlaceholder(
            bundleIdentifier: bundleIdentifier,
            title: title,
            applicationName: applicationName,
            frame: frame
        )
    }

    static func isSystemPlaceholder(
        bundleIdentifier: String?,
        title: String,
        applicationName: String,
        frame: CGRect?
    ) -> Bool {
        guard bundleIdentifier == "com.apple.controlcenter" else {
            return false
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isControlCenterPlaceholder = normalizedTitle.localizedCaseInsensitiveCompare("Control Center") == .orderedSame ||
            (normalizedTitle.isEmpty && applicationName.localizedCaseInsensitiveCompare("Control Center") == .orderedSame)
        return isControlCenterPlaceholder
    }
}

private extension CGRect {
    var isEffectivelyEmpty: Bool {
        width <= 2 || height <= 2
    }
}
