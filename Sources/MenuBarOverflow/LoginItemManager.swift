import AppKit
import ServiceManagement

enum LoginItemManager {
    enum Status {
        case enabled
        case notRegistered
        case requiresApproval
        case unavailable(String)
        case error(String)
    }

    private static var lastOperationError: String?

    static var status: Status {
        switch AppInstallation.loginStartupEligibility {
        case .failure(let error):
            return .unavailable(error.localizedDescription)
        case .success:
            break
        }

        if let lastOperationError {
            return .error(lastOperationError)
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .error("macOS could not locate the login item for this app.")
        @unknown default:
            return .error("macOS returned an unrecognized login-item status.")
        }
    }

    static func enable() throws {
        lastOperationError = nil

        switch AppInstallation.loginStartupEligibility {
        case .failure(let error):
            let loginItemError = LoginItemError.notInstalled(error)
            lastOperationError = loginItemError.localizedDescription
            throw loginItemError
        case .success:
            break
        }

        do {
            try SMAppService.mainApp.register()
        } catch {
            let loginItemError = LoginItemError.operationFailed("register", error)
            lastOperationError = loginItemError.localizedDescription
            throw loginItemError
        }
    }

    static func disable() throws {
        lastOperationError = nil

        switch AppInstallation.loginStartupEligibility {
        case .failure(let error):
            let loginItemError = LoginItemError.notInstalled(error)
            lastOperationError = loginItemError.localizedDescription
            throw loginItemError
        case .success:
            break
        }

        switch SMAppService.mainApp.status {
        case .notRegistered, .notFound:
            return
        case .enabled, .requiresApproval:
            break
        @unknown default:
            break
        }

        do {
            try SMAppService.mainApp.unregister()
        } catch {
            let loginItemError = LoginItemError.operationFailed("unregister", error)
            lastOperationError = loginItemError.localizedDescription
            throw loginItemError
        }
    }

    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum LoginItemError: LocalizedError {
    case notInstalled(AppInstallation.ValidationError)
    case operationFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let error):
            return error.localizedDescription
        case .operationFailed(let operation, let error):
            return "Could not \(operation) Menu Bar Overflow as a login item: \(error.localizedDescription)"
        }
    }
}
