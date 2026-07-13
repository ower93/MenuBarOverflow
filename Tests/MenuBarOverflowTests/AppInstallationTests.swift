import Foundation
import XCTest
@testable import MenuBarOverflow

final class AppInstallationTests: XCTestCase {
    func testRejectsNonApplicationBundle() {
        let result = AppInstallation.validate(
            bundleURL: URL(fileURLWithPath: "/tmp/MenuBarOverflow"),
            executableURL: URL(fileURLWithPath: "/bin/sh")
        )

        assertFailure(result) { error in
            if case .notApplicationBundle = error {
                return true
            }
            return false
        }
    }

    func testRejectsIncompleteBundleBeforeCheckingLocation() {
        let result = AppInstallation.validate(
            bundleURL: URL(fileURLWithPath: "/tmp/MenuBarOverflow.app"),
            executableURL: URL(fileURLWithPath: "/tmp/MenuBarOverflow.app/Contents/MacOS/MenuBarOverflow")
        )

        assertFailure(result) { error in
            if case .missingExecutable = error {
                return true
            }
            return false
        }
    }

    func testRejectsTemporaryApplicationBundle() {
        let result = AppInstallation.validate(
            bundleURL: URL(fileURLWithPath: "/tmp/MenuBarOverflow.app"),
            executableURL: URL(fileURLWithPath: "/bin/sh")
        )

        assertFailure(result) { error in
            if case .unsupportedLocation = error {
                return true
            }
            return false
        }
    }

    private func assertFailure(
        _ result: Result<URL, AppInstallation.ValidationError>,
        matches: (AppInstallation.ValidationError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else {
            return XCTFail("Expected validation to fail", file: file, line: line)
        }
        XCTAssertTrue(matches(error), "Unexpected validation error: \(error)", file: file, line: line)
    }
}
