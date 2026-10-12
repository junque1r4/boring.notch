// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import Defaults
import SwiftUI

struct DotLauncherButton: View {
    let unreadCount: Int
    var isTransitioning: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.enableOpeningAnimation) private var enableOpeningAnimation
    @State private var isHovered = false
    @State private var hasObservedUnreadCount = false
    @State private var previousUnreadCount = 0
    @State private var reactionID = 0
    @State private var isNodding = false

    private var motionAllowed: Bool {
        !reduceMotion && enableOpeningAnimation
    }

    var body: some View {
        Button(action: action) {
            Image("DotLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, unreadCount > 9 ? 3 : 0)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Color(red: 1, green: 0.8, blue: 57.0 / 255), in: Capsule())
                            .fixedSize()
                            .offset(x: 6, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
                .scaleEffect(motionAllowed && isHovered ? 1.06 : 1)
                .rotationEffect(.degrees(motionAllowed && isHovered ? -3 : 0))
                .rotationEffect(.degrees(motionAllowed && isNodding ? 4 : 0))
                .offset(y: motionAllowed && isHovered ? -1 : 0)
                .animation(motionAllowed ? .spring(response: 0.22, dampingFraction: 0.72) : nil, value: isHovered)
                .animation(motionAllowed ? .spring(response: 0.24, dampingFraction: 0.62) : nil, value: isNodding)
        }
        .buttonStyle(DotLauncherPressStyle(motionAllowed: motionAllowed))
        .frame(width: 36, height: 32)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = !isTransitioning && hovering
        }
        .onChange(of: isTransitioning) { _, moving in
            if moving { isHovered = false }
        }
        .onAppear {
            previousUnreadCount = unreadCount
            hasObservedUnreadCount = true
        }
        .onChange(of: unreadCount) { _, newCount in
            defer { previousUnreadCount = newCount }
            guard hasObservedUnreadCount, newCount > previousUnreadCount, newCount > 0, motionAllowed else { return }
            reactionID += 1
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { cancelReaction() }
        }
        .onChange(of: enableOpeningAnimation) { _, enabled in
            if !enabled { cancelReaction() }
        }
        .task(id: reactionID) {
            let currentReactionID = reactionID
            guard currentReactionID > 0, motionAllowed else { return }
            isNodding = true
            do {
                try await Task.sleep(for: .milliseconds(130))
                try Task.checkCancellation()
                if reactionID == currentReactionID { isNodding = false }
            } catch {
                if reactionID == currentReactionID { isNodding = false }
            }
        }
        .accessibilityLabel("Open Dot chat")
        .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread \(unreadCount == 1 ? "message" : "messages")" : "No unread messages")
        .help(unreadCount > 0 ? "Open Dot chat, \(unreadCount) unread" : "Open Dot chat")
    }

    private func cancelReaction() {
        reactionID += 1
        isNodding = false
        isHovered = false
    }
}

private struct DotLauncherPressStyle: ButtonStyle {
    let motionAllowed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(motionAllowed && configuration.isPressed ? 0.94 : 1)
            .animation(motionAllowed ? .easeOut(duration: 0.08) : nil, value: configuration.isPressed)
    }
}
