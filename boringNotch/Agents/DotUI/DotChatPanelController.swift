// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

@MainActor final class DotChatPanelController: NSObject {
    static let shared = DotChatPanelController()
    private var panel: DotTextPanel?
    private weak var parent: NSWindow?
    private weak var owner: BoringViewModel?
    private let interactionID = UUID()
    private var previousApplication: NSRunningApplication?
    private weak var previousKeyWindow: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    func show(attachedTo parent: NSWindow, owner: BoringViewModel?) {
        if self.parent === parent, let panel { panel.makeKeyAndOrderFront(nil); return }
        dismiss(restoreFocus: false)
        self.parent = parent
        self.owner = owner
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousKeyWindow = NSApp.keyWindow
        owner?.acquireDotInteraction(interactionID)
        let panel = DotTextPanel(contentRect: Self.frame(parent: parent.frame, visible: parent.screen?.visibleFrame ?? parent.frame),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.isReleasedWhenClosed = false
        panel.title = "Dot chat"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = parent.level
        panel.collectionBehavior = parent.collectionBehavior
        panel.sharingType = parent.sharingType
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: DotChatPanelView(store: .shared,
            connect: { [weak panel] in guard let panel else { return }; Task { await DotChatStore.shared.connect(presentationAnchor: panel) } },
            close: { [weak self] in self?.dismiss() }))
        self.panel = panel
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        DotChatStore.shared.setPresentation(visible: true, atLatest: true)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.parent { self.dismiss(restoreFocus: false) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Outside clicks choose their own focus target.
            self?.dismiss(restoreFocus: false)
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        })
    }

    func dismiss(ifOwnedBy viewModel: BoringViewModel) {
        if owner === viewModel { dismiss() }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        owner?.releaseDotInteraction(interactionID)
        owner = nil; parent = nil
        DotChatStore.shared.setPresentation(visible: false, atLatest: false)
        try? DotChatStore.shared.flush()
        if restoreFocus {
            if let previousKeyWindow, previousKeyWindow.canBecomeKey { previousKeyWindow.makeKey() }
            else if let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication.activate(options: [])
            }
        }
        previousKeyWindow = nil; previousApplication = nil
    }

    static func frame(parent: NSRect, visible: NSRect) -> NSRect {
        let width = min(560, max(0, visible.width - 16))
        let height = min(420, max(0, visible.height - 16))
        let x = min(max(parent.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = min(max(parent.minY - height + 4, visible.minY + 8), visible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class DotTextPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

struct DotParentWindowReader: NSViewRepresentable {
    var resolved: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.resolved = resolved; return view }
    func updateNSView(_ view: Reader, context: Context) { view.resolved = resolved }
    final class Reader: NSView {
        var resolved: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.resolved?(self.window) }
        }
    }
}
