import AppKit
import ApplicationServices
import OSLog

private let appDelegateLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.codex.MenuBarOverflow",
    category: "AppDelegate"
)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let scanner = MenuExtraScanner()
    private let popupRelocator = MenuExtraPopupRelocator()
    private var panelModel: OverflowPanelModel!
    private var panelController: OverflowPanelController!
    private var isScanning = false

    private let isUIPreview = ProcessInfo.processInfo.arguments.contains("--ui-preview") ||
        ProcessInfo.processInfo.arguments.contains("--ui-preview-dark")
    private let isDarkUIPreview = ProcessInfo.processInfo.arguments.contains("--ui-preview-dark")
    private let isLiveUITest = ProcessInfo.processInfo.arguments.contains("--ui-live-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isUIPreview {
            NSApp.appearance = NSAppearance(named: isDarkUIPreview ? .darkAqua : .aqua)
        }
        configureStatusItem()
        configurePanel()
        configureAppearanceHandling()
        updateAppearanceSensitiveAssets()

        if isUIPreview {
            panelModel.loadPreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.panelController.show()
            }
        } else if isLiveUITest {
            appDelegateLogger.debug("Starting live UI test mode")
            panelModel.refreshSystemState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panelController.show(installEventMonitors: false)
                self.refreshOverflowItems()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        popupRelocator.cancel()
        panelController?.tearDown()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusBarImage()
        button.imagePosition = .imageOnly
        button.toolTip = "Menu Bar Overflow"
        button.target = self
        button.action = #selector(handleStatusItemAction)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePanel() {
        panelModel = OverflowPanelModel()
        panelController = OverflowPanelController(
            model: panelModel,
            statusItem: statusItem,
            visibilityDidChange: { [weak self] isVisible in
                self?.statusItem.button?.highlight(isVisible)
            }
        )

        panelModel.onRefresh = { [weak self] in self?.refreshOverflowItems() }
        panelModel.onActivate = { [weak self] item, anchorFrame in
            self?.activateMenuExtra(item, anchorFrame: anchorFrame)
        }
        panelModel.onRequestAccessibility = { [weak self] in self?.requestAccessibilityAccess() }
        panelModel.onOpenAccessibilitySettings = { [weak self] in self?.openAccessibilitySettings() }
        panelModel.onToggleOpenAtLogin = { [weak self] in self?.toggleOpenAtLogin() }
        panelModel.onOpenLoginItemsSettings = { [weak self] in self?.openLoginItemsSettings() }
        panelModel.onQuit = { [weak self] in self?.quit() }
    }

    private func makeStatusBarImage() -> NSImage {
        if let url = resourceURL(named: "StatusBarIconTemplate", extension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "Menu Bar Overflow"
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }

    private func configureAppearanceHandling() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemAppearanceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateAppearanceSensitiveAssets() }
    }

    private func updateAppearanceSensitiveAssets() {
        statusItem.button?.image = makeStatusBarImage()
        NSApp.applicationIconImage = makeApplicationIconImage()
    }

    private func makeApplicationIconImage() -> NSImage? {
        let resourceName = usesDarkAppearance ? "AppIconDark" : "AppIcon"
        guard let url = resourceURL(named: resourceName, extension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 512, height: 512)
        return image
    }

    private var usesDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension) ??
            Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "Resources"
            )
    }

    @objc private func handleStatusItemAction() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panelController.close()
            showContextMenu()
            return
        }

        if panelController.isVisible {
            panelController.close()
        } else {
            panelModel.refreshSystemState()
            panelController.show()
            refreshOverflowItems()
        }
    }

    private func refreshOverflowItems() {
        if isUIPreview {
            panelModel.loadPreview()
            return
        }

        let accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
        panelModel.refreshSystemState(accessibilityTrusted: accessibilityTrusted)
        guard accessibilityTrusted, !isScanning else { return }

        isScanning = true
        panelModel.beginScan()
        scanner.scan { [weak self] items in
            guard let self else { return }
            self.isScanning = false
            self.panelModel.finishScan(with: items)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(
            title: "Show Hidden Items",
            action: #selector(openPanelFromContextMenu),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(openPanelFromContextMenu),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let loginStatus = LoginItemManager.status
        let openAtLogin = NSMenuItem(
            title: openAtLoginMenuTitle(for: loginStatus),
            action: #selector(toggleOpenAtLogin),
            keyEquivalent: ""
        )
        openAtLogin.target = self
        openAtLogin.state = openAtLoginMenuState(for: loginStatus)
        openAtLogin.toolTip = openAtLoginMenuToolTip(for: loginStatus)
        openAtLogin.isEnabled = isOpenAtLoginActionAvailable(for: loginStatus)
        menu.addItem(openAtLogin)

        if case .requiresApproval = loginStatus {
            let settings = NSMenuItem(
                title: "Open Login Items Settings",
                action: #selector(openLoginItemsSettings),
                keyEquivalent: ""
            )
            settings.target = self
            menu.addItem(settings)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanelFromContextMenu() {
        panelModel.refreshSystemState()
        panelController.show()
        refreshOverflowItems()
    }

    private func activateMenuExtra(_ item: MenuExtraItem, anchorFrame: CGRect?) {
        let relocationSession = popupRelocator.prepare(
            ownerPID: item.ownerPID,
            applicationName: item.applicationName,
            anchorFrame: anchorFrame
        )
        if relocationSession == nil {
            panelController.close()
        }

        let result = item.press()
        if MenuExtraActivationPolicy.shouldReport(result) {
            popupRelocator.cancel()
            panelController.close()
            presentActivationFailure(for: item, error: result)
            return
        }

        panelController.close()
        guard let relocationSession else { return }
        popupRelocator.relocate(session: relocationSession) { _ in }
    }

    @objc private func requestAccessibilityAccess() {
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        refreshPermissionState(after: 0.5)
        refreshPermissionState(after: 1.5)
    }

    @objc private func openAccessibilitySettings() {
        panelController.close()
        Permissions.openAccessibilitySettings()
    }

    private func refreshPermissionState(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let trusted = Permissions.isAccessibilityTrusted(prompt: false)
            self.panelModel.refreshSystemState(accessibilityTrusted: trusted)
            if trusted {
                self.refreshOverflowItems()
            }
        }
    }

    @objc private func toggleOpenAtLogin() {
        do {
            switch LoginItemManager.status {
            case .enabled:
                try LoginItemManager.disable()
            case .requiresApproval:
                presentLoginItemApprovalRequired()
            case .notRegistered, .error:
                try LoginItemManager.enable()
                if case .requiresApproval = LoginItemManager.status {
                    presentLoginItemApprovalRequired()
                }
            case .unavailable(let message):
                presentOpenAtLoginError(message)
            }
        } catch {
            presentOpenAtLoginError(error)
        }
        panelModel.refreshSystemState()
    }

    @objc private func openLoginItemsSettings() {
        panelController.close()
        LoginItemManager.openLoginItemsSettings()
    }

    private func openAtLoginMenuTitle(for status: LoginItemManager.Status) -> String {
        switch status {
        case .enabled, .notRegistered:
            return "Open at Login"
        case .requiresApproval:
            return "Open at Login (Approval Needed)"
        case .unavailable:
            return "Open at Login (Install App First)"
        case .error:
            return "Open at Login (Retry)"
        }
    }

    private func openAtLoginMenuState(for status: LoginItemManager.Status) -> NSControl.StateValue {
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .mixed
        case .notRegistered, .unavailable, .error:
            return .off
        }
    }

    private func openAtLoginMenuToolTip(for status: LoginItemManager.Status) -> String {
        OverflowLoginState(status).helpText
    }

    private func isOpenAtLoginActionAvailable(for status: LoginItemManager.Status) -> Bool {
        if case .unavailable = status {
            return false
        }
        return true
    }

    private func presentLoginItemApprovalRequired() {
        panelController.close()
        let alert = NSAlert()
        alert.messageText = "Approve Open at Login"
        alert.informativeText = "macOS requires approval before Menu Bar Overflow can open automatically when you log in."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Login Items Settings")
        alert.addButton(withTitle: "Not Now")

        if present(alert) == .alertFirstButtonReturn {
            LoginItemManager.openLoginItemsSettings()
        }
    }

    private func presentOpenAtLoginError(_ error: Error) {
        presentOpenAtLoginError(error.localizedDescription)
    }

    private func presentOpenAtLoginError(_ message: String) {
        panelController.close()
        let alert = NSAlert()
        alert.messageText = "Could Not Update Open at Login"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Login Items Settings")

        if present(alert) == .alertSecondButtonReturn {
            LoginItemManager.openLoginItemsSettings()
        }
    }

    private func presentActivationFailure(for item: MenuExtraItem, error: AXError) {
        let alert = NSAlert()
        alert.messageText = "Could Not Open \(item.applicationName)'s Menu Bar Item"
        alert.informativeText = activationFailureMessage(for: error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if error == .apiDisabled {
            alert.addButton(withTitle: "Open Accessibility Settings")
            if present(alert) == .alertSecondButtonReturn {
                Permissions.openAccessibilitySettings()
            }
        } else {
            _ = present(alert)
        }
    }

    private func activationFailureMessage(for error: AXError) -> String {
        switch error {
        case .apiDisabled:
            return "Accessibility access is no longer available. Grant access in System Settings, then try again."
        case .actionUnsupported:
            return "This menu bar item no longer supports being opened by Menu Bar Overflow."
        default:
            return "macOS could not activate this menu bar item (Accessibility error \(error.rawValue)). Try refreshing the panel."
        }
    }

    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum MenuExtraActivationPolicy {
    static func shouldReport(_ result: AXError) -> Bool {
        result != .success && result != .cannotComplete
    }
}
