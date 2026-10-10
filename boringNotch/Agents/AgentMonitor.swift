// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Observation
import UserNotifications

@MainActor @Observable
final class AgentMonitor {
    static let shared = AgentMonitor()
    private(set) var sessions: [AgentSession] = []
    private(set) var usage: [AgentUsageWindow] = []
    private(set) var detectedApps: [DetectedAgentApp] = []
    private(set) var diagnostics: [String] = []
    private(set) var folderNames: [String: String] = [:]
    private(set) var latestAlert: AgentSession?
    private(set) var navigationMessage: String?
    private(set) var refreshedAt: Date?
    var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "agents.alerts") }
    }
    private var providers: [String: any AgentSessionProvider] = [:]
    private var grants: [String: URL] = [:]
    private var task: Task<Void, Never>?
    private var generation = 0
    private var alerts = AgentAlertPolicy(startedAt: Date())
    private let notifications = AgentNotificationDelegate()

    private init() {
        alertsEnabled = UserDefaults.standard.bool(forKey: "agents.alerts")
        UNUserNotificationCenter.current().delegate = notifications
        restore("logs")
        restore("hooks")
        restore("grok")
        restart()
    }

    private func restore(_ kind: String) {
        guard let data = UserDefaults.standard.data(forKey: "agents.bookmark.\(kind)") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else {
                diagnostics.append("Folder access expired. Choose the \(kind) folder again.")
                return
            }
            attach(url, kind: kind)
        } catch { diagnostics.append("Saved folder access unavailable. Choose the \(kind) folder again.") }
    }

    func chooseFolder(_ kind: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = AgentDiscovery.suggestedFolder(kind)
        panel.message = kind == "grok" ? "Choose Grok Bot’s sand-client-persistence folder. Only its weekly usage cache is read; conversation blobs and credentials are ignored." : kind == "logs"
            ? "Choose your Codex sessions folder (usually ~/.codex/sessions). Only lifecycle metadata is kept."
            : "Choose the notch-agent-status folder created by the optional Codex hook bridge."
        panel.prompt = "Monitor locally"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            guard url.startAccessingSecurityScopedResource() else {
                navigationMessage = "Folder access was not granted. Choose the folder again."
                return
            }
            detach(kind)
            UserDefaults.standard.set(bookmark, forKey: "agents.bookmark.\(kind)")
            attach(url, kind: kind)
            restart()
        } catch { navigationMessage = "Could not save folder access. Choose the folder again." }
    }

    private func attach(_ url: URL, kind: String) {
        grants[kind] = url
        folderNames[kind] = url.lastPathComponent
        switch kind {
        case "logs": providers[kind] = CodexLogProvider(root: url)
        case "grok": providers[kind] = GrokBotCacheProvider(root: url)
        default: providers[kind] = CodexHookProvider(root: url)
        }
    }

    private func detach(_ kind: String) {
        grants.removeValue(forKey: kind)?.stopAccessingSecurityScopedResource()
        providers.removeValue(forKey: kind)
        folderNames.removeValue(forKey: kind)
        UserDefaults.standard.removeObject(forKey: "agents.bookmark.\(kind)")
    }

    func disconnect(_ kind: String) {
        detach(kind)
        restart()
    }

    private func restart() {
        generation += 1
        task?.cancel()
        sessions = []
        usage = []
        latestAlert = nil
        refreshedAt = nil
        alerts = AgentAlertPolicy(startedAt: Date())
        detectedApps = AgentDiscovery.apps()
        if providers.isEmpty { diagnostics = ["Monitoring is off. Connect a detected app to start."] }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    func refresh() async {
        let currentGeneration = generation
        let date = Date()
        let activeProviders = Array(providers.values)
        let snapshots = await withTaskGroup(of: AgentSnapshot.self) { group in
            for provider in activeProviders { group.addTask { await provider.snapshot(at: date) } }
            var snapshots: [AgentSnapshot] = []
            for await snapshot in group { snapshots.append(snapshot) }
            return snapshots
        }
        guard !Task.isCancelled, currentGeneration == generation else { return }
        detectedApps = AgentDiscovery.apps()
        sessions = AgentSessionMerge.merge(snapshots)
        usage = AgentUsageWindow.merge(snapshots.flatMap(\.usage))
        diagnostics = snapshots.isEmpty ? ["Monitoring is off. Connect a detected app to start."] : snapshots.map(\.diagnostic).sorted()
        refreshedAt = date
        let transitions = alerts.transitions(sessions, now: date)
        if let session = transitions.first { latestAlert = session }
        if alertsEnabled {
            for session in transitions { sendNotification(session) }
        }
    }

    func enableAlerts() {
        Task {
            do {
                alertsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !alertsEnabled { navigationMessage = "Notifications are disabled in macOS. In-app alerts remain available." }
            } catch { navigationMessage = "Notifications unavailable. In-app alerts remain available." }
        }
    }

    private func sendNotification(_ session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "Codex \(session.state.displayName.lowercased())"
        content.body = session.state == .completed ? "A turn finished. Check its result in Codex." : "A session needs your attention in Codex."
        content.sound = .default
        // No project path, prompt, response or tool data in lock-screen alerts.
        content.userInfo = ["sessionID": session.id, "surface": session.surface.rawValue]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                Task { @MainActor in AgentMonitor.shared.navigationMessage = "macOS could not deliver an alert. In-app alerts remain available." }
            }
        }
    }

    func openApp(_ providerID: String) {
        guard let app = detectedApps.first(where: { $0.id == providerID }), let url = app.url else {
            navigationMessage = "App not detected. Install or open it, then refresh discovery."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { Task { @MainActor in AgentMonitor.shared.navigationMessage = "Could not open the detected app." } }
        }
    }

    func dismissAlert() { latestAlert = nil }

    func navigate(_ session: AgentSession) {
        guard session.isNavigable else { navigationMessage = "This session has no supported navigation ID."; return }
        if session.surface == .desktop, let url = session.desktopURL,
           let handler = NSWorkspace.shared.urlForApplication(toOpen: url),
           Bundle(url: handler)?.bundleIdentifier == "com.openai.codex", NSWorkspace.shared.open(url) {
            navigationMessage = "Opened Codex. Thread routing depends on the installed app version."
        } else if let command = session.resumeCommand {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            navigationMessage = "Resume command copied. Run it in your terminal to open this session."
        }
    }
}

private final class AgentNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["sessionID"] as? String
        let surface = (info["surface"] as? String).flatMap(AgentSurface.init(rawValue:)) ?? .unspecified
        Task { @MainActor in
            if let id, let session = AgentMonitor.shared.sessions.first(where: { $0.id == id }) {
                AgentMonitor.shared.navigate(session)
            } else if let id, UUID(uuidString: id) != nil {
                AgentMonitor.shared.navigate(AgentSession(id: id, providerID: "codex", project: "Codex session", surface: surface,
                    state: .unknown, evidence: .hook, updatedAt: Date(), turnID: nil))
            }
        }
        completionHandler()
    }
}
