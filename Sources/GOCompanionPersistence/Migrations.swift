import Foundation

public enum DatabaseKind: String, CaseIterable, Sendable {
    case user, knowledge, derived
}

public struct Migration: Hashable, Sendable {
    public let version: Int
    public let name: String
    public let sql: String
    public let checksum: String

    public init(version: Int, name: String, sql: String) {
        self.version = version
        self.name = name
        self.sql = sql
        self.checksum = Self.stableChecksum(sql)
    }

    private static func stableChecksum(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public enum MigrationCatalog {
    public static func load(for kind: DatabaseKind) throws -> [Migration] {
        try load(for: kind, bundle: .module)
    }

    static func load(for kind: DatabaseKind, bundle: Bundle) throws -> [Migration] {
        let names: [String]
        switch kind {
        case .user: names = ["001_user_initial", "002_user_collection_engine"]
        case .knowledge: names = ["001_knowledge_initial"]
        case .derived: names = ["001_derived_initial"]
        }
        return try names.enumerated().map { index, name in
            guard let url = bundle.url(forResource: name, withExtension: "sql") else {
                throw SQLiteError.execute("Missing migration resource \(name).sql")
            }
            return Migration(version: index + 1, name: name, sql: try String(contentsOf: url, encoding: .utf8))
        }
    }
}

public struct MigrationRunner: Sendable {
    public init() {}

    public func migrate(_ database: SQLiteDatabase, using migrations: [Migration]) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              checksum TEXT NOT NULL,
              applied_at TEXT NOT NULL
            );
            """)
        for migration in migrations.sorted(by: { $0.version < $1.version }) {
            let escapedChecksum = migration.checksum.replacingOccurrences(of: "'", with: "''")
            let existing = try database.scalarInt(
                "SELECT COUNT(*) FROM schema_migrations WHERE version = \(migration.version) AND checksum = '\(escapedChecksum)'"
            )
            if existing == 1 { continue }
            let versionExists = try database.scalarInt(
                "SELECT COUNT(*) FROM schema_migrations WHERE version = \(migration.version)"
            )
            guard versionExists == 0 else {
                throw SQLiteError.migrationChecksumChanged(version: migration.version)
            }
            let escapedName = migration.name.replacingOccurrences(of: "'", with: "''")
            try database.execute("BEGIN IMMEDIATE;")
            do {
                try database.execute(migration.sql)
                try database.execute(
                    """
                    INSERT INTO schema_migrations(version, name, checksum, applied_at)
                    VALUES(\(migration.version), '\(escapedName)', '\(escapedChecksum)', CURRENT_TIMESTAMP);
                    """)
                try database.execute("COMMIT;")
            } catch {
                try? database.execute("ROLLBACK;")
                throw error
            }
        }
    }
}

public struct DatabaseSet: Sendable {
    public let user: SQLiteDatabase
    public let knowledge: SQLiteDatabase
    public let derived: SQLiteDatabase

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        user = try SQLiteDatabase(path: directory.appendingPathComponent("user.sqlite").path)
        knowledge = try SQLiteDatabase(path: directory.appendingPathComponent("knowledge.sqlite").path)
        derived = try SQLiteDatabase(path: directory.appendingPathComponent("derived.sqlite").path)
        let runner = MigrationRunner()
        try runner.migrate(user, using: MigrationCatalog.load(for: .user))
        try runner.migrate(knowledge, using: MigrationCatalog.load(for: .knowledge))
        try runner.migrate(derived, using: MigrationCatalog.load(for: .derived))
    }
}
