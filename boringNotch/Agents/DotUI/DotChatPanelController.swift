// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Compatibility bridge for existing Agents dashboard callers while Dot moves
/// into the notch's fourth tab. This no longer creates a secondary window.
@MainActor final class DotChatPanelController: NSObject {
    static let shared = DotChatPanelController()

    func show(attachedTo _: NSWindow, owner: BoringViewModel?) {
        guard let owner else { return }
        owner.coordinator.currentView = .dot
        if owner.notchState != .open { _ = owner.open() }
    }

    func dismiss(ifOwnedBy _: BoringViewModel) {}
    func dismiss(restoreFocus _: Bool = true) {}

    /// Preserved for existing geometry tests and callers; no panel is created.
    static func frame(parent: NSRect, visible: NSRect) -> NSRect {
        let width = min(560, max(0, visible.width - 16))
        let height = min(420, max(0, visible.height - 16))
        let x = min(max(parent.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = min(max(parent.minY - height + 4, visible.minY + 8), visible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Kept until all existing views stop needing their owning notch window.
struct DotParentWindowReader: NSViewRepresentable {
    var resolved: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.resolved = resolved; return view }
    func updateNSView(_ view: Reader, context: Context) { view.resolved = resolved }
    final class Reader: NSView {
        var resolved: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resolved?(self.window)
            }
        }
    }
}
