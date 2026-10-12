// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct DotChatView: View {
    @Bindable var store: DotChatStore
    let viewModel: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @State private var inputFocus = DotChatInputFocus()
    @State private var endpoint = ""
    @State private var setupError: String?
    @State private var atLatest = true
    @State private var viewportHeight: CGFloat = 0
    @State private var editingConnection = false

    private var compactSetupLayout: Bool {
        viewModel.notchSize.height < 390 && (store.configuration == nil || editingConnection)
    }

    var body: some View {
        VStack(spacing: 8) {
            DotChatHeader(store: store, close: dismissDot, editingConnection: $editingConnection)
            if store.configuration == nil || editingConnection {
                DotConnectionSetup(store: store, endpoint: $endpoint, setupError: $setupError,
                    editingConnection: $editingConnection, connect: connect)
            } else if store.connectionState == .signedOut || store.connectionState == .unavailable {
                Button("Sign in with GitHub", action: connect)
                    .buttonStyle(.borderedProminent)
            } else if store.connectionState == .connected && !store.subscriptionActive {
                Text("Waiting for ChatGPT to subscribe. A relay connection alone does not connect Dot.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = setupError ?? store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !compactSetupLayout {
                DotTranscript(store: store, atLatest: $atLatest, viewportHeight: $viewportHeight)
                if !atLatest && store.unreadCount > 0 {
                    Text("New replies below · scroll to the latest message")
                        .font(.caption).foregroundStyle(.cyan)
                }
                DotPendingControls(store: store, setupError: $setupError)
                DotComposerRow(store: store, close: dismissDot, inputWindowAttached: inputFocus.attachComposer)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
        .foregroundStyle(.white)
        .onAppear {
            inputFocus.begin(viewModel: viewModel)
            store.setPresentation(visible: true, atLatest: true)
        }
        .onDisappear {
            inputFocus.dismiss(restoreForegroundApplication: false)
            store.setPresentation(visible: false, atLatest: false)
            store.flushOnDismiss()
        }
        .background(DotParentWindowReader { inputFocus.attach(to: $0) })
        .onChange(of: coordinator.currentView) { _, selected in
            if selected != .dot { inputFocus.dismiss(restoreForegroundApplication: true) }
        }
        .onChange(of: editingConnection) { _, editing in
            if editing { endpoint = store.configuration?.origin.absoluteString ?? "" }
        }
    }

    private func connect() {
        setupError = nil
        guard let window = inputFocus.presentationAnchor else {
            setupError = "Open Dot in the notch to continue sign-in."
            return
        }
        Task { await store.connect(presentationAnchor: window) }
    }

    private func dismissDot() {
        inputFocus.dismiss(restoreForegroundApplication: true)
        viewModel.close(forced: true)
    }
}

private struct DotChatHeader: View {
    @Bindable var store: DotChatStore
    let close: () -> Void
    @Binding var editingConnection: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image("DotLogo").renderingMode(.original)
                .resizable().scaledToFit().frame(width: 25, height: 25)
                .accessibilityLabel("Dot logo")
            VStack(alignment: .leading, spacing: 1) {
                Text("Dot").font(.headline)
                Text(store.connectionState.label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if store.configuration != nil {
                Button {
                    editingConnection.toggle()
                } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).accessibilityLabel("Private Dot connection settings")
            }
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Close Dot chat")
        }
    }
}

private struct DotConnectionSetup: View {
    @Bindable var store: DotChatStore
    @Binding var endpoint: String
    @Binding var setupError: String?
    @Binding var editingConnection: Bool
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Connect your private Dot relay").font(.subheadline.weight(.semibold))
            Text("Only messages you send here leave this Mac. Your existing ChatGPT history stays in ChatGPT.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("https://your-relay.workers.dev", text: $endpoint)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Private relay address")
                Button("Set up") {
                    do {
                        try store.configureEndpoint(endpoint)
                        setupError = nil
                        editingConnection = false
                        connect()
                    } catch { setupError = error.localizedDescription }
                }.disabled(endpoint.isEmpty)
            }
            if store.configuration != nil {
                Button("Disconnect private relay") { Task { await store.disconnect() } }
                    .font(.caption).help("Revokes this app's connection. Messages and drafts stay on this Mac.")
            }
        }
    }
}

private struct DotPendingControls: View {
    @Bindable var store: DotChatStore
    @Binding var setupError: String?

    var body: some View {
        if store.pendingMessageID != nil {
            HStack {
                if store.canRetryPending {
                    Button("Retry receipt") { Task { await store.retryPending() } }
                        .help("Retries the same message ID; the relay deduplicates it.")
                }
                Spacer()
                Button("New message") {
                    do { try store.abandonPending() }
                    catch { setupError = error.localizedDescription }
                }.help("Keeps the pending message and allows another. This does not stop Dot; a later reply can still arrive.")
            }.font(.caption)
        }
    }
}

private struct DotTranscript: View {
    @Bindable var store: DotChatStore
    @Binding var atLatest: Bool
    @Binding var viewportHeight: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.messages.isEmpty {
                        Text("Your notch conversation will appear here.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 16)
                    }
                    ForEach(store.messages) { message in
                        DotMessageRow(message: message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("latest")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: DotBottomPreference.self,
                                value: geometry.frame(in: .named("dotTranscript")).maxY)
                        })
                }.padding(.trailing, 3)
            }
            .coordinateSpace(name: "dotTranscript")
            .background(GeometryReader { geometry in
                Color.clear.onAppear { viewportHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in viewportHeight = value }
            })
            .onPreferenceChange(DotBottomPreference.self) { bottom in
                let latest = bottom >= 0 && bottom <= viewportHeight + 20
                if atLatest != latest { atLatest = latest }
                store.setPresentation(visible: true, atLatest: latest)
            }
            .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
            .onChange(of: store.messages.count) { _, _ in
                if atLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DotMessageRow: View {
    let message: DotChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Dot")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(message.text).font(.system(size: 13)).textSelection(.enabled)
            if let delivery = message.delivery {
                Text(delivery.label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Color.white.opacity(0.07) : Color.cyan.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DotComposerRow: View {
    @Bindable var store: DotChatStore
    let close: () -> Void
    let inputWindowAttached: (NSWindow, Bool) -> Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom) {
                DotComposer(text: $store.draft, send: { Task { await store.sendDraft() } }, close: close,
                    inputWindowAttached: inputWindowAttached)
                    .frame(height: 62)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                Button("Send") { Task { await store.sendDraft() } }
                    .disabled(!store.canSend)
            }
            Text("Return sends · Shift–Return adds a line · \(store.draft.utf8.count)/8192 bytes")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct DotBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Owns focus and outside-click dismissal for one notch window.
@MainActor final class DotChatInputFocus {
    private var previousApplication: NSRunningApplication?
    private weak var ownerWindow: NSWindow?
    private weak var viewModel: BoringViewModel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var shouldFocusComposerOnAppear = false

    var presentationAnchor: NSWindow? { ownerWindow }

    func begin(viewModel: BoringViewModel) {
        self.viewModel = viewModel
        viewModel.isDotInputActive = true
        previousApplication = NSWorkspace.shared.frontmostApplication
        shouldFocusComposerOnAppear = viewModel.isMouseHovering()
    }

    func attach(to window: NSWindow?) {
        guard let window else { return }
        if ownerWindow !== window {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            ownerWindow = window
            localMonitor = nil
            globalMonitor = nil
            keyMonitor = nil
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard let window = self.ownerWindow else { return event }
                let point = event.window === window
                    ? window.convertPoint(toScreen: event.locationInWindow)
                    : NSEvent.mouseLocation
                if !self.containsNotchContent(point, in: window) { self.dismissFromOutsideClick() }
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let window = self.ownerWindow,
                          !self.containsNotchContent(NSEvent.mouseLocation, in: window) else { return }
                    self.dismissFromOutsideClick()
                }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.ownerWindow,
                      event.window === window, event.keyCode == 53 else { return event }
                if (window.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
                self.dismissFromEscape()
                return nil
            }
        }
    }

    func attachComposer(to window: NSWindow, userInitiated: Bool) -> Bool {
        guard let notchWindow = window as? BoringNotchSkyLightWindow else { return false }
        attach(to: notchWindow)
        guard userInitiated || shouldFocusComposerOnAppear else { return false }
        notchWindow.wantsKeyForTextInput = true
        return true
    }

    func dismiss(restoreForegroundApplication: Bool) {
        if let notchWindow = ownerWindow as? BoringNotchSkyLightWindow {
            notchWindow.wantsKeyForTextInput = false
            if notchWindow.isKeyWindow { notchWindow.resignKey() }
        }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        localMonitor = nil
        globalMonitor = nil
        keyMonitor = nil
        viewModel?.isDotInputActive = false
        let application = previousApplication
        previousApplication = nil
        ownerWindow = nil
        viewModel = nil
        if restoreForegroundApplication { application?.activate(options: []) }
    }

    private func dismissFromOutsideClick() {
        guard let viewModel else { return }
        dismiss(restoreForegroundApplication: false)
        viewModel.close(forced: true)
    }

    private func dismissFromEscape() {
        guard let viewModel else { return }
        dismiss(restoreForegroundApplication: true)
        viewModel.close(forced: true)
    }

    private func containsNotchContent(_ point: NSPoint, in window: NSWindow) -> Bool {
        guard let viewModel else { return false }
        let size = viewModel.notchSize
        let rect = NSRect(
            x: window.frame.midX - size.width / 2,
            y: window.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.contains(point)
    }
}

/// AppKit text input keeps IME marked text intact. Return sends only after
/// composition ends; Shift–Return remains a line break.
struct DotComposer: NSViewRepresentable {
    @Binding var text: String
    let send: () -> Void
    let close: () -> Void
    let inputWindowAttached: (NSWindow, Bool) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = ComposerTextView()
        editor.didAttachWindow = inputWindowAttached
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .white
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Message Dot")
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, !editor.hasMarkedText(), editor.string != text else { return }
        let selection = editor.selectedRange()
        editor.string = text
        editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DotComposer
        init(_ parent: DotComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if !editor.hasMarkedText() { parent.text = editor.string }
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) {
                parent.text = textView.string
                parent.send()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.close()
                return true
            }
            return false
        }
    }

    final class ComposerTextView: NSTextView {
        var didAttachWindow: ((NSWindow, Bool) -> Bool)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                let shouldFocus = didAttachWindow?(window, false) ?? false
                if shouldFocus {
                    DispatchQueue.main.async { [weak self, weak window] in
                        if let self { window?.makeFirstResponder(self) }
                    }
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            if let window, didAttachWindow?(window, true) == true {
                window.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }
    }
}
