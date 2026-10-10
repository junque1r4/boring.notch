// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AgentMonitorCore

final class AgentUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func grok(_ edits: [String: Any] = [:], date: Date? = nil) throws -> Data {
        var usage: [String: Any] = ["percentUsed": 62.4, "nextResetMs": now.addingTimeInterval(86400).timeIntervalSince1970 * 1000,
            "hasNonZeroIncludedLimit": true, "isTeamSeat": false, "isSandTrial": false]
        usage.merge(edits) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "value": ["kind": "present",
            "expiresAtMs": now.addingTimeInterval(86400).timeIntervalSince1970 * 1000,
            "reading": ["readAtMs": (date ?? now).timeIntervalSince1970 * 1000, "usage": usage]]])
    }
    func testGrokQuotaIsDistinctAndNeverInventsNewResetUsage() throws {
        let value = try XCTUnwrap(GrokBotUsageCache.decode(grok(), now: now).first)
        XCTAssertEqual(value.providerID, "grok-bot")
        XCTAssertEqual(try XCTUnwrap(value.remainingPercent(at: now)), 37.6, accuracy: 0.001)
        XCTAssertNil(value.remainingPercent(at: now.addingTimeInterval(86401)))
        XCTAssertTrue(value.isStale(at: now.addingTimeInterval(601)))
        XCTAssertEqual(GrokBotUsageCache.decode(try grok(["percentUsed": 120]), now: now).first?.remainingPercent(at: now), 0)
    }
    func testGrokMalformedUnknownPlanAndFutureReadingsStayUnavailable() throws {
        for edits: [String: Any] in [["percentUsed": true], ["percentUsed": -1], ["percentUsed": "40"],
            ["hasNonZeroIncludedLimit": false], ["hasNonZeroIncludedLimit": 1], ["isTeamSeat": true], ["nextResetMs": 1e100]] {
            XCTAssertTrue(GrokBotUsageCache.decode(try grok(edits), now: now).isEmpty)
        }
        XCTAssertTrue(GrokBotUsageCache.decode(try grok(date: now.addingTimeInterval(60)), now: now).isEmpty)
        XCTAssertTrue(GrokBotUsageCache.decode(Data("{}".utf8), now: now).isEmpty)
    }
    func base32(_ key: String) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var value: UInt32 = 0, bits = 0, result = ""
        for byte in key.utf8 {
            value = (value << 8 | UInt32(byte)) & 0xffff; bits += 8
            while bits >= 5 { bits -= 5; result.append(alphabet[Int(value >> bits & 31)]) }
        }
        if bits > 0 { result.append(alphabet[Int(value << (5 - bits) & 31)]) }
        return result + ".blob"
    }
    func testGrokProviderIgnoresOtherBlobsAndHidesAmbiguousAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = base32("sand-client-persistence.account.test.weekly-usage.cache")
        XCTAssertTrue(GrokBotUsageCache.isWeeklyCacheFilename(name))
        XCTAssertFalse(GrokBotUsageCache.isWeeklyCacheFilename(base32("account.test.transcript.replicas")))
        XCTAssertFalse(GrokBotUsageCache.isWeeklyCacheFilename("../../auth.json"))
        try grok().write(to: root.appendingPathComponent(name))
        try Data("not read".utf8).write(to: root.appendingPathComponent(base32("account.test.transcript.replicas")))
        let provider = GrokBotCacheProvider(root: root)
        let valid = await provider.snapshot(at: now)
        XCTAssertEqual(valid.usage.count, 1)
        XCTAssertTrue(valid.sessions.isEmpty, "App presence/cache must never become fabricated task status")
        try grok().write(to: root.appendingPathComponent(base32("account.other.weekly-usage.cache")))
        let ambiguous = await provider.snapshot(at: now)
        XCTAssertTrue(ambiguous.usage.isEmpty)
        XCTAssertTrue(ambiguous.diagnostic.contains("Multiple"))
    }
    func testUsageMergeDoesNotResurrectOldSecondaryWindow() {
        func window(_ id: String, _ date: Date) -> AgentUsageWindow {
            AgentUsageWindow(id: id, providerID: "codex", label: "Weekly", usedPercent: 10,
                resetsAt: now.addingTimeInterval(86400), observedAt: date, expiresAt: nil, source: "Local log")
        }
        let merged = AgentUsageWindow.merge([window("codex.primary", now), window("codex.secondary", now),
            window("codex.primary", now.addingTimeInterval(1))])
        XCTAssertEqual(merged.map(\.id), ["codex.primary"])
    }
    func testCodexUsesReportedWindowDurationAndReplacesMissingSecondary() throws {
        var session: AgentSession?, usage: [AgentUsageWindow] = []
        func line(_ limits: [String: Any], at date: Date) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date),
                "payload": ["type": "token_count", "rate_limits": limits]])
        }
        let window: [String: Any] = ["used_percent": 11, "window_minutes": 10080, "resets_at": now.addingTimeInterval(86400).timeIntervalSince1970]
        CodexLogReducer.reduce(line: try line(["limit_id": "codex", "primary": window, "secondary": window], at: now), session: &session, usage: &usage)
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.first?.label, "Weekly", "Primary is not necessarily a five-hour window")
        XCTAssertEqual(usage.first?.remainingPercent(at: now), 89)
        CodexLogReducer.reduce(line: try line(["limit_id": "codex", "primary": window, "secondary": NSNull()], at: now.addingTimeInterval(1)), session: &session, usage: &usage)
        XCTAssertEqual(usage.count, 1)
        XCTAssertNil(session, "Usage must not synthesize a session or change lifecycle state")
        CodexLogReducer.reduce(line: try line(["limit_id": "other-provider", "primary": window], at: now.addingTimeInterval(2)), session: &session, usage: &usage)
        XCTAssertEqual(usage.count, 1)
    }
}
