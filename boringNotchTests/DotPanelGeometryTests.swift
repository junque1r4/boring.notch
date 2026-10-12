// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
@testable import boringNotch

@MainActor final class DotNotchSizingTests: XCTestCase {
    func testStandardDisplayUsesBoundedEmbeddedDotSize() {
        let size = DotNotchSizing.size(available: CGSize(width: 1600, height: 1080))
        XCTAssertEqual(size, dotNotchSize)
        XCTAssertEqual(size, CGSize(width: 760, height: 450))
    }

    func testSmallDisplayKeepsDotInsideScreenBounds() {
        let size = DotNotchSizing.size(available: CGSize(width: 400, height: 320))
        XCTAssertEqual(size, CGSize(width: 368, height: 300))
        XCTAssertLessThanOrEqual(size.width, 400)
        XCTAssertLessThanOrEqual(size.height, 320)
        XCTAssertGreaterThan(size.width - 62, 300, "Transcript stays readable after notch insets")
        XCTAssertGreaterThan(size.height - 60, 220, "Composer and transcript keep usable vertical space")
    }

    func testTinyDisplayNeverExceedsAvailableArea() {
        let available = CGSize(width: 240, height: 180)
        let size = DotNotchSizing.size(available: available)
        XCTAssertEqual(size, CGSize(width: 208, height: 160))
        XCTAssertLessThanOrEqual(size.width, available.width)
        XCTAssertLessThanOrEqual(size.height, available.height)
    }
}
