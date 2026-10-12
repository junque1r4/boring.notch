// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// Bounded, local-only calendar of days with observed Codex session metadata.
/// It stores one-way session digests per day so refresh polling never inflates counts.
struct AgentActivityHistory: Codable, Equatable, Sendable {
    static let retainedDays = 84
    private static let digestsPerDay = 5
    private(set) var trackingStartedAt: Date?
    private(set) var sessionDigestsByDay: [String: Set<String>] = [:]

    mutating func record(_ sessions: [AgentSession], observedAt: Date, calendar: Calendar = .current) {
        if trackingStartedAt == nil { trackingStartedAt = observedAt }
        let today = calendar.startOfDay(for: observedAt)
        let oldest = calendar.date(byAdding: .day, value: -(Self.retainedDays - 1), to: today) ?? today
        let futureLimit = observedAt.addingTimeInterval(300)
        for session in sessions where session.providerID == "codex" && session.isNavigable
            && session.updatedAt >= oldest && session.updatedAt <= futureLimit {
            let key = Self.dayKey(for: session.updatedAt, calendar: calendar)
            let digest = SHA256.hash(data: Data(session.id.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
            var digests = sessionDigestsByDay[key, default: []]
            if digests.count < Self.digestsPerDay { digests.insert(digest) }
            sessionDigestsByDay[key] = digests
        }
        let oldestKey = Self.dayKey(for: oldest, calendar: calendar)
        sessionDigestsByDay = sessionDigestsByDay.filter { $0.key >= oldestKey }
    }

    func sessionCount(on date: Date, calendar: Calendar = .current) -> Int {
        sessionDigestsByDay[Self.dayKey(for: date, calendar: calendar)]?.count ?? 0
    }

    func hasRecordedActivity(on date: Date, calendar: Calendar = .current) -> Bool {
        sessionCount(on: date, calendar: calendar) > 0
    }

    var activeDayCount: Int { sessionDigestsByDay.values.filter { !$0.isEmpty }.count }
    var isTracking: Bool { trackingStartedAt != nil }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
