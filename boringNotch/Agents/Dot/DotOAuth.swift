// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

struct DotPKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String
    init() {
        let entropy = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        verifier = Self.base64URL(entropy)
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        state = Self.base64URL(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct DotOAuthMetadata: Decodable, Sendable {
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL
    let revocationEndpoint: URL
    let codeChallengeMethodsSupported: [String]
    let authorizationResponseIssParameterSupported: Bool
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint", tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint", revocationEndpoint = "revocation_endpoint"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case authorizationResponseIssParameterSupported = "authorization_response_iss_parameter_supported"
    }
}

enum DotOAuthProtocol {
    static let callback = URL(string: "boringnotch-agents://oauth/callback")!
    static let scope = "notch:send notch:read offline_access"
    static func metadata(configuration: DotRelayConfiguration, http: any DotHTTPClient) async throws -> DotOAuthMetadata {
        let request = URLRequest(url: configuration.origin.appendingPathComponent(".well-known/oauth-authorization-server"))
        let data = try await http.request(request, maximumBytes: 65_536)
        let value = try JSONDecoder().decode(DotOAuthMetadata.self, from: data)
        guard configuration.accepts(value.issuer), value.issuer.path.isEmpty || value.issuer.path == "/",
              value.issuer.query == nil, value.authorizationResponseIssParameterSupported,
              [value.authorizationEndpoint, value.tokenEndpoint, value.registrationEndpoint, value.revocationEndpoint].allSatisfy(configuration.accepts),
              value.codeChallengeMethodsSupported.contains("S256") else { throw DotChatError.invalidAuthorization }
        return value
    }
    static func register(metadata: DotOAuthMetadata, http: any DotHTTPClient) async throws -> String {
        var request = URLRequest(url: metadata.registrationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Boring Notch Agents", "redirect_uris": [callback.absoluteString],
            "token_endpoint_auth_method": "none", "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"], "scope": scope
        ])
        struct Client: Decodable { let client_id: String }
        let data = try await http.request(request, maximumBytes: 65_536)
        let client = try JSONDecoder().decode(Client.self, from: data)
        guard !client.client_id.isEmpty, client.client_id.utf8.count <= 512 else { throw DotChatError.invalidAuthorization }
        return client.client_id
    }
    static func authorizationURL(configuration: DotRelayConfiguration, metadata: DotOAuthMetadata,
        clientID: String, proof: DotPKCE) throws -> URL {
        guard var parts = URLComponents(url: metadata.authorizationEndpoint, resolvingAgainstBaseURL: false), parts.query == nil else { throw DotChatError.invalidAuthorization }
        parts.queryItems = [
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callback.absoluteString), URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "resource", value: configuration.resource.absoluteString), URLQueryItem(name: "state", value: proof.state),
            URLQueryItem(name: "code_challenge", value: proof.challenge), URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = parts.url else { throw DotChatError.invalidAuthorization }
        return url
    }
    static func authorizationCode(callback url: URL, expectedState: String, expectedIssuer: URL) throws -> String {
        guard url.scheme == callback.scheme, url.host == callback.host, url.path == callback.path,
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = parts.queryItems,
              items.filter({ $0.name == "state" }).count == 1, items.filter({ $0.name == "code" }).count == 1,
              items.filter({ $0.name == "iss" }).count == 1,
              items.first(where: { $0.name == "iss" })?.value == expectedIssuer.absoluteString,
              !items.contains(where: { $0.name == "error" }),
              items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.utf8.count <= 8_192
        else { throw DotChatError.invalidAuthorization }
        return code
    }
    static func form(_ values: [String: String]) -> Data {
        var parts = URLComponents()
        parts.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        // URL query escaping leaves '+' literal; form decoding treats it as a space.
        return Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    static func token(configuration: DotRelayConfiguration, endpoint: URL, values: [String: String],
        clientID: String, previousRefreshToken: String? = nil, http: any DotHTTPClient) async throws -> DotOAuthCredentials {
        guard configuration.accepts(endpoint) else { throw DotChatError.invalidAuthorization }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(values.merging(["client_id": clientID, "resource": configuration.resource.absoluteString]) { _, new in new })
        struct Response: Decodable {
            let access_token: String
            let token_type: String
            let expires_in: Double
            let refresh_token: String?
        }
        let data = try await http.request(request, maximumBytes: 65_536)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.token_type.lowercased() == "bearer", !response.access_token.isEmpty,
              response.access_token.utf8.count <= 16_384, response.expires_in.isFinite, response.expires_in > 0,
              response.expires_in <= 2_592_000, (response.refresh_token?.utf8.count ?? 0) <= 16_384
        else { throw DotChatError.invalidAuthorization }
        return DotOAuthCredentials(clientID: clientID, accessToken: response.access_token,
            refreshToken: response.refresh_token ?? previousRefreshToken, expiresAt: Date().addingTimeInterval(response.expires_in))
    }
    static func refresh(configuration: DotRelayConfiguration, credentials: DotOAuthCredentials,
        refreshToken: String, http: any DotHTTPClient) async throws -> DotOAuthCredentials {
        let metadata = try await metadata(configuration: configuration, http: http)
        return try await token(configuration: configuration, endpoint: metadata.tokenEndpoint,
            values: ["grant_type": "refresh_token", "refresh_token": refreshToken], clientID: credentials.clientID,
            previousRefreshToken: refreshToken, http: http)
    }
    static func revoke(configuration: DotRelayConfiguration, credentials: DotOAuthCredentials, http: any DotHTTPClient) async throws {
        let metadata = try await metadata(configuration: configuration, http: http)
        var request = URLRequest(url: metadata.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["client_id": credentials.clientID, "token": credentials.refreshToken ?? credentials.accessToken,
            "token_type_hint": credentials.refreshToken == nil ? "access_token" : "refresh_token"])
        _ = try await http.request(request, maximumBytes: 65_536)
    }
}

@MainActor protocol DotOAuthAuthorizing {
    func authorize(configuration: DotRelayConfiguration, presentationAnchor: NSWindow) async throws -> DotOAuthCredentials
}

@MainActor final class DotNativeOAuth: NSObject, DotOAuthAuthorizing, ASWebAuthenticationPresentationContextProviding {
    private let http: any DotHTTPClient
    private var session: ASWebAuthenticationSession?
    private weak var anchor: NSWindow?
    private var continuation: CheckedContinuation<URL, Error>?
    init(http: any DotHTTPClient = DotURLSessionClient()) { self.http = http }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? NSWindow() }
    func authorize(configuration: DotRelayConfiguration, presentationAnchor: NSWindow) async throws -> DotOAuthCredentials {
        guard session == nil else { throw DotChatError.invalidAuthorization }
        let metadata = try await DotOAuthProtocol.metadata(configuration: configuration, http: http)
        let clientID = try await DotOAuthProtocol.register(metadata: metadata, http: http)
        let proof = DotPKCE()
        let authorizationURL = try DotOAuthProtocol.authorizationURL(configuration: configuration, metadata: metadata, clientID: clientID, proof: proof)
        anchor = presentationAnchor
        let callback = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: DotOAuthProtocol.callback.scheme) { [weak self] url, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let url { self.finish(.success(url)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { self.finish(.failure(DotChatError.authorizationCancelled)) }
                        else { self.finish(.failure(DotChatError.invalidAuthorization)) }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() { finish(.failure(DotChatError.invalidAuthorization)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.session?.cancel()
                self?.finish(.failure(CancellationError()))
            }
        }
        let code = try DotOAuthProtocol.authorizationCode(callback: callback, expectedState: proof.state, expectedIssuer: metadata.issuer)
        return try await DotOAuthProtocol.token(configuration: configuration, endpoint: metadata.tokenEndpoint,
            values: ["grant_type": "authorization_code", "code": code, "redirect_uri": DotOAuthProtocol.callback.absoluteString,
                "code_verifier": proof.verifier], clientID: clientID, http: http)
    }
    private func finish(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        anchor = nil
        pending?.resume(with: result)
    }
}
