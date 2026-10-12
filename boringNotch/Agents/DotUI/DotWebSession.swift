// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Observation
import SwiftUI
import WebKit

/// A single app-owned browser session. Keeping the web view here preserves the
/// page, draft, and scroll position while SwiftUI removes the notch content.
@MainActor @Observable
final class DotWebSession: NSObject {
    static let shared = DotWebSession()

    private(set) var isLoading = false
    private(set) var pageTitle: String?
    private(set) var currentURL: URL?
    private(set) var errorMessage: String?
    private(set) var canGoBack = false
    private(set) var isPickerActive = false
    private(set) var isPopupActive = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored let isInputCheckMode: Bool
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var hasLoadedDot = false
    @ObservationIgnored private weak var activeHost: DotWebHostView?
    @ObservationIgnored private weak var attachedWindow: NSWindow?
    @ObservationIgnored private var waitingHosts: [WeakDotWebHost] = []
    @ObservationIgnored private var openPanel: NSOpenPanel?
    @ObservationIgnored private var restoreFocusAfterPicker = true
    @ObservationIgnored private var popupWindows: [ObjectIdentifier: NSWindow] = [:]

    private static let dotHome = URL(string: "https://chatgpt.com/dots/home")!
    // The identifier is dedicated to this app's Dot WebKit profile. WebKit
    // persists its cookies and website data without touching Safari's store.
    private static let profileID = UUID(uuidString: "E2F99BC4-1A7D-44AD-8A29-D6231DB794B7")!
    private static let inputCheckHTML = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
          <title>Local input check</title>
          <style>
            :root { color-scheme: dark; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            body { margin: 0; padding: 18px; background: #17191d; color: #f3f4f6; }
            h1 { margin: 0 0 8px; font-size: 18px; }
            p { margin: 0 0 16px; color: #c3c9d3; line-height: 1.4; }
            label { display: block; margin: 14px 0 5px; font-weight: 600; }
            input, textarea { box-sizing: border-box; width: 100%; padding: 10px;
              border: 1px solid #8793a7; border-radius: 7px; background: #252a32;
              color: white; font: inherit; }
            textarea { min-height: 90px; resize: vertical; }
            :focus-visible { outline: 3px solid #7cc7ff; outline-offset: 2px; }
          </style>
        </head>
        <body>
          <h1>Local input check</h1>
          <p>This page is offline. Click a field, type harmless text, press Tab,
             then try the notch controls and return to a field.</p>
          <label for="first">First text field</label>
          <input id="first" type="text" autocomplete="off" spellcheck="false" placeholder="Type a short test phrase">
          <label for="notes">Notes area</label>
          <textarea id="notes" autocomplete="off" spellcheck="false" placeholder="Type another test phrase"></textarea>
          <label for="last">Last text field</label>
          <input id="last" type="text" autocomplete="off" spellcheck="false" placeholder="Tab here after notes">
        </body>
        </html>
        """

    override init() {
        #if DOT_BROWSER_INPUT_CHECK
        let isInputCheckMode = true
        #else
        let isInputCheckMode = ProcessInfo.processInfo.arguments.contains("--dot-browser-input-check")
        #endif
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isInputCheckMode
            ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: Self.profileID)
        self.isInputCheckMode = isInputCheckMode
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observePageState()
    }

    func loadDotIfNeeded() {
        guard !hasLoadedDot else { return }
        hasLoadedDot = true
        errorMessage = nil
        if isInputCheckMode {
            webView.loadHTMLString(Self.inputCheckHTML, baseURL: nil)
        } else {
            webView.load(URLRequest(url: Self.dotHome))
        }
    }

    func reload() {
        errorMessage = nil
        if isInputCheckMode {
            hasLoadedDot = true
            webView.loadHTMLString(Self.inputCheckHTML, baseURL: nil)
            return
        }
        if hasLoadedDot, webView.url != nil {
            webView.reload()
        } else {
            hasLoadedDot = true
            webView.load(URLRequest(url: Self.dotHome))
        }
    }

    func goBack() {
        guard !isInputCheckMode else { return }
        guard webView.canGoBack else { return }
        errorMessage = nil
        webView.goBack()
    }

    func cancelActivePicker() {
        restoreFocusAfterPicker = false
        openPanel?.cancel(nil)
    }

    func cancelTransientUI() {
        cancelActivePicker()
        for window in Array(popupWindows.values) { window.close() }
        popupWindows.removeAll()
        isPopupActive = false
    }

    fileprivate func attach(_ host: DotWebHostView) {
        guard let window = host.window else { return }
        if let owner = activeHost, owner !== host, owner.window != nil {
            if !waitingHosts.contains(where: { $0.value === host }) {
                waitingHosts.append(WeakDotWebHost(host))
            }
            host.showOccupiedMessage()
            return
        }

        let isNewAttachment = activeHost !== host || webView.superview !== host || attachedWindow !== window
        activeHost = host
        attachedWindow = window
        waitingHosts.removeAll { $0.value == nil || $0.value === host }
        if webView.superview !== host {
            webView.removeFromSuperview()
            host.addSubview(webView)
        }
        host.hideOccupiedMessage()
        webView.frame = host.bounds
        webView.autoresizingMask = [.width, .height]
        if isNewAttachment { host.reportWindowAttachment() }
        loadDotIfNeeded()
    }

    fileprivate func detach(_ host: DotWebHostView) {
        waitingHosts.removeAll { $0.value == nil || $0.value === host }
        guard activeHost === host else { return }
        // End transient UI while this host still owns the web view. Parent
        // onDisappear can run after SwiftUI has already dismantled this view.
        cancelTransientUI()
        webView.removeFromSuperview()
        activeHost = nil
        attachedWindow = nil
        if let next = waitingHosts.compactMap(\.value).first(where: { $0.window != nil }) {
            attach(next)
        }
    }

    private func observePageState() {
        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.isLoading
                DispatchQueue.main.async { self?.isLoading = value }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.title
                DispatchQueue.main.async { self?.pageTitle = value }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.url
                DispatchQueue.main.async { self?.currentURL = value }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.canGoBack
                DispatchQueue.main.async { self?.canGoBack = value }
            }
        ]
    }

    private func beginUpload(parameters: WKOpenPanelParameters, from browser: WKWebView,
                             completionHandler: @escaping ([URL]?) -> Void) {
        guard openPanel == nil else {
            completionHandler(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.prompt = "Attach"
        openPanel = panel
        isPickerActive = true
        restoreFocusAfterPicker = true

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self, weak browser] response in
            completionHandler(response == .OK ? panel.urls : nil)
            let shouldRestore = self?.restoreFocusAfterPicker == true
            self?.openPanel = nil
            self?.isPickerActive = false
            if shouldRestore, let browser, let window = browser.window, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(browser)
            }
        }
        if let window = browser.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

@MainActor
extension DotWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if isInputCheckMode {
            // The diagnostic document has no remote resources, and no link,
            // redirect, popup, or authentication navigation may leave it.
            decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
            return
        }
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        switch DotWebNavigationPolicy.decision(for: url, navigationType: action.navigationType,
                                               isPopup: webView !== self.webView) {
        case .allow:
            decisionHandler(.allow)
        case .openExternally:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { errorMessage = nil }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        record(error, from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record(error, from: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView {
            errorMessage = isInputCheckMode
                ? "The local input check stopped responding. Reload to try again."
                : "Dot's page stopped responding. Reload to try again."
        }
    }

    private func record(_ error: Error, from browser: WKWebView) {
        guard browser === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }
}

@MainActor
extension DotWebSession: WKUIDelegate {
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        if isInputCheckMode {
            completionHandler(nil)
            return
        }
        beginUpload(parameters: parameters, from: webView, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isInputCheckMode else { return nil }
        guard let url = action.request.url else { return nil }
        switch DotWebNavigationPolicy.decision(for: url, navigationType: action.navigationType,
                                               isPopup: true) {
        case .cancel:
            return nil
        case .openExternally:
            NSWorkspace.shared.open(url)
            return nil
        case .allow:
            break
        }
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 650), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Dot sign in"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.delegate = self
        popupWindows[ObjectIdentifier(popup)] = window
        isPopupActive = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.removeValue(forKey: ObjectIdentifier(webView))?.close()
        isPopupActive = !popupWindows.isEmpty
    }
}

@MainActor
extension DotWebSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let entry = popupWindows.first(where: { $0.value === window }) {
            popupWindows.removeValue(forKey: entry.key)
            isPopupActive = !popupWindows.isEmpty
        }
    }
}

private final class WeakDotWebHost {
    weak var value: DotWebHostView?
    init(_ value: DotWebHostView) { self.value = value }
}

/// One WebKit view can only belong to one AppKit parent at a time. A second
/// visible notch receives an explicit placeholder until the owner disappears.
@MainActor
final class DotWebHostView: NSView {
    weak var session: DotWebSession?
    var inputWindowAttached: ((NSWindow, NSView, Bool) -> Bool)?
    private var clickMonitor: Any?
    private var occupiedLabel: NSTextField?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeClickMonitor()
        if window != nil {
            session?.attach(self)
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      self.session?.webView.superview === self else { return event }
                // Make the panel eligible for keys, then let WebKit's own
                // mouseDown select the HTML field's internal responder.
                _ = self.inputWindowAttached?(window, self.session!.webView, true)
                return event
            }
        } else {
            session?.detach(self)
        }
    }

    func reportWindowAttachment() {
        guard let window, let webView = session?.webView else { return }
        if inputWindowAttached?(window, webView, false) == true {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      self.session?.webView.superview === self else { return }
                window.makeFirstResponder(webView)
            }
        }
    }

    func showOccupiedMessage() {
        guard occupiedLabel == nil else { return }
        let label = NSTextField(labelWithString: "Dot is open on another display.")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        occupiedLabel = label
    }

    func hideOccupiedMessage() {
        occupiedLabel?.removeFromSuperview()
        occupiedLabel = nil
    }

    func dismantle() {
        removeClickMonitor()
        session?.detach(self)
        session = nil
        inputWindowAttached = nil
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

struct DotWebBrowser: NSViewRepresentable {
    let session: DotWebSession
    let inputWindowAttached: (NSWindow, NSView, Bool) -> Bool

    func makeNSView(context: Context) -> DotWebHostView {
        let host = DotWebHostView()
        host.session = session
        host.inputWindowAttached = inputWindowAttached
        return host
    }

    func updateNSView(_ host: DotWebHostView, context: Context) {
        host.inputWindowAttached = inputWindowAttached
        session.attach(host)
    }

    static func dismantleNSView(_ host: DotWebHostView, coordinator: ()) {
        host.dismantle()
    }
}
