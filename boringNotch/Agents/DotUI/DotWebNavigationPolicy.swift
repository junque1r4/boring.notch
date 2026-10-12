// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import WebKit

/// Keep Dot and common sign-in redirects in the embedded session. Explicit
/// links to other sites leave the app; unsupported schemes never enter WebKit.
enum DotWebNavigationPolicy {
    enum Decision: Equatable {
        case allow
        case openExternally
        case cancel
    }

    static func decision(for url: URL, navigationType: WKNavigationType,
                         isPopup: Bool) -> Decision {
        if url.absoluteString == "about:blank" && isPopup { return .allow }
        let scheme = url.scheme?.lowercased()
        if navigationType == .linkActivated && ["mailto", "tel"].contains(scheme ?? "") {
            return .openExternally
        }
        guard scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            return .cancel
        }
        if navigationType == .linkActivated && !isDotOrSignInHost(host) {
            return .openExternally
        }
        return .allow
    }

    private static func isDotOrSignInHost(_ host: String) -> Bool {
        host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
            || host == "openai.com" || host.hasSuffix(".openai.com")
            || host == "accounts.google.com" || host == "appleid.apple.com"
            || host == "login.microsoftonline.com" || host == "login.live.com"
    }
}
