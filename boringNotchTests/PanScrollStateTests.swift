// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import boringNotch

final class PanScrollStateTests: XCTestCase {
    func testEnabledGestureKeepsThresholdDirectionAndCompletionBehavior() {
        var state = PanScrollState()
        XCTAssertNil(state.receive(delta: 2, now: 0))
        XCTAssertEqual(state.receive(delta: 2, now: 0.02), .init(translation: 4, phase: .began))
        XCTAssertEqual(state.receive(delta: 3, now: 0.04), .init(translation: 7, phase: .changed))
        XCTAssertEqual(state.receive(delta: -1, now: 0.06), .init(translation: 0, phase: .changed))
        XCTAssertEqual(state.receive(delta: nil, ends: true, now: 0.08), .init(translation: 0, phase: .ended))
        XCTAssertFalse(state.active)
        XCTAssertNil(state.finishIdle(now: 1), "Explicit completion must not deliver a second delayed callback")
    }

    func testDisabledNativeScrollingNeverProducesNotchActions() {
        var state = PanScrollState(enabled: false)
        XCTAssertNil(state.receive(delta: 800, begins: true, now: 0))
        XCTAssertNil(state.receive(delta: 800, now: 0.05))
        XCTAssertNil(state.receive(delta: nil, ends: true, now: 0.1))
        XCTAssertNil(state.finishIdle(now: 0.5))
        XCTAssertEqual(state.accumulated, 0)
        XCTAssertFalse(state.active)
    }

    func testTabChangeClearsOverThresholdGestureAndSuppressesOldMomentum() {
        var state = PanScrollState()
        XCTAssertEqual(state.receive(delta: 400, begins: true, now: 0), .init(translation: 400, phase: .began))
        state.update(enabled: false, threshold: 4, now: 0.01)
        XCTAssertEqual(state.accumulated, 0)
        XCTAssertFalse(state.active)
        state.update(enabled: true, threshold: 4, now: 0.02)
        XCTAssertNil(state.receive(delta: 800, now: 0.03))
        XCTAssertNil(state.receive(delta: nil, ends: true, now: 0.04))
        XCTAssertNil(state.finishIdle(now: 0.35), "A cancelled old gesture must never send .ended to a new tab")
    }

    func testFreshTrackpadBeganCanResumeBeforeIdleBoundary() {
        var state = PanScrollState()
        state.update(enabled: false, threshold: 4, now: 0)
        XCTAssertNil(state.receive(delta: 300, now: 0.01))
        state.update(enabled: true, threshold: 4, now: 0.02)
        XCTAssertEqual(state.receive(delta: 4, begins: true, now: 0.03), .init(translation: 4, phase: .began))
        XCTAssertFalse(state.suppressingSequence)
    }

    func testPhaseFreeMouseWheelResumesOnlyAfterIdle() {
        var state = PanScrollState()
        state.update(enabled: false, threshold: 4, now: 0)
        XCTAssertNil(state.receive(delta: 80, now: 0.01))
        state.update(enabled: true, threshold: 4, now: 0.02)
        XCTAssertNil(state.receive(delta: 80, now: 0.03))
        XCTAssertNil(state.receive(delta: 80, now: 0.32), "Movement refreshes the suppression deadline")
        XCTAssertEqual(state.receive(delta: 80, now: 0.63), .init(translation: 80, phase: .began))
    }

    func testDisabledEventsOnOtherAxisStillExtendMomentumSuppression() {
        var state = PanScrollState()
        state.update(enabled: false, threshold: 4, now: 0)
        XCTAssertNil(state.receive(delta: nil, now: 0.2))
        state.update(enabled: true, threshold: 4, now: 0.21)
        XCTAssertNil(state.receive(delta: 600, now: 0.4))
        XCTAssertNil(state.finishIdle(now: 0.69))
        XCTAssertNil(state.finishIdle(now: 0.71))
        XCTAssertEqual(state.receive(delta: 4, now: 0.72), .init(translation: 4, phase: .began))
    }

    func testRepeatedViewUpdatesKeepEnabledAccumulationAndLatestThreshold() {
        var state = PanScrollState(threshold: 10)
        XCTAssertNil(state.receive(delta: 3, now: 0))
        state.update(enabled: true, threshold: 5, now: 0.01)
        XCTAssertEqual(state.receive(delta: 2, now: 0.02), .init(translation: 5, phase: .began))
        XCTAssertEqual(state.finishIdle(now: 0.33), .init(translation: 5, phase: .ended))
    }

    func testIdleResetCannotDeliverDisabledDelayedCallback() {
        var state = PanScrollState()
        _ = state.receive(delta: 400, now: 0)
        state.update(enabled: false, threshold: 4, now: 0.1)
        XCTAssertNil(state.finishIdle(now: 0.41))
        XCTAssertFalse(state.active)
        state.update(enabled: true, threshold: 4, now: 0.42)
        XCTAssertEqual(state.receive(delta: 4, now: 0.43), .init(translation: 4, phase: .began))
    }
}
