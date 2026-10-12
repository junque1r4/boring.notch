// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Presents the retained website session in the same notch area as the relay.
struct DotBrowserChatView: View {
    @ObservedObject var viewModel: BoringViewModel
    @Binding var selectedMode: DotChatMode
    let focusReturn: DotChatFocusReturn
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @State private var inputFocus = DotChatInputFocus()
    @State private var session = DotWebSession.shared

    var body: some View {
        VStack(spacing: 8) {
            DotBrowserHeader(session: session, viewModel: viewModel, selectedMode: $selectedMode,
                close: dismissDot)
            if let error = session.errorMessage {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Retry") { session.reload() }
                        .font(.caption)
                }
            }
            DotWebBrowser(session: session, inputWindowAttached: inputFocus.attachComposer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
        .foregroundStyle(.white)
        .onAppear {
            inputFocus.externalPickerIsActive = { session.isPickerActive || session.isPopupActive }
            inputFocus.begin(viewModel: viewModel, focusReturn: focusReturn)
            session.loadDotIfNeeded()
        }
        .onDisappear {
            cancelTransientUIIfOwned()
            inputFocus.dismiss(restoreForegroundApplication: false)
        }
        .background(DotParentWindowReader { inputFocus.attach(to: $0) })
        .onChange(of: coordinator.currentView) { _, selected in
            if selected != .dot {
                cancelTransientUIIfOwned()
                inputFocus.dismiss(restoreForegroundApplication: true)
            }
        }
        .onChange(of: viewModel.notchState) { _, state in
            if state == .closed {
                cancelTransientUIIfOwned()
                inputFocus.dismiss(restoreForegroundApplication: false)
            }
        }
        .onChange(of: viewModel.dotKeyboardFocusRequested) { _, requested in
            if requested { inputFocus.focusComposerForKeyboardRequest() }
        }
    }

    private func dismissDot() {
        cancelTransientUIIfOwned()
        inputFocus.dismiss(restoreForegroundApplication: true)
        viewModel.close(forced: true)
    }

    private func cancelTransientUIIfOwned() {
        guard let window = inputFocus.presentationAnchor, session.webView.window === window else { return }
        session.cancelTransientUI()
    }
}

private struct DotBrowserHeader: View {
    let session: DotWebSession
    @ObservedObject var viewModel: BoringViewModel
    @Binding var selectedMode: DotChatMode
    let close: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image("DotLogo").renderingMode(.original)
                .resizable().scaledToFit().frame(width: 25, height: 25)
                .accessibilityLabel("Dot logo")
            VStack(alignment: .leading, spacing: 1) {
                Text(session.pageTitle ?? "Website")
                    .font(.headline)
                    .lineLimit(1)
                Text(session.currentURL?.host ?? "chatgpt.com")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 170, alignment: .leading)
            Spacer(minLength: 4)
            DotChatModePicker(selectedMode: $selectedMode)
            if session.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Loading website")
            }
            Button { session.goBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .disabled(!session.canGoBack)
                .help("Go back")
                .accessibilityLabel("Go back")
            Button { session.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .help("Reload website")
                .accessibilityLabel("Reload website")
            Button(action: openInSafari) { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.plain)
                .help("Open website in Safari")
                .accessibilityLabel("Open website in Safari")
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

    private func openInSafari() {
        guard let url = session.currentURL ?? URL(string: "https://chatgpt.com/dots/home") else { return }
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            NSWorkspace.shared.open(url)
            return
        }
        Task {
            do {
                try await NSWorkspace.shared.open([url], withApplicationAt: safari,
                    configuration: NSWorkspace.OpenConfiguration())
            } catch {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
