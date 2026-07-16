import AppKit
import OSLog
import SwiftUI

private let overflowPanelLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.codex.MenuBarOverflow",
    category: "OverflowPanel"
)

private final class OverflowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverflowPanelController {
    private enum Layout {
        static let statusBarGap: CGFloat = 8
        static let screenMargin: CGFloat = 8
    }

    private let panel: OverflowPanel
    private weak var statusItem: NSStatusItem?
    private let visibilityDidChange: (Bool) -> Void
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(
        model: OverflowPanelModel,
        statusItem: NSStatusItem,
        visibilityDidChange: @escaping (Bool) -> Void
    ) {
        self.statusItem = statusItem
        self.visibilityDidChange = visibilityDidChange
        panel = OverflowPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: OverflowPanelMetrics.width,
                height: model.preferredHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel(model: model)
    }

    func show(installEventMonitors shouldInstallEventMonitors: Bool = true) {
        overflowPanelLogger.debug("Showing panel; event monitors: \(shouldInstallEventMonitors)")
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        overflowPanelLogger.debug(
            "Panel ordered front; visible: \(self.panel.isVisible), frame: \(NSStringFromRect(self.panel.frame), privacy: .public)"
        )
        visibilityDidChange(true)
        guard shouldInstallEventMonitors else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.installEventMonitors()
        }
    }

    func close() {
        overflowPanelLogger.debug("Closing panel; visible: \(self.panel.isVisible)")
        if panel.isVisible {
            panel.orderOut(nil)
            visibilityDidChange(false)
        }
        removeEventMonitors()
    }

    func tearDown() {
        close()
    }

    private func configurePanel(model: OverflowPanelModel) {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let rootView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.layer?.cornerRadius = OverflowPanelMetrics.cornerRadius
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true

        let blurView = NSVisualEffectView(frame: rootView.bounds)
        blurView.autoresizingMask = [.width, .height]
        blurView.material = .underWindowBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.isEmphasized = false
        blurView.alphaValue = 0.48
        rootView.addSubview(blurView)

        let hostingView = NSHostingView(
            rootView: OverflowPanelView(
                model: model,
                onHeightChange: { [weak self] height in
                    self?.resizePanel(to: height)
                }
            )
        )
        hostingView.frame = rootView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.addSubview(hostingView)
        panel.contentView = rootView
    }

    private func resizePanel(to proposedHeight: CGFloat) {
        let height = min(
            OverflowPanelMetrics.maximumHeight,
            max(OverflowPanelMetrics.minimumHeight, proposedHeight.rounded())
        )
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        if panel.isVisible {
            frame.origin.y += frame.height - height
        }
        frame.size.height = height
        panel.setFrame(frame, display: panel.isVisible, animate: panel.isVisible)
        panel.invalidateShadow()
    }

    private func positionPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        var x = buttonFrameOnScreen.midX - OverflowPanelMetrics.width / 2
        x = max(visibleFrame.minX + Layout.screenMargin, x)
        x = min(visibleFrame.maxX - OverflowPanelMetrics.width - Layout.screenMargin, x)

        var y = buttonFrameOnScreen.minY - panel.frame.height - Layout.statusBarGap
        if y < visibleFrame.minY + Layout.screenMargin {
            y = buttonFrameOnScreen.maxY + Layout.statusBarGap
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func installEventMonitors() {
        guard globalEventMonitor == nil, localEventMonitor == nil else { return }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                overflowPanelLogger.debug("Closing panel after a global mouse event")
                self?.close()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                overflowPanelLogger.debug("Closing panel after Escape")
                self.close()
                return nil
            }
            if event.window !== self.panel, event.window !== self.statusItem?.button?.window {
                overflowPanelLogger.debug("Closing panel after a local event outside the panel")
                self.close()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        globalEventMonitor = nil
        localEventMonitor = nil
    }
}
