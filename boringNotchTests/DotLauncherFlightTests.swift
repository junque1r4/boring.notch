// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import XCTest
@testable import boringNotch

final class DotLauncherFlightTests: XCTestCase {
    private let start = CGPoint(x: 720, y: 18)
    private let end = CGPoint(x: 80, y: 18)
    private let clearanceY: CGFloat = 72

    func testEndpointsAreExact() {
        XCTAssertEqual(DotLauncherFlight.point(progress: 0, from: start, to: end, clearanceY: clearanceY), start)
        XCTAssertEqual(DotLauncherFlight.point(progress: 1, from: start, to: end, clearanceY: clearanceY), end)
    }

    func testMidpointTravelsUnderCameraCutout() {
        let midpoint = DotLauncherFlight.point(progress: 0.5, from: start, to: end, clearanceY: clearanceY)
        XCTAssertEqual(midpoint.x, (start.x + end.x) / 2, accuracy: 0.0001)
        XCTAssertEqual(midpoint.y, clearanceY, accuracy: 0.0001)
    }

    func testProgressClampsSpringOvershoot() {
        XCTAssertEqual(DotLauncherFlight.point(progress: -0.2, from: start, to: end, clearanceY: clearanceY), start)
        XCTAssertEqual(DotLauncherFlight.point(progress: 1.2, from: start, to: end, clearanceY: clearanceY), end)
    }

    func testRouteIsReversible() {
        for step in 0...100 {
            let progress = CGFloat(step) / 100
            let forward = DotLauncherFlight.point(progress: progress, from: start, to: end, clearanceY: clearanceY)
            let reverse = DotLauncherFlight.point(progress: 1 - progress, from: end, to: start, clearanceY: clearanceY)
            XCTAssertEqual(forward.x, reverse.x, accuracy: 0.0001)
            XCTAssertEqual(forward.y, reverse.y, accuracy: 0.0001)
        }
    }

    func testHorizontalTravelStaysAtOrBelowClearance() {
        for step in 0...100 {
            let point = DotLauncherFlight.point(
                progress: CGFloat(step) / 100,
                from: start,
                to: end,
                clearanceY: clearanceY
            )
            if point.x > end.x && point.x < start.x {
                XCTAssertGreaterThanOrEqual(point.y, clearanceY)
            }
        }
    }
}
