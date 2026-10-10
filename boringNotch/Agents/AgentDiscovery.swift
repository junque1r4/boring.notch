// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin

struct DetectedAgentApp: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL?
    let isRunning: Bool
    let cliInstalled: Bool
    var isIdentified: Bool { url != nil || isRunning || cliInstalled }
    var status: String {
        if isRunning { return "App running" }
        if url != nil { return cliInstalled ? "App + CLI detected" : "App detected" }
        return cliInstalled ? "CLI detected" : "Not detected"
    }
}

@MainActor enum AgentDiscovery {
    /// The sandbox's home is its container; suggested paths refer to the user's home.
    static var userHome: URL {
        guard let path = getpwuid(getuid())?.pointee.pw_dir else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    static func suggestedFolder(_ kind: String) -> URL {
        userHome.appendingPathComponent(kind == "grok" ? "Library/Application Support/Grok Bot/sand-client-persistence"
            : kind == "hooks" ? ".codex/notch-agent-status" : ".codex/sessions", isDirectory: true)
    }
    static func apps() -> [DetectedAgentApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [("codex", "Codex", "com.openai.codex"), ("grok-bot", "Grok Bot", "com.anysphere.sand")].map { id, name, bundle in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            let cli = id == "codex" && ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                userHome.appendingPathComponent(".local/bin/codex").path].contains { FileManager.default.isExecutableFile(atPath: $0) }
            return DetectedAgentApp(id: id, name: name, url: url, isRunning: running.contains(bundle), cliInstalled: cli)
        }
    }
}
