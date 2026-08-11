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

public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var string: String? {
        if case .text(let value) = self { value } else { nil }
    }

    public var int: Int? {
        if case .integer(let value) = self { Int(value) } else { nil }
    }

    public var double: Double? {
        switch self {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }
}

public struct SQLiteRow: Sendable {
    private let values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) {
        self.values = values
    }

    public subscript(_ column: String) -> SQLiteValue {
        values[column] ?? .null
    }

    var firstInt: Int? {
        values.values.first?.int
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
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
        lock.lock()
        defer { lock.unlock() }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "code \(result)"
            sqlite3_free(errorMessage)
            throw SQLiteError.execute(message)
        }
    }

    public func execute(_ sql: String, bindings: [SQLiteValue]) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.execute(errorMessage)
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [SQLiteRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                var values: [String: SQLiteValue] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    guard let namePointer = sqlite3_column_name(statement, index) else { continue }
                    let name = String(cString: namePointer)
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER:
                        values[name] = .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT:
                        values[name] = .real(sqlite3_column_double(statement, index))
                    case SQLITE_TEXT:
                        values[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                    case SQLITE_BLOB:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        if let bytes = sqlite3_column_blob(statement, index) {
                            values[name] = .blob(Data(bytes: bytes, count: count))
                        } else {
                            values[name] = .blob(Data())
                        }
                    default:
                        values[name] = .null
                    }
                }
                rows.append(SQLiteRow(values: values))
            case SQLITE_DONE:
                return rows
            default:
                throw SQLiteError.execute(errorMessage)
            }
        }
    }

    public func transaction<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try operation()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func scalarInt(_ sql: String) throws -> Int {
        try query(sql).first?.firstInt ?? 0
    }

    public var changes: Int {
        lock.lock()
        defer { lock.unlock() }
        return Int(sqlite3_changes(handle))
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
    }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.execute(errorMessage)
        }
        do {
            for (offset, value) in bindings.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .null:
                    result = sqlite3_bind_null(statement, index)
                case .integer(let value):
                    result = sqlite3_bind_int64(statement, index, value)
                case .real(let value):
                    result = sqlite3_bind_double(statement, index, value)
                case .text(let value):
                    result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
                case .blob(let data):
                    result = data.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
                    }
                }
                guard result == SQLITE_OK else { throw SQLiteError.execute(errorMessage) }
            }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
