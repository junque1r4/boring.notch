// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
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

/// A single silhouette spans the notch and its accessory. The invisible left
/// margin balances the right extension without shifting the physical notch.
struct DotNotchSurface: Shape {
    var leadingInset: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(leadingInset, .init(topRadius, bottomRadius)) }
        set {
            leadingInset = newValue.first
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let inset = min(max(0, leadingInset), rect.width)
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
            .path(in: CGRect(x: rect.minX + inset, y: rect.minY,
                             width: max(0, rect.width - inset), height: rect.height))
    }
}

/// One persistent button, above the content clipping and transitions. The
/// accessory and tab emit geometry only; neither creates a second avatar.
struct DotLauncherOverlay: View {
    let anchors: [DotLauncherSlot: Anchor<CGRect>]
    let useTab: Bool
    let clearanceY: CGFloat
    let motion: Animation?
    let onHover: (Bool) -> Void
    let action: () -> Void
    @State private var source = CGPoint.zero
    @State private var destination = CGPoint.zero
    @State private var progress: CGFloat = 0
    @State private var placed = false

    var body: some View {
        GeometryReader { geometry in
            let accessory = anchors[.accessory].map { geometry[$0] }
            let tab = anchors[.tab].map { geometry[$0] }
            let target = useTab ? (tab ?? accessory) : accessory
            let measurement = DotLauncherMeasurement(rect: target, useTab: useTab)
            DotLauncherButton(unreadCount: DotChatStore.shared.unreadCount, action: action)
                .position(x: 0, y: 0)
                .modifier(DotLauncherTravel(progress: progress, source: source,
                                            destination: destination, clearanceY: clearanceY))
                .opacity(placed ? 1 : 0)
                .allowsHitTesting(placed)
                .onHover(perform: onHover)
                .onChange(of: measurement, initial: true) { _, newValue in
                    guard let rect = newValue.rect else { return }
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    // Endpoints come from layout in the fixed window space.
                    // Never interpolate them alongside the flight progress.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if !placed {
                            source = center
                            destination = center
                            progress = newValue.useTab ? 1 : 0
                            placed = true
                        } else if newValue.useTab {
                            destination = center
                        } else {
                            source = center
                        }
                    }
                    withAnimation(motion) { progress = newValue.useTab ? 1 : 0 }
                }
        }
    }
}

private struct DotLauncherMeasurement: Equatable {
    let rect: CGRect?
    let useTab: Bool
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
