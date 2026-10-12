// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
import CryptoKit
@testable import boringNotch

private final class DotTestSecrets: DotSecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ account: String) throws -> Data? { lock.withLock { values[account] } }
    func write(_ data: Data, account: String) throws { lock.withLock { values[account] = data } }
    func remove(_ account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}

private final class DotTestArchive: DotArchiveStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DotChatArchive?
    var failSave = false
    init(_ archive: DotChatArchive? = nil) { value = archive }
    func load() throws -> DotChatArchive? { lock.withLock { value } }
    func save(_ archive: DotChatArchive) throws {
        try lock.withLock {
            if failSave { throw DotChatError.persistenceUnavailable }
            value = archive
        }
    }
    func clear() throws { lock.withLock { value = nil } }
}

private actor DotTestTransport: DotChatTransporting {
    private(set) var sent: [UUID] = []
    private var failures: Int
    private let eventError: DotChatError?
    private(set) var eventAttempts = 0
    init(failures: Int = 0, eventError: DotChatError? = nil) { self.failures = failures; self.eventError = eventError }
    func configure(_ configuration: DotRelayConfiguration) -> Bool { true }
    func install(_ credentials: DotOAuthCredentials, configuration: DotRelayConfiguration) {}
    func send(messageID: UUID, text: String) throws -> DotRelayReceipt {
        sent.append(messageID)
        if failures > 0 { failures -= 1; throw DotChatError.unavailable }
        return DotRelayReceipt(messageId: messageID, status: .queued, sequence: 1, subscriptionActive: true)
    }
    func events(after sequence: Int64) throws -> DotRelayEventBatch {
        eventAttempts += 1
        if let eventError { throw eventError }
        return DotRelayEventBatch(events: [], cursor: sequence, subscriptionActive: true)
    }
    func disconnect() {}
}

@MainActor private final class DotTestOAuth: DotOAuthAuthorizing {
    func authorize(configuration: DotRelayConfiguration, presentationAnchor: NSWindow) -> DotOAuthCredentials {
        DotOAuthCredentials(clientID: "test-public-client", accessToken: "test-token", refreshToken: nil, expiresAt: .distantFuture)
    }
}

private actor DotTestHTTP: DotHTTPClient {
    private(set) var requests: [URLRequest] = []
    let responses: [String: Data]
    let errors: [String: DotChatError]
    init(responses: [String: Data], errors: [String: DotChatError] = [:]) { self.responses = responses; self.errors = errors }
    func request(_ request: URLRequest, maximumBytes: Int) throws -> Data {
        requests.append(request)
        guard let path = request.url?.path else { throw DotChatError.invalidResponse }
        if let error = errors[path] { throw error }
        guard let data = responses[path], data.count <= maximumBytes else { throw DotChatError.invalidResponse }
        return data
    }
}

@MainActor final class DotChatTests: XCTestCase {
    private let endpoint = "https://private-dot.example.com"
    private func archive(pendingID: UUID = UUID()) throws -> DotChatArchive {
        DotChatArchive(configuration: try DotRelayConfiguration(endpoint: endpoint),
            messages: [DotChatMessage(id: pendingID, role: .user, text: "Private draft fixture", createdAt: Date(), delivery: .delivered)],
            draft: "Next message", pendingMessageID: pendingID)
    }
    private func store(_ archive: DotChatArchive? = nil, transport: DotTestTransport = DotTestTransport()) -> DotChatStore {
        DotChatStore(storage: DotTestArchive(archive), transport: transport, authorization: DotTestOAuth(), autoResume: false)
    }
    private func reply(sequence: Int64, eventID: UUID = UUID(), messageID: UUID, text: String = "Reply from Dot") -> DotRelayEvent {
        DotRelayEvent(sequence: sequence, eventId: eventID, type: .reply, messageId: messageID,
            status: nil, text: text, createdAt: Date())
    }

    func testEncryptedTranscriptRoundTripHasNoPlaintextAndTamperingFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.aesgcm")
        let storage = DotEncryptedArchiveStorage(url: url, secrets: DotTestSecrets())
        let value = try archive()
        try storage.save(value)
        XCTAssertEqual(try storage.load(), value)
        var ciphertext = try Data(contentsOf: url)
        XCTAssertNil(ciphertext.range(of: Data(value.messages[0].text.utf8)))
        XCTAssertNil(ciphertext.range(of: Data(value.draft.utf8)))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        ciphertext[ciphertext.count / 2] ^= 1
        try ciphertext.write(to: url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try Data(contentsOf: url), ciphertext, "An unreadable archive must remain intact")
    }

    func testMissingKeyNeverReplacesEncryptedHistoryWithEmptyPlaintext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.aesgcm")
        let first = DotEncryptedArchiveStorage(url: url, secrets: DotTestSecrets())
        try first.save(archive())
        let original = try Data(contentsOf: url)
        let missingKey = DotEncryptedArchiveStorage(url: url, secrets: DotTestSecrets())
        let store = DotChatStore(storage: missingKey, transport: DotTestTransport(), authorization: DotTestOAuth(), autoResume: false)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.flush())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDraftUsesUTF8LimitWithoutSplittingComposedCharacters() throws {
        let store = store()
        store.draft = String(repeating: "👨‍👩‍👧‍👦", count: 1_000)
        XCTAssertLessThanOrEqual(store.draft.utf8.count, DotChatLimits.draftBytes)
        XCTAssertTrue(store.draft.allSatisfy { String($0) == "👨‍👩‍👧‍👦" })
        try store.flush()
    }

    func testRelayReceiptDoesNotClaimDotProcessedOrReleasePending() throws {
        let id = UUID()
        let store = store(try archive(pendingID: id))
        store.apply(receipt: DotRelayReceipt(messageId: id, status: .delivered, sequence: 2, subscriptionActive: true))
        XCTAssertEqual(store.pendingMessageID, id)
        XCTAssertEqual(store.messages[0].delivery, .delivered)
        XCTAssertTrue(DotMessageDelivery.delivered.label.contains("awaiting Dot"))
        store.apply(receipt: DotRelayReceipt(messageId: id, status: .replied, sequence: 3, subscriptionActive: true))
        XCTAssertEqual(store.pendingMessageID, id, "Only the correlated reply event completes the native pending turn")
    }

    func testReplyDeduplicationUnreadAndForeignChannelIsolation() throws {
        let id = UUID(), eventID = UUID()
        let store = store(try archive(pendingID: id))
        try store.apply(batch: DotRelayEventBatch(events: [reply(sequence: 1, eventID: eventID, messageID: id)], cursor: 1, subscriptionActive: true))
        XCTAssertNil(store.pendingMessageID)
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.unreadCount, 1)
        try store.apply(batch: DotRelayEventBatch(events: [reply(sequence: 2, eventID: eventID, messageID: id), reply(sequence: 3, messageID: UUID(), text: "Foreign content")], cursor: 3, subscriptionActive: true))
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertFalse(store.messages.contains { $0.text == "Foreign content" })
        store.setPresentation(visible: true, atLatest: false)
        XCTAssertEqual(store.unreadCount, 1)
        store.setPresentation(visible: true, atLatest: true)
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testMalformedBatchCannotPartiallyAppendReplies() throws {
        let id = UUID()
        let store = store(try archive(pendingID: id))
        let original = store.messages
        let events = [reply(sequence: 1, messageID: id), reply(sequence: 2, messageID: id, text: String(repeating: "x", count: DotChatLimits.replyBytes + 1))]
        XCTAssertThrowsError(try store.apply(batch: DotRelayEventBatch(events: events, cursor: 2, subscriptionActive: true)))
        XCTAssertEqual(store.messages, original)
        XCTAssertEqual(store.pendingMessageID, id)
    }

    func testHistoryRetentionKeepsPendingAndFitsEncryptedArchiveBudget() throws {
        let id = UUID()
        var value = try archive(pendingID: id)
        value.messages += (0..<99).map { _ in DotChatMessage(id: UUID(), role: .assistant,
            text: String(repeating: "z", count: 24_000), createdAt: Date(), inReplyTo: id) }
        let storage = DotTestArchive(value)
        let store = DotChatStore(storage: storage, transport: DotTestTransport(), authorization: DotTestOAuth(), autoResume: false)
        try store.flush()
        let saved = try XCTUnwrap(storage.load())
        XCTAssertLessThanOrEqual(saved.messages.count, 100)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(saved).count, DotChatLimits.archiveBytes)
        XCTAssertTrue(saved.messages.contains { $0.id == id })
        XCTAssertEqual(saved.pendingMessageID, id)
    }

    func testNoAutomaticResendAndExplicitRetryKeepsStableUUID() async throws {
        let transport = DotTestTransport(failures: 1)
        let storage = DotTestArchive()
        let store = DotChatStore(storage: storage, transport: transport, authorization: DotTestOAuth(), autoResume: false)
        try store.configureEndpoint(endpoint)
        await store.connect(presentationAnchor: NSWindow())
        try store.apply(batch: DotRelayEventBatch(events: [], cursor: 0, subscriptionActive: true))
        store.draft = "A single user message"
        await store.sendDraft()
        let pending = try XCTUnwrap(store.pendingMessageID)
        XCTAssertEqual(try storage.load()?.pendingMessageID, pending)
        for _ in 0..<10 { await Task.yield() }
        let firstIDs = await transport.sent
        XCTAssertEqual(firstIDs, [pending])
        XCTAssertTrue(store.canRetryPending)
        await store.retryPending()
        let retriedIDs = await transport.sent
        XCTAssertEqual(retriedIDs, [pending, pending])
        XCTAssertEqual(store.messages.filter { $0.role == .user }.count, 1)
        await store.disconnect()
        let restored = DotChatStore(storage: storage, transport: transport, authorization: DotTestOAuth(), autoResume: false)
        XCTAssertEqual(restored.pendingMessageID, pending)
        XCTAssertEqual(restored.draft, "")
        let restoredSendCount = await transport.sent.count
        XCTAssertEqual(restoredSendCount, 2)
    }

    func testSaveFailurePreventsNetworkSendAndKeepsDraft() async throws {
        let transport = DotTestTransport()
        let storage = DotTestArchive()
        let store = DotChatStore(storage: storage, transport: transport, authorization: DotTestOAuth(), autoResume: false)
        try store.configureEndpoint(endpoint)
        await store.connect(presentationAnchor: NSWindow())
        try store.apply(batch: DotRelayEventBatch(events: [], cursor: 0, subscriptionActive: true))
        storage.failSave = true
        store.draft = "Must remain local"
        await store.sendDraft()
        XCTAssertEqual(store.draft, "Must remain local")
        XCTAssertNil(store.pendingMessageID)
        let sendCount = await transport.sent.count
        XCTAssertEqual(sendCount, 0)
        await store.disconnect()
    }

    func testSendWaitsForLiveDotSubscriptionAndLocalAbandonAcceptsLaterReply() async throws {
        let id = UUID()
        let store = store(try archive(pendingID: id))
        await store.connect(presentationAnchor: NSWindow())
        XCTAssertFalse(store.canSend)
        try store.abandonPending()
        try store.apply(batch: DotRelayEventBatch(events: [], cursor: 0, subscriptionActive: false))
        XCTAssertFalse(store.canSend)
        try store.apply(batch: DotRelayEventBatch(events: [reply(sequence: 1, messageID: id)], cursor: 1, subscriptionActive: true))
        XCTAssertTrue(store.canSend)
        XCTAssertEqual(store.messages.last?.inReplyTo, id)
        await store.disconnect()
    }

    func testPublicHTTPSOriginValidation() throws {
        XCTAssertEqual(try DotRelayConfiguration(endpoint: endpoint + "/").origin.absoluteString, endpoint)
        // The same public OAuth grant must cover /v1 and /mcp sibling routes.
        XCTAssertEqual(try DotRelayConfiguration(endpoint: endpoint).resource.absoluteString, endpoint)
        for value in ["http://example.com", "https://localhost", "https://127.0.0.1", "https://169.254.169.254", "https://dot.local",
                      "https://name:password@example.com", "https://example.com/path", "https://example.com?secret=x", "https://example.com:8443"] {
            XCTAssertThrowsError(try DotRelayConfiguration(endpoint: value), value)
        }
    }

    func testPKCEAndIssuerCallbackRejectMixupDuplicateAndWrongDestination() throws {
        let proof = DotPKCE()
        XCTAssertEqual(proof.verifier.count, 43)
        XCTAssertEqual(proof.challenge, DotPKCE.base64URL(Data(SHA256.hash(data: Data(proof.verifier.utf8)))))
        let issuer = try XCTUnwrap(URL(string: endpoint))
        var parts = URLComponents(url: DotOAuthProtocol.callback, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "code", value: "valid-code"), URLQueryItem(name: "state", value: proof.state), URLQueryItem(name: "iss", value: endpoint)]
        XCTAssertEqual(try DotOAuthProtocol.authorizationCode(callback: parts.url!, expectedState: proof.state, expectedIssuer: issuer), "valid-code")
        parts.queryItems?.append(URLQueryItem(name: "iss", value: endpoint))
        XCTAssertThrowsError(try DotOAuthProtocol.authorizationCode(callback: parts.url!, expectedState: proof.state, expectedIssuer: issuer))
        parts.queryItems?.removeLast()
        XCTAssertThrowsError(try DotOAuthProtocol.authorizationCode(callback: parts.url!, expectedState: "wrong-state", expectedIssuer: issuer))
        XCTAssertThrowsError(try DotOAuthProtocol.authorizationCode(callback: parts.url!, expectedState: proof.state, expectedIssuer: URL(string: "https://wrong.example.com")!))
        parts.port = 444
        XCTAssertThrowsError(try DotOAuthProtocol.authorizationCode(callback: parts.url!, expectedState: proof.state, expectedIssuer: issuer))
    }

    func testRelayWireContractAndFractionalTimestampDecode() async throws {
        let id = UUID(), eventID = UUID()
        let receipt = Data("{\"messageId\":\"\(id)\",\"status\":\"delivered\",\"sequence\":1,\"subscriptionActive\":true}".utf8)
        let events = Data("{\"events\":[{\"sequence\":2,\"eventId\":\"\(eventID)\",\"type\":\"reply\",\"messageId\":\"\(id)\",\"text\":\"Actual reply fixture\",\"createdAt\":\"2026-10-11T00:00:00.123Z\"}],\"cursor\":2,\"subscriptionActive\":true}".utf8)
        let http = DotTestHTTP(responses: ["/v1/messages": receipt, "/v1/events": events])
        let transport = DotChatTransport(http: http, secrets: DotTestSecrets())
        try await transport.install(DotOAuthCredentials(clientID: "public", accessToken: "fixture-token", refreshToken: nil, expiresAt: .distantFuture), configuration: DotRelayConfiguration(endpoint: endpoint))
        let sentReceipt = try await transport.send(messageID: id, text: "Private input fixture")
        XCTAssertEqual(sentReceipt.status, .delivered)
        let batch = try await transport.events(after: 1)
        XCTAssertEqual(batch.events.first?.eventId, eventID)
        XCTAssertEqual(batch.events.first?.text, "Actual reply fixture")
        let requests = await http.requests
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertEqual(Set(payload.keys), ["messageId", "text"])
        XCTAssertEqual(payload["messageId"]?.lowercased(), id.uuidString.lowercased())
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        XCTAssertEqual(requests[1].url?.query, "after=1")
    }

    func testRefreshInvalidGrantRequiresReconnectAndDoesNotExposeServerBody() async throws {
        let metadata = Data("""
        {"issuer":"\(endpoint)","authorization_endpoint":"\(endpoint)/authorize","token_endpoint":"\(endpoint)/oauth/token","registration_endpoint":"\(endpoint)/oauth/register","revocation_endpoint":"\(endpoint)/oauth/revoke","code_challenge_methods_supported":["S256"],"authorization_response_iss_parameter_supported":true}
        """.utf8)
        let http = DotTestHTTP(responses: ["/.well-known/oauth-authorization-server": metadata],
            errors: ["/oauth/token": .httpFailure(statusCode: 400, errorCode: "invalid_grant")])
        let credentials = DotOAuthCredentials(clientID: "public", accessToken: "test-token", refreshToken: "refresh-fixture", expiresAt: Date())

        do {
            _ = try await DotOAuthProtocol.refresh(configuration: DotRelayConfiguration(endpoint: endpoint),
                credentials: credentials, refreshToken: "refresh-fixture", http: http)
            XCTFail("Invalid refresh grant must require a new authorization")
        } catch let error as DotChatError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertEqual(error.localizedDescription, "Sign in again to reconnect the private relay.")
        } catch {
            XCTFail("Unexpected refresh failure category")
        }
    }

    func testHTTPErrorParsingRetainsOnlyAllowlistedCodes() {
        let invalidGrant = Data("{\"error\":\"invalid_grant\",\"error_description\":\"private provider detail\"}".utf8)
        let arbitraryError = Data("{\"error\":\"secret-provider-diagnostic\",\"message\":\"private\"}".utf8)
        XCTAssertEqual(DotURLSessionClient.recognizedErrorCode(from: invalidGrant), "invalid_grant")
        XCTAssertNil(DotURLSessionClient.recognizedErrorCode(from: arbitraryError))
    }

    func testPermanentPollFailureStopsRetryingWithActionableSanitizedMessage() async throws {
        let value = try archive()
        let transport = DotTestTransport(eventError: .httpFailure(statusCode: 403, errorCode: "insufficient_scope"))
        let store = DotChatStore(storage: DotTestArchive(value), transport: transport, authorization: DotTestOAuth(), autoResume: false)
        await store.resumeSavedConnection()
        for _ in 0..<100 where store.connectionState != .unavailable { await Task.yield() }

        XCTAssertEqual(store.connectionState, .unavailable)
        XCTAssertFalse(store.subscriptionActive)
        XCTAssertEqual(store.errorMessage, "The private relay denied access. Reconnect Dot to refresh its permissions.")
        let attempts = await transport.eventAttempts
        XCTAssertEqual(attempts, 1)
    }

    func testNetworkRateLimitAndServerFailuresRemainRetryable() {
        XCTAssertTrue(DotChatError.unavailable.isRetryable)
        for status in [408, 425, 429, 500, 503, 599] {
            XCTAssertTrue(DotChatError.httpFailure(statusCode: status, errorCode: nil).isRetryable, "HTTP \(status)")
        }
        for status in [400, 401, 403, 404, 421] {
            XCTAssertFalse(DotChatError.httpFailure(statusCode: status, errorCode: nil).isRetryable, "HTTP \(status)")
        }
    }
}
