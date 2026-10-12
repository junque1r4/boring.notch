// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Hosted unit tests load the app executable, but must not start the owner's
/// notch windows, monitoring, persistence or authenticated services.
enum BoringAppExecution {
    static var isBrowserInputCheck: Bool {
        #if DOT_BROWSER_INPUT_CHECK
        true
        #else
        ProcessInfo.processInfo.arguments.contains("--dot-browser-input-check")
        #endif
    }

    static var usesLiveDotStorage: Bool { !isTestHost && !isBrowserInputCheck }

    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["BORING_NOTCH_TEST_HOST"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
