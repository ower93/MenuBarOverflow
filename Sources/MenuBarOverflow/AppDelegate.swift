import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let scanner = MenuExtraScanner()
    private var isScanning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureAppearanceHandling()
        updateAppearanceSensitiveAssets()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = makeStatusBarImage()
        button.imagePosition = .imageOnly
        button.toolTip = "Menu Bar Overflow"
        button.target = self
        button.action = #selector(showOverflowMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        DispatchQueue.main.async { [weak self] in
            self?.updateAppearanceSensitiveAssets()
        }
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

    @objc private func showOverflowMenu() {
        guard !isScanning else {
            return
        }

        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            presentMenu(makePermissionMenu())
            return
        }

        isScanning = true
        statusItem.button?.isEnabled = false

        scanner.scan { [weak self] items in
            guard let self else {
                return
            }
            self.isScanning = false
            self.statusItem.button?.isEnabled = true
            self.presentMenu(self.makeOverflowMenu(items: items))
        }
    }

    private func presentMenu(_ menu: NSMenu) {
        statusItem.popUpMenu(menu)
    }

    private func makePermissionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let explanation = NSMenuItem(
            title: "Accessibility access is required",
            action: nil,
            keyEquivalent: ""
        )
        explanation.isEnabled = false
        menu.addItem(explanation)

        let request = NSMenuItem(
            title: "Request Accessibility Access",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        request.target = self
        menu.addItem(request)

        let openSettings = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openSettings.target = self
        menu.addItem(openSettings)

        menu.addItem(.separator())
        addUtilityItems(to: menu)
        return menu
    }

    private func makeOverflowMenu(items: [MenuExtraItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if items.isEmpty {
            let empty = NSMenuItem(title: "No hidden menu bar icons found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in items {
                let menuItem = NSMenuItem(
                    title: item.menuTitle,
                    action: #selector(activateMenuExtra(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item
                menuItem.image = item.icon
                menuItem.toolTip = item.tooltip
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        addUtilityItems(to: menu)
        return menu
    }

    private func addUtilityItems(to menu: NSMenu) {
        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(showOverflowMenu),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let screenCaptureEnabled = Permissions.hasScreenCaptureAccess
        let screenCapture = NSMenuItem(
            title: screenCaptureEnabled ? "Screen Recording Enabled" : "Request Screen Recording for Real Icons",
            action: #selector(requestScreenCaptureAccess),
            keyEquivalent: ""
        )
        screenCapture.target = self
        screenCapture.isEnabled = !screenCaptureEnabled
        menu.addItem(screenCapture)

        let loginItemStatus = LoginItemManager.status
        let openAtLogin = NSMenuItem(
            title: openAtLoginMenuTitle(for: loginItemStatus),
            action: #selector(toggleOpenAtLogin),
            keyEquivalent: ""
        )
        openAtLogin.target = self
        openAtLogin.state = openAtLoginMenuState(for: loginItemStatus)
        openAtLogin.toolTip = openAtLoginMenuToolTip(for: loginItemStatus)
        openAtLogin.isEnabled = isOpenAtLoginActionAvailable(for: loginItemStatus)
        menu.addItem(openAtLogin)

        if case .requiresApproval = loginItemStatus {
            let loginItemsSettings = NSMenuItem(
                title: "Open Login Items Settings",
                action: #selector(openLoginItemsSettings),
                keyEquivalent: ""
            )
            loginItemsSettings.target = self
            menu.addItem(loginItemsSettings)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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
        switch status {
        case .enabled:
            return "Menu Bar Overflow will open automatically when you log in."
        case .requiresApproval:
            return "macOS needs you to approve this login item in System Settings."
        case .notRegistered:
            return "Start Menu Bar Overflow automatically when you log in."
        case .unavailable(let message), .error(let message):
            return message
        }
    }

    private func isOpenAtLoginActionAvailable(for status: LoginItemManager.Status) -> Bool {
        if case .unavailable = status {
            return false
        }
        return true
    }

    @objc private func activateMenuExtra(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuExtraItem else {
            return
        }

        let result = item.press()
        if MenuExtraActivationPolicy.shouldReport(result) {
            presentActivationFailure(for: item, error: result)
        }
    }

    @objc private func requestAccessibilityAccess() {
        _ = Permissions.isAccessibilityTrusted(prompt: true)
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func requestScreenCaptureAccess() {
        Permissions.requestScreenCaptureAccess()
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
    }

    @objc private func openLoginItemsSettings() {
        LoginItemManager.openLoginItemsSettings()
    }

    private func presentLoginItemApprovalRequired() {
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
            return "macOS could not activate this menu bar item (Accessibility error \(error.rawValue)). Try refreshing the menu."
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
