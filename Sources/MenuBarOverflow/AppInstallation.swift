import Foundation

enum AppInstallation {
    enum ValidationError: LocalizedError {
        case notApplicationBundle
        case missingExecutable
        case unsupportedLocation(URL)

        var errorDescription: String? {
            switch self {
            case .notApplicationBundle:
                return "Open at Login is available only when Menu Bar Overflow is running from its app bundle."
            case .missingExecutable:
                return "This Menu Bar Overflow app bundle is incomplete and cannot be registered to open at login."
            case .unsupportedLocation:
                return "Move Menu Bar Overflow to /Applications or ~/Applications before enabling Open at Login."
            }
        }
    }

    static var loginStartupEligibility: Result<URL, ValidationError> {
        validate(bundleURL: Bundle.main.bundleURL, executableURL: Bundle.main.executableURL)
    }

    static func validate(bundleURL: URL, executableURL: URL?) -> Result<URL, ValidationError> {
        let resolvedBundleURL = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedBundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return .failure(.notApplicationBundle)
        }

        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            return .failure(.missingExecutable)
        }

        guard applicationDirectories.contains(where: { resolvedBundleURL.isContained(in: $0) }) else {
            return .failure(.unsupportedLocation(resolvedBundleURL))
        }

        return .success(resolvedBundleURL)
    }

    private static var applicationDirectories: [URL] {
        let fileManager = FileManager.default
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }
}

private extension URL {
    func isContained(in directory: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return path.hasPrefix(directoryPath)
    }
}
