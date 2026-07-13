import CoreGraphics
import XCTest
@testable import MenuBarOverflow

final class MenuExtraVisibilityTests: XCTestCase {
    private let primaryMenuBar = CGRect(x: 0, y: 0, width: 1_440, height: 24)

    func testVisibleItemDoesNotShowInOverflow() {
        let frame = CGRect(x: 1_320, y: 2, width: 20, height: 20)

        XCTAssertTrue(MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: true,
            visibleRegions: [primaryMenuBar]
        ))
        XCTAssertFalse(shouldShow(frame: frame, windowServerOnScreen: true))
    }

    func testOffscreenItemShowsInOverflow() {
        let frame = CGRect(x: 1_500, y: 2, width: 20, height: 20)

        XCTAssertFalse(MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: true,
            visibleRegions: [primaryMenuBar]
        ))
        XCTAssertTrue(shouldShow(frame: frame, windowServerOnScreen: true))
    }

    func testLeftClippedItemShowsEvenWhenWindowServerSaysOnScreen() {
        let frame = CGRect(x: -5, y: 2, width: 20, height: 20)

        XCTAssertFalse(MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: true,
            visibleRegions: [primaryMenuBar]
        ))
        XCTAssertTrue(shouldShow(frame: frame, windowServerOnScreen: true))
    }

    func testRightClippedItemShowsEvenWhenWindowServerSaysOnScreen() {
        let frame = CGRect(x: 1_430, y: 2, width: 20, height: 20)

        XCTAssertFalse(MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: true,
            visibleRegions: [primaryMenuBar]
        ))
        XCTAssertTrue(shouldShow(frame: frame, windowServerOnScreen: true))
    }

    func testMissingSnapshotMatchKeepsContainedItemOutOfOverflow() {
        let frame = CGRect(x: 1_300, y: 2, width: 20, height: 20)

        XCTAssertTrue(MenuExtraVisibility.isVisible(
            frame: frame,
            windowServerOnScreen: nil,
            visibleRegions: [primaryMenuBar]
        ))
        XCTAssertFalse(shouldShow(frame: frame, windowServerOnScreen: nil))
    }

    func testUsesContainingRegionOnSecondaryDisplay() {
        let secondaryMenuBar = CGRect(x: 1_600, y: 0, width: 1_280, height: 24)
        let visibleFrame = CGRect(x: 1_900, y: 2, width: 20, height: 20)
        let gapFrame = CGRect(x: 1_590, y: 2, width: 20, height: 20)

        XCTAssertTrue(MenuExtraVisibility.isVisible(
            frame: visibleFrame,
            windowServerOnScreen: nil,
            visibleRegions: [primaryMenuBar, secondaryMenuBar]
        ))
        XCTAssertFalse(MenuExtraVisibility.isVisible(
            frame: gapFrame,
            windowServerOnScreen: nil,
            visibleRegions: [primaryMenuBar, secondaryMenuBar]
        ))
        XCTAssertTrue(MenuExtraVisibility.shouldShowInOverflow(
            frame: gapFrame,
            windowServerOnScreen: nil,
            visibleRegions: [primaryMenuBar, secondaryMenuBar],
            bundleIdentifier: "com.example.extra",
            title: "Extra",
            applicationName: "Example"
        ))
    }

    func testControlCenterPlaceholderDoesNotShowInOverflow() {
        let hiddenFrame = CGRect(x: -5, y: 2, width: 20, height: 20)

        XCTAssertTrue(MenuExtraVisibility.isSystemPlaceholder(
            bundleIdentifier: "com.apple.controlcenter",
            title: "Control Center",
            applicationName: "Control Center",
            frame: hiddenFrame
        ))
        XCTAssertFalse(MenuExtraVisibility.shouldShowInOverflow(
            frame: hiddenFrame,
            windowServerOnScreen: false,
            visibleRegions: [primaryMenuBar],
            bundleIdentifier: "com.apple.controlcenter",
            title: "Control Center",
            applicationName: "Control Center"
        ))
    }

    func testControlCenterModuleCanShowInOverflow() {
        let hiddenFrame = CGRect(x: -5, y: 2, width: 20, height: 20)

        XCTAssertFalse(MenuExtraVisibility.isSystemPlaceholder(
            bundleIdentifier: "com.apple.controlcenter",
            title: "Wi-Fi",
            applicationName: "Control Center",
            frame: hiddenFrame
        ))
        XCTAssertTrue(MenuExtraVisibility.shouldShowInOverflow(
            frame: hiddenFrame,
            windowServerOnScreen: false,
            visibleRegions: [primaryMenuBar],
            bundleIdentifier: "com.apple.controlcenter",
            title: "Wi-Fi",
            applicationName: "Control Center"
        ))
    }

    private func shouldShow(frame: CGRect, windowServerOnScreen: Bool?) -> Bool {
        MenuExtraVisibility.shouldShowInOverflow(
            frame: frame,
            windowServerOnScreen: windowServerOnScreen,
            visibleRegions: [primaryMenuBar],
            bundleIdentifier: "com.example.extra",
            title: "Extra",
            applicationName: "Example"
        )
    }
}
