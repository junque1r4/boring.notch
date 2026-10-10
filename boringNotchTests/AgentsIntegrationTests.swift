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

    func testForkHasSeparateIdentityAndNoUpstreamFeed() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.junque1r4.boringnotch.agents")
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        XCTAssertEqual(BoringNotchAppBundleNames.current, "Boring Notch Agents.app")
    }
}
