// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor final class AgentMetadataClient {
    static let shared = AgentMetadataClient()
    private var connection: NSXPCConnection?
    private func connect() -> NSXPCConnection {
        if let connection { return connection }
        let client = NSXPCConnection(serviceName: "com.junque1r4.boringnotch.agents.BoringNotchXPCHelper")
        client.remoteObjectInterface = NSXPCInterface(with: BoringNotchXPCHelperProtocol.self)
        client.invalidationHandler = { [weak self, weak client] in
            Task { @MainActor in if self?.connection === client { self?.connection = nil } }
        }
        client.interruptionHandler = { [weak self, weak client] in
            Task { @MainActor in if self?.connection === client { self?.connection = nil; client?.invalidate() } }
        }
        client.resume()
        connection = client
        return client
    }
    func snapshot(providerID: String) async -> AgentSnapshot {
        let unavailable = AgentSnapshot(sessions: [], diagnostic: "Automatic \(providerID) reader unavailable; retrying locally.")
        guard ["codex", "grok-bot"].contains(providerID) else { return unavailable }
        let client = connect()
        return await withCheckedContinuation { continuation in
            let reply = AgentMetadataReply(continuation: continuation)
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                reply.complete(unavailable)
            }
            reply.installTimeout(timeout)
            guard let proxy = client.remoteObjectProxyWithErrorHandler({ _ in reply.complete(unavailable) }) as? BoringNotchXPCHelperProtocol else {
                reply.complete(unavailable); return
            }
            proxy.readAgentSnapshot(providerID: providerID) { data in
                guard let data, data.count <= 262_144,
                      let value = try? JSONDecoder().decode(AgentSnapshot.self, from: data) else { reply.complete(unavailable); return }
                reply.complete(value)
            }
        }
    }
}

/// XPC failure, timeout and reply race; exactly one completes the continuation.
private final class AgentMetadataReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AgentSnapshot, Never>?
    private var timeout: Task<Void, Never>?
    init(continuation: CheckedContinuation<AgentSnapshot, Never>) { self.continuation = continuation }
    func installTimeout(_ task: Task<Void, Never>) {
        lock.lock()
        if continuation == nil { lock.unlock(); task.cancel(); return }
        timeout = task
        lock.unlock()
    }
    func complete(_ snapshot: AgentSnapshot) {
        lock.lock()
        let current = continuation, timer = timeout
        continuation = nil; timeout = nil
        lock.unlock()
        timer?.cancel()
        current?.resume(returning: snapshot)
    }
}

actor AutomaticAgentProvider: AgentSessionProvider {
    nonisolated let id: String
    private let providerID: String
    init(providerID: String) { self.providerID = providerID; id = "automatic-\(providerID)" }
    func snapshot(at date: Date) async -> AgentSnapshot {
        await AgentMetadataClient.shared.snapshot(providerID: providerID)
    }
}
