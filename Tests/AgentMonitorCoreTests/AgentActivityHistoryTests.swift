// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AgentMonitorCore

final class AgentActivityHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, updatedAt: Date) -> AgentSession {
        AgentSession(id: id, providerID: "codex", project: "project", surface: .cli,
            state: .completed, evidence: .localLog, updatedAt: updatedAt, turnID: nil)
    }

    func testRepeatedObservationsCountEachSessionOnceAndPersistOnlyDigests() throws {
        let observedAt = now
        let sessionID = "11111111-2222-3333-4444-555555555555"
        var history = AgentActivityHistory()
        history.record([session(sessionID, updatedAt: now)], observedAt: observedAt, calendar: calendar)
        history.record([session(sessionID, updatedAt: now)], observedAt: observedAt.addingTimeInterval(3), calendar: calendar)
        XCTAssertEqual(history.sessionCount(on: now, calendar: calendar), 1)
        XCTAssertEqual(history.activeDayCount, 1)
        XCTAssertEqual(history.trackingStartedAt, observedAt)

        let data = try JSONEncoder().encode(history)
        let storedText = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(storedText.contains(sessionID))
        XCTAssertEqual(try JSONDecoder().decode(AgentActivityHistory.self, from: data), history)
    }

    func testDistinctSessionsAreCountedAndUnobservedDaysStayEmpty() {
        var history = AgentActivityHistory()
        history.record([
            session("11111111-2222-3333-4444-555555555555", updatedAt: now),
            session("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", updatedAt: now)
        ], observedAt: now, calendar: calendar)
        XCTAssertEqual(history.sessionCount(on: now, calendar: calendar), 2)
        XCTAssertEqual(history.sessionCount(on: now.addingTimeInterval(-86_400), calendar: calendar), 0)
        XCTAssertFalse(history.hasRecordedActivity(on: now.addingTimeInterval(-86_400), calendar: calendar))
    }

    func testPollingOldSessionDoesNotMarkObservationDay() {
        var history = AgentActivityHistory()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let oldSession = session("11111111-2222-3333-4444-555555555555", updatedAt: yesterday)
        history.record([oldSession], observedAt: now, calendar: calendar)
        history.record([oldSession], observedAt: now.addingTimeInterval(3), calendar: calendar)
        XCTAssertEqual(history.sessionCount(on: yesterday, calendar: calendar), 1)
        XCTAssertEqual(history.sessionCount(on: now, calendar: calendar), 0)
    }

    func testHistoryRejectsOtherProvidersAndBoundsRetainedDays() {
        var history = AgentActivityHistory()
        var otherProvider = session("11111111-2222-3333-4444-555555555555", updatedAt: now)
        otherProvider.providerID = "grok-bot"
        let old = session("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", updatedAt: now.addingTimeInterval(-90 * 86_400))
        history.record([otherProvider, old], observedAt: now, calendar: calendar)
        XCTAssertEqual(history.activeDayCount, 0)
        XCTAssertEqual(history.sessionCount(on: now, calendar: calendar), 0)
    }

    func testDailySessionIdentifiersAreCapped() {
        let ids = (0..<12).map { index in
            String(format: "%08x-2222-3333-4444-%012x", index + 1, index + 1)
        }
        var history = AgentActivityHistory()
        history.record(ids.map { session($0, updatedAt: now) }, observedAt: now, calendar: calendar)
        XCTAssertEqual(history.sessionCount(on: now, calendar: calendar), 5)
    }
}
