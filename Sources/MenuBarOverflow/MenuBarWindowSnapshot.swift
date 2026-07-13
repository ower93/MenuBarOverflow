import AppKit
import CoreGraphics

private typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
private func cgsGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
private func cgsGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
private func cgsGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowLevel")
private func cgsGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError

struct MenuBarWindowSnapshot {
    struct Window {
        let windowID: CGWindowID
        let bounds: CGRect
        let isOnScreen: Bool
        let level: CGWindowLevel
    }

    let windows: [Window]
    let visibleRegions: [CGRect]

    static func current() -> MenuBarWindowSnapshot {
        let connection = cgsMainConnectionID()
        let onScreenIDs = Set(windowIDsFromOnScreenList(connection: connection))
        var visibleRegions = [CGRect]()
        let windows = windowIDsFromMenuBarList(connection: connection).compactMap { windowID -> Window? in
            let info = windowDescription(for: windowID)
            guard let level = windowLevel(for: windowID, connection: connection),
                  let bounds = info.bounds,
                  !bounds.isEffectivelyEmpty
            else {
                return nil
            }

            let isOnScreen = onScreenIDs.contains(windowID) || info.isOnScreen
            if level == CGWindowLevelForKey(.mainMenuWindow) {
                if isOnScreen {
                    visibleRegions.append(bounds)
                }
                return nil
            }

            return Window(
                windowID: windowID,
                bounds: bounds,
                isOnScreen: isOnScreen,
                level: level
            )
        }

        // CGS normally provides the menu-bar windows above. If it does not,
        // use complete display bounds as a containment-only fallback. This is
        // intentionally not an intersection check, so clipped frames stay
        // eligible for the overflow menu.
        if visibleRegions.isEmpty {
            visibleRegions = activeDisplayBounds()
        }

        return MenuBarWindowSnapshot(windows: windows, visibleRegions: visibleRegions)
    }

    func isWindowServerOnScreen(for frame: CGRect?) -> Bool? {
        guard let frame, !frame.isEffectivelyEmpty else {
            return nil
        }

        return bestMatch(for: frame)?.isOnScreen
    }

    private func bestMatch(for frame: CGRect) -> Window? {
        let candidates = windows.filter { window in
            window.bounds.isLikelySameMenuExtra(as: frame)
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.bounds.midX - frame.midX) + abs(lhs.bounds.midY - frame.midY)
            let rhsDistance = abs(rhs.bounds.midX - frame.midX) + abs(rhs.bounds.midY - frame.midY)
            return lhsDistance < rhsDistance
        }
    }

    private static func windowIDsFromMenuBarList(connection: CGSConnectionID) -> [CGWindowID] {
        guard var count = windowCount(connection: connection), count > 0 else {
            return []
        }

        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = cgsGetProcessMenuBarWindowList(connection, 0, count, &list, &count)
        guard result == .success else {
            return []
        }

        return [CGWindowID](list.prefix(Int(count)))
    }

    private static func windowIDsFromOnScreenList(connection: CGSConnectionID) -> [CGWindowID] {
        guard var count = windowCount(connection: connection), count > 0 else {
            return []
        }

        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = cgsGetOnScreenWindowList(connection, 0, count, &list, &count)
        guard result == .success else {
            return []
        }

        return [CGWindowID](list.prefix(Int(count)))
    }

    private static func windowCount(connection: CGSConnectionID) -> Int32? {
        var count: Int32 = 0
        let result = cgsGetWindowCount(connection, 0, &count)
        return result == .success ? count : nil
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success,
              count > 0
        else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return []
        }

        return displayIDs.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func windowLevel(for windowID: CGWindowID, connection: CGSConnectionID) -> CGWindowLevel? {
        var level = CGWindowLevel()
        let result = cgsGetWindowLevel(connection, windowID, &level)
        return result == .success ? level : nil
    }

    private static func windowDescription(for windowID: CGWindowID) -> (bounds: CGRect?, isOnScreen: Bool) {
        guard let array = createCGWindowArray(with: [windowID]),
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary],
              let dictionary = descriptions.first as? [CFString: Any]
        else {
            return (nil, false)
        }

        let bounds = (dictionary[kCGWindowBounds] as? NSDictionary).flatMap {
            CGRect(dictionaryRepresentation: $0)
        }
        let isOnScreen = dictionary[kCGWindowIsOnscreen] as? Bool ?? false
        return (bounds, isOnScreen)
    }

    private static func createCGWindowArray(with windowIDs: [CGWindowID]) -> NSArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap { windowID in
            UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard !pointers.isEmpty else {
            return nil
        }

        var callbacks = CFArrayCallBacks(
            version: 0,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil
        )
        return CFArrayCreate(nil, &pointers, pointers.count, &callbacks) as NSArray?
    }
}

private extension CGRect {
    var isEffectivelyEmpty: Bool {
        width <= 2 || height <= 2
    }

    func isLikelySameMenuExtra(as axFrame: CGRect) -> Bool {
        let xTolerance = max(10, min(width, axFrame.width) * 0.6)
        let yTolerance: CGFloat = 18
        return abs(midX - axFrame.midX) <= xTolerance &&
            abs(midY - axFrame.midY) <= yTolerance
    }
}
