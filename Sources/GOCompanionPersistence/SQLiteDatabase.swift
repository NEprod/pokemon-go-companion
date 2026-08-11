import CSQLite
import Foundation

public enum SQLiteError: Error, Equatable, CustomStringConvertible {
    case open(String)
    case execute(String)
    case migrationChecksumChanged(version: Int)

    public var description: String {
        switch self {
        case .open(let message): "SQLite open failed: \(message)"
        case .execute(let message): "SQLite statement failed: \(message)"
        case .migrationChecksumChanged(let version): "Applied migration \(version) has changed"
        }
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    public let path: String

    public init(path: String) throws {
        self.path = path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.open(message)
        }
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "code \(result)"
            sqlite3_free(errorMessage)
            throw SQLiteError.execute(message)
        }
    }

    public func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.execute(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
