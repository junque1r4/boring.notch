// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Security

protocol DotSecretStorage: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(_ account: String) throws
}

/// Tokens and the local AES key never enter UserDefaults or the transcript.
final class DotKeychainStorage: DotSecretStorage, @unchecked Sendable {
    private let service: String
    init(service: String = "com.junque1r4.boringnotch.agents.dot") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read(_ account: String) throws -> Data? {
        // Tests inject in-memory secret storage. Fail before Security.framework
        // if a hosted test accidentally reaches the production implementation.
        guard BoringAppExecution.usesLiveDotStorage else { throw DotChatError.persistenceUnavailable }
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DotChatError.persistenceUnavailable }
        return data
    }
    func write(_ data: Data, account: String) throws {
        guard BoringAppExecution.usesLiveDotStorage else { throw DotChatError.persistenceUnavailable }
        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
            else { throw DotChatError.persistenceUnavailable }
        } else if status != errSecSuccess { throw DotChatError.persistenceUnavailable }
    }
    func remove(_ account: String) throws {
        guard BoringAppExecution.usesLiveDotStorage else { throw DotChatError.persistenceUnavailable }
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DotChatError.persistenceUnavailable }
    }
}

protocol DotArchiveStorage: Sendable {
    func load() throws -> DotChatArchive?
    func save(_ archive: DotChatArchive) throws
    func clear() throws
}

final class DotEncryptedArchiveStorage: DotArchiveStorage, @unchecked Sendable {
    private let url: URL
    private let secrets: any DotSecretStorage
    private let account = "local-history-aes256-v1"
    init(url: URL, secrets: any DotSecretStorage = DotKeychainStorage()) {
        self.url = url
        self.secrets = secrets
    }
    static func standard() -> DotEncryptedArchiveStorage {
        guard BoringAppExecution.usesLiveDotStorage else {
            // No production archive is read by unit tests or the offline input
            // diagnostic. Keychain access is also rejected above.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Notch-Isolated-\(ProcessInfo.processInfo.processIdentifier)")
            return DotEncryptedArchiveStorage(url: directory.appendingPathComponent("history.aesgcm"))
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoringNotchAgents/Dot", isDirectory: true)
        return DotEncryptedArchiveStorage(url: directory.appendingPathComponent("history.aesgcm"))
    }
    private func key(create: Bool) throws -> SymmetricKey {
        if let data = try secrets.read(account) {
            guard data.count == 32 else { throw DotChatError.missingEncryptionKey }
            return SymmetricKey(data: data)
        }
        guard create else { throw DotChatError.missingEncryptionKey }
        let value = SymmetricKey(size: .bits256)
        try secrets.write(value.withUnsafeBytes { Data($0) }, account: account)
        return value
    }
    func load() throws -> DotChatArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= DotChatLimits.combinedArchiveBytes + 128 else { throw DotChatError.persistenceUnavailable }
        let data = try Data(contentsOf: url)
        let sealed = try AES.GCM.SealedBox(combined: data)
        let cleartext = try AES.GCM.open(sealed, using: key(create: false))
        guard cleartext.count <= DotChatLimits.combinedArchiveBytes else { throw DotChatError.persistenceUnavailable }
        let archive = try JSONDecoder().decode(DotChatArchive.self, from: cleartext)
        guard archive.version == 1 else { throw DotChatError.persistenceUnavailable }
        return archive
    }
    func save(_ archive: DotChatArchive) throws {
        let data = try JSONEncoder().encode(archive)
        guard data.count <= DotChatLimits.combinedArchiveBytes else { throw DotChatError.persistenceUnavailable }
        let encrypted = try AES.GCM.seal(data, using: key(create: true))
        guard let combined = encrypted.combined else { throw DotChatError.persistenceUnavailable }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try combined.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

struct DotOAuthCredentials: Codable, Equatable, Sendable {
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

extension DotRelayConfiguration {
    var credentialAccount: String {
        "relay-oauth-" + SHA256.hash(data: Data(origin.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
