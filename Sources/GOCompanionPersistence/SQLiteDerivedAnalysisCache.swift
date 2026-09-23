import Foundation
import GOCompanionKnowledge

public final class SQLiteDerivedAnalysisCache: DerivedAnalysisCache, @unchecked Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func data(for key: DerivedCacheKey) async throws -> Data? {
        let versions = try Self.versionsJSON(key.inputVersions)
        let rows = try database.query(
            """
            SELECT payload FROM derived_entries
            WHERE cache_kind = ? AND subject_key = ? AND input_versions_json = ? AND engine_version = ?;
            """,
            bindings: [
                .text(key.kind), .text(key.subject), .text(versions), .text(key.engineVersion),
            ]
        )
        guard let row = rows.first, case .blob(let payload) = row["payload"] else { return nil }
        try database.execute(
            """
            UPDATE derived_entries SET last_accessed_at = ?
            WHERE cache_kind = ? AND subject_key = ? AND input_versions_json = ? AND engine_version = ?;
            """,
            bindings: [
                .text(Self.timestamp()), .text(key.kind), .text(key.subject), .text(versions),
                .text(key.engineVersion),
            ]
        )
        return payload
    }

    public func store(_ data: Data, for key: DerivedCacheKey) async throws {
        let versions = try Self.versionsJSON(key.inputVersions)
        let now = Self.timestamp()
        try database.execute(
            """
            INSERT INTO derived_entries(
              cache_kind, subject_key, input_versions_json, engine_version,
              payload, created_at, last_accessed_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(cache_kind, subject_key, input_versions_json, engine_version) DO UPDATE SET
              payload = excluded.payload, last_accessed_at = excluded.last_accessed_at;
            """,
            bindings: [
                .text(key.kind), .text(key.subject), .text(versions), .text(key.engineVersion),
                .blob(data), .text(now), .text(now),
            ]
        )
        if key.kind == "pvp-iv-ranking", let version = key.inputVersions["gameMaster"] {
            try database.execute(
                """
                INSERT OR REPLACE INTO pvp_iv_cache_metadata(
                  subject_key, knowledge_version, engine_version, league_configuration_key, generated_at
                ) VALUES(?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(key.subject), .text(version), .text(key.engineVersion), .text(key.subject),
                    .text(now),
                ]
            )
        }
    }

    public func invalidate(affectedBy category: DataCategory, newVersion: String) async throws {
        let oldCount = try database.scalarInt("SELECT COUNT(*) FROM derived_entries;")
        try database.execute(
            "DELETE FROM derived_entries WHERE input_versions_json LIKE ?;",
            bindings: [.text("%\"\(category.rawValue)\"%")]
        )
        let affected = oldCount - (try database.scalarInt("SELECT COUNT(*) FROM derived_entries;"))
        try database.execute(
            """
            INSERT INTO invalidation_log(
              category, old_version, new_version, invalidated_at, affected_count
            ) VALUES(?, NULL, ?, ?, ?);
            """,
            bindings: [
                .text(category.rawValue), .text(newVersion), .text(Self.timestamp()),
                .integer(Int64(affected)),
            ]
        )
        if category == .gameMaster {
            try database.execute(
                "DELETE FROM pvp_iv_cache_metadata WHERE knowledge_version <> ?;",
                bindings: [.text(newVersion)]
            )
        }
    }

    public func rebuildableDataMayBeDiscarded() async throws {
        try database.transaction {
            try database.execute("DELETE FROM derived_entries;")
            try database.execute("DELETE FROM pvp_iv_cache_metadata;")
        }
    }

    private static func versionsJSON(_ versions: [String: String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(versions), as: UTF8.self)
    }

    private static func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }
}
