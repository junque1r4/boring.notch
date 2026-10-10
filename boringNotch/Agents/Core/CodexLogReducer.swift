// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Deliberately projects only lifecycle metadata; prompts, responses, tool
/// arguments, credentials and account IDs never enter the session model.
enum CodexLogReducer {
    static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func reduce(line: Data, session: inout AgentSession?) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return }
        if type == "session_meta" {
            guard let id = payload["id"] as? String, UUID(uuidString: id) != nil else { return }
            let origin = (payload["originator"] as? String ?? "").lowercased()
            let source = payload["source"] as? String
            let surface: AgentSurface = origin.contains("desktop") ? .desktop : source == "cli" ? .cli : .unspecified
            session = AgentSession(id: id, providerID: "codex", project: project(payload["cwd"]),
                surface: surface, state: .unknown, evidence: .localLog,
                updatedAt: timestamp(record["timestamp"]) ?? .distantPast, turnID: nil)
            return
        }
        guard type == "event_msg", var current = session,
              let event = payload["type"] as? String,
              let date = timestamp(record["timestamp"]), date >= current.updatedAt else { return }
        let state: AgentState
        switch event {
        case "task_started", "turn_started": state = .working
        case "task_complete", "task_completed", "turn_complete": state = .completed
        case "turn_aborted": state = .waiting
        case "task_failed", "turn_failed": state = .failed
        // No guesses from assistant prose, tool exit codes or inactivity.
        default: return
        }
        current.state = state
        current.updatedAt = date
        current.turnID = payload["turn_id"] as? String ?? current.turnID
        session = current
    }

    static func project(_ value: Any?) -> String {
        guard let path = value as? String else { return "Codex session" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return String(name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(80))
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
