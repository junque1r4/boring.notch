// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Fixed roots and provider IDs only. The helper never accepts a client path,
/// reads authentication, or returns raw transcripts through XPC.
actor AutomaticAgentReader {
    private let codex: CodexLogProvider
    private let grok: GrokBotCacheProvider
    init(home: URL) {
        codex = CodexLogProvider(root: home.appendingPathComponent(".codex/sessions", isDirectory: true))
        grok = GrokBotCacheProvider(root: home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence", isDirectory: true))
    }
    func snapshot(providerID: String, at date: Date) async -> AgentSnapshot? {
        switch providerID {
        case "codex": return await codex.snapshot(at: date)
        case "grok-bot": return await grok.snapshot(at: date)
        default: return nil
        }
    }
}
