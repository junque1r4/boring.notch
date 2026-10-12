// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
// Dense session list inspired by Notchi (GPL-3.0). Original SwiftUI implementation;
// see docs/AGENT-DESIGN-NOTICES.md.
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

enum AgentSessionFilter: String, CaseIterable, Identifiable {
    case all = "All", working = "Working", attention = "Attention"
    var id: Self { self }
    func includes(_ session: AgentSession) -> Bool {
        self == .all || (self == .working && session.state == .working)
            || (self == .attention && [.waiting, .failed].contains(session.state))
    }
}

struct AgentsView: View {
    var monitor = AgentMonitor.shared
    @Binding var popoverActive: Bool
    @State private var activePopovers = AgentPopoverState()
    init(monitor: AgentMonitor = .shared, popoverActive: Binding<Bool> = .constant(false), notchViewModel: BoringViewModel? = nil) {
        self.monitor = monitor
        _popoverActive = popoverActive
    }
    var body: some View {
        AgentsDashboard(sessions: monitor.sessions, usage: monitor.usage, activity: monitor.activityHistory,
            apps: monitor.detectedApps,
            connected: Set(monitor.folderNames.keys), alert: monitor.latestAlert, now: monitor.refreshedAt ?? Date(),
            navigate: monitor.navigate, connect: monitor.chooseFolder, openApp: monitor.openApp,
            settings: { AgentsWindowController.shared.show() }, dismissAlert: monitor.dismissAlert,
            popoverChanged: { id, showing in
                activePopovers.update(providerID: id, showing: showing)
                popoverActive = activePopovers.isActive
            })
            .onDisappear { activePopovers.reset(); popoverActive = false }
    }
}

struct AgentsDashboard: View {
    let sessions: [AgentSession]
    let usage: [AgentUsageWindow]
    let activity: AgentActivityHistory
    let apps: [DetectedAgentApp]
    let connected: Set<String>
    let alert: AgentSession?
    let now: Date
    let navigate: (AgentSession) -> Void
    let connect: (String) -> Void
    let openApp: (String) -> Void
    let settings: () -> Void
    let dismissAlert: () -> Void
    var popoverChanged: (String, Bool) -> Void = { _, _ in }
    @State private var filter: AgentSessionFilter = .all

    var body: some View {
        GeometryReader { geometry in
            dashboard(compact: geometry.size.height < 230)
        }
    }

    private func dashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 3) {
            HStack {
                Text("Agents Status").font(.system(size: 13, weight: .semibold))
                if !compact { Text("ON THIS MAC").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
                Spacer()
                Button(action: settings) { Image(systemName: "slider.horizontal.3") }
                    .help("Agent monitoring settings").accessibilityLabel("Agent monitoring settings")
            }
            HStack(spacing: 8) {
                quotaCard("codex", title: "ChatGPT", caption: "Codex allowance · weekly", glyph: "C", kind: "logs", compact: compact)
                quotaCard("grok-bot", title: "Grok Bot", caption: "Weekly allowance", glyph: "G", kind: "grok", compact: compact)
            }
            AgentActivityCalendar(history: activity, now: now)
            if let alert {
                HStack(spacing: 6) {
                    Image(systemName: alert.state.symbol).foregroundStyle(alert.state.color)
                    Text("Codex \(alert.state.displayName.lowercased())").font(.system(size: 9))
                    Spacer()
                    Button("View") { navigate(alert) }
                    Button(action: dismissAlert) { Image(systemName: "xmark") }.accessibilityLabel("Dismiss agent alert")
                }.padding(compact ? 3 : 4).background(alert.state.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                    HStack { filters(compact: compact); Spacer() }
                    if sessions.filter(filter.includes).isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessions.isEmpty ? connected.contains("logs") ? "No recent local sessions" : "No local sessions detected" : "No sessions in this view")
                                .font(.system(size: 11, weight: .medium))
                            if !compact { Text("Grok Bot is detected separately; its cloud task states are unavailable locally.")
                                .font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(spacing: 3) {
                            ForEach(sessions.filter(filter.includes)) { session in
                                AgentSessionRow(session: session, now: now, navigate: navigate, compact: compact)
                            }
                        }
                    }
                }
            }.frame(maxHeight: .infinity)
            Text("Local session records · Approvals stay in the agent app")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, compact ? 3 : 8).foregroundStyle(.white)
    }

    private func filters(compact: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            ForEach(AgentSessionFilter.allCases) { choice in
                Button { filter = choice } label: {
                    Text("\(choice.rawValue) \(sessions.filter(choice.includes).count)")
                        .font(.system(size: compact ? 9 : 10, weight: .medium))
                        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 3 : 4)
                        .background(.white.opacity(filter == choice ? 0.14 : 0.04), in: Capsule())
                }.accessibilityAddTraits(filter == choice ? .isSelected : [])
            }
        }
    }

    private func quotaCard(_ id: String, title: String, caption: String, glyph: String, kind: String, compact: Bool) -> some View {
        AgentQuotaCard(providerID: id, title: title, caption: caption, glyph: glyph, windows: usage.filter { $0.providerID == id },
            app: apps.first { $0.id == id }, connected: connected.contains(kind), now: now,
            connect: { connect(kind) }, openApp: { openApp(id) }, compact: compact, popoverChanged: { popoverChanged(id, $0) })
    }
}

struct AgentQuotaCard: View {
    let providerID: String
    let title: String
    let caption: String
    let glyph: String
    let windows: [AgentUsageWindow]
    let app: DetectedAgentApp?
    let connected: Bool
    let now: Date
    let connect: () -> Void
    let openApp: () -> Void
    var compact = false
    var popoverChanged: (Bool) -> Void = { _ in }
    @State private var showDetails = false
    private var headline: AgentUsageWindow? { AgentUsageWindow.headline(for: providerID, in: windows) }
    var offersManualConnection: Bool { app?.isIdentified != true && !connected }
    private var resetPassed: Bool { headline?.resetsAt.map { $0 <= now } ?? false }
    private var currentUsedPercent: Double? { resetPassed ? nil : headline?.usedPercent }
    private var statusLabel: String {
        guard let headline else { return offersManualConnection ? "Connect local data" : "Usage unavailable" }
        if resetPassed { return "Reset passed · waiting for reading" }
        if headline.isStale(at: now) { return "Stale reading · may have changed" }
        return headline.resetsAt.map { "Reset \($0.formatted(.relative(presentation: .numeric)))" } ?? "Reset time unavailable"
    }
    private var usageColor: Color { glyph == "C" ? .cyan : .purple }
    private var percentLabel: String? { currentUsedPercent.map { "\(Int($0.rounded(.down)))%" } }

    var body: some View {
        Button { popoverChanged(true); showDetails = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(percentLabel.map { "USED \($0)" } ?? "USAGE —")
                        .font(.system(size: compact ? 18 : 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(currentUsedPercent == nil ? .secondary : usageColor)
                }
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        if let currentUsedPercent {
                            Capsule().fill(.white.opacity(0.10))
                            Capsule().fill(usageColor.opacity(headline?.isStale(at: now) == true ? 0.42 : 0.95))
                                .frame(width: geometry.size.width * min(1, max(0, currentUsedPercent / 100)))
                        } else {
                            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                    }
                }.frame(height: 4)
                HStack(spacing: 4) {
                    Text(statusLabel).lineLimit(1)
                    Spacer(minLength: 0)
                    if headline?.isStale(at: now) == true || resetPassed {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                    }
                }.font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(headline?.isStale(at: now) == true || resetPassed ? .orange : .secondary)
            }.padding(.horizontal, compact ? 7 : 9).padding(.vertical, compact ? 4 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("\(title), \(percentLabel.map { "used \($0)" } ?? "usage unavailable"), \(statusLabel)")
        .onChange(of: showDetails) { _, showing in popoverChanged(showing) }
        .onDisappear { popoverChanged(false) }
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(app?.status ?? "Discovery pending").font(.caption)
                if windows.isEmpty {
                    Text(offersManualConnection ? "App not detected. Choose its local data folder to connect manually." : "No weekly reading yet. Automatic monitoring retries as the app updates its local data.")
                        .font(.caption)
                }
                ForEach(windows) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(window.label): \(window.resetsAt.map { $0 <= now } == true ? "last reading \(Int(window.usedPercent.rounded(.down)))%" : "\(Int(window.usedPercent.rounded(.down)))% used")")
                            .font(.subheadline)
                        if let reset = window.resetsAt { Text("Reset: \(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                        Text("Observed: \(window.observedAt.formatted(date: .abbreviated, time: .shortened)) · \(window.source)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if window.isStale(at: now) { Text("Stale snapshot — current usage may differ.").font(.caption).foregroundStyle(.orange) }
                    }
                }
                Text(glyph == "C" ? "This is Codex allowance on your ChatGPT plan. Chat and voice message limits are separate and are not exposed here."
                    : "This is Grok Bot’s cached weekly pool, separate from Grok Build CLI. Task status is not exposed by this cache.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if offersManualConnection { Button("Connect local data…") { showDetails = false; popoverChanged(false); connect() } }
                    if app?.url != nil { Button("Open app", action: openApp) }
                }
            }.padding(16).frame(width: 310).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AgentActivityCalendar: View {
    let history: AgentActivityHistory
    let now: Date
    private var calendar: Calendar { .current }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Session activity").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Text(history.isTracking ? "\(history.activeDayCount) days with records" : "Waiting for local records")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1)
                Text(history.trackingStartedAt.map {
                    "Recording since \($0.formatted(.dateTime.month(.abbreviated).day())) · blank = unknown"
                } ?? "Codex session timestamps · blank = unknown")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 126, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 2) {
                if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
                   let firstWeek = calendar.date(byAdding: .weekOfYear, value: -11, to: currentWeek) {
                    ForEach(0..<12, id: \.self) { week in
                        VStack(spacing: 1) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstWeek) {
                                    activityCell(for: date)
                                }
                            }
                        }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("12-week local session activity calendar")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func activityCell(for date: Date) -> some View {
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
        let count = history.sessionCount(on: date, calendar: calendar)
        let tint: Color = count == 0 ? .white.opacity(0.035) : .cyan.opacity(count == 1 ? 0.42 : count < 4 ? 0.68 : 1)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(isFuture ? .clear : tint)
            .frame(width: 5, height: 5)
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.white.opacity(isFuture ? 0.035 : 0.025), lineWidth: 0.5))
            .help(dayDescription(date, count: count, isFuture: isFuture))
            .accessibilityLabel(dayDescription(date, count: count, isFuture: isFuture))
    }

    private func dayDescription(_ date: Date, count: Int, isFuture: Bool) -> String {
        let label = date.formatted(date: .complete, time: .omitted)
        if isFuture { return "\(label): future date" }
        if count == 0 { return "\(label): no local session record; activity is unknown" }
        let countLabel = count >= 5 ? "5+ recorded sessions" : "\(count) recorded session\(count == 1 ? "" : "s")"
        return "\(label): \(countLabel)"
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    let now: Date
    let navigate: (AgentSession) -> Void
    var compact = false
    @State private var hovered = false
    var body: some View {
        Button { navigate(session) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(session.state.color).frame(width: 3)
                Image(systemName: session.state.symbol).foregroundStyle(session.state.color).frame(width: 16)
                VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                    Text(session.project).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 3) {
                        Text(session.surface == .desktop ? "Codex Desktop" : session.surface == .cli ? "Codex CLI" : "Codex")
                        Text("· \(session.evidence == .hook ? "Hook" : "Local log")")
                        if session.isStale(at: now) { Text("· Stale").foregroundStyle(.orange) }
                    }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.state.displayName).font(.system(size: 10, weight: .semibold)).foregroundStyle(session.state.color)
                    Text(session.updatedAt, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Image(systemName: session.surface == .desktop ? "arrow.up.right" : "doc.on.doc")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 7).padding(.vertical, compact ? 4 : 7).frame(height: compact ? 36 : 44)
                .background(.white.opacity(hovered ? 0.11 : 0.045), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).disabled(!session.isNavigable).onHover { hovered = $0 }
            .help(session.surface == .desktop ? "Open session in Codex (version dependent)" : "Copy CLI resume command")
            .accessibilityLabel("\(session.project), \(session.state.displayName), \(session.surface == .desktop ? "open session in Codex" : "copy CLI resume command")")
    }
}

@MainActor final class AgentsWindowController: NSWindowController {
    static let shared = AgentsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Boring Notch Agents"
        window.contentView = NSHostingView(rootView: AgentSettingsView())
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
}

struct AgentSettingsView: View {
    var monitor = AgentMonitor.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your agents, at a glance").font(.title2.bold())
                Text("Apps and their local data are connected automatically. Monitoring keeps only status and usage metadata on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(monitor.detectedApps) { app in
                    HStack {
                        VStack(alignment: .leading) { Text(app.name).font(.headline); Text(app.status).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if app.url != nil { Button("Open app") { monitor.openApp(app.id) } }
                        let kind = app.id == "codex" ? "logs" : "grok"
                        if monitor.pausedKinds.contains(kind) && app.isIdentified {
                            Text("Paused").font(.caption)
                            Button("Resume monitoring") { monitor.resume(kind) }
                        } else if let name = monitor.folderNames[kind] {
                            Text(monitor.automaticKinds.contains(kind) ? "Automatic monitoring" : name).font(.caption).lineLimit(1)
                            Button("Pause monitoring") { monitor.disconnect(kind) }
                        } else if !app.isIdentified {
                            Button("Connect local data…") { monitor.chooseFolder(kind) }
                        } else { Text("Detecting local data…").font(.caption) }
                    }
                }
                Text("Detected apps use their usual local data folders automatically. Manual connection is available when an app cannot be detected. These local formats may change; snapshots can be stale.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Choose Codex hook bridge…") { monitor.chooseFolder("hooks") }
                    if let name = monitor.folderNames["hooks"] {
                        Text(name).font(.caption)
                        Button("Disconnect hooks") { monitor.disconnect("hooks") }
                    }
                }
                Link("Setup, privacy and integration details", destination: URL(string: "https://github.com/junque1r4/boring.notch/blob/agents/phase-1/docs/AGENTS.md")!).font(.caption)
                HStack {
                    Button(monitor.alertsEnabled ? "Disable macOS alerts" : "Enable macOS alerts") {
                        if monitor.alertsEnabled { monitor.alertsEnabled = false } else { monitor.enableAlerts() }
                    }
                    Text("In-app alerts are always available.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Completed means a turn ended. Waiting can mean interruption or approval. Grok Bot’s cloud session states and approval controls are unavailable through local usage data. Approve requests in the original app.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(monitor.diagnostics, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if let message = monitor.navigationMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                Divider()
                AgentsView(monitor: monitor).frame(height: 280).padding(10).background(.black, in: RoundedRectangle(cornerRadius: 12))
            }.padding(22)
        }.frame(minWidth: 520, minHeight: 560)
    }
}
