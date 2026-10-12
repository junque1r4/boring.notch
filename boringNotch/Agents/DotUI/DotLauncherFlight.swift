// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics

/// A reversible route that takes Dot below the physical camera cutout before
/// moving horizontally between the closed launcher and the tab bar.
enum DotLauncherFlight {
    static func point(
        progress: CGFloat,
        from start: CGPoint,
        to end: CGPoint,
        clearanceY requestedClearanceY: CGFloat
    ) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        guard progress > 0, progress < 1 else {
            return progress == 0 ? start : end
        }

        let clearanceY = max(requestedClearanceY, start.y, end.y)

        if progress < 0.2 {
            let amount = smoothstep(progress / 0.2)
            return CGPoint(x: start.x, y: interpolate(start.y, clearanceY, amount))
        }

        if progress <= 0.8 {
            let amount = smoothstep((progress - 0.2) / 0.6)
            return CGPoint(x: interpolate(start.x, end.x, amount), y: clearanceY)
        }

        let amount = smoothstep((progress - 0.8) / 0.2)
        return CGPoint(x: end.x, y: interpolate(clearanceY, end.y, amount))
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    private static func interpolate(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (end - start) * amount
    }
}
