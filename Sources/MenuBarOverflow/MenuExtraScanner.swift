import AppKit
import ApplicationServices

final class MenuExtraScanner {
    private let scanQueue = DispatchQueue(label: "MenuBarOverflow.scan", qos: .userInitiated)
    private let iconProvider = MenuExtraIconProvider()

    func scan(completion: @escaping ([MenuExtraItem]) -> Void) {
        scanQueue.async { [iconProvider] in
            let items = autoreleasepool {
                Self.scanSynchronously(iconProvider: iconProvider)
            }

            DispatchQueue.main.async {
                completion(items)
            }
        }
    }

    private static func scanSynchronously(iconProvider: MenuExtraIconProvider) -> [MenuExtraItem] {
        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != ownPID &&
                    !app.isTerminated &&
                    app.isFinishedLaunching
            }
        let menuBarWindows = MenuBarWindowSnapshot.current()

        var items = [MenuExtraItem]()
        for application in applications {
            autoreleasepool {
                items.append(contentsOf: menuExtras(
                    for: application,
                    iconProvider: iconProvider,
                    menuBarWindows: menuBarWindows
                ))
            }
        }

        return items
            .deduplicated()
            .filter(\.shouldShowInOverflow)
            .sortedForMenuBarOverflow()
    }

    private static func menuExtras(
        for application: NSRunningApplication,
        iconProvider: MenuExtraIconProvider,
        menuBarWindows: MenuBarWindowSnapshot
    ) -> [MenuExtraItem] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.12)

        guard let extrasMenuBar = accessibilityElementAttribute(appElement, "AXExtrasMenuBar"),
              let children = accessibilityElementArrayAttribute(extrasMenuBar, kAXChildrenAttribute as String),
              !children.isEmpty
        else {
            return []
        }

        return children.enumerated().compactMap { index, child in
            AXUIElementSetMessagingTimeout(child, 0.12)

            guard supportsPress(child) else {
                return nil
            }

            let frame = frame(for: child)
            let title = bestTitle(for: child, application: application, index: index)
            let applicationName = application.localizedName ?? application.bundleIdentifier ?? "Unknown App"
            let bundleIdentifier = application.bundleIdentifier
            let isWindowServerOnScreen = menuBarWindows.isWindowServerOnScreen(for: frame)

            let icon = iconProvider.icon(for: application)

            return MenuExtraItem(
                id: "\(application.processIdentifier):\(index):\(title):\(frame?.debugDescription ?? "no-frame")",
                title: title,
                applicationName: applicationName,
                bundleIdentifier: bundleIdentifier,
                ownerPID: application.processIdentifier,
                frame: frame,
                isWindowServerOnScreen: isWindowServerOnScreen,
                menuBarVisibleRegions: menuBarWindows.visibleRegions,
                icon: icon,
                element: child
            )
        }
    }

    private static func bestTitle(
        for element: AXUIElement,
        application: NSRunningApplication,
        index: Int
    ) -> String {
        let candidates = [
            stringAttribute(element, kAXTitleAttribute as String),
            stringAttribute(element, kAXDescriptionAttribute as String),
            stringAttribute(element, "AXHelp"),
            application.localizedName,
            application.bundleIdentifier,
        ]

        if let title = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return title
        }

        return "Menu Extra \(index + 1)"
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        let error = AXUIElementCopyActionNames(element, &actions)
        guard error == .success,
              let actionNames = actions as? [String]
        else {
            // Do not list a menu extra unless we can confirm it accepts the
            // same action used to open it. This avoids dropdown entries that
            // are guaranteed to fail when Accessibility is transiently busy.
            return false
        }

        return actionNames.contains(kAXPressAction as String)
    }

    private static func accessibilityElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func accessibilityElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value
        else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }

        return value as? String
    }

    private static func frame(for element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}

private extension Array where Element == MenuExtraItem {
    func deduplicated() -> [MenuExtraItem] {
        var seen = Set<String>()
        var result = [MenuExtraItem]()

        for item in self {
            let stableKey = [
                item.bundleIdentifier ?? "\(item.ownerPID)",
                item.title,
                item.frame.map { "\(Int($0.minX)):\(Int($0.minY)):\(Int($0.width)):\(Int($0.height))" } ?? "no-frame",
            ].joined(separator: "|")

            guard seen.insert(stableKey).inserted else {
                continue
            }
            result.append(item)
        }

        return result
    }

    func sortedForMenuBarOverflow() -> [MenuExtraItem] {
        sorted { lhs, rhs in
            if lhs.isLikelyHidden != rhs.isLikelyHidden {
                return lhs.isLikelyHidden && !rhs.isLikelyHidden
            }

            switch (lhs.frame, rhs.frame) {
            case let (.some(leftFrame), .some(rightFrame)):
                if abs(leftFrame.midY - rightFrame.midY) > 4 {
                    return leftFrame.midY < rightFrame.midY
                }
                return leftFrame.maxX > rightFrame.maxX
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName) == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName) == .orderedAscending
            }
        }
    }
}
