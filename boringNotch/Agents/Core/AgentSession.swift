// Modified 2026-10-10: local agent monitoring for the junque1r4 fork.
// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentState: String, Codable, CaseIterable, Sendable {
    case working, waiting, completed, failed, unknown
}

enum AgentEvidence: String, Codable, Sendable {
    case hook, localLog
}

enum AgentSurface: String, Codable, Sendable {
    case desktop, cli, unspecified
}

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    var providerID: String
    var project: String
    var surface: AgentSurface
    var state: AgentState
    var evidence: AgentEvidence
    var updatedAt: Date
    var turnID: String?

    var isNavigable: Bool { UUID(uuidString: id) != nil }
    var resumeCommand: String? { isNavigable ? "codex resume \(id)" : nil }
    var desktopURL: URL? { isNavigable ? URL(string: "codex://threads/\(id)") : nil }
    func isStale(at date: Date) -> Bool {
        (state == .working || state == .waiting || state == .unknown)
            && date.timeIntervalSince(updatedAt) > 600
    }
}

struct AgentSnapshot: Sendable {
    var sessions: [AgentSession]
    var diagnostic: String
    var usage: [AgentUsageWindow] = []
}

/// Providers only observe. Control capabilities must be added through a separate,
/// supported interface; a status file is never an approval authorization channel.
protocol AgentSessionProvider: Sendable {
    var id: String { get }
    func snapshot(at date: Date) async -> AgentSnapshot
}

enum AgentSessionMerge {
    static func merge(_ snapshots: [AgentSnapshot]) -> [AgentSession] {
        var sessions: [String: AgentSession] = [:]
        for session in snapshots.flatMap(\.sessions) {
            guard let previous = sessions[session.id] else { sessions[session.id] = session; continue }
            var newest = session.updatedAt > previous.updatedAt
                || (session.updatedAt == previous.updatedAt && session.evidence == .hook) ? session : previous
            if newest.surface == .unspecified {
                newest.surface = session.surface == .unspecified ? previous.surface : session.surface
            }
            sessions[session.id] = newest
        }
        return sessions.values.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }
}

struct AgentAlertKey: Hashable, Sendable {
    let id: String
    let turnID: String?
    let state: AgentState
}

/// Silent baseline; only new, fresh transitions after monitoring starts alert.
struct AgentAlertPolicy: Sendable {
    let startedAt: Date
    private var baselineLoaded = false
    private var seen: Set<AgentAlertKey> = []

    mutating func transitions(_ sessions: [AgentSession], now: Date) -> [AgentSession] {
        var result: [AgentSession] = []
        for session in sessions {
            let key = AgentAlertKey(id: session.id, turnID: session.turnID, state: session.state)
            let fresh = seen.insert(key).inserted
            if baselineLoaded && fresh && session.updatedAt >= startedAt && !session.isStale(at: now)
                && [.waiting, .completed, .failed].contains(session.state) {
                result.append(session)
            }
        }
        baselineLoaded = true
        return Array(result.prefix(5))
    }
}
