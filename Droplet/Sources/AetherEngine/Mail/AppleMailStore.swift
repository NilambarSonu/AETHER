// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation
import SQLite3

/// Reads ~/Library/Mail/V*/MailData/Envelope Index and .emlx bodies read-only using Droppy's Full Disk Access.
public final class AppleMailStore: LocalStore {
    public static let sourceKey = "applemail"
    public static let bodyWait: TimeInterval = 60

    public let name = "Apple Mail"
    public var watchDirectory: String? { (version ?? root).path }
    public private(set) var position: Int64 = 0
    private let root: URL
    private var version: URL?
    private var db: SQLiteReader?
    private var since = Date.distantPast
    private var waiting: [Int64: Date] = [:]

    public init(root: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mail")) {
        self.root = root
    }

    public func open(since: Date) -> String? {
        let notSetUp = "Add an account in Mail"
        let versions: [String]
        do { versions = try FileManager.default.contentsOfDirectory(atPath: root.path) } catch CocoaError.fileReadNoSuchFile {
            return notSetUp
        } catch { return SourceStatus.needsDiskAccess }
        guard
            let newest = versions.compactMap({ name in Int(name.dropFirst()).flatMap { name.hasPrefix("V") ? ($0, name) : nil } })
                .max(by: { $0.0 < $1.0 })?.1
        else { return notSetUp }
        let version = root.appendingPathComponent(newest)
        let index = version.appendingPathComponent("MailData/Envelope Index").path
        guard FileManager.default.fileExists(atPath: index) else { return notSetUp }
        guard let db = SQLiteReader(path: index) else { return SourceStatus.needsDiskAccess }
        guard let inboxes = try? db.query("SELECT COUNT(*) FROM mailboxes WHERE \(Self.isInbox)", row: { sqlite3_column_int64($0, 0) }).first
        else { return "Can't read Apple Mail" }
        guard inboxes > 0 else { return notSetUp }
        (self.db, self.version, self.since, position, waiting) = (db, version, since, 0, [:])
        return nil
    }

    public func close() { db = nil }

    private static let isInbox = "lower(url) LIKE '%/inbox'"

    public func newMessages() throws -> [IncomingMessage] {
        guard let db, let version else { return [] }
        let top = try db.query("SELECT COALESCE(MAX(ROWID), 0) FROM messages") { sqlite3_column_int64($0, 0) }.first ?? position
        let now = Date()
        waiting = waiting.filter { $0.value > now }
        func text(_ s: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(s, column).map { String(cString: $0) } ?? "" }
        func rows(_ filter: String, limit: String = "") throws -> [IncomingMessage] {
            let sql = """
                SELECT m.ROWID, m.date_received, COALESCE(a.address, ''), COALESCE(a.comment, ''),
                       COALESCE(m.subject_prefix, '') || COALESCE(s.subject, ''), COALESCE(y.summary, ''), b.url
                FROM messages m JOIN mailboxes b ON b.ROWID = m.mailbox
                LEFT JOIN addresses a ON a.ROWID = m.sender LEFT JOIN subjects s ON s.ROWID = m.subject
                LEFT JOIN summaries y ON y.ROWID = m.summary
                WHERE \(filter) AND m.deleted = 0 AND m.date_received > \(Int64(since.timeIntervalSince1970)) AND \(Self.isInbox)
                ORDER BY m.date_received DESC \(limit)
                """
            return try db.query(sql, position) { s -> IncomingMessage? in
                let id = sqlite3_column_int64(s, 0)
                let mail = Self.body(of: id, mailbox: text(s, 6), in: version).map { MIME.parse($0) }
                if mail != nil {
                    waiting[id] = nil
                } else if waiting[id] != nil {
                    return nil
                } else {
                    waiting[id] = now.addingTimeInterval(Self.bodyWait)
                }
                return IncomingMessage(
                    text: mail?.text ?? text(s, 5),
                    subject: mail?.subject ?? text(s, 4),
                    senderName: mail?.fromName ?? text(s, 3),
                    senderID: mail?.fromAddress ?? text(s, 2),
                    sourceKey: Self.sourceKey,
                    sourceLabel: name,
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(s, 1))),
                    isMail: true,
                    links: mail?.links ?? [],
                    messageID: String(id),
                    senderVerified: mail?.senderVerified,
                    internetMessageID: mail?.messageID
                )
            }.compactMap { $0 }.reversed()
        }
        let late = waiting.isEmpty ? [] : try rows("m.ROWID IN (\(waiting.keys.map(String.init).joined(separator: ",")))")
        let new = try rows("m.ROWID > ?1 AND m.ROWID <= \(top)", limit: "LIMIT 60")
        position = top
        return late + new
    }

    public static func body(of id: Int64, mailbox: String, in version: URL) -> Data? {
        guard let url = URL(string: mailbox), let account = url.host else { return nil }
        let box = url.pathComponents.dropFirst().reduce(version.appendingPathComponent(account)) { $0.appendingPathComponent($1 + ".mbox") }
        let shards = id < 1000 ? [] : String(id / 1000).reversed().map(String.init)
        for store in (try? FileManager.default.contentsOfDirectory(atPath: box.path)) ?? [] {
            let messages = shards.reduce(box.appendingPathComponent(store).appendingPathComponent("Data")) { $0.appendingPathComponent($1) }
                .appendingPathComponent("Messages")
            for name in ["\(id).emlx", "\(id).partial.emlx"] {
                guard let file = try? FileHandle(forReadingFrom: messages.appendingPathComponent(name)) else { continue }
                defer { try? file.close() }
                if let data = try? file.read(upToCount: IncomingMessage.mailReadLimit), let message = message(inEMLX: data) { return message }
            }
        }
        return nil
    }

    public static func message(inEMLX data: Data) -> Data? {
        guard let newline = data.firstIndex(of: 0x0A),
            let length = Int(String(decoding: data[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces)), length >= 0
        else { return nil }
        let message = data[(newline + 1)...].prefix(length)
        return message.count == length || data.count >= IncomingMessage.mailReadLimit ? Data(message) : nil
    }
}
