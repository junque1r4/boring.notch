// Modified 2026-10-11. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Observation

@MainActor @Observable
final class DotChatStore {
    static let shared = DotChatStore()
    private(set) var messages: [DotChatMessage] = []
    private(set) var connectionState: DotConnectionState = .unconfigured
    private(set) var subscriptionActive = false
    private(set) var pendingMessageID: UUID?
    private(set) var unreadCount = 0
    private(set) var errorMessage: String?
    private(set) var configuration: DotRelayConfiguration?
    var draft = "" {
        didSet {
            let clipped = DotChatLimits.prefix(draft, bytes: DotChatLimits.draftBytes)
            if clipped != draft { draft = clipped }
            if !restoring { schedulePersistence() }
        }
    }
    var canSend: Bool {
        connectionState == .connected && subscriptionActive && configuration != nil && pendingMessageID == nil && !persistenceBlocked
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canRetryPending: Bool {
        connectionState == .connected && subscriptionActive && !persistenceBlocked
            && messages.contains { $0.id == pendingMessageID && $0.delivery == .uncertain }
    }

    @ObservationIgnored private let storage: any DotArchiveStorage
    @ObservationIgnored private let transport: any DotChatTransporting
    @ObservationIgnored private let authorization: any DotOAuthAuthorizing
    @ObservationIgnored private var lastSequence: Int64 = 0
    @ObservationIgnored private var seenEvents: [UUID] = []
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var atLatest = false
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var persistenceBlocked = false
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(storage: any DotArchiveStorage = DotEncryptedArchiveStorage.standard(),
        transport: any DotChatTransporting = DotChatTransport(), authorization: (any DotOAuthAuthorizing)? = nil,
        autoResume: Bool = true) {
        self.storage = storage
        self.transport = transport
        self.authorization = authorization ?? DotNativeOAuth()
        restoring = true
        do {
            if let archive = try storage.load() {
                guard archive.messages.count <= DotChatLimits.messageCount, archive.draft.utf8.count <= DotChatLimits.draftBytes,
                      archive.lastSequence >= 0, archive.seenEvents.count <= 256,
                      archive.messages.allSatisfy({ $0.text.utf8.count <= ($0.role == .user ? DotChatLimits.draftBytes : DotChatLimits.replyBytes) }),
                      Set(archive.messages.map(\.id)).count == archive.messages.count else { throw DotChatError.persistenceUnavailable }
                configuration = archive.configuration
                if let configuration { _ = try DotRelayConfiguration(endpoint: configuration.origin.absoluteString) }
                messages = archive.messages
                draft = archive.draft
                lastSequence = archive.lastSequence
                pendingMessageID = archive.pendingMessageID
                seenEvents = archive.seenEvents
                unreadCount = max(0, min(archive.unreadCount, DotChatLimits.messageCount))
                if let pendingMessageID, !messages.contains(where: { $0.id == pendingMessageID && $0.role == .user }) {
                    throw DotChatError.persistenceUnavailable
                }
                connectionState = configuration == nil ? .unconfigured : .signedOut
            }
        } catch {
            persistenceBlocked = true
            errorMessage = "Encrypted local history is unavailable. It has been kept intact; reconnecting will not overwrite it."
        }
        restoring = false
        if autoResume, configuration != nil, !persistenceBlocked {
            Task { [weak self] in await self?.resumeSavedConnection() }
        }
    }

    func configureEndpoint(_ endpoint: String) throws {
        guard !persistenceBlocked else { throw DotChatError.persistenceUnavailable }
        let value = try DotRelayConfiguration(endpoint: endpoint)
        if let configuration, configuration != value, !messages.isEmpty || pendingMessageID != nil { throw DotChatError.endpointHasHistory }
        guard configuration != value else { return }
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        configuration = value
        connectionState = .signedOut
        subscriptionActive = false
        lastSequence = 0
        seenEvents = []
        errorMessage = nil
        try flush()
    }

    func connect(presentationAnchor: NSWindow) async {
        guard let configuration, !persistenceBlocked, connectionState != .connecting else { return }
        generation += 1
        let current = generation
        pollTask?.cancel()
        pollTask = nil
        connectionState = .connecting
        errorMessage = nil
        do {
            let credentials = try await authorization.authorize(configuration: configuration, presentationAnchor: presentationAnchor)
            guard generation == current, self.configuration == configuration else { return }
            try await transport.install(credentials, configuration: configuration)
            guard generation == current else { return }
            connectionState = .connected
            startPolling()
        } catch {
            guard generation == current else { return }
            connectionState = .signedOut
            errorMessage = safeDescription(error)
        }
    }

    func resumeSavedConnection() async {
        guard let configuration, !persistenceBlocked else { return }
        let current = generation
        do {
            let available = try await transport.configure(configuration)
            guard generation == current else { return }
            connectionState = available ? .reconnecting : .signedOut
            if available { startPolling() }
        } catch {
            guard generation == current else { return }
            connectionState = .signedOut
            errorMessage = safeDescription(error)
        }
    }

    func sendDraft() async {
        guard canSend else { return }
        let text = draft
        guard text.utf8.count <= DotChatLimits.draftBytes else { errorMessage = DotChatError.draftTooLarge.localizedDescription; return }
        let id = UUID()
        let current = generation
        messages.append(DotChatMessage(id: id, role: .user, text: text, createdAt: Date(), delivery: .uncertain))
        pendingMessageID = id
        draft = ""
        errorMessage = nil
        // Persist the stable ID before the first network write. If this fails,
        // restore the draft and do not send anything to the relay.
        do { try flush() }
        catch {
            messages.removeAll { $0.id == id }
            pendingMessageID = nil
            draft = text
            errorMessage = DotChatError.persistenceUnavailable.localizedDescription
            return
        }
        do {
            let receipt = try await transport.send(messageID: id, text: text)
            guard generation == current else { return }
            apply(receipt: receipt)
            try flush()
        } catch {
            guard generation == current else { return }
            // A timeout may occur after the relay accepted the UUID. Reconcile
            // through events; never create another ID or automatically POST again.
            errorMessage = "Receipt unconfirmed. The app will check the relay without sending this message again."
            if error as? DotChatError == .unauthorized { connectionState = .signedOut }
            else if error as? DotChatError == .rejected || error as? DotChatError == .draftTooLarge {
                updateDelivery(id: id, value: .failed)
                pendingMessageID = nil
                errorMessage = safeDescription(error)
            }
            try? flush()
        }
    }

    func apply(receipt: DotRelayReceipt) {
        guard receipt.messageId == pendingMessageID else { return }
        subscriptionActive = receipt.subscriptionActive
        updateDelivery(id: receipt.messageId, value: receipt.status)
        if receipt.status == .failed { pendingMessageID = nil }
        // 'replied' receipt is not itself the reply text; keep waiting for its event.
    }

    /// Explicit retry preserves the original UUID; relay idempotency reconciles
    /// an uncertain receipt. It never constructs a second user message.
    func retryPending() async {
        guard canRetryPending, let id = pendingMessageID, let message = messages.first(where: { $0.id == id }) else { return }
        let current = generation
        do {
            let receipt = try await transport.send(messageID: id, text: message.text)
            guard generation == current else { return }
            apply(receipt: receipt)
            errorMessage = nil
            try flush()
        } catch {
            guard generation == current else { return }
            errorMessage = "Receipt remains unconfirmed. The original message ID was kept."
            try? flush()
        }
    }

    /// Stops blocking the composer locally. This cannot cancel a ChatGPT turn;
    /// a later correlated reply is still accepted while its user entry is kept.
    func abandonPending() throws {
        pendingMessageID = nil
        errorMessage = nil
        try flush()
    }

    func apply(batch: DotRelayEventBatch) throws {
        guard batch.cursor >= lastSequence, batch.events.count <= 100 else { throw DotChatError.invalidResponse }
        var previous = lastSequence
        for event in batch.events {
            guard event.sequence > previous, event.sequence <= batch.cursor, event.status != .uncertain else { throw DotChatError.invalidResponse }
            previous = event.sequence
            if event.type == .reply {
                guard let text = event.text, !text.isEmpty, text.utf8.count <= DotChatLimits.replyBytes else { throw DotChatError.invalidResponse }
            } else if event.status == nil { throw DotChatError.invalidResponse }
        }
        for event in batch.events {
            guard !seenEvents.contains(event.eventId) else { continue }
            if event.type == .reply {
                guard let text = event.text, !text.isEmpty, text.utf8.count <= DotChatLimits.replyBytes else { throw DotChatError.invalidResponse }
                // Only this native channel's messages can enter its transcript.
                if messages.contains(where: { $0.id == event.messageId && $0.role == .user }) {
                    if !messages.contains(where: { $0.id == event.eventId }) {
                        messages.append(DotChatMessage(id: event.eventId, role: .assistant, text: text,
                            createdAt: event.createdAt, inReplyTo: event.messageId))
                        if !visible || !atLatest { unreadCount += 1 }
                    }
                    updateDelivery(id: event.messageId, value: .replied)
                    if pendingMessageID == event.messageId { pendingMessageID = nil }
                }
            } else {
                guard let status = event.status else { throw DotChatError.invalidResponse }
                updateDelivery(id: event.messageId, value: status)
                if status == .failed && pendingMessageID == event.messageId { pendingMessageID = nil }
            }
            seenEvents.append(event.eventId)
        }
        seenEvents = Array(seenEvents.suffix(256))
        lastSequence = batch.cursor
        subscriptionActive = batch.subscriptionActive
        try flush()
    }

    func setPresentation(visible: Bool, atLatest: Bool) {
        self.visible = visible
        self.atLatest = atLatest
        if visible && atLatest && unreadCount != 0 { unreadCount = 0; schedulePersistence() }
    }

    func clearLocalHistory() throws {
        persistenceTask?.cancel()
        persistenceTask = nil
        try storage.clear()
        persistenceBlocked = false
        messages = []
        pendingMessageID = nil
        draft = ""
        unreadCount = 0
        seenEvents = []
        errorMessage = nil
        // Preserve the sequence so clearing local history does not replay old
        // replies. Clearing does not delete ChatGPT's copy or cancel a Dot turn.
        try flush()
    }

    func disconnect() async {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        subscriptionActive = false
        connectionState = configuration == nil ? .unconfigured : .signedOut
        await transport.disconnect()
    }

    func flush() throws {
        persistenceTask?.cancel()
        persistenceTask = nil
        guard !persistenceBlocked else { throw DotChatError.persistenceUnavailable }
        trimHistory()
        do { try storage.save(archive()) }
        catch { throw DotChatError.persistenceUnavailable }
    }

    private func updateDelivery(id: UUID, value: DotMessageDelivery) {
        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else { return }
        // Late queued/delivered events cannot downgrade a completed reply.
        if messages[index].delivery == .replied { return }
        messages[index].delivery = value
    }
    private func archive() -> DotChatArchive {
        DotChatArchive(configuration: configuration, messages: messages, draft: draft, lastSequence: lastSequence,
            pendingMessageID: pendingMessageID, seenEvents: seenEvents, unreadCount: unreadCount)
    }
    private func trimHistory() {
        while messages.count > DotChatLimits.messageCount || ((try? JSONEncoder().encode(archive()).count) ?? Int.max) > DotChatLimits.archiveBytes {
            guard let index = messages.firstIndex(where: { $0.id != pendingMessageID }) else { break }
            messages.remove(at: index)
        }
        unreadCount = min(unreadCount, messages.filter { $0.role == .assistant }.count)
    }
    private func schedulePersistence() {
        persistenceTask?.cancel()
        guard !persistenceBlocked else { return }
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do { try self?.flush() }
            catch { self?.errorMessage = DotChatError.persistenceUnavailable.localizedDescription }
        }
    }
    private func startPolling() {
        pollTask?.cancel()
        let current = generation
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                do {
                    let batch = try await self.transport.events(after: self.lastSequence)
                    guard !Task.isCancelled, self.generation == current else { return }
                    try self.apply(batch: batch)
                    self.connectionState = .connected
                    failures = 0
                    self.errorMessage = nil
                } catch {
                    guard !Task.isCancelled, self.generation == current else { return }
                    if error as? DotChatError == .unauthorized {
                        self.connectionState = .signedOut
                        self.subscriptionActive = false
                        self.errorMessage = self.safeDescription(error)
                        return
                    }
                    failures = min(failures + 1, 5)
                    self.connectionState = .reconnecting
                    self.errorMessage = "Checking the private relay again. Pending messages will not be sent twice."
                }
                let delay = failures == 0 ? (self.visible ? 2 : 8) : min(30, 1 << failures)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
    private func safeDescription(_ error: Error) -> String {
        (error as? DotChatError)?.localizedDescription ?? DotChatError.unavailable.localizedDescription
    }
}
