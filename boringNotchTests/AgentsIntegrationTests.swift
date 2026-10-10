// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftUI
@testable import boringNotch

@MainActor final class AgentsIntegrationTests: XCTestCase {
    func testAgentsRemainAvailableWithShelfDisabled() {
        let disabled = TabSelectionView.availableTabs(shelfEnabled: false)
        XCTAssertTrue(disabled.contains { $0.view == .agents })
        XCTAssertTrue(disabled.contains { $0.view == .home })
        XCTAssertFalse(disabled.contains { $0.view == .shelf })
        XCTAssertTrue(TabSelectionView.availableTabs(shelfEnabled: true).contains { $0.view == .shelf })
    }

    func testRowsRenderAllStatesAndStaleEvidence() throws {
        let states = AgentState.allCases
        let sessions = states.enumerated().map { index, state in
            AgentSession(id: "11111111-2222-3333-4444-55555555555\(index)", providerID: "codex",
                project: "Sample project", surface: index == 0 ? .desktop : .cli, state: state,
                evidence: index == 1 ? .hook : .localLog, updatedAt: Date().addingTimeInterval(-700), turnID: "t")
        }
        let view = VStack {
            ForEach(sessions) { session in AgentSessionRow(session: session, now: Date(), navigate: { _ in }) }
        }.padding().frame(width: 520).background(.black).foregroundStyle(.white)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        var painted = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 10) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 10) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(color.redComponent, color.greenComponent, color.blueComponent) > 0.15 { painted += 1 }
            }
        }
        XCTAssertGreaterThan(painted, 30, "Agent rows must paint visible content")
        // Optional reproducible visual artifact, never production session data.
        if ProcessInfo.processInfo.environment["AGENTS_TEST_RENDER_DIR"] != nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentMonitorValidation", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = directory.appendingPathComponent("agent-states.png")
            try data.write(to: url)
            print("Agent states snapshot: \(url.path)")
        }
    }

    func testDashboardRendersBothQuotasAndDiscovery() throws {
        let now = Date()
        let windows = [AgentUsageWindow(id: "codex.primary", providerID: "codex", label: "5-hour", usedPercent: 22,
            resetsAt: now.addingTimeInterval(3600), observedAt: now, expiresAt: nil, source: "Local log"),
            AgentUsageWindow(id: "grok-bot.weekly", providerID: "grok-bot", label: "Weekly", usedPercent: 62,
            resetsAt: now.addingTimeInterval(86400), observedAt: now.addingTimeInterval(-700), expiresAt: nil, source: "Desktop cache")]
        let sessions = AgentState.allCases.enumerated().map { index, state in
            AgentSession(id: "11111111-2222-3333-4444-55555555555\(index)", providerID: "codex",
                project: "Sample project \(index + 1)", surface: index == 0 ? .desktop : .cli, state: state,
                evidence: .localLog, updatedAt: now.addingTimeInterval(-10), turnID: "t")
        }
        let apps = [DetectedAgentApp(id: "codex", name: "Codex", url: nil, isRunning: true, cliInstalled: true),
            DetectedAgentApp(id: "grok-bot", name: "Grok Bot", url: nil, isRunning: true, cliInstalled: false)]
        let view = AgentsDashboard(sessions: sessions, usage: windows, apps: apps, connected: ["logs", "grok"],
            alert: nil, now: now, navigate: { _ in }, connect: { _ in }, openApp: { _ in }, settings: {}, dismissAlert: {})
            .padding(16).frame(width: 540, height: 430).background(.black)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 540, height: 430)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 2000)
        if ProcessInfo.processInfo.environment["AGENTS_TEST_RENDER_DIR"] != nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentMonitorValidation")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("agent-dashboard.png"))
        }
    }

    func testCompactNotchStillPaintsWorkingSessionBelowUsageCards() throws {
        let now = Date()
        let session = AgentSession(id: "11111111-2222-3333-4444-555555555555", providerID: "codex",
            project: "Working project", surface: .cli, state: .working, evidence: .localLog, updatedAt: now, turnID: "t")
        let windows = [AgentUsageWindow(id: "codex.primary", providerID: "codex", label: "5-hour", usedPercent: 22,
            resetsAt: now.addingTimeInterval(3600), observedAt: now, expiresAt: nil, source: "Local log"),
            AgentUsageWindow(id: "grok-bot.weekly", providerID: "grok-bot", label: "Weekly", usedPercent: 62,
            resetsAt: now.addingTimeInterval(86400), observedAt: now, expiresAt: nil, source: "Desktop cache")]
        let view = AgentsDashboard(sessions: [session], usage: windows, apps: [], connected: ["logs", "grok"],
            alert: nil, now: now, navigate: { _ in }, connect: { _ in }, openApp: { _ in }, settings: {}, dismissAlert: {})
            .frame(width: 580, height: 135).background(.black)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 580, height: 135)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var cyan = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent < 0.4, color.greenComponent > 0.55, color.blueComponent > 0.75 { cyan += 1 }
            }
        }
        XCTAssertGreaterThan(cyan, 10, "The Working row must remain visible alongside quotas at the real notch height")
        if ProcessInfo.processInfo.environment["AGENTS_TEST_RENDER_DIR"] != nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentMonitorValidation")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("agent-notch.png"))
        }
    }

    func testDiscoveryIncludesCodexAndGrokWithoutFabricatingSessions() {
        let apps = AgentDiscovery.apps()
        XCTAssertEqual(Set(apps.map(\.id)), ["codex", "grok-bot"])
        XCTAssertEqual(AgentDiscovery.suggestedFolder("logs").lastPathComponent, "sessions")
        XCTAssertEqual(AgentDiscovery.suggestedFolder("grok").lastPathComponent, "sand-client-persistence")
        XCTAssertFalse(AgentDiscovery.suggestedFolder("logs").path.contains("/Containers/"))
        XCTAssertEqual(DetectedAgentApp(id: "grok-bot", name: "Grok Bot", url: nil,
            isRunning: true, cliInstalled: false).status, "App running")
    }

    func testForkHasSeparateIdentityAndNoUpstreamFeed() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.junque1r4.boringnotch.agents")
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        XCTAssertEqual(BoringNotchAppBundleNames.current, "Boring Notch Agents.app")
    }
}
