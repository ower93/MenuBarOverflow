import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

private let popupRelocationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.codex.MenuBarOverflow",
    category: "PopupRelocation"
)

struct PopupWindowSnapshot: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int

    static func currentOnScreen() -> [PopupWindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]]
        else {
            return []
        }

        return dictionaries.compactMap { dictionary in
            guard let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                  bounds.width >= 40,
                  bounds.height >= 24,
                  (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01
            else {
                return nil
            }

            return PopupWindowSnapshot(
                windowID: CGWindowID(windowNumber.uint32Value),
                ownerPID: pid_t(ownerPID.int32Value),
                bounds: bounds,
                layer: layer.intValue
            )
        }
    }
}

enum PopupWindowMatcher {
    static func newCandidates(
        in snapshots: [PopupWindowSnapshot],
        ownerPID: pid_t,
        excluding baselineWindowIDs: Set<CGWindowID>
    ) -> [PopupWindowSnapshot] {
        snapshots
            .filter { snapshot in
                snapshot.ownerPID == ownerPID &&
                    !baselineWindowIDs.contains(snapshot.windowID) &&
                    snapshot.layer > 0
            }
            .sorted { lhs, rhs in
                if lhs.layer != rhs.layer {
                    return lhs.layer > rhs.layer
                }
                return lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
            }
    }
}

struct PopupScreenGeometry: Equatable {
    let anchorFrame: CGRect
    let visibleFrame: CGRect

    @MainActor
    static func current(for appKitAnchorFrame: CGRect) -> PopupScreenGeometry? {
        guard !appKitAnchorFrame.isEmpty else { return nil }

        let anchorPoint = CGPoint(x: appKitAnchorFrame.midX, y: appKitAnchorFrame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main,
              let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber
        else {
            return nil
        }

        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        let convertedAnchor = convertToAccessibilityCoordinates(
            appKitAnchorFrame,
            screenFrame: screen.frame,
            displayBounds: displayBounds
        )
        let convertedVisibleFrame = convertToAccessibilityCoordinates(
            screen.visibleFrame,
            screenFrame: screen.frame,
            displayBounds: displayBounds
        )
        return PopupScreenGeometry(
            anchorFrame: convertedAnchor,
            visibleFrame: convertedVisibleFrame
        )
    }

    private static func convertToAccessibilityCoordinates(
        _ rect: CGRect,
        screenFrame: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        CGRect(
            x: displayBounds.minX + rect.minX - screenFrame.minX,
            y: displayBounds.minY + screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

enum PopupPlacement {
    static func targetOrigin(
        anchorFrame: CGRect,
        popupSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 6
    ) -> CGPoint {
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - popupSize.width)
        let centeredX = anchorFrame.midX - popupSize.width / 2
        let x = min(max(centeredX, minimumX), maximumX)

        let belowY = anchorFrame.maxY + gap
        let aboveY = anchorFrame.minY - gap - popupSize.height
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - popupSize.height)
        let y: CGFloat
        if belowY + popupSize.height <= visibleFrame.maxY {
            y = belowY
        } else if aboveY >= visibleFrame.minY {
            y = aboveY
        } else {
            y = min(max(belowY, visibleFrame.minY), maximumY)
        }

        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

enum PopupRelocationResult: Equatable {
    case moved
    case unsupported
}

@MainActor
final class MenuExtraPopupRelocator {
    struct Session {
        let ownerPID: pid_t
        let applicationName: String
        let baselineWindowIDs: Set<CGWindowID>
        let geometry: PopupScreenGeometry
    }

    private final class ActiveRelocation {
        let session: Session
        let completion: (PopupRelocationResult) -> Void
        var observer: PopupAXObserver?
        var hasLoggedCandidates = false

        init(session: Session, completion: @escaping (PopupRelocationResult) -> Void) {
            self.session = session
            self.completion = completion
        }
    }

    private var activeRelocation: ActiveRelocation?
    private var pollingTask: Task<Void, Never>?

    func prepare(
        ownerPID: pid_t,
        applicationName: String,
        anchorFrame: CGRect?
    ) -> Session? {
        guard let anchorFrame,
              let geometry = PopupScreenGeometry.current(for: anchorFrame)
        else {
            return nil
        }

        let baselineWindowIDs = Set(
            PopupWindowSnapshot.currentOnScreen()
                .filter { $0.ownerPID == ownerPID }
                .map(\.windowID)
        )
        let session = Session(
            ownerPID: ownerPID,
            applicationName: applicationName,
            baselineWindowIDs: baselineWindowIDs,
            geometry: geometry
        )
        popupRelocationLogger.debug(
            "Prepared relocation for \(applicationName, privacy: .public), baseline windows: \(baselineWindowIDs.count)"
        )
        return session
    }

    func relocate(
        session: Session,
        completion: @escaping (PopupRelocationResult) -> Void
    ) {
        cancel()

        let activeRelocation = ActiveRelocation(session: session, completion: completion)
        self.activeRelocation = activeRelocation
        activeRelocation.observer = PopupAXObserver(pid: session.ownerPID) { [weak self] in
            Task { @MainActor in
                self?.attemptRelocation()
            }
        }

        attemptRelocation()
        pollingTask = Task { [weak self] in
            for _ in 0..<24 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 25_000_000)
                guard !Task.isCancelled else { return }
                self?.attemptRelocation()
                if self?.activeRelocation == nil {
                    return
                }
            }
            self?.finish(.unsupported)
        }
    }

    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        activeRelocation = nil
    }

    private func attemptRelocation() {
        guard let activeRelocation else { return }

        let candidates = PopupWindowMatcher.newCandidates(
            in: PopupWindowSnapshot.currentOnScreen(),
            ownerPID: activeRelocation.session.ownerPID,
            excluding: activeRelocation.session.baselineWindowIDs
        )
        if !candidates.isEmpty, !activeRelocation.hasLoggedCandidates {
            activeRelocation.hasLoggedCandidates = true
            popupRelocationLogger.debug(
                "Found \(candidates.count) popup candidate(s) for \(activeRelocation.session.applicationName, privacy: .public)"
            )
        }
        for candidate in candidates where move(candidate, using: activeRelocation.session.geometry) {
            finish(.moved)
            return
        }
    }

    private func move(
        _ candidate: PopupWindowSnapshot,
        using geometry: PopupScreenGeometry
    ) -> Bool {
        let applicationElement = AXUIElementCreateApplication(candidate.ownerPID)
        AXUIElementSetMessagingTimeout(applicationElement, 0.2)

        guard let windows = accessibilityWindows(of: applicationElement) else {
            return false
        }

        let matches = windows.compactMap { window -> (AXUIElement, CGRect)? in
            guard let frame = accessibilityFrame(of: window),
                  frame.isLikelyMatch(for: candidate.bounds),
                  isPositionSettable(for: window)
            else {
                return nil
            }
            return (window, frame)
        }
        .sorted { lhs, rhs in
            lhs.1.matchDistance(to: candidate.bounds) < rhs.1.matchDistance(to: candidate.bounds)
        }

        guard let (window, frame) = matches.first else { return false }
        var target = PopupPlacement.targetOrigin(
            anchorFrame: geometry.anchorFrame,
            popupSize: frame.size,
            visibleFrame: geometry.visibleFrame
        )
        guard let value = AXValueCreate(.cgPoint, &target) else { return false }

        return AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    private func finish(_ result: PopupRelocationResult) {
        guard let activeRelocation else { return }
        let completion = activeRelocation.completion
        pollingTask?.cancel()
        pollingTask = nil
        self.activeRelocation = nil
        switch result {
        case .moved:
            popupRelocationLogger.info(
                "Moved popup for \(activeRelocation.session.applicationName, privacy: .public)"
            )
        case .unsupported:
            popupRelocationLogger.info(
                "Kept original popup position for \(activeRelocation.session.applicationName, privacy: .public)"
            )
        }
        completion(result)
    }

    private func accessibilityWindows(of applicationElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func isPositionSettable(for element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            kAXPositionAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }
}

private final class PopupAXObserver {
    private final class CallbackBox {
        let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private let observer: AXObserver
    private let applicationElement: AXUIElement
    private let callbackBox: CallbackBox
    private let notifications: [CFString]

    init?(pid: pid_t, handler: @escaping () -> Void) {
        let callbackBox = CallbackBox(handler: handler)
        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            { _, _, _, refcon in
                guard let refcon else { return }
                Unmanaged<CallbackBox>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handler()
            },
            &observer
        )
        guard result == .success, let observer else { return nil }

        let applicationElement = AXUIElementCreateApplication(pid)
        let notifications = [
            kAXWindowCreatedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
        ]
        let refcon = Unmanaged.passUnretained(callbackBox).toOpaque()
        let registeredNotifications = notifications.filter { notification in
            AXObserverAddNotification(
                observer,
                applicationElement,
                notification,
                refcon
            ) == .success
        }
        guard !registeredNotifications.isEmpty else { return nil }

        self.observer = observer
        self.applicationElement = applicationElement
        self.callbackBox = callbackBox
        self.notifications = registeredNotifications
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    deinit {
        for notification in notifications {
            AXObserverRemoveNotification(observer, applicationElement, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }
}

private extension CGRect {
    func isLikelyMatch(for other: CGRect) -> Bool {
        abs(width - other.width) <= max(80, other.width * 0.25) &&
            abs(height - other.height) <= max(80, other.height * 0.25) &&
            abs(midX - other.midX) <= 120 &&
            abs(midY - other.midY) <= 120
    }

    func matchDistance(to other: CGRect) -> CGFloat {
        abs(midX - other.midX) +
            abs(midY - other.midY) +
            abs(width - other.width) +
            abs(height - other.height)
    }
}
