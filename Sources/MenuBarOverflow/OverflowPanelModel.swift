import AppKit
import Combine

enum OverflowPanelContentKind: Equatable {
    case accessibility
    case loading
    case empty
    case items(Int)
}

enum OverflowLoginState: Equatable {
    case enabled
    case disabled
    case approvalRequired
    case unavailable(String)
    case failed(String)

    init(_ status: LoginItemManager.Status) {
        switch status {
        case .enabled:
            self = .enabled
        case .notRegistered:
            self = .disabled
        case .requiresApproval:
            self = .approvalRequired
        case .unavailable(let message):
            self = .unavailable(message)
        case .error(let message):
            self = .failed(message)
        }
    }

    var isOn: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }

    var canToggle: Bool {
        if case .unavailable = self {
            return false
        }
        return true
    }

    var needsSettings: Bool {
        if case .approvalRequired = self {
            return true
        }
        return false
    }

    var helpText: String {
        switch self {
        case .enabled:
            return "Menu Bar Overflow opens automatically when you log in."
        case .disabled:
            return "Open Menu Bar Overflow automatically when you log in."
        case .approvalRequired:
            return "Approve this login item in System Settings."
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

struct OverflowPanelItem: Identifiable {
    let id: String
    let title: String
    let toolTip: String
    let icon: NSImage?
    fileprivate let menuExtra: MenuExtraItem?

    init(menuExtra: MenuExtraItem) {
        id = menuExtra.id
        title = menuExtra.applicationName
        toolTip = menuExtra.tooltip
        icon = menuExtra.icon
        self.menuExtra = menuExtra
    }

    private init(
        id: String,
        title: String,
        symbolName: String
    ) {
        self.id = id
        self.title = title
        toolTip = "UI preview item"
        icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        menuExtra = nil
    }

    static let previewItems = [
        OverflowPanelItem(id: "preview-rectangle", title: "Rectangle", symbolName: "rectangle.inset.filled"),
        OverflowPanelItem(id: "preview-backup", title: "Codex Restic Status", symbolName: "externaldrive.fill"),
        OverflowPanelItem(id: "preview-chatgpt", title: "ChatGPT", symbolName: "sparkles"),
        OverflowPanelItem(id: "preview-security", title: "Kaspersky", symbolName: "checkmark.shield.fill"),
        OverflowPanelItem(id: "preview-computer-use", title: "Codex Computer Use", symbolName: "cursorarrow.motionlines"),
        OverflowPanelItem(id: "preview-wecom", title: "WeCom", symbolName: "message.fill"),
    ]
}

@MainActor
final class OverflowPanelModel: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var items = [OverflowPanelItem]()
    @Published private(set) var loginState = OverflowLoginState.disabled

    var onRefresh: (() -> Void)?
    var onActivate: ((MenuExtraItem, CGRect?) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onToggleOpenAtLogin: (() -> Void)?
    var onOpenLoginItemsSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    var contentKind: OverflowPanelContentKind {
        if !isAccessibilityTrusted {
            return .accessibility
        }
        if !hasScanned {
            return .loading
        }
        if items.isEmpty {
            return .empty
        }
        return .items(items.count)
    }

    var preferredHeight: CGFloat {
        OverflowPanelMetrics.preferredHeight(for: contentKind)
    }

    var subtitle: String {
        if !isAccessibilityTrusted {
            return "Accessibility access required"
        }
        if isScanning {
            return items.isEmpty ? "Looking for hidden items" : "Refreshing hidden items"
        }
        switch items.count {
        case 0:
            return "No hidden items found"
        case 1:
            return "1 hidden item"
        default:
            return "\(items.count) hidden items"
        }
    }

    func refreshSystemState(accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted(prompt: false)) {
        isAccessibilityTrusted = accessibilityTrusted
        loginState = OverflowLoginState(LoginItemManager.status)
        if !accessibilityTrusted {
            isScanning = false
            hasScanned = false
            items = []
        }
    }

    func beginScan() {
        guard isAccessibilityTrusted else { return }
        isScanning = true
    }

    func finishScan(with menuExtras: [MenuExtraItem]) {
        items = menuExtras.map(OverflowPanelItem.init(menuExtra:))
        isScanning = false
        hasScanned = true
        refreshSystemState()
    }

    func failScan() {
        isScanning = false
        hasScanned = true
    }

    func activate(_ item: OverflowPanelItem, anchorFrame: CGRect?) {
        guard let menuExtra = item.menuExtra else { return }
        onActivate?(menuExtra, anchorFrame)
    }

    func loadPreview() {
        isAccessibilityTrusted = true
        isScanning = false
        hasScanned = true
        items = OverflowPanelItem.previewItems
        loginState = .enabled
    }
}
