// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import Defaults
import SwiftUI

enum DotLauncherSlot: Hashable {
    case accessory, tab
}

struct DotLauncherAnchors: PreferenceKey {
    static var defaultValue: [DotLauncherSlot: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [DotLauncherSlot: Anchor<CGRect>], nextValue: () -> [DotLauncherSlot: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct SharedDotLauncherKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sharedDotLauncher: Bool {
        get { self[SharedDotLauncherKey.self] }
        set { self[SharedDotLauncherKey.self] = newValue }
    }
}

/// One persistent button, above the content clipping and transitions. The
/// accessory and tab emit geometry only; neither creates a second avatar.
struct DotLauncherOverlay: View {
    let anchors: [DotLauncherSlot: Anchor<CGRect>]
    let useTab: Bool
    let isOpen: Bool
    /// The closed dock center in this overlay's coordinate space. Used only
    /// when the overlay first appears while the notch is already open.
    let closedFallbackOffset: CGPoint
    let clearanceY: CGFloat
    let motion: Animation?
    let onHover: (Bool) -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.enableOpeningAnimation) private var enableOpeningAnimation
    @State private var source = CGPoint.zero
    @State private var destination = CGPoint.zero
    @State private var progress: CGFloat = 0
    @State private var placed = false
    @State private var routeIsOpen = false
    @State private var isAnimatingRoute = false
    @State private var closedAnchor = DotLauncherClosedAnchor()
    @State private var transitionID = 0

    private var routeMotion: Animation? {
        reduceMotion || !enableOpeningAnimation ? nil : motion
    }

    var body: some View {
        GeometryReader { geometry in
            let accessory = anchors[.accessory].map { geometry[$0] }
            let tab = anchors[.tab].map { geometry[$0] }
            let measurement = DotLauncherMeasurement(
                closedRect: accessory,
                tabRect: useTab ? tab : accessory,
                isOpen: isOpen
            )
            DotLauncherButton(unreadCount: DotChatStore.shared.unreadCount, action: action)
                // Preserve the pre-overlay hover boundary: only Dot's fixed
                // button owns this callback. position expands its wrapper to
                // the window, where it would cancel the original notch timer.
                .onHover(perform: onHover)
                .position(x: 0, y: 0)
                .modifier(DotLauncherTravel(progress: progress, source: source,
                                            destination: destination, clearanceY: clearanceY))
                .opacity(placed ? 1 : 0)
                .allowsHitTesting(placed)
                .onChange(of: measurement, initial: true) { _, newValue in
                    if let rect = newValue.closedRect {
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        closedAnchor.observe(center, isOpen: newValue.isOpen,
                                             routeAnimating: isAnimatingRoute || newValue.isOpen != routeIsOpen)
                    }

                    if !placed {
                        guard newValue.isOpen ? newValue.tabRect != nil : newValue.closedRect != nil else {
                            return
                        }
                        let stableClosed = closedAnchor.resolvedCenter(
                            fallbackOffset: closedFallbackOffset,
                            containerWidth: geometry.size.width
                        )
                        let tabCenter = newValue.tabRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            source = stableClosed
                            destination = newValue.isOpen ? (tabCenter ?? stableClosed) : stableClosed
                            progress = newValue.isOpen ? 1 : 0
                            placed = true
                            routeIsOpen = newValue.isOpen
                        }
                        return
                    }

                    let fallback = closedAnchor.resolvedCenter(
                        fallbackOffset: closedFallbackOffset,
                        containerWidth: geometry.size.width
                    )
                    if newValue.isOpen == routeIsOpen {
                        if !isAnimatingRoute, !newValue.isOpen,
                           let stableClosed = closedAnchor.stableCenter,
                           stableClosed != source || stableClosed != destination {
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                source = stableClosed
                                destination = stableClosed
                            }
                        } else if newValue.isOpen, !isAnimatingRoute,
                                  let tabRect = newValue.tabRect {
                            let tabCenter = CGPoint(x: tabRect.midX, y: tabRect.midY)
                            if tabCenter != destination {
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { destination = tabCenter }
                            }
                        } else if !newValue.isOpen && !isAnimatingRoute {
                            // Closed live activities can resize the dock. Only
                            // follow them outside an open/close transition.
                            source = fallback
                        }
                        return
                    }
                    routeIsOpen = newValue.isOpen
                    transitionID += 1
                    let currentTransition = transitionID
                    isAnimatingRoute = routeMotion != nil

                    // Lock both endpoints for the whole route. In particular,
                    // closing never adopts the accessory's interpolated bounds.
                    let stableClosed = closedAnchor.stableCenter ?? fallback
                    let tabCenter = newValue.tabRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        source = stableClosed
                        if newValue.isOpen {
                            destination = tabCenter ?? destination
                        }
                    }

                    guard placed else { return }
                    withAnimation(routeMotion, completionCriteria: .logicallyComplete) {
                        progress = newValue.isOpen ? 1 : 0
                    } completion: {
                        guard transitionID == currentTransition,
                              routeIsOpen == newValue.isOpen else { return }
                        isAnimatingRoute = false
                    }
                }
                .onChange(of: reduceMotion) { _, _ in finishRouteImmediatelyIfNeeded() }
                .onChange(of: enableOpeningAnimation) { _, _ in finishRouteImmediatelyIfNeeded() }
        }
    }

    private func finishRouteImmediatelyIfNeeded() {
        guard isAnimatingRoute, reduceMotion || !enableOpeningAnimation else { return }
        transitionID += 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = routeIsOpen ? 1 : 0
            isAnimatingRoute = false
        }
    }
}

private struct DotLauncherMeasurement: Equatable {
    let closedRect: CGRect?
    let tabRect: CGRect?
    let isOpen: Bool
}

/// Holds the last fully settled closed endpoint while geometry is animating.
/// The transient measurement can change each frame without changing the route.
struct DotLauncherClosedAnchor {
    private(set) var stableCenter: CGPoint?

    mutating func observe(_ center: CGPoint, isOpen: Bool, routeAnimating: Bool) {
        if !isOpen && !routeAnimating {
            stableCenter = center
        }
    }

    func resolvedCenter(fallbackOffset: CGPoint, containerWidth: CGFloat) -> CGPoint {
        stableCenter ?? CGPoint(x: containerWidth / 2 + fallbackOffset.x,
                                y: fallbackOffset.y)
    }

}

private struct DotLauncherTravel: GeometryEffect {
    var progress: CGFloat
    let source: CGPoint
    let destination: CGPoint
    let clearanceY: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let point = DotLauncherFlight.point(progress: progress, from: source,
                                            to: destination, clearanceY: clearanceY)
        return ProjectionTransform(CGAffineTransform(translationX: point.x, y: point.y))
    }
}
