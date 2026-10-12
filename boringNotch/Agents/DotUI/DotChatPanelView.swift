// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct DotChatView: View {
    @Bindable var store: DotChatStore
    @ObservedObject var viewModel: BoringViewModel
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
            DotChatHeader(store: store, viewModel: viewModel, close: dismissDot, editingConnection: $editingConnection)
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
        .onChange(of: viewModel.dotKeyboardFocusRequested) { _, requested in
            if requested { inputFocus.focusComposerForKeyboardRequest() }
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
    @ObservedObject var viewModel: BoringViewModel
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
            Button {
                viewModel.isDotPinned.toggle()
            } label: {
                Image(systemName: viewModel.isDotPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .help(viewModel.isDotPinned ? "Unpin Dot chat" : "Pin Dot chat")
            .accessibilityLabel(viewModel.isDotPinned ? "Unpin Dot chat" : "Pin Dot chat")
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
                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(spacing: 10) {
                            if index == 0 || !Calendar.current.isDate(message.createdAt, inSameDayAs: store.messages[index - 1].createdAt) {
                                DotDateSeparator(date: message.createdAt)
                            }
                            DotMessageRow(message: message)
                        }
                        .id(message.id)
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
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 6) {
                if message.role == .assistant {
                    Image("DotLogo").renderingMode(.original)
                        .resizable().scaledToFit().frame(width: 17, height: 17)
                        .accessibilityLabel("Dot")
                }
                DotMarkdownView(source: message.text)
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .help(message.createdAt.formatted(date: .complete, time: .complete))
                    if message.role == .user, let delivery = message.delivery {
                        DotDeliveryMark(delivery: delivery)
                    }
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 0, alignment: .leading)
            .frame(maxWidth: 520, alignment: .leading)
            .background(message.role == .user ? Color.white.opacity(0.085) : Color.cyan.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }
}

private struct DotDateSeparator: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.white.opacity(0.07), in: Capsule())
            .frame(maxWidth: .infinity).padding(.vertical, 2)
    }
}

private struct DotDeliveryMark: View {
    let delivery: DotMessageDelivery

    private var symbol: String {
        switch delivery {
        case .queued: return "clock"
        case .uncertain: return "questionmark.circle"
        case .delivered: return "checkmark"
        case .failed: return "xmark"
        case .replied: return "checkmark"
        }
    }

    private var label: String {
        switch delivery {
        case .queued: return "Queued at the private relay. Delivery to ChatGPT is not confirmed."
        case .uncertain: return "The relay receipt is unconfirmed; the app is checking the relay."
        case .delivered: return "The relay confirms delivery to ChatGPT. This does not confirm that Dot has read or processed the message."
        case .failed: return "The relay reports that delivery failed."
        case .replied: return "Dot replied to this message. This is a reply receipt, not a read receipt."
        }
    }

    var body: some View {
        HStack(spacing: -3) {
            Image(systemName: symbol)
            if delivery == .replied { Image(systemName: symbol) }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(delivery == .failed ? Color.orange : Color.cyan)
        .accessibilityElement()
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct DotMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(DotMarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .paragraph:
                    inlineText(block.text).font(.system(size: 13))
                case .heading:
                    inlineText(block.text).font(.system(size: 14, weight: .semibold))
                case .list:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(block.marker).foregroundStyle(.secondary)
                        inlineText(block.text)
                    }.font(.system(size: 13))
                case .code:
                    Text(block.text).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inlineText(_ source: String) -> Text {
        Text(DotMarkdownBlock.inline(source))
    }
}

struct DotMarkdownBlock {
    enum Kind: Equatable { case paragraph, heading, list, code }
    let kind: Kind
    let text: String
    var marker = ""

    static func parse(_ source: String) -> [DotMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [DotMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(DotMarkdownBlock(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(DotMarkdownBlock(kind: .code, text: code.joined(separator: "\n")))
                    code.removeAll(keepingCapacity: true)
                } else {
                    flushParagraph()
                }
                inCode.toggle()
                continue
            }
            if inCode { code.append(line); continue }
            if trimmed.isEmpty { flushParagraph(); continue }
            if let heading = headingContent(trimmed) {
                flushParagraph()
                blocks.append(DotMarkdownBlock(kind: .heading, text: heading))
            } else if let (marker, content) = listContent(trimmed) {
                flushParagraph()
                blocks.append(DotMarkdownBlock(kind: .list, text: content, marker: marker))
            } else {
                paragraph.append(trimmed)
            }
        }
        if inCode { blocks.append(DotMarkdownBlock(kind: .code, text: code.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func headingContent(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return String(line.dropFirst(hashes + 1))
    }

    private static func listContent(_ line: String) -> (String, String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return ("•", String(line.dropFirst(2)))
        }
        var digits = 0
        for character in line {
            guard character.isNumber else { break }
            digits += 1
        }
        let separator = line.dropFirst(digits).first
        guard digits > 0, (separator == "." || separator == ")"),
              line.dropFirst(digits + 1).first == " " else { return nil }
        let marker = String(line.prefix(digits + 1))
        return (marker, String(line.dropFirst(digits + 2)))
    }

    static func isSafeLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil else { return false }
        if components.scheme?.lowercased() == "https" { return components.host?.isEmpty == false }
        if components.scheme?.lowercased() == "http" { return components.host?.isEmpty == false }
        return false
    }

    static func inline(_ source: String) -> AttributedString {
        var value: AttributedString
        do {
            value = try AttributedString(markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            value = AttributedString(source)
        }
        for run in Array(value.runs) {
            guard let link = run.link, !isSafeLink(link) else { continue }
            value[run.range].link = nil
        }
        return value
    }
}

private struct DotComposerRow: View {
    @Bindable var store: DotChatStore
    let close: () -> Void
    let inputWindowAttached: (NSWindow, NSTextView, Bool) -> Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            DotComposer(text: $store.draft, send: { Task { await store.sendDraft() } }, close: close,
                inputWindowAttached: inputWindowAttached)
                .frame(height: 62)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { Task { await store.sendDraft() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .help("Send message")
            .accessibilityLabel("Send message")
            .disabled(!store.canSend)
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
    private weak var composer: NSTextView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var shouldFocusComposerOnAppear = false

    var presentationAnchor: NSWindow? { ownerWindow }

    func begin(viewModel: BoringViewModel) {
        self.viewModel = viewModel
        viewModel.isDotInputActive = true
        let request = viewModel.consumeDotKeyboardFocusRequest()
        previousApplication = request.previousApplication ?? NSWorkspace.shared.frontmostApplication
        shouldFocusComposerOnAppear = request.requested || viewModel.isMouseHovering()
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

    func attachComposer(to window: NSWindow, composer: NSTextView, userInitiated: Bool) -> Bool {
        guard let notchWindow = window as? BoringNotchSkyLightWindow else { return false }
        attach(to: notchWindow)
        self.composer = composer
        guard userInitiated || shouldFocusComposerOnAppear || viewModel?.dotKeyboardFocusRequested == true else { return false }
        notchWindow.wantsKeyForTextInput = true
        return true
    }

    func focusComposerForKeyboardRequest() {
        guard let viewModel else { return }
        let request = viewModel.consumeDotKeyboardFocusRequest()
        guard request.requested else { return }
        if let application = request.previousApplication { previousApplication = application }
        shouldFocusComposerOnAppear = true
        guard let notchWindow = ownerWindow as? BoringNotchSkyLightWindow else { return }
        notchWindow.wantsKeyForTextInput = true
        notchWindow.makeKeyAndOrderFront(nil)
        if let composer { notchWindow.makeFirstResponder(composer) }
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
        _ = viewModel?.consumeDotKeyboardFocusRequest()
        let application = previousApplication
        previousApplication = nil
        ownerWindow = nil
        viewModel = nil
        composer = nil
        if restoreForegroundApplication { application?.activate(options: []) }
    }

    private func dismissFromOutsideClick() {
        guard let viewModel else { return }
        guard !viewModel.isDotPinned else { return }
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
    let inputWindowAttached: (NSWindow, NSTextView, Bool) -> Bool

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
        var didAttachWindow: ((NSWindow, NSTextView, Bool) -> Bool)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                let shouldFocus = didAttachWindow?(window, self, false) ?? false
                if shouldFocus {
                    DispatchQueue.main.async { [weak self, weak window] in
                        if let self { window?.makeFirstResponder(self) }
                    }
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            if let window, didAttachWindow?(window, self, true) == true {
                window.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }
    }
}
