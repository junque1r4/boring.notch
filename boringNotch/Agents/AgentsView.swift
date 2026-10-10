// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension AgentState {
    var displayName: String {
        switch self {
        case .working: return String(localized: "Working")
        case .waiting: return String(localized: "Waiting")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .unknown: return String(localized: "Unknown")
        }
    }
    var color: Color {
        switch self {
        case .working: return .cyan
        case .waiting: return .orange
        case .completed: return .green
        case .failed: return .red
        case .unknown: return .gray
        }
    }
    var symbol: String {
        switch self {
        case .working: return "arrow.triangle.2.circlepath"
        case .waiting: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct AgentsView: View {
    var monitor = AgentMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Agents", systemImage: "cpu").font(.headline)
                Text("Local only").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { AgentsWindowController.shared.show() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Agent monitoring settings")
                    .accessibilityLabel("Agent monitoring settings")
            }
            if let alert = monitor.latestAlert {
                HStack(spacing: 6) {
                    Image(systemName: alert.state.symbol).foregroundStyle(alert.state.color)
                    Text("Codex \(alert.state.displayName.lowercased())").font(.caption)
                    Spacer()
                    Button("View") { monitor.navigate(alert) }
                    Button { monitor.dismissAlert() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss agent alert")
                }
            }
            if monitor.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(monitor.folderNames.isEmpty ? "Connect your Codex sessions" : "No recent sessions found").font(.subheadline)
                    Text("Read local activity, then return to Codex when a session needs you.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Set up monitoring") { AgentsWindowController.shared.show() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(monitor.sessions) { session in AgentSessionRow(session: session, now: monitor.refreshedAt ?? Date(), navigate: monitor.navigate) }
                    }
                }
            }
            Text("Approvals stay in Codex").font(.caption2).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    let now: Date
    let navigate: (AgentSession) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.state.symbol).foregroundStyle(session.state.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(session.surface == .desktop ? "Codex Desktop" : session.surface == .cli ? "Codex CLI" : "Codex")
                    Text("·")
                    Text(session.evidence == .hook ? "Hook" : "Local log")
                    if session.isStale(at: now) { Text("· Stale").foregroundStyle(.orange) }
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.state.displayName).font(.system(size: 10, weight: .semibold)).foregroundStyle(session.state.color)
                Text(session.updatedAt, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Button { navigate(session) } label: { Image(systemName: session.surface == .desktop ? "arrow.up.right.square" : "doc.on.doc") }
                .disabled(!session.isNavigable)
                .help(session.surface == .desktop ? "Open session in Codex (version dependent)" : "Copy CLI resume command")
                .accessibilityLabel(session.surface == .desktop ? "Open session in Codex" : "Copy CLI resume command")
        }
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class AgentsWindowController: NSWindowController {
    static let shared = AgentsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Boring Notch Agents"
        window.contentView = NSHostingView(rootView: AgentSettingsView())
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AgentSettingsView: View {
    var monitor = AgentMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your agents, at a glance").font(.title2.bold())
            Text("Monitoring stays on this Mac. Choose a folder to allow read-only access. Prompts, replies and tool arguments are not retained or sent anywhere.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Choose session logs…") { monitor.chooseFolder("logs") }
                if let name = monitor.folderNames["logs"] {
                    Text(name).font(.caption)
                    Button("Disconnect") { monitor.disconnect("logs") }
                }
            }
            Text("Usually ~/.codex/sessions. This optional adapter uses an unstable log format; states reflect the last lifecycle event, not a live process check.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Choose hook bridge…") { monitor.chooseFolder("hooks") }
                if let name = monitor.folderNames["hooks"] {
                    Text(name).font(.caption)
                    Button("Disconnect") { monitor.disconnect("hooks") }
                }
            }
            Link("Hook setup and source", destination: URL(string: "https://github.com/junque1r4/boring.notch/blob/agents/phase-1/docs/AGENTS.md")!)
                .font(.caption)
            HStack {
                Button(monitor.alertsEnabled ? "Disable macOS alerts" : "Enable macOS alerts") {
                    if monitor.alertsEnabled { monitor.alertsEnabled = false } else { monitor.enableAlerts() }
                }
                Text("In-app alerts are always available.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Completed means a turn ended, not that its goal succeeded. Waiting can mean an interruption or approval request. Stale means no recent lifecycle event. Approve and deny requests in Codex.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.diagnostics, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            if let message = monitor.navigationMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            Divider()
            AgentsView(monitor: monitor).frame(minHeight: 130).padding(10).background(.black, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 560)
    }
}
