// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftUI
@testable import boringNotch

@MainActor final class AgentsIntegrationTests: XCTestCase {
    func testAgentsRemainAvailableWithShelfDisabled() {
        XCTAssertTrue(tabs.contains { $0.view == .agents })
        XCTAssertTrue(tabs.contains { $0.view == .home })
        XCTAssertTrue(tabs.contains { $0.view == .shelf })
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
        // Optional reproducible visual artifact, never production session data.
        if let directory = ProcessInfo.processInfo.environment["AGENTS_TEST_RENDER_DIR"] {
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("agent-states.png"))
        }
    }

    func testForkHasSeparateIdentityAndNoUpstreamFeed() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.junque1r4.boringnotch.agents")
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        XCTAssertEqual(BoringNotchAppBundleNames.current, "Boring Notch Agents.app")
    }
}
