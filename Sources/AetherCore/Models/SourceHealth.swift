import Foundation

public enum SourceEvent: Equatable, Sendable {
    case checked(Date)
    case message(Date)
    case retry(Date?)
    /// Everything up to here was handed on; `SourceMonitor` keeps it for a restart to carry on from.
    case read(ReadPosition)
}

/// How far a source has read, so a restart after sleep or a network change carries on from there
/// instead of reading its whole history window again.
public enum ReadPosition: Equatable, Sendable {
    /// Messages: chat.db's ROWID, and the GUID of the message there, which tells the same database from
    /// a rebuilt one that numbers its rows anew.
    case row(Int64, guid: String)
    /// IMAP: the last UID, which holds only while the mailbox's UIDVALIDITY stays the same.
    case uid(Int, validity: Int?)
    /// Gmail's history ID, Outlook's arrival time.
    case cursor(String)
}

public struct SourceHealth: Equatable, Sendable {
    public var status: SourceStatus = .off
    public var lastChecked: Date?
    public var lastMessage: Date?
    public var lastCode: Date?
    public var retryAt: Date?

    public init(
        status: SourceStatus = .off,
        lastChecked: Date? = nil,
        lastMessage: Date? = nil,
        lastCode: Date? = nil,
        retryAt: Date? = nil
    ) {
        self.status = status
        self.lastChecked = lastChecked
        self.lastMessage = lastMessage
        self.lastCode = lastCode
        self.retryAt = retryAt
    }

    public mutating func record(_ event: SourceEvent) {
        switch event {
        case .checked(let date): lastChecked = max(lastChecked ?? date, date)
        case .message(let date): lastMessage = max(lastMessage ?? date, date)
        case .retry(let date): retryAt = date
        case .read: break  // not health: SourceMonitor keeps it
        }
    }
}
