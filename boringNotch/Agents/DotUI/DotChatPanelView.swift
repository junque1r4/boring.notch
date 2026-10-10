// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct DotChatPanelView: View {
    @Bindable var store: DotChatStore
    let connect: () -> Void
    let close: () -> Void
    @State private var endpoint = ""
    @State private var setupError: String?
    @State private var atLatest = true
    @State private var viewportHeight: CGFloat = 0
    @State private var editingConnection = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "circle.fill").font(.system(size: 13)).foregroundStyle(.cyan)
                Text("Dot").font(.headline)
                Spacer()
                Text(store.connectionState.label).font(.caption).foregroundStyle(.secondary)
                if store.configuration != nil {
                    Button { editingConnection.toggle(); endpoint = store.configuration?.origin.absoluteString ?? "" } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).accessibilityLabel("Private Dot connection settings")
                }
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain)
                    .accessibilityLabel("Close Dot chat")
            }
            if store.configuration == nil || editingConnection {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Connect your private Dot relay").font(.subheadline.weight(.semibold))
                    Text("Only messages you send here leave this Mac. Your existing ChatGPT history stays in ChatGPT.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("https://your-relay.workers.dev", text: $endpoint)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Private relay address")
                        Button("Set up") {
                            do { try store.configureEndpoint(endpoint); setupError = nil; editingConnection = false; connect() }
                            catch { setupError = error.localizedDescription }
                        }.disabled(endpoint.isEmpty)
                    }
                    if store.configuration != nil {
                        Button("Disconnect private relay") { Task { await store.disconnect() } }
                            .font(.caption).help("Revokes this app's connection. Messages and drafts stay on this Mac.")
                    }
                }
            } else if store.connectionState == .signedOut || store.connectionState == .unavailable {
                Button("Sign in with GitHub", action: connect)
            } else if store.connectionState == .connected && !store.subscriptionActive {
                Text("Waiting for ChatGPT to subscribe. A relay connection alone does not connect Dot.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = setupError ?? store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            transcript
            if !atLatest && store.unreadCount > 0 {
                Text("New replies below · scroll to the latest message").font(.caption).foregroundStyle(.cyan)
            }
            Divider()
            if store.pendingMessageID != nil {
                HStack {
                    if store.canRetryPending {
                        Button("Retry receipt") { Task { await store.retryPending() } }
                            .help("Retries the same message ID; the relay deduplicates it.")
                    }
                    Spacer()
                    Button("New message") {
                        do { try store.abandonPending() } catch { setupError = error.localizedDescription }
                    }.help("Keeps the pending message and allows another. This does not stop Dot; a later reply can still arrive.")
                }.font(.caption)
            }
            HStack(alignment: .bottom) {
                DotComposer(text: $store.draft, send: { Task { await store.sendDraft() } }, close: close)
                    .frame(height: 68)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                Button("Send") { Task { await store.sendDraft() } }
                    .disabled(!store.canSend)
            }
            Text("Return sends · Shift–Return adds a line · \(store.draft.utf8.count)/8192 bytes")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16).background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
        .foregroundStyle(.white)
        .onDisappear { store.setPresentation(visible: false, atLatest: false) }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.messages.isEmpty {
                        Text("Your notch conversation will appear here.").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 16)
                    }
                    ForEach(store.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Dot").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(message.text).font(.system(size: 13)).textSelection(.enabled)
                            if let delivery = message.delivery {
                                Text(delivery.label).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == .user ? Color.white.opacity(0.07) : Color.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("latest")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: DotBottomPreference.self, value: geometry.frame(in: .named("dotTranscript")).maxY)
                        })
                }.padding(.trailing, 3)
            }.coordinateSpace(name: "dotTranscript")
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
    }
}

private struct DotBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// AppKit text input keeps IME marked text intact. An insertNewline command
/// becomes Send only when composition is finished and Shift is not held.
struct DotComposer: NSViewRepresentable {
    @Binding var text: String
    let send: () -> Void
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = ComposerTextView()
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
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { parent.close(); return true }
            return false
        }
    }
    final class ComposerTextView: NSTextView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { [weak self, weak window] in if let self { window?.makeFirstResponder(self) } } }
        }
    }
}
