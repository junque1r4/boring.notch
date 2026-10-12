// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DotChatLimits {
    static let draftBytes = 8_192
    static let replyBytes = 65_536
    static let messageCount = 100
    static let archiveBytes = 1_048_576
    static let networkBytes = 8_388_608

    static func prefix(_ text: String, bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var size = 0
        return String(text.prefix { character in
            let count = String(character).utf8.count
            guard size + count <= limit else { return false }
            size += count
            return true
        })
    }
}

enum DotMessageRole: String, Codable, Sendable { case user, assistant }

/// Relay receipt and delivery do not claim that Dot has processed a message.
enum DotMessageDelivery: String, Codable, Sendable {
    case queued, delivered, failed, replied, uncertain
    var label: String {
        switch self {
        case .queued: return "Queued at relay"
        case .delivered: return "Delivered to ChatGPT · awaiting Dot"
        case .failed: return "Delivery failed"
        case .replied: return "Dot replied"
        case .uncertain: return "Receipt unconfirmed · checking relay"
        }
    }
}

struct DotChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: DotMessageRole
    let text: String
    let createdAt: Date
    var delivery: DotMessageDelivery?
    var inReplyTo: UUID?
}

enum DotConnectionState: Equatable, Sendable {
    case unconfigured, signedOut, connecting, connected, reconnecting, unavailable
    var label: String {
        switch self {
        case .unconfigured: return "Set up private relay"
        case .signedOut: return "Connect ChatGPT Dot"
        case .connecting: return "Connecting"
        case .connected: return "Relay connected"
        case .reconnecting: return "Reconnecting"
        case .unavailable: return "Connection unavailable"
        }
    }
}

enum DotChatError: Error, Equatable, LocalizedError {
    case invalidEndpoint, invalidResponse, responseTooLarge, unauthorized, unavailable
    case httpFailure(statusCode: Int, errorCode: String?)
    case invalidAuthorization, authorizationCancelled, missingEncryptionKey, persistenceUnavailable
    case pendingMessage, endpointHasHistory, draftTooLarge

    /// Only network failures and server-directed throttling/transient statuses
    /// should keep the poller retrying. Other HTTP failures need user action.
    var isRetryable: Bool {
        switch self {
        case .unavailable:
            return true
        case .httpFailure(let statusCode, _):
            return statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter a public HTTPS relay origin, without a path, credentials or query."
        case .invalidResponse: return "The relay returned an unsupported response."
        case .responseTooLarge: return "The relay response exceeded the local safety limit."
        case .unauthorized: return "Sign in again to reconnect the private relay."
        case .unavailable: return "The private relay could not be reached."
        case .httpFailure(let statusCode, let errorCode):
            if errorCode == "insufficient_scope" || statusCode == 403 {
                return "The private relay denied access. Reconnect Dot to refresh its permissions."
            }
            if statusCode == 404 || statusCode == 421 {
                return "The private relay endpoint could not be found. Check the relay address."
            }
            if isRetryable {
                return "The private relay is temporarily unavailable (HTTP \(statusCode)). Retrying."
            }
            return "The private relay returned an error (HTTP \(statusCode)). Check the connection and reconnect."
        case .invalidAuthorization: return "The private relay’s authorization response could not be verified."
        case .authorizationCancelled: return "Connection was cancelled."
        case .missingEncryptionKey: return "The encrypted history key is unavailable. Local history was kept intact."
        case .persistenceUnavailable: return "Encrypted local history could not be saved."
        case .pendingMessage: return "Wait for the current message’s reply or delivery result."
        case .endpointHasHistory: return "Clear local history before changing the private relay."
        case .draftTooLarge: return "Messages must be at most 8 KiB."
        }
    }
}

struct DotRelayConfiguration: Codable, Equatable, Sendable {
    let origin: URL
    // One audience covers both the native /v1 API and private /mcp endpoint.
    var resource: URL { origin }

    init(endpoint: String) throws {
        guard let parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let hostname = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", parts.port == nil || parts.port == 443,
              hostname.count <= 253, hostname.contains("."),
              hostname.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }),
              hostname.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
              !hostname.split(separator: ".").allSatisfy({ Int($0) != nil }),
              !["localhost", "local", "internal", "lan", "home", "onion", "invalid", "test"].contains(String(hostname.split(separator: ".").last ?? "")),
              let origin = URL(string: "https://\(hostname)") else { throw DotChatError.invalidEndpoint }
        self.origin = origin
    }

    func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == origin.host
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil && url.fragment == nil
    }
}

struct DotRelayReceipt: Codable, Equatable, Sendable {
    let messageId: UUID
    let status: DotMessageDelivery
    let sequence: Int64
    let subscriptionActive: Bool
}

struct DotRelayEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case delivery, reply }
    let sequence: Int64
    let eventId: UUID
    let type: Kind
    let messageId: UUID
    let status: DotMessageDelivery?
    let text: String?
    let createdAt: Date
}

struct DotRelayEventBatch: Codable, Equatable, Sendable {
    let events: [DotRelayEvent]
    let cursor: Int64
    let subscriptionActive: Bool
}

struct DotChatArchive: Codable, Equatable, Sendable {
    var version = 1
    var configuration: DotRelayConfiguration?
    var messages: [DotChatMessage] = []
    var draft = ""
    var lastSequence: Int64 = 0
    var pendingMessageID: UUID?
    var seenEvents: [UUID] = []
    var unreadCount = 0
}
