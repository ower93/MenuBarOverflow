import CoreGraphics
import XCTest
@testable import MenuBarOverflow

final class MenuExtraPopupRelocatorTests: XCTestCase {
    func testCandidateMatchingKeepsOnlyNewFloatingWindowsForOwner() {
        let snapshots = [
            snapshot(id: 1, pid: 100, layer: 25, width: 260, height: 320),
            snapshot(id: 2, pid: 100, layer: 0, width: 500, height: 500),
            snapshot(id: 3, pid: 200, layer: 25, width: 260, height: 320),
            snapshot(id: 4, pid: 100, layer: 101, width: 180, height: 220),
        ]

        let candidates = PopupWindowMatcher.newCandidates(
            in: snapshots,
            ownerPID: 100,
            excluding: [1]
        )

        XCTAssertEqual(candidates.map(\.windowID), [4])
    }

    func testCandidateMatchingPrioritizesHigherWindowLevels() {
        let snapshots = [
            snapshot(id: 1, pid: 100, layer: 3, width: 240, height: 260),
            snapshot(id: 2, pid: 100, layer: 25, width: 280, height: 360),
        ]

        let candidates = PopupWindowMatcher.newCandidates(
            in: snapshots,
            ownerPID: 100,
            excluding: []
        )

        XCTAssertEqual(candidates.map(\.windowID), [2, 1])
    }

    func testPlacementOpensBelowCenteredAnchorWhenSpaceAllows() {
        let origin = PopupPlacement.targetOrigin(
            anchorFrame: CGRect(x: 100, y: 80, width: 40, height: 40),
            popupSize: CGSize(width: 100, height: 120),
            visibleFrame: CGRect(x: 0, y: 24, width: 500, height: 450)
        )

        XCTAssertEqual(origin, CGPoint(x: 70, y: 126))
    }

    func testPlacementOpensAboveAnchorWhenBottomSpaceIsInsufficient() {
        let origin = PopupPlacement.targetOrigin(
            anchorFrame: CGRect(x: 200, y: 400, width: 40, height: 40),
            popupSize: CGSize(width: 140, height: 180),
            visibleFrame: CGRect(x: 0, y: 24, width: 500, height: 450)
        )

        XCTAssertEqual(origin, CGPoint(x: 150, y: 214))
    }

    func testPlacementClampsHorizontallyToVisibleScreen() {
        let origin = PopupPlacement.targetOrigin(
            anchorFrame: CGRect(x: 5, y: 80, width: 30, height: 30),
            popupSize: CGSize(width: 180, height: 100),
            visibleFrame: CGRect(x: 12, y: 24, width: 420, height: 450)
        )

        XCTAssertEqual(origin.x, 12)
    }

    private func snapshot(
        id: CGWindowID,
        pid: pid_t,
        layer: Int,
        width: CGFloat,
        height: CGFloat
    ) -> PopupWindowSnapshot {
        PopupWindowSnapshot(
            windowID: id,
            ownerPID: pid,
            bounds: CGRect(x: 100, y: 100, width: width, height: height),
            layer: layer
        )
    }
}
