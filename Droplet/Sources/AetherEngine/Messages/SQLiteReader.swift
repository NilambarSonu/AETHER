// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation
import SQLite3

/// A read-only SQLite URI connection used for Messages (`chat.db`) and Apple Mail (`Envelope Index`).
public final class SQLiteReader {
    public struct Failure: Error {}
    private var db: OpaquePointer?

    public init?(path: String) {
        let uri = "file:\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    public func query<T>(_ sql: String, _ arg: Int64 = 0, row: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw Failure() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, arg)
        var out: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: out.append(row(stmt))
            case SQLITE_DONE: return out
            default: throw Failure()
            }
        }
    }
}
