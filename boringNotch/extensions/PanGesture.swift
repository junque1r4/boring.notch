//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//
// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import Defaults

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, enabled: Bool = true,
                    action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in if enabled { action(0, .ended) } },
                including: enabled ? .all : .subviews
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, enabled: enabled, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let enabled: Bool
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(direction: direction, threshold: threshold, enabled: enabled, action: action)
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator {
        Coordinator(direction: direction, threshold: threshold, enabled: enabled, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private var direction: PanDirection
        private var action: (CGFloat, NSEvent.Phase) -> Void
        private var localMonitor: Any?
        private var state: PanScrollState
        private var endTask: Task<Void, Never>?

        init(direction: PanDirection, threshold: CGFloat, enabled: Bool,
             action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.action = action
            self.state = PanScrollState(enabled: enabled, threshold: threshold)
        }

        func update(direction: PanDirection, threshold: CGFloat, enabled: Bool,
                    action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            let wasEnabled = state.enabled
            self.direction = direction
            self.action = action
            state.update(enabled: enabled, threshold: threshold, now: ProcessInfo.processInfo.systemUptime)
            if wasEnabled && !enabled {
                endTask?.cancel()
                endTask = nil
                scheduleEndTimeout()
            }
        }

        private func emit(_ event: PanScrollState.Action?) {
            guard let event, state.enabled else { return }
            switch event.phase {
            case .began: action(event.translation, .began)
            case .changed: action(event.translation, .changed)
            case .ended: action(event.translation, .ended)
            }
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let event = state.finishIdle(now: ProcessInfo.processInfo.systemUptime)
                emit(event)
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()

            // Local monitor for normal in-window scroll events.
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let lm = localMonitor {
                NSEvent.removeMonitor(lm)
                self.localMonitor = nil
            }

            state.reset()
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)

            // Determine whether to normalize system deltas to device (physical) direction.
            let deviceDirectionMultiplier: CGFloat = Defaults[.normalizeGestureDirection] ? (event.isDirectionInvertedFromDevice ? 1 : -1) : 1

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let rawDelta = direction.signed(
                deltaX: event.scrollingDeltaX * deviceDirectionMultiplier,
                deltaY: event.scrollingDeltaY * deviceDirectionMultiplier
            )
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let delta = rawDelta * scale

            let ends = event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled
            let callback = state.receive(delta: isAxisDominant ? delta : nil, begins: event.phase == .began,
                                         ends: ends, now: ProcessInfo.processInfo.systemUptime)
            emit(callback)
            if ends && !state.suppressingSequence && state.enabled {
                endTask?.cancel()
                endTask = nil
                return
            }
            guard isAxisDominant || state.suppressingSequence || !state.enabled else { return }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
