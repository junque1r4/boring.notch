// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
@testable import boringNotch

final class AppTestIsolationTests: XCTestCase {
    func testHostedTestsNeverAccessRealDotSecrets() throws {
        XCTAssertTrue(BoringAppExecution.isTestHost)
        // These calls must fail before any system Keychain operation, including
        // reads, writes and deletes. Use a fixture account as defense in depth.
        let secrets = DotKeychainStorage(service: "invalid.notch-unit-test")
        XCTAssertThrowsError(try secrets.read("fixture"))
        XCTAssertThrowsError(try secrets.write(Data([1]), account: "fixture"))
        XCTAssertThrowsError(try secrets.remove("fixture"))
    }

    @MainActor func testHostedAppDoesNotCreateProductionNotchWindows() throws {
        XCTAssertTrue(NSApplication.shared.windows.compactMap { $0 as? BoringNotchSkyLightWindow }.isEmpty)
    }
}
