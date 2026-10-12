// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import XCTest
import WebKit
@testable import boringNotch

final class DotWebNavigationPolicyTests: XCTestCase {
    func testDotAndAuthenticationLinksStayInTheWebSession() throws {
        for value in [
            "https://chatgpt.com/dots/home",
            "https://auth.chatgpt.com/login",
            "https://openai.com/",
            "https://accounts.google.com/o/oauth2/auth",
            "https://appleid.apple.com/auth/authorize",
            "https://login.microsoftonline.com/authorize",
            "https://login.live.com/oauth20_authorize.srf"
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .linkActivated,
                                                            isPopup: false), .allow, value)
        }
    }

    func testClickedExternalHTTPSLinkOpensOutsideButHTTPSRedirectStaysEmbedded() throws {
        let url = try XCTUnwrap(URL(string: "https://example.org/article"))
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .linkActivated,
                                                        isPopup: false), .openExternally)
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .other,
                                                        isPopup: false), .allow)
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .formSubmitted,
                                                        isPopup: false), .allow)
    }

    func testPopupBlankDocumentIsAllowedOnlyForPopup() throws {
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: blank, navigationType: .other,
                                                        isPopup: true), .allow)
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: blank, navigationType: .other,
                                                        isPopup: false), .cancel)
    }

    func testUnsupportedSchemesAndHTTPAreCancelled() throws {
        for value in ["http://chatgpt.com/dots/home", "javascript:alert(1)", "file:///etc/passwd",
                      "data:text/html,hello", "myapp://callback"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .linkActivated,
                                                            isPopup: false), .cancel, value)
        }
    }

    func testOnlyClickedMailAndTelephoneLinksOpenExternally() throws {
        for value in ["mailto:help@example.org", "tel:+15551234567"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .linkActivated,
                                                            isPopup: false), .openExternally, value)
            XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .other,
                                                            isPopup: false), .cancel, value)
        }
    }

    func testLookalikeHostDoesNotInheritChatGPTTrust() throws {
        let url = try XCTUnwrap(URL(string: "https://chatgpt.com.attacker.example/login"))
        XCTAssertEqual(DotWebNavigationPolicy.decision(for: url, navigationType: .linkActivated,
                                                        isPopup: false), .openExternally)
    }
}
