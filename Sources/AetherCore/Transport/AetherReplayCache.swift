import Foundation

/// Bounded in-memory replay protection cache for ephemeral OTP events.
///
/// Prevents duplicate presentation, replayed wire frames, and expired event delivery.
/// Capacity is strictly capped at 256 entries, ensuring maximum memory consumption is < 16 KB.
/// OTP secret codes are NEVER stored in this cache—only event UUIDs and expiration deadlines.
public final class AetherReplayCache: @unchecked Sendable {
    public static let maxEntries: Int = 256

    private var entries: [UUID: Date] = [:]
    private var order: [UUID] = []
    private let lock = NSLock()

    public init() {
        entries.reserveCapacity(Self.maxEntries)
        order.reserveCapacity(Self.maxEntries)
    }

    /// Evaluates whether an event is a replay or expired, and records it if fresh.
    ///
    /// - Parameters:
    ///   - eventID: The cryptographically unique event UUID.
    ///   - expiresAt: The deadline after which the event must not be presented.
    ///   - now: Reference time for expiration checks (defaults to `Date()`).
    /// - Returns: `true` if the event is expired or was already recorded; `false` if fresh and recorded.
    public func isReplayOrRecord(eventID: UUID, expiresAt: Date, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // 1. Immediately reject expired events
        guard expiresAt > now else {
            return true
        }

        // 2. Reject duplicates
        if entries[eventID] != nil {
            return true
        }

        // 3. Purge expired entries if approaching capacity
        if entries.count >= Self.maxEntries {
            purgeExpired(now: now)
        }

        // 4. If still at capacity, evict oldest entry (LRU ring behavior)
        if entries.count >= Self.maxEntries, !order.isEmpty {
            let oldest = order.removeFirst()
            entries.removeValue(forKey: oldest)
        }

        // 5. Record fresh entry
        entries[eventID] = expiresAt
        order.append(eventID)
        return false
    }

    /// Returns the current number of tracked active event IDs.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Purges all records from the cache.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private func purgeExpired(now: Date) {
        let expiredIDs = entries.compactMap { id, expiry in
            expiry <= now ? id : nil
        }
        for id in expiredIDs {
            entries.removeValue(forKey: id)
        }
        order.removeAll { entries[$0] == nil }
    }
}
