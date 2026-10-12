// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import XCTest
@testable import boringNotch

final class DotLauncherClosedAnchorTests: XCTestCase {
    func testClosingKeepsSettledDockWhileAccessoryAnchorMoves() {
        let dock = CGPoint(x: 720, y: 18)
        let expandedIntermediate = CGPoint(x: 1080, y: 42)
        var anchor = DotLauncherClosedAnchor()

        anchor.observe(dock, isOpen: false, routeAnimating: false)
        // The first closed measurement can arrive in the same update that
        // starts closing. It is transient and must not replace the endpoint.
        anchor.observe(expandedIntermediate, isOpen: false, routeAnimating: true)

        XCTAssertEqual(anchor.stableCenter, dock)
    }

    func testClosedEndpointRefreshesAfterCloseSettles() {
        let dock = CGPoint(x: 720, y: 18)
        let completedDock = CGPoint(x: 718, y: 18)
        let expandedIntermediate = CGPoint(x: 1080, y: 42)
        var anchor = DotLauncherClosedAnchor()

        anchor.observe(dock, isOpen: false, routeAnimating: false)
        anchor.observe(expandedIntermediate, isOpen: false, routeAnimating: true)
        XCTAssertEqual(anchor.stableCenter, dock)

        anchor.observe(completedDock, isOpen: false, routeAnimating: false)
        XCTAssertEqual(anchor.stableCenter, completedDock)
    }

    func testOpenStartupResolvesClosedDockFallbackFromContainerCenter() {
        let offset = CGPoint(x: 42, y: 18)
        let anchor = DotLauncherClosedAnchor()

        XCTAssertEqual(anchor.resolvedCenter(fallbackOffset: offset, containerWidth: 1_440),
                       CGPoint(x: 762, y: 18))
    }
}
