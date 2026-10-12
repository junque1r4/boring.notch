// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import Foundation

protocol DotHTTPClient: Sendable {
    func request(_ request: URLRequest, maximumBytes: Int) async throws -> Data
}

/// Ephemeral sessions retain neither cookies nor response bodies in a disk cache.
/// Redirects are rejected so bearer credentials cannot move to another origin.
final class DotURLSessionClient: NSObject, DotHTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    private static let safeHTTPErrorCodes: Set<String> = ["invalid_grant", "insufficient_scope", "temporarily_unavailable"]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Retains only a recognized error code; server descriptions are discarded.
    static func recognizedErrorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["error"] as? String,
              Self.safeHTTPErrorCodes.contains(code) else { return nil }
        return code
    }

    /// Reads only a small bounded error body and retains only a recognized code.
    /// Server messages and response content are never surfaced or logged.
    private func recognizedErrorCode(from bytes: URLSession.AsyncBytes) async -> String? {
        var data = Data()
        do {
            for try await byte in bytes {
                if data.count >= 8_192 { break }
                data.append(byte)
            }
        } catch {
            return nil
        }
        return Self.recognizedErrorCode(from: data)
    }

    func request(_ request: URLRequest, maximumBytes: Int) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw DotChatError.invalidResponse }
            if http.statusCode == 401 { throw DotChatError.unauthorized }
            guard (200...299).contains(http.statusCode) else {
                let errorCode = await recognizedErrorCode(from: bytes)
                throw DotChatError.httpFailure(statusCode: http.statusCode, errorCode: errorCode)
            }
            guard response.expectedContentLength <= maximumBytes else { throw DotChatError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumBytes else { throw DotChatError.responseTooLarge }
                data.append(byte)
            }
            return data
        } catch let error as DotChatError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw DotChatError.unavailable }
    }
}

protocol DotChatTransporting: Sendable {
    func configure(_ configuration: DotRelayConfiguration) async throws -> Bool
    func install(_ credentials: DotOAuthCredentials, configuration: DotRelayConfiguration) async throws
    func send(messageID: UUID, text: String) async throws -> DotRelayReceipt
    func events(after sequence: Int64) async throws -> DotRelayEventBatch
    func disconnect() async
}

actor DotChatTransport: DotChatTransporting {
    private let http: any DotHTTPClient
    private let secrets: any DotSecretStorage
    private var configuration: DotRelayConfiguration?
    private var credentials: DotOAuthCredentials?
    private var refreshTask: Task<DotOAuthCredentials, Error>?
    private var generation = 0

    init(http: any DotHTTPClient = DotURLSessionClient(), secrets: any DotSecretStorage = DotKeychainStorage()) {
        self.http = http
        self.secrets = secrets
    }
    func configure(_ configuration: DotRelayConfiguration) throws -> Bool {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        self.configuration = configuration
        credentials = nil
        credentials = try secrets.read(configuration.credentialAccount).map { try JSONDecoder().decode(DotOAuthCredentials.self, from: $0) }
        return credentials != nil
    }
    func install(_ credentials: DotOAuthCredentials, configuration: DotRelayConfiguration) throws {
        try secrets.write(JSONEncoder().encode(credentials), account: configuration.credentialAccount)
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        self.configuration = configuration
        self.credentials = credentials
    }
    private func accessToken() async throws -> String {
        guard let configuration, let credentials else { throw DotChatError.unauthorized }
        let current = generation
        if credentials.expiresAt.timeIntervalSinceNow > 60 { return credentials.accessToken }
        if let refreshTask {
            let value = try await refreshTask.value
            guard generation == current, self.configuration == configuration else { throw CancellationError() }
            return value.accessToken
        }
        guard let refresh = credentials.refreshToken else { throw DotChatError.unauthorized }
        let client = http
        let task = Task {
            try await DotOAuthProtocol.refresh(configuration: configuration, credentials: credentials, refreshToken: refresh, http: client)
        }
        refreshTask = task
        defer { if generation == current { refreshTask = nil } }
        let value = try await task.value
        guard generation == current, self.configuration == configuration else { throw CancellationError() }
        try secrets.write(JSONEncoder().encode(value), account: configuration.credentialAccount)
        self.credentials = value
        return value.accessToken
    }
    private func authorizedRequest(path: String, method: String = "GET") async throws -> URLRequest {
        guard let configuration else { throw DotChatError.unauthorized }
        let current = generation
        var request = URLRequest(url: configuration.origin.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        guard generation == current, self.configuration == configuration else { throw CancellationError() }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    func send(messageID: UUID, text: String) async throws -> DotRelayReceipt {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= DotChatLimits.draftBytes
        else { throw DotChatError.draftTooLarge }
        var request = try await authorizedRequest(path: "v1/messages", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Payload: Encodable { let messageId: UUID; let text: String }
        request.httpBody = try JSONEncoder().encode(Payload(messageId: messageID, text: text))
        let data = try await http.request(request, maximumBytes: 65_536)
        let receipt = try JSONDecoder().decode(DotRelayReceipt.self, from: data)
        guard receipt.messageId == messageID, receipt.sequence >= 0, receipt.status != .uncertain else { throw DotChatError.invalidResponse }
        return receipt
    }
    func events(after sequence: Int64) async throws -> DotRelayEventBatch {
        guard sequence >= 0 else { throw DotChatError.invalidResponse }
        var request = try await authorizedRequest(path: "v1/events")
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw DotChatError.invalidEndpoint }
        parts.queryItems = [URLQueryItem(name: "after", value: String(sequence))]
        request.url = parts.url
        let data = try await http.request(request, maximumBytes: DotChatLimits.networkBytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DotChatError.invalidResponse
        }
        let batch = try decoder.decode(DotRelayEventBatch.self, from: data)
        guard batch.cursor >= sequence, batch.events.count <= 100 else { throw DotChatError.invalidResponse }
        var previous = sequence
        var identifiers = Set<UUID>()
        for event in batch.events {
            guard event.sequence > previous, event.sequence <= batch.cursor, identifiers.insert(event.eventId).inserted,
                  event.status != .uncertain else { throw DotChatError.invalidResponse }
            if event.type == .reply {
                guard let text = event.text, !text.isEmpty, text.utf8.count <= DotChatLimits.replyBytes else { throw DotChatError.invalidResponse }
            } else if event.status == nil { throw DotChatError.invalidResponse }
            previous = event.sequence
        }
        return batch
    }
    func disconnect() async {
        let oldConfiguration = configuration
        let oldCredentials = credentials
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        credentials = nil
        configuration = nil
        if let configuration = oldConfiguration {
            try? secrets.remove(configuration.credentialAccount)
            if let credentials = oldCredentials {
                // Best effort revocation; local credentials are always removed.
                try? await DotOAuthProtocol.revoke(configuration: configuration, credentials: credentials, http: http)
            }
        }
    }
}
