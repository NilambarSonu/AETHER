// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public enum SourceStatus: Equatable, Sendable {
    case off, connecting, live
    case attention(String)
    case failed(String)

    public static let needsDiskAccess = "Needs Full Disk Access"
    public static let signInExpired = "Sign-in expired. Sign in again."
    public static let needsSignIn = "Needs sign-in"
    public static let signInFailed = "Sign-in failed. Check the app password."
    public static let waitingForNetwork = "Waiting for network"

    public var needsDiskAccess: Bool { self == .attention(Self.needsDiskAccess) }
    public var needsSignIn: Bool { needsAttention && [Self.needsSignIn, Self.signInExpired, Self.signInFailed].contains(summary) }

    public var needsAttention: Bool {
        switch self {
        case .attention, .failed: true
        default: false
        }
    }

    public var summary: String {
        switch self {
        case .off: "Off"
        case .connecting: "Connecting…"
        case .live: "Watching"
        case .attention(let s), .failed(let s): s
        }
    }
}

public enum SourceEvent: Equatable, Sendable {
    case checked(Date)
    case latencyMs(Int)
    case message(Date)
    case retry(Date?)
    case read(ReadPosition)
}

public enum ReadPosition: Equatable, Sendable {
    case row(Int64, guid: String)
    case uid(Int, validity: Int?)
    case cursor(String)
}

public struct SourceHealth: Equatable, Sendable {
    public var status: SourceStatus = .off
    public var lastChecked: Date?
    public var lastLatencyMs: Int?
    public var lastMessage: Date?
    public var lastCode: Date?
    public var retryAt: Date?

    public init(
        status: SourceStatus = .off,
        lastChecked: Date? = nil,
        lastLatencyMs: Int? = nil,
        lastMessage: Date? = nil,
        lastCode: Date? = nil,
        retryAt: Date? = nil
    ) {
        self.status = status
        self.lastChecked = lastChecked
        self.lastLatencyMs = lastLatencyMs
        self.lastMessage = lastMessage
        self.lastCode = lastCode
        self.retryAt = retryAt
    }

    public mutating func record(_ event: SourceEvent) {
        switch event {
        case .checked(let date): lastChecked = max(lastChecked ?? date, date)
        case .latencyMs(let ms): lastLatencyMs = max(0, ms)
        case .message(let date): lastMessage = max(lastMessage ?? date, date)
        case .retry(let date): retryAt = date
        case .read: break
        }
    }
}
