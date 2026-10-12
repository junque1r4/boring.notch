// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Scroll callbacks belong to the content that received the start of a gesture.
/// A tab change must not let an old momentum stream become a notch command.
struct PanScrollState {
    enum Phase { case began, changed, ended }
    struct Action: Equatable {
        let translation: CGFloat
        let phase: Phase
    }

    static let idleInterval: TimeInterval = 0.3
    private(set) var enabled: Bool
    private(set) var threshold: CGFloat
    private(set) var accumulated: CGFloat = 0
    private(set) var active = false
    private(set) var suppressingSequence = false
    private var lastInputAt: TimeInterval?

    init(enabled: Bool = true, threshold: CGFloat = 4) {
        self.enabled = enabled
        self.threshold = threshold
    }

    mutating func update(enabled: Bool, threshold: CGFloat, now: TimeInterval) {
        if self.enabled && !enabled {
            clearAccumulation()
            suppressingSequence = true
            lastInputAt = now
        }
        self.enabled = enabled
        self.threshold = threshold
    }

    /// `delta == nil` means the event is primarily on the other axis.
    mutating func receive(delta: CGFloat?, begins: Bool = false, ends: Bool = false,
                          now: TimeInterval) -> Action? {
        releaseSuppressionAfterIdle(now: now)

        guard enabled else {
            clearAccumulation()
            suppressingSequence = true
            lastInputAt = now
            return nil
        }

        if suppressingSequence && begins {
            clearAccumulation()
            suppressingSequence = false
        }
        guard !suppressingSequence else {
            // Keep returning the native event, but never interpret its old
            // momentum (or delayed .ended) as a command in the new tab.
            lastInputAt = now
            return nil
        }

        if ends {
            let action = Action(translation: active ? accumulated.magnitude : 0, phase: .ended)
            clearAccumulation()
            lastInputAt = nil
            return action
        }
        guard let delta else { return nil }
        lastInputAt = now
        guard delta.magnitude > 0.2 else { return nil }

        accumulated = delta > 0 ? accumulated + delta : 0
        if !active && accumulated >= threshold {
            active = true
            return Action(translation: accumulated, phase: .began)
        }
        if active { return Action(translation: accumulated, phase: .changed) }
        return nil
    }

    mutating func finishIdle(now: TimeInterval) -> Action? {
        guard let lastInputAt, now - lastInputAt >= Self.idleInterval else { return nil }
        let action = enabled && !suppressingSequence
            ? Action(translation: active ? accumulated.magnitude : 0, phase: .ended) : nil
        clearAccumulation()
        suppressingSequence = false
        self.lastInputAt = nil
        return action
    }

    mutating func reset() {
        clearAccumulation()
        suppressingSequence = false
        lastInputAt = nil
    }

    private mutating func clearAccumulation() {
        accumulated = 0
        active = false
    }

    private mutating func releaseSuppressionAfterIdle(now: TimeInterval) {
        guard suppressingSequence, let lastInputAt,
              now - lastInputAt >= Self.idleInterval else { return }
        clearAccumulation()
        suppressingSequence = false
        self.lastInputAt = nil
    }
}
