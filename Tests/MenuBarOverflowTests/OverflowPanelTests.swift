import AppKit
import SwiftUI
import XCTest
@testable import MenuBarOverflow

final class OverflowPanelTests: XCTestCase {
    func testPanelHeightUsesStableMinimumForSmallStates() {
        XCTAssertEqual(
            OverflowPanelMetrics.preferredHeight(for: .loading),
            OverflowPanelMetrics.minimumHeight
        )
        XCTAssertEqual(
            OverflowPanelMetrics.preferredHeight(for: .empty),
            OverflowPanelMetrics.minimumHeight
        )
        XCTAssertEqual(
            OverflowPanelMetrics.preferredHeight(for: .items(3)),
            OverflowPanelMetrics.minimumHeight
        )
    }

    func testPanelHeightGrowsUntilThreeGridRowsAndThenStops() {
        let oneRow = OverflowPanelMetrics.preferredHeight(for: .items(3))
        let twoRows = OverflowPanelMetrics.preferredHeight(for: .items(4))
        let threeRows = OverflowPanelMetrics.preferredHeight(for: .items(9))
        let manyRows = OverflowPanelMetrics.preferredHeight(for: .items(20))

        XCTAssertGreaterThan(twoRows, oneRow)
        XCTAssertGreaterThan(threeRows, twoRows)
        XCTAssertEqual(manyRows, threeRows)
        XCTAssertLessThanOrEqual(manyRows, OverflowPanelMetrics.maximumHeight)
    }

    func testGridUsesThreeColumns() {
        XCTAssertEqual(OverflowPanelMetrics.gridRowCount(for: 1), 1)
        XCTAssertEqual(OverflowPanelMetrics.gridRowCount(for: 3), 1)
        XCTAssertEqual(OverflowPanelMetrics.gridRowCount(for: 4), 2)
        XCTAssertEqual(OverflowPanelMetrics.gridRowCount(for: 9), 3)
        XCTAssertEqual(OverflowPanelMetrics.maximumVisibleItems, 9)
    }

    func testPanelUsesCompactMenuBarScale() {
        XCTAssertLessThanOrEqual(OverflowPanelMetrics.width, 300)
        XCTAssertLessThanOrEqual(OverflowPanelMetrics.gridCellHeight, 72)
        XCTAssertLessThanOrEqual(
            OverflowPanelMetrics.preferredHeight(for: .items(4)),
            280
        )
    }

    func testLoginStateMapsSystemStatusesToPanelControls() {
        XCTAssertEqual(OverflowLoginState(.enabled), .enabled)
        XCTAssertEqual(OverflowLoginState(.notRegistered), .disabled)
        XCTAssertEqual(OverflowLoginState(.requiresApproval), .approvalRequired)
        XCTAssertEqual(OverflowLoginState(.unavailable("Install first")), .unavailable("Install first"))
        XCTAssertEqual(OverflowLoginState(.error("Try again")), .failed("Try again"))
    }

    @MainActor
    func testPanelRendersInLightAndDarkAppearances() throws {
        let model = OverflowPanelModel()
        model.loadPreview()
        let outputDirectory = ProcessInfo.processInfo.environment["MENU_BAR_OVERFLOW_PREVIEW_DIR"]

        for (name, colorScheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let renderer = ImageRenderer(
                content: OverflowPanelView(model: model, onHeightChange: { _ in })
                    .environment(\.colorScheme, colorScheme)
            )
            renderer.proposedSize = ProposedViewSize(
                width: OverflowPanelMetrics.width,
                height: model.preferredHeight
            )
            renderer.scale = 2

            guard let cgImage = renderer.cgImage else {
                return XCTFail("Could not render the \(name) panel preview")
            }
            XCTAssertEqual(cgImage.width, Int(OverflowPanelMetrics.width * 2))
            XCTAssertEqual(cgImage.height, Int(model.preferredHeight * 2))

            if let outputDirectory {
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    return XCTFail("Could not encode the \(name) panel preview")
                }
                try png.write(
                    to: URL(fileURLWithPath: outputDirectory)
                        .appendingPathComponent("MenuBarOverflow-\(name)-preview.png")
                )
            }
        }
    }
}
