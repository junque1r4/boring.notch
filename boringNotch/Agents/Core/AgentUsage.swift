// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation

/// An observed quota, never a guessed limit or a ChatGPT chat-message allowance.
struct AgentUsageWindow: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let providerID: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Date
    let expiresAt: Date?
    let source: String

    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(observedAt) > 600 || expiresAt.map { $0 <= now } == true
    }
    func remainingPercent(at now: Date) -> Double? {
        // Crossing a reset does not prove that the new window is unused.
        guard resetsAt.map({ $0 > now }) ?? true else { return nil }
        return max(0, 100 - min(100, usedPercent))
    }
    static func headline(for providerID: String, in windows: [AgentUsageWindow]) -> AgentUsageWindow? {
        // Weekly quota can arrive as primary or secondary. Never substitute
        // five-hour quota for the ChatGPT weekly headline if weekly is absent.
        windows.first { $0.providerID == providerID && $0.label == "Weekly" }
    }
    static func validPercent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
    static func merge(_ windows: [AgentUsageWindow]) -> [AgentUsageWindow] {
        let newestReadings = Dictionary(grouping: windows, by: \.providerID).mapValues { $0.map(\.observedAt).max()! }
        var latest: [String: AgentUsageWindow] = [:]
        for window in windows where window.observedAt == newestReadings[window.providerID] {
            latest[window.id] = window
        }
        return latest.values.sorted { $0.id < $1.id }
    }
}

/// Grok Bot 0.68.1's local schema-2 weekly cache. This is separate from Grok Build.
/// Only a single cache is accepted: multiple account caches require user selection.
enum GrokBotUsageCache {
    static func decode(_ data: Data, now: Date) -> [AgentUsageWindow] {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["schemaVersion"] as? Int == 2,
              let value = envelope["value"] as? [String: Any], value["kind"] as? String == "present",
              let reading = value["reading"] as? [String: Any],
              let usage = reading["usage"] as? [String: Any],
              boolean(usage["hasNonZeroIncludedLimit"]) == true,
              boolean(usage["isTeamSeat"]) == false,
              let percent = AgentUsageWindow.validPercent(usage["percentUsed"]),
              let observed = milliseconds(reading["readAtMs"]), observed <= now.addingTimeInterval(30),
              let expires = milliseconds(value["expiresAtMs"]), expires > observed else { return [] }
        if let reset = usage["nextResetMs"], !(reset is NSNull), milliseconds(reset) == nil { return [] }
        return [AgentUsageWindow(id: "grok-bot.weekly", providerID: "grok-bot", label: "Weekly",
            usedPercent: percent, resetsAt: milliseconds(usage["nextResetMs"]), observedAt: observed,
            expiresAt: expires, source: "Desktop cache")]
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func milliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (946_684_800_000...4_102_444_800_000).contains(number.doubleValue) else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }
    static func isWeeklyCacheFilename(_ name: String) -> Bool {
        guard name.hasSuffix(".blob"), name.count <= 512 else { return false }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var accumulator: UInt32 = 0, bits = 0
        var bytes: [UInt8] = []
        for char in name.dropLast(5).uppercased().utf8 {
            guard let value = alphabet.firstIndex(of: char) else { return false }
            accumulator = (accumulator << 5 | UInt32(value)) & 0xffff
            bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8((accumulator >> bits) & 255)) }
        }
        guard bits == 0 || accumulator & UInt32((1 << bits) - 1) == 0,
              let key = String(bytes: bytes, encoding: .utf8) else { return false }
        return key.hasSuffix(".weekly-usage.cache")
    }
}

actor GrokBotCacheProvider: AgentSessionProvider {
    nonisolated let id = "grok-bot-cache"
    private let root: URL
    init(root: URL) { self.root = root }
    func snapshot(at date: Date) async -> AgentSnapshot {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil), files.count <= 2000 else {
            return AgentSnapshot(sessions: [], diagnostic: "Grok Bot cache folder unavailable or scan limit reached.")
        }
        let candidates = files.filter { GrokBotUsageCache.isWeeklyCacheFilename($0.lastPathComponent) }
        guard candidates.count == 1, let url = candidates.first else {
            return AgentSnapshot(sessions: [], diagnostic: candidates.count > 1
                ? "Multiple Grok Bot account caches found; usage hidden to avoid mixing accounts."
                : "No Grok Bot weekly cache found. Open Grok Bot to refresh its usage.")
        }
        guard AgentFileSafety.regularFile(url, under: root, maximumSize: 16_384),
              let data = try? Data(contentsOf: url) else {
            return AgentSnapshot(sessions: [], diagnostic: "Grok Bot usage cache is unreadable.")
        }
        let windows = GrokBotUsageCache.decode(data, now: date)
        return AgentSnapshot(sessions: [], diagnostic: windows.isEmpty
            ? "Grok Bot usage unavailable for this cache or plan. Open Grok Bot to check."
            : "Grok Bot • local weekly cache • refreshes when its app does", usage: windows)
    }
}
