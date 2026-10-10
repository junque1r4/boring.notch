// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
@testable import boringNotch

@MainActor final class DotPanelGeometryTests: XCTestCase {
    func testPanelUsesOriginalSizeWithoutChangingNotchFrame() {
        let notch = NSRect(x: 500, y: 900, width: 640, height: 210)
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 1080)
        let panel = DotChatPanelController.frame(parent: notch, visible: visible)
        XCTAssertEqual(panel.size, NSSize(width: 560, height: 420))
        XCTAssertEqual(panel.midX, notch.midX)
        XCTAssertEqual(panel.maxY, notch.minY + 4)
        XCTAssertTrue(visible.contains(panel))
    }
    func testPanelClampsToNegativeOriginExternalDisplay() {
        let visible = NSRect(x: -1920, y: 40, width: 1920, height: 1040)
        for x in [-1915.0, -320.0] {
            let panel = DotChatPanelController.frame(parent: NSRect(x: x, y: 900, width: 640, height: 210), visible: visible)
            XCTAssertTrue(visible.contains(panel))
        }
    }
    func testPanelFitsSmallDisplay() {
        let visible = NSRect(x: 10, y: 20, width: 400, height: 320)
        let panel = DotChatPanelController.frame(parent: NSRect(x: 100, y: 200, width: 640, height: 210), visible: visible)
        XCTAssertTrue(visible.contains(panel))
        XCTAssertEqual(panel.size, NSSize(width: 384, height: 304))
    }
}
