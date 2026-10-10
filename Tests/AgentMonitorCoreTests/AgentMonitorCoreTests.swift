// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AgentMonitorCore

final class AgentMonitorCoreTests: XCTestCase {
    let id = "11111111-2222-3333-4444-555555555555"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func line(_ type: String, _ payload: [String: Any], date: Date? = nil) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": type, "payload": payload,
            "timestamp": ISO8601DateFormatter().string(from: date ?? now)])
    }
    func session(state: AgentState = .working, evidence: AgentEvidence = .localLog, date: Date? = nil) -> AgentSession {
        AgentSession(id: id, providerID: "codex", project: "project", surface: .desktop,
            state: state, evidence: evidence, updatedAt: date ?? now, turnID: "turn-1")
    }

    func testLifecycleAndNoProseInference() {
        var value: AgentSession?
        CodexLogReducer.reduce(line: line("session_meta", ["id": id, "cwd": "/secret/project", "originator": "Codex Desktop"]), session: &value)
        XCTAssertEqual(value?.state, .unknown)
        XCTAssertEqual(value?.surface, .desktop)
        XCTAssertEqual(value?.project, "project")
        for (index, pair) in [("task_started", AgentState.working), ("task_complete", .completed), ("turn_aborted", .waiting), ("task_failed", .failed)].enumerated() {
            CodexLogReducer.reduce(line: line("event_msg", ["type": pair.0, "turn_id": "t"], date: now.addingTimeInterval(Double(index))), session: &value)
            XCTAssertEqual(value?.state, pair.1)
        }
        CodexLogReducer.reduce(line: line("event_msg", ["type": "agent_message", "message": "I failed. Approve?"], date: now.addingTimeInterval(10)), session: &value)
        XCTAssertEqual(value?.state, .failed)
        CodexLogReducer.reduce(line: Data("incomplete".utf8), session: &value)
        XCTAssertEqual(value?.state, .failed)
    }

    func testStalenessNeverInventsCompletion() {
        let value = session(date: now.addingTimeInterval(-601))
        XCTAssertTrue(value.isStale(at: now))
        XCTAssertEqual(value.state, .working)
    }

    func testMergeDeduplicatesAndRetainsSurface() {
        var hook = session(state: .waiting, evidence: .hook, date: now.addingTimeInterval(1))
        hook.surface = .unspecified
        let values = AgentSessionMerge.merge([AgentSnapshot(sessions: [session()], diagnostic: ""), AgentSnapshot(sessions: [hook], diagnostic: "")])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.surface, .desktop)
        XCTAssertEqual(values.first?.state, .waiting)
        XCTAssertEqual(values.first?.evidence, .hook)
    }

    func testAlertsSilentBaselineDeduplicatedAndStaleSuppressed() {
        var policy = AgentAlertPolicy(startedAt: now)
        XCTAssertTrue(policy.transitions([session(state: .completed)], now: now).isEmpty)
        XCTAssertEqual(policy.transitions([session(state: .waiting, date: now.addingTimeInterval(1))], now: now).count, 1)
        XCTAssertTrue(policy.transitions([session(state: .waiting, date: now.addingTimeInterval(2))], now: now).isEmpty)
        XCTAssertTrue(policy.transitions([session(state: .failed, date: now.addingTimeInterval(-700))], now: now).isEmpty)
        var nextTurn = session(state: .completed, date: now.addingTimeInterval(3))
        nextTurn.turnID = "turn-2"
        XCTAssertEqual(policy.transitions([nextTurn], now: now).count, 1)
    }

    func testNavigationRejectsUntrustedIDs() {
        var value = session()
        XCTAssertEqual(value.desktopURL?.absoluteString, "codex://threads/\(id)")
        XCTAssertEqual(value.resumeCommand, "codex resume \(id)")
        value = AgentSession(id: "x; curl evil", providerID: "codex", project: "p", surface: .cli,
            state: .waiting, evidence: .hook, updatedAt: now, turnID: nil)
        XCTAssertNil(value.resumeCommand)
        XCTAssertNil(value.desktopURL)
    }

    func testProvidersRejectSymlinksMalformedAndFutureStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("{}".utf8).write(to: external)
        defer { try? FileManager.default.removeItem(at: external) }
        let link = root.appendingPathComponent("escape.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertFalse(AgentFileSafety.regularFile(link, under: root))
        let record: [String: Any] = ["schema": 1, "session_id": id, "state": "waiting", "updated_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(500))]
        try JSONSerialization.data(withJSONObject: record).write(to: root.appendingPathComponent("future.json"))
        let snapshot = await CodexHookProvider(root: root).snapshot(at: now)
        XCTAssertTrue(snapshot.sessions.isEmpty)
    }

    func testLogProviderHandlesPartialAppendAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("session.jsonl")
        var content = line("session_meta", ["id": id, "cwd": "/p", "source": "cli"], date: Date())
        content.append(10)
        content.append(line("event_msg", ["type": "task_started", "turn_id": "1"], date: Date()))
        content.append(10)
        try content.write(to: url)
        let provider = CodexLogProvider(root: root)
        let working = await provider.snapshot(at: Date())
        XCTAssertEqual(working.sessions.first?.state, .working)
        content.append(Data("{\"type\":\"event_msg\"".utf8))
        try content.write(to: url)
        let partial = await provider.snapshot(at: Date())
        XCTAssertEqual(partial.sessions.first?.state, .working)
        try FileManager.default.removeItem(at: url)
        let removed = await provider.snapshot(at: Date())
        XCTAssertTrue(removed.sessions.isEmpty)
    }
}
