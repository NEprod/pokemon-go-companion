import Foundation
import GOCompanionKnowledge

public final class SQLiteKnowledgeStore: KnowledgeStore, @unchecked Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func recordSource(
        _ payload: ProviderPayload, validation: SourceValidation, error: String?
    ) async throws {
        let state = validation == .valid ? "candidate" : "invalid"
        try database.execute(
            """
            INSERT INTO source_payloads(
              provider_name, category, source_version, parser_version, etag, checksum,
              fetched_at, payload, validation_status, validation_error, lifecycle_state
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider_name, category, source_version, parser_version) DO UPDATE SET
              etag = excluded.etag,
              checksum = excluded.checksum,
              fetched_at = excluded.fetched_at,
              payload = excluded.payload,
              validation_status = excluded.validation_status,
              validation_error = excluded.validation_error,
              lifecycle_state = CASE
                WHEN source_payloads.lifecycle_state IN ('active', 'previous')
                  THEN source_payloads.lifecycle_state
                ELSE excluded.lifecycle_state
              END;
            """,
            bindings: [
                .text(payload.version.providerName), .text(payload.version.category.rawValue),
                .text(payload.version.sourceVersion), .text(payload.version.parserVersion),
                payload.etag.map(SQLiteValue.text) ?? .null, .text(payload.version.contentHash),
                .text(Self.timestamp(payload.version.fetchedAt)), .blob(payload.bytes),
                .text(validation.rawValue), error.map(SQLiteValue.text) ?? .null, .text(state),
            ]
        )
    }

    public func activeVersion(category: DataCategory) async throws -> ProviderVersion? {
        let rows = try database.query(
            """
            SELECT d.provider_name, d.source_version, d.parser_version, d.content_hash, s.fetched_at
            FROM knowledge_active_versions a
            JOIN knowledge_datasets d ON d.normalized_version = a.active_normalized_version
            JOIN source_payloads s
              ON s.provider_name = d.provider_name AND s.category = d.category
              AND s.source_version = d.source_version AND s.parser_version = d.parser_version
            WHERE a.category = ?;
            """,
            bindings: [.text(category.rawValue)]
        )
        guard let row = rows.first,
            let provider = row["provider_name"].string,
            let source = row["source_version"].string,
            let parser = row["parser_version"].string,
            let hash = row["content_hash"].string,
            let fetched = row["fetched_at"].string.flatMap(Self.date)
        else { return nil }
        return ProviderVersion(
            providerName: provider,
            category: category,
            sourceVersion: source,
            parserVersion: parser,
            fetchedAt: fetched,
            contentHash: hash
        )
    }

    public func sourcePayload(
        provider: String, category: DataCategory, sourceVersion: String, parserVersion: String
    ) async throws -> ProviderPayload? {
        let rows = try database.query(
            """
            SELECT payload, etag, checksum, fetched_at
            FROM source_payloads
            WHERE provider_name = ? AND category = ? AND source_version = ? AND parser_version = ?;
            """,
            bindings: [
                .text(provider), .text(category.rawValue), .text(sourceVersion), .text(parserVersion),
            ]
        )
        guard let row = rows.first, case .blob(let bytes) = row["payload"],
            let checksum = row["checksum"].string,
            let fetchedAt = row["fetched_at"].string.flatMap(Self.date)
        else { return nil }
        return ProviderPayload(
            bytes: bytes,
            version: ProviderVersion(
                providerName: provider, category: category, sourceVersion: sourceVersion,
                parserVersion: parserVersion, fetchedAt: fetchedAt, contentHash: checksum),
            etag: row["etag"].string)
    }

    public func activeDataset(category: DataCategory) async throws -> KnowledgeDataset? {
        let rows = try database.query(
            """
            SELECT d.payload_json
            FROM knowledge_active_versions a
            JOIN knowledge_datasets d ON d.normalized_version = a.active_normalized_version
            WHERE a.category = ?;
            """,
            bindings: [.text(category.rawValue)]
        )
        guard let row = rows.first, case .blob(let data) = row["payload_json"] else { return nil }
        do {
            let dataset = try JSONDecoder().decode(KnowledgeDataset.self, from: data)
            try KnowledgeValidator.validate(dataset)
            return dataset
        } catch {
            throw KnowledgeError.corruptStoredData(String(describing: error))
        }
    }

    public func activate(_ dataset: KnowledgeDataset, from payload: ProviderPayload) async throws {
        guard payload.version.category == .gameMaster else {
            throw KnowledgeError.unsupportedCategory(payload.version.category)
        }
        try KnowledgeValidator.validate(dataset)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let datasetJSON = try encoder.encode(dataset)
        let now = Self.timestamp(Date())
        try database.transaction {
            let validSource =
                try database.query(
                    """
                    SELECT COUNT(*) AS count FROM source_payloads
                    WHERE provider_name = ? AND category = ? AND source_version = ?
                      AND parser_version = ? AND validation_status = 'valid';
                    """,
                    bindings: Self.sourceBindings(payload)
                ).first?["count"].int ?? 0
            guard validSource == 1 else {
                throw KnowledgeError.invalidDataset("activation requires a validated source payload")
            }

            try database.execute(
                """
                INSERT INTO knowledge_datasets(
                  normalized_version, category, provider_name, source_version, parser_version,
                  content_hash, payload_json, lifecycle_state, staged_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, 'staged', ?);
                """,
                bindings: [
                    .text(dataset.normalizedVersion), .text(payload.version.category.rawValue),
                    .text(payload.version.providerName), .text(payload.version.sourceVersion),
                    .text(payload.version.parserVersion), .text(payload.version.contentHash),
                    .blob(datasetJSON), .text(now),
                ]
            )
            try insertNormalizedRows(dataset, encoder: encoder)
            try verifyStagedRows(dataset)

            let activeRow = try database.query(
                """
                SELECT active_normalized_version, previous_normalized_version
                FROM knowledge_active_versions WHERE category = ?;
                """,
                bindings: [.text(payload.version.category.rawValue)]
            ).first
            let oldActive = activeRow?["active_normalized_version"].string
            let oldPrevious = activeRow?["previous_normalized_version"].string
            if let oldPrevious {
                try database.execute(
                    "UPDATE knowledge_datasets SET lifecycle_state = 'inactive' WHERE normalized_version = ?;",
                    bindings: [.text(oldPrevious)]
                )
            }
            if let oldActive {
                try database.execute(
                    "UPDATE knowledge_datasets SET lifecycle_state = 'previous' WHERE normalized_version = ?;",
                    bindings: [.text(oldActive)]
                )
            }
            try database.execute(
                """
                UPDATE source_payloads SET lifecycle_state = 'inactive'
                WHERE category = ? AND lifecycle_state = 'previous';
                """,
                bindings: [.text(payload.version.category.rawValue)]
            )
            try database.execute(
                """
                UPDATE source_payloads SET lifecycle_state = 'previous'
                WHERE category = ? AND lifecycle_state = 'active';
                """,
                bindings: [.text(payload.version.category.rawValue)]
            )
            try database.execute(
                """
                UPDATE source_payloads SET lifecycle_state = 'active', activated_at = ?
                WHERE provider_name = ? AND category = ? AND source_version = ? AND parser_version = ?;
                """,
                bindings: [.text(now)] + Self.sourceBindings(payload)
            )
            try database.execute(
                """
                UPDATE knowledge_datasets
                SET lifecycle_state = 'active', activated_at = ?
                WHERE normalized_version = ?;
                """,
                bindings: [.text(now), .text(dataset.normalizedVersion)]
            )
            try database.execute(
                """
                INSERT INTO knowledge_active_versions(
                  category, active_normalized_version, previous_normalized_version, updated_at
                ) VALUES(?, ?, ?, ?)
                ON CONFLICT(category) DO UPDATE SET
                  active_normalized_version = excluded.active_normalized_version,
                  previous_normalized_version = excluded.previous_normalized_version,
                  updated_at = excluded.updated_at;
                """,
                bindings: [
                    .text(payload.version.category.rawValue), .text(dataset.normalizedVersion),
                    oldActive.map(SQLiteValue.text) ?? .null, .text(now),
                ]
            )
            try database.execute(
                """
                INSERT INTO provider_versions(
                  provider_name, category, source_version, parser_version, content_hash,
                  fetched_at, activated_at, status, error
                ) VALUES(?, ?, ?, ?, ?, ?, ?, 'current', NULL)
                ON CONFLICT(provider_name, category, source_version) DO UPDATE SET
                  parser_version = excluded.parser_version,
                  content_hash = excluded.content_hash,
                  fetched_at = excluded.fetched_at,
                  activated_at = excluded.activated_at,
                  status = 'current', error = NULL;
                """,
                bindings: [
                    .text(payload.version.providerName), .text(payload.version.category.rawValue),
                    .text(payload.version.sourceVersion), .text(payload.version.parserVersion),
                    .text(payload.version.contentHash), .text(Self.timestamp(payload.version.fetchedAt)),
                    .text(now),
                ]
            )
        }
    }

    public func rollback(category: DataCategory) async throws -> KnowledgeDataset {
        try database.transaction {
            guard
                let pointer = try database.query(
                    """
                    SELECT active_normalized_version, previous_normalized_version
                    FROM knowledge_active_versions WHERE category = ?;
                    """,
                    bindings: [.text(category.rawValue)]
                ).first,
                let active = pointer["active_normalized_version"].string,
                let previous = pointer["previous_normalized_version"].string
            else { throw KnowledgeError.invalidDataset("no previous-good version to restore") }
            let now = Self.timestamp(Date())
            try database.execute(
                "UPDATE knowledge_datasets SET lifecycle_state = 'previous' WHERE normalized_version = ?;",
                bindings: [.text(active)]
            )
            try database.execute(
                "UPDATE knowledge_datasets SET lifecycle_state = 'active', activated_at = ? WHERE normalized_version = ?;",
                bindings: [.text(now), .text(previous)]
            )
            try database.execute(
                """
                UPDATE knowledge_active_versions
                SET active_normalized_version = ?, previous_normalized_version = ?, updated_at = ?
                WHERE category = ?;
                """,
                bindings: [.text(previous), .text(active), .text(now), .text(category.rawValue)]
            )
            try database.execute(
                "UPDATE source_payloads SET lifecycle_state = 'previous' WHERE category = ? AND lifecycle_state = 'active';",
                bindings: [.text(category.rawValue)]
            )
            let restored = try database.query(
                """
                SELECT provider_name, source_version, parser_version, payload_json
                FROM knowledge_datasets WHERE normalized_version = ?;
                """,
                bindings: [.text(previous)]
            ).first
            guard let restored,
                let provider = restored["provider_name"].string,
                let source = restored["source_version"].string,
                let parser = restored["parser_version"].string,
                case .blob(let json) = restored["payload_json"]
            else { throw KnowledgeError.corruptStoredData("rollback target is missing") }
            try database.execute(
                """
                UPDATE source_payloads SET lifecycle_state = 'active', activated_at = ?
                WHERE provider_name = ? AND category = ? AND source_version = ? AND parser_version = ?;
                """,
                bindings: [
                    .text(now), .text(provider), .text(category.rawValue), .text(source), .text(parser),
                ]
            )
            return try JSONDecoder().decode(KnowledgeDataset.self, from: json)
        }
    }

    public func recordFailure(provider: String, category: DataCategory, error: String) async throws {
        try database.execute(
            """
            UPDATE provider_versions SET status = 'failed', error = ?
            WHERE provider_name = ? AND category = ? AND source_version = (
              SELECT d.source_version
              FROM knowledge_active_versions a
              JOIN knowledge_datasets d ON d.normalized_version = a.active_normalized_version
              WHERE a.category = ? AND d.provider_name = ?
            );
            """,
            bindings: [
                .text(error), .text(provider), .text(category.rawValue), .text(category.rawValue),
                .text(provider),
            ]
        )
    }

    private func insertNormalizedRows(_ dataset: KnowledgeDataset, encoder: JSONEncoder) throws {
        let version = SQLiteValue.text(dataset.normalizedVersion)
        for type in dataset.types {
            try database.execute(
                "INSERT INTO knowledge_types(normalized_version, type_id) VALUES(?, ?);",
                bindings: [version, .text(type)]
            )
        }
        for form in dataset.speciesForms {
            try database.execute(
                """
                INSERT INTO knowledge_species_forms(
                  normalized_version, species_id, form_id, display_name, primary_type_id,
                  secondary_type_id, base_attack, base_defense, base_stamina, evolution_family_id,
                  shadow_capable, mega_capable, dynamax_capable, gigantamax_capable
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    version, .text(form.id.speciesID), .text(form.id.formID), .text(form.displayName),
                    .text(form.types[0]), form.types.count > 1 ? .text(form.types[1]) : .null,
                    .integer(Int64(form.baseStats.attack)), .integer(Int64(form.baseStats.defense)),
                    .integer(Int64(form.baseStats.stamina)), .text(form.evolutionFamilyID),
                    .integer(form.capabilities.shadow ? 1 : 0),
                    .integer(form.capabilities.mega ? 1 : 0),
                    .integer(form.capabilities.dynamax ? 1 : 0),
                    .integer(form.capabilities.gigantamax ? 1 : 0),
                ]
            )
        }
        for evolution in dataset.evolutions {
            try database.execute(
                """
                INSERT INTO knowledge_evolutions(
                  normalized_version, from_species_id, from_form_id, to_species_id, to_form_id,
                  candy_cost, requirements_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    version, .text(evolution.from.speciesID), .text(evolution.from.formID),
                    .text(evolution.to.speciesID), .text(evolution.to.formID),
                    .integer(Int64(evolution.candyCost)), .blobText(try encoder.encode(evolution.requirements)),
                ]
            )
        }
        for move in dataset.moves {
            try database.execute(
                """
                INSERT INTO knowledge_moves(
                  normalized_version, move_id, display_name, move_kind, type_id, pve_json, pvp_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    version, .text(move.moveID), .text(move.displayName), .text(move.kind.rawValue),
                    .text(move.typeID), .blobText(try encoder.encode(move.pve)),
                    .blobText(try encoder.encode(move.pvp)),
                ]
            )
        }
        for pool in dataset.movePools {
            try database.execute(
                """
                INSERT INTO knowledge_move_pools(
                  normalized_version, species_id, form_id, move_id, availability
                ) VALUES(?, ?, ?, ?, ?);
                """,
                bindings: [
                    version, .text(pool.speciesForm.speciesID), .text(pool.speciesForm.formID),
                    .text(pool.moveID), .text(pool.availability.rawValue),
                ]
            )
        }
        for cpm in dataset.cpMultipliers {
            try database.execute(
                """
                INSERT INTO knowledge_cp_multipliers(
                  normalized_version, level_half_steps, multiplier, stardust_cost, candy_cost,
                  xl_candy_cost, requires_xl, best_buddy_only
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    version, .integer(Int64(cpm.level.halfSteps)), .real(cpm.multiplier),
                    .integer(Int64(cpm.stardustCost)), .integer(Int64(cpm.candyCost)),
                    .integer(Int64(cpm.xlCandyCost)), .integer(cpm.requiresXL ? 1 : 0),
                    .integer(cpm.bestBuddyOnly ? 1 : 0),
                ]
            )
        }
    }

    private func verifyStagedRows(_ dataset: KnowledgeDataset) throws {
        let version = dataset.normalizedVersion.replacingOccurrences(of: "'", with: "''")
        let expectations = [
            ("knowledge_types", dataset.types.count),
            ("knowledge_species_forms", dataset.speciesForms.count),
            ("knowledge_evolutions", dataset.evolutions.count),
            ("knowledge_moves", dataset.moves.count),
            ("knowledge_move_pools", dataset.movePools.count),
            ("knowledge_cp_multipliers", dataset.cpMultipliers.count),
        ]
        for (table, expected) in expectations {
            let count = try database.scalarInt(
                "SELECT COUNT(*) FROM \(table) WHERE normalized_version = '\(version)';")
            guard count == expected else {
                throw KnowledgeError.invalidDataset("staged row count mismatch for \(table)")
            }
        }
    }

    private static func sourceBindings(_ payload: ProviderPayload) -> [SQLiteValue] {
        [
            .text(payload.version.providerName), .text(payload.version.category.rawValue),
            .text(payload.version.sourceVersion), .text(payload.version.parserVersion),
        ]
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private extension SQLiteValue {
    static func blobText(_ data: Data) -> SQLiteValue {
        .text(String(decoding: data, as: UTF8.self))
    }
}
