import ApplicationServices
import XCTest
@testable import MenuBarOverflow

final class MenuExtraActivationPolicyTests: XCTestCase {
    func testDoesNotReportSuccessOrCannotComplete() {
        XCTAssertFalse(MenuExtraActivationPolicy.shouldReport(.success))
        XCTAssertFalse(MenuExtraActivationPolicy.shouldReport(.cannotComplete))
    }

    func testReportsActionableFailures() {
        XCTAssertTrue(MenuExtraActivationPolicy.shouldReport(.apiDisabled))
        XCTAssertTrue(MenuExtraActivationPolicy.shouldReport(.actionUnsupported))
    }
}
