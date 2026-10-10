// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentFileSafety {
    static func regularFile(_ url: URL, under root: URL, maximumSize: Int? = nil) -> Bool {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().path.hasPrefix(base),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return maximumSize.map { (values.fileSize ?? Int.max) <= $0 } ?? true
    }
}

actor CodexLogProvider: AgentSessionProvider {
    nonisolated let id = "codex-logs"
    private let root: URL
    private var cache: [URL: (Date, Int, AgentSession?)] = [:]
    init(root: URL) { self.root = root }

    func snapshot(at date: Date) async -> AgentSnapshot {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return AgentSnapshot(sessions: [], diagnostic: "Session folder unavailable. Choose it again.")
        }
        var candidates: [(URL, Date, Int)] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { break }
            guard url.pathExtension == "jsonl", AgentFileSafety.regularFile(url, under: root),
                  let values = try? url.resourceValues(forKeys: keys),
                  let modified = values.contentModificationDate, date.timeIntervalSince(modified) <= 86_400 else { continue }
            candidates.append((url, modified, values.fileSize ?? 0))
        }
        candidates.sort { $0.1 > $1.1 }
        candidates = Array(candidates.prefix(80))
        let active = Set(candidates.map { $0.0 })
        cache = cache.filter { active.contains($0.key) }
        var sessions: [AgentSession] = []
        var unreadable = 0
        for (url, modified, size) in candidates {
            if let cached = cache[url], cached.0 == modified, cached.1 == size {
                if let session = cached.2 { sessions.append(session) }
                continue
            }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let header = try handle.read(upToCount: 1_048_576) ?? Data()
                var session: AgentSession?
                if let end = header.firstIndex(of: 10) {
                    CodexLogReducer.reduce(line: header[..<end], session: &session)
                }
                let offset = max(0, size - 262_144)
                try handle.seek(toOffset: UInt64(offset))
                let tail = try handle.read(upToCount: 262_144) ?? Data()
                var lines = tail.split(separator: 10, omittingEmptySubsequences: false)
                if offset > 0 && !lines.isEmpty { lines.removeFirst() }
                if tail.last != 10 && !lines.isEmpty { lines.removeLast() }
                for line in lines { CodexLogReducer.reduce(line: Data(line), session: &session) }
                cache[url] = (modified, size, session)
                if let session { sessions.append(session) }
            } catch { unreadable += 1 }
        }
        return AgentSnapshot(sessions: sessions, diagnostic:
            "Local logs • last 24 hours • up to 80 sessions\(unreadable > 0 ? " • some files unreadable" : "")\(visited > 20_000 ? " • scan limit reached" : "")")
    }
}

actor CodexHookProvider: AgentSessionProvider {
    nonisolated let id = "codex-hooks"
    private let root: URL
    init(root: URL) { self.root = root }

    func snapshot(at date: Date) async -> AgentSnapshot {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return AgentSnapshot(sessions: [], diagnostic: "Hook folder unavailable. Choose it again.")
        }
        var sessions: [AgentSession] = []
        for url in files.prefix(500) where url.pathExtension == "json" {
            guard AgentFileSafety.regularFile(url, under: root, maximumSize: 8192),
                  let data = try? Data(contentsOf: url),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["schema"] as? Int == 1,
                  let id = record["session_id"] as? String, UUID(uuidString: id) != nil,
                  let stateValue = record["state"] as? String, let state = AgentState(rawValue: stateValue),
                  let updated = CodexLogReducer.timestamp(record["updated_at"]),
                  updated <= date.addingTimeInterval(30), date.timeIntervalSince(updated) <= 86_400 else { continue }
            let project = String((record["project"] as? String ?? "Codex session").filter { !$0.isNewline && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }.prefix(80))
            sessions.append(AgentSession(id: id, providerID: "codex", project: project,
                surface: .unspecified, state: state, evidence: .hook, updatedAt: updated,
                turnID: (record["turn_id"] as? String).map { String($0.prefix(80)) }))
        }
        return AgentSnapshot(sessions: sessions, diagnostic: "Codex hooks • last 24 hours")
    }
}
