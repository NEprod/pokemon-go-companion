import Foundation
import GOCompanionApplication
import GOCompanionDomain

public final class SQLiteCollectionRepository: CollectionRepository, @unchecked Sendable {
    public let database: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: SQLiteDatabase) {
        self.database = database
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func ensureProfile(_ profile: UserProfile) throws {
        let json = try encodeString(profile)
        let timestamp = dateString(Date())
        try database.execute(
            """
            INSERT INTO profiles(id, display_name, preferences_json, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              display_name = excluded.display_name,
              preferences_json = excluded.preferences_json,
              updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(profile.id.uuidString), .text(profile.displayName), .text(json), .text(timestamp),
                .text(timestamp),
            ]
        )
    }

    public func profile() throws -> UserProfile {
        guard
            let row = try database.query(
                "SELECT preferences_json FROM profiles ORDER BY created_at, id LIMIT 1"
            ).first, let json = row["preferences_json"].string
        else {
            throw CollectionEngineError.profileMissing
        }
        return try decode(UserProfile.self, from: json)
    }

    public func create(_ record: PokemonRecord, event: CollectionHistoryEvent) throws {
        try database.transaction {
            if try pokemon(id: record.identity.recordID) != nil {
                throw CollectionEngineError.duplicatePokemon(record.identity.recordID)
            }
            let profileID = try profile().id
            try insertPokemon(record, profileID: profileID)
            try replaceAssociations(for: record)
            try insertHistory(event)
        }
    }

    public func save(
        _ record: PokemonRecord,
        expectedRevision: Int,
        event: CollectionHistoryEvent
    ) throws -> PokemonRecord {
        try database.transaction {
            let currentRevision = try database.query(
                "SELECT revision FROM pokemon WHERE id = ?",
                bindings: [.text(record.identity.recordID.uuidString)]
            ).first?["revision"].int
            guard let currentRevision else {
                throw CollectionEngineError.pokemonNotFound(record.identity.recordID)
            }
            guard currentRevision == expectedRevision else {
                throw CollectionEngineError.staleRevision(expected: expectedRevision, actual: currentRevision)
            }
            try updatePokemon(record, expectedRevision: expectedRevision)
            guard database.changes == 1 else {
                throw CollectionEngineError.staleRevision(expected: expectedRevision, actual: currentRevision)
            }
            try replaceAssociations(for: record)
            try insertHistory(event)
            return record
        }
    }

    public func pokemon(id: UUID) throws -> PokemonRecord? {
        guard
            let row = try database.query(
                "SELECT * FROM pokemon WHERE id = ?",
                bindings: [.text(id.uuidString)]
            ).first
        else { return nil }
        return try hydrate(row)
    }

    public func list(_ query: CollectionQuery) throws -> [PokemonRecord] {
        var sql = "SELECT DISTINCT p.* FROM pokemon p WHERE 1 = 1"
        var bindings: [SQLiteValue] = []
        if let archived = query.archived {
            let archivedValues = [
                CollectionStatus.archivedTransferred.rawValue,
                CollectionStatus.archivedTraded.rawValue,
                CollectionStatus.archivedOther.rawValue,
            ]
            sql += archived ? " AND p.status IN (?, ?, ?)" : " AND p.status NOT IN (?, ?, ?)"
            bindings += archivedValues.map(SQLiteValue.text)
        }
        if !query.statuses.isEmpty {
            let values = query.statuses.map(\.rawValue).sorted()
            sql += " AND p.status IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindings += values.map(SQLiteValue.text)
        }
        if let speciesID = query.speciesID {
            sql += " AND p.species_id = ?"
            bindings.append(.text(speciesID))
        }
        if let formID = query.formID {
            sql += " AND p.form_id = ?"
            bindings.append(.text(formID))
        }
        if let internalTag = query.internalTag {
            sql += " AND EXISTS (SELECT 1 FROM pokemon_internal_tags t WHERE t.pokemon_id = p.id AND t.tag = ?)"
            bindings.append(.text(internalTag))
        }
        if let tag = query.recommendedGOTag {
            sql +=
                " AND EXISTS (SELECT 1 FROM recommended_go_tags r WHERE r.pokemon_id = p.id AND r.tag = ? AND r.recommendation_state = 'recommended')"
            bindings.append(.text(tag.rawValue))
        }
        switch query.sort {
        case .updatedNewest: sql += " ORDER BY p.updated_at DESC, p.id"
        case .updatedOldest: sql += " ORDER BY p.updated_at, p.id"
        case .speciesAscending: sql += " ORDER BY p.species_id, p.form_id, p.cp DESC, p.id"
        case .cpDescending: sql += " ORDER BY p.cp DESC, p.species_id, p.id"
        }
        sql += " LIMIT ? OFFSET ?"
        bindings += [.integer(Int64(query.limit)), .integer(Int64(query.offset))]
        return try database.query(sql, bindings: bindings).map(hydrate)
    }

    public func addObservation(
        session: ScanSession,
        observation: PokemonObservation,
        event: CollectionHistoryEvent?
    ) throws {
        try database.transaction {
            try insertSession(session)
            try insertObservation(observation)
            if let event { try insertHistory(event) }
        }
    }

    public func observations(for pokemonID: UUID) throws -> [PokemonObservation] {
        try database.query(
            "SELECT fields_json FROM observations WHERE pokemon_id = ? ORDER BY observed_at, id",
            bindings: [.text(pokemonID.uuidString)]
        ).map { row in
            guard let json = row["fields_json"].string else {
                throw SQLiteError.execute("Observation JSON is missing")
            }
            return try decode(PokemonObservation.self, from: json)
        }
    }

    public func history(for pokemonID: UUID) throws -> [CollectionHistoryEvent] {
        try database.query(
            "SELECT payload_json FROM collection_history WHERE pokemon_id = ? ORDER BY occurred_at, rowid",
            bindings: [.text(pokemonID.uuidString)]
        ).map { row in
            guard let json = row["payload_json"].string else {
                throw SQLiteError.execute("History payload is missing")
            }
            return try decode(CollectionHistoryEvent.self, from: json)
        }
    }

    public func allAggregates() throws -> [CollectionAggregate] {
        let records = try database.query("SELECT * FROM pokemon ORDER BY created_at, id").map(hydrate)
        return try records.map { record in
            let observations = try observations(for: record.identity.recordID)
            let sessionIDs = Set(observations.map(\.scanSessionID))
            let sessions = try sessionIDs.map(loadSession)
                .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
            return CollectionAggregate(
                pokemon: record,
                scanSessions: sessions,
                observations: observations,
                history: try history(for: record.identity.recordID)
            )
        }
    }

    public func currentUserSchemaVersion() throws -> Int {
        try database.scalarInt("SELECT COALESCE(MAX(version), 0) FROM schema_migrations")
    }

    public func inventory() throws -> Inventory? {
        let rows = try database.query("SELECT * FROM resources ORDER BY resource_id")
        guard !rows.isEmpty else { return nil }
        guard
            let profileIDString = rows[0]["profile_id"].string,
            let profileID = UUID(uuidString: profileIDString)
        else { throw SQLiteError.execute("Invalid inventory profile") }
        let resources = try rows.map { row -> ResourceAmount in
            guard
                row["profile_id"].string == profileIDString,
                let resourceID = row["resource_id"].string,
                let quantity = row["quantity"].int,
                let observedString = row["observed_at"].string,
                let observedAt = parseDate(observedString),
                let confidenceValue = row["confidence"].double
            else { throw SQLiteError.execute("Invalid inventory row") }
            return ResourceAmount(
                resourceID: resourceID,
                quantity: quantity,
                observedAt: observedAt,
                confidence: try Confidence(confidenceValue)
            )
        }
        return Inventory(profileID: profileID, resources: resources)
    }

    public func storageProfile() throws -> StorageProfile? {
        guard let row = try database.query("SELECT * FROM storage_profiles ORDER BY profile_id LIMIT 1").first else {
            return nil
        }
        guard
            let pokemonUsed = row["pokemon_used"].int,
            let pokemonCapacity = row["pokemon_capacity"].int,
            let bagUsed = row["bag_used"].int,
            let bagCapacity = row["bag_capacity"].int,
            let observedString = row["observed_at"].string,
            let observedAt = parseDate(observedString)
        else { throw SQLiteError.execute("Invalid storage profile row") }
        return StorageProfile(
            pokemonUsed: pokemonUsed,
            pokemonCapacity: pokemonCapacity,
            bagUsed: bagUsed,
            bagCapacity: bagCapacity,
            observedAt: observedAt
        )
    }

    public func buildPlans() throws -> [BuildPlan] {
        try database.query("SELECT * FROM build_plans ORDER BY created_at, id").map { row in
            guard
                let idString = row["id"].string, let id = UUID(uuidString: idString),
                let pokemonIDString = row["pokemon_id"].string, let pokemonID = UUID(uuidString: pokemonIDString),
                let title = row["title"].string,
                let stepsJSON = row["steps_json"].string,
                let createdString = row["created_at"].string, let createdAt = parseDate(createdString)
            else { throw SQLiteError.execute("Invalid build plan row") }
            return BuildPlan(
                id: id,
                pokemonID: pokemonID,
                title: title,
                steps: try decode([BuildPlanStep].self, from: stepsJSON),
                createdAt: createdAt
            )
        }
    }

    public func restoreEmptyDatabase(from backup: UserBackup) throws {
        try database.transaction {
            let occupied = try [
                "pokemon", "observations", "collection_history", "resources", "storage_profiles", "build_plans",
            ]
            .reduce(0) { count, table in count + (try database.scalarInt("SELECT COUNT(*) FROM \(table)")) }
            guard occupied == 0 else { throw CollectionEngineError.restoreRequiresEmptyDatabase }
            try database.execute("DELETE FROM profiles")
            try ensureProfile(backup.profile)
            for aggregate in backup.collection {
                try insertPokemon(aggregate.pokemon, profileID: backup.profile.id)
                try replaceAssociations(for: aggregate.pokemon)
                for session in aggregate.scanSessions { try insertSession(session) }
                for observation in aggregate.observations { try insertObservation(observation) }
                for event in aggregate.history { try insertHistory(event) }
            }
            if let inventory = backup.inventory {
                for resource in inventory.resources {
                    try database.execute(
                        """
                        INSERT INTO resources(profile_id, resource_id, quantity, observed_at, confidence)
                        VALUES(?, ?, ?, ?, ?)
                        """,
                        bindings: [
                            .text(backup.profile.id.uuidString), .text(resource.resourceID),
                            .integer(Int64(resource.quantity)), .text(dateString(resource.observedAt)),
                            .real(resource.confidence.value),
                        ]
                    )
                }
            }
            if let storage = backup.storageProfile {
                try database.execute(
                    """
                    INSERT INTO storage_profiles(
                      profile_id, pokemon_used, pokemon_capacity, bag_used, bag_capacity, observed_at
                    ) VALUES(?, ?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        .text(backup.profile.id.uuidString), .integer(Int64(storage.pokemonUsed)),
                        .integer(Int64(storage.pokemonCapacity)), .integer(Int64(storage.bagUsed)),
                        .integer(Int64(storage.bagCapacity)), .text(dateString(storage.observedAt)),
                    ]
                )
            }
            for plan in backup.buildPlans {
                try database.execute(
                    """
                    INSERT INTO build_plans(
                      id, profile_id, pokemon_id, title, steps_json, created_at, updated_at
                    ) VALUES(?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        .text(plan.id.uuidString), .text(backup.profile.id.uuidString),
                        .text(plan.pokemonID.uuidString), .text(plan.title), .text(try encodeString(plan.steps)),
                        .text(dateString(plan.createdAt)), .text(dateString(plan.createdAt)),
                    ]
                )
            }
        }
    }

    private func insertPokemon(_ record: PokemonRecord, profileID: UUID) throws {
        try database.execute(
            """
            INSERT INTO pokemon(
              id, profile_id, species_id, form_id, fingerprint, nickname, cp, hp, level,
              iv_attack, iv_defense, iv_stamina, moves_json, traits_json, status,
              created_at, updated_at, archived_at, revision
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: try pokemonBindings(record, profileID: profileID)
        )
    }

    private func updatePokemon(_ record: PokemonRecord, expectedRevision: Int) throws {
        let movesJSON = try encodeString(record.moves)
        let traitsJSON = try encodeString(record.traits)
        try database.execute(
            """
            UPDATE pokemon SET
              species_id = ?, form_id = ?, fingerprint = ?, nickname = ?, cp = ?, hp = ?, level = ?,
              iv_attack = ?, iv_defense = ?, iv_stamina = ?, moves_json = ?, traits_json = ?, status = ?,
              updated_at = ?, archived_at = ?, revision = ?
            WHERE id = ? AND revision = ?
            """,
            bindings: [
                .text(record.identity.speciesID), .text(record.identity.formID), value(record.identity.fingerprint),
                value(record.nickname), value(record.cp), value(record.hp), value(record.level),
                value(record.ivs?.attack), value(record.ivs?.defense), value(record.ivs?.stamina),
                .text(movesJSON), .text(traitsJSON),
                .text(record.status.rawValue),
                .text(dateString(record.updatedAt)),
                record.status.isArchived ? .text(dateString(record.updatedAt)) : .null,
                .integer(Int64(record.revision)), .text(record.identity.recordID.uuidString),
                .integer(Int64(expectedRevision)),
            ]
        )
    }

    private func pokemonBindings(_ record: PokemonRecord, profileID: UUID) throws -> [SQLiteValue] {
        let movesJSON = try encodeString(record.moves)
        let traitsJSON = try encodeString(record.traits)
        return [
            .text(record.identity.recordID.uuidString), .text(profileID.uuidString),
            .text(record.identity.speciesID), .text(record.identity.formID), value(record.identity.fingerprint),
            value(record.nickname), value(record.cp), value(record.hp), value(record.level),
            value(record.ivs?.attack), value(record.ivs?.defense), value(record.ivs?.stamina),
            .text(movesJSON), .text(traitsJSON),
            .text(record.status.rawValue),
            .text(dateString(record.createdAt)), .text(dateString(record.updatedAt)),
            record.status.isArchived ? .text(dateString(record.updatedAt)) : .null, .integer(Int64(record.revision)),
        ]
    }

    private func replaceAssociations(for record: PokemonRecord) throws {
        let id = record.identity.recordID.uuidString
        try database.execute("DELETE FROM pokemon_tags WHERE pokemon_id = ?", bindings: [.text(id)])
        try database.execute("DELETE FROM pokemon_internal_tags WHERE pokemon_id = ?", bindings: [.text(id)])
        try database.execute("DELETE FROM pokemon_roles WHERE pokemon_id = ?", bindings: [.text(id)])
        try database.execute("DELETE FROM recommended_go_tags WHERE pokemon_id = ?", bindings: [.text(id)])
        for tag in record.appliedGOTags.sorted() {
            try database.execute(
                "INSERT INTO pokemon_tags(pokemon_id, tag, observed_at) VALUES(?, ?, ?)",
                bindings: [.text(id), .text(tag), .text(dateString(record.updatedAt))]
            )
        }
        for tag in record.internalTags.sorted() {
            try database.execute(
                "INSERT INTO pokemon_internal_tags(pokemon_id, tag, created_at) VALUES(?, ?, ?)",
                bindings: [.text(id), .text(tag), .text(dateString(record.updatedAt))]
            )
        }
        for role in record.roles.map(\.rawValue).sorted() {
            try database.execute(
                "INSERT INTO pokemon_roles(pokemon_id, role, assigned_at) VALUES(?, ?, ?)",
                bindings: [.text(id), .text(role), .text(dateString(record.updatedAt))]
            )
        }
        for recommendation in record.recommendedGOTags.sorted(by: { $0.tag.rawValue < $1.tag.rawValue }) {
            try database.execute(
                """
                INSERT INTO recommended_go_tags(
                  pokemon_id, tag, recommendation_state, reason, appears_applied,
                  user_confirmation, created_at, updated_at, source_version
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(id), .text(recommendation.tag.rawValue), .text(recommendation.state.rawValue),
                    .text(recommendation.reason), .integer(recommendation.appearsApplied ? 1 : 0),
                    .text(recommendation.userConfirmation.rawValue), .text(dateString(recommendation.createdAt)),
                    .text(dateString(recommendation.updatedAt)), .text(recommendation.sourceVersion),
                ]
            )
        }
    }

    private func insertSession(_ session: ScanSession) throws {
        try database.execute(
            """
            INSERT INTO scan_sessions(id, source, candidate_pokemon_id, status, started_at, ended_at)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            bindings: [
                .text(session.id.uuidString), .text(session.source.rawValue),
                value(session.candidateRecordID?.uuidString),
                .text(session.status.rawValue), .text(dateString(session.startedAt)),
                value(session.endedAt.map(dateString)),
            ]
        )
    }

    private func insertObservation(_ observation: PokemonObservation) throws {
        try database.execute(
            """
            INSERT INTO observations(id, scan_session_id, observed_at, fields_json, pokemon_id, provenance_json)
            VALUES(?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(observation.id.uuidString), .text(observation.scanSessionID.uuidString),
                .text(dateString(observation.observedAt)), .text(try encodeString(observation)),
                value(observation.pokemonID?.uuidString), .text(try observationProvenanceJSON(observation)),
            ]
        )
    }

    private func insertHistory(_ event: CollectionHistoryEvent) throws {
        let provenanceValue: SQLiteValue
        if let provenance = event.provenance {
            provenanceValue = .text(try encodeString(provenance))
        } else {
            provenanceValue = .null
        }
        try database.execute(
            """
            INSERT INTO collection_history(
              id, pokemon_id, event_type, occurred_at, payload_json, reason, source,
              changes_json, provenance_json, correlation_id
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.id.uuidString), .text(event.pokemonID.uuidString), .text(event.type.rawValue),
                .text(dateString(event.occurredAt)), .text(try encodeString(event)), value(event.reason),
                .text(event.source), .text(try encodeString(event.changes)),
                provenanceValue,
                .text(event.correlationID.uuidString),
            ]
        )
    }

    private func hydrate(_ row: SQLiteRow) throws -> PokemonRecord {
        guard
            let idString = row["id"].string, let id = UUID(uuidString: idString),
            let speciesID = row["species_id"].string,
            let formID = row["form_id"].string,
            let movesJSON = row["moves_json"].string,
            let traitsJSON = row["traits_json"].string,
            let statusString = row["status"].string, let status = CollectionStatus(rawValue: statusString),
            let createdString = row["created_at"].string, let createdAt = parseDate(createdString),
            let updatedString = row["updated_at"].string, let updatedAt = parseDate(updatedString)
        else { throw SQLiteError.execute("Invalid Pokémon row") }

        let ivs: IVs?
        if let attack = row["iv_attack"].int, let defense = row["iv_defense"].int, let stamina = row["iv_stamina"].int {
            ivs = try IVs(attack: attack, defense: defense, stamina: stamina)
        } else {
            ivs = nil
        }
        let pokemonID = id.uuidString
        let applied = try stringSet(
            "SELECT tag FROM pokemon_tags WHERE pokemon_id = ? ORDER BY tag", id: pokemonID, column: "tag")
        let internalTags = try stringSet(
            "SELECT tag FROM pokemon_internal_tags WHERE pokemon_id = ? ORDER BY tag", id: pokemonID, column: "tag")
        let roleStrings = try stringSet(
            "SELECT role FROM pokemon_roles WHERE pokemon_id = ? ORDER BY role", id: pokemonID, column: "role")
        let roles = Set(roleStrings.compactMap(PokemonRole.init(rawValue:)))
        let recommendations = try database.query(
            "SELECT * FROM recommended_go_tags WHERE pokemon_id = ? ORDER BY tag",
            bindings: [.text(pokemonID)]
        ).map(decodeRecommendation)
        return PokemonRecord(
            identity: PokemonIdentity(
                recordID: id, speciesID: speciesID, formID: formID, fingerprint: row["fingerprint"].string),
            nickname: row["nickname"].string,
            cp: row["cp"].int,
            hp: row["hp"].int,
            level: row["level"].double,
            ivs: ivs,
            moves: try decode(MoveSet.self, from: movesJSON),
            traits: try decode(Set<PokemonTrait>.self, from: traitsJSON),
            appliedGOTags: applied,
            internalTags: internalTags,
            roles: roles,
            recommendedGOTags: recommendations,
            status: status,
            revision: row["revision"].int ?? 1,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeRecommendation(_ row: SQLiteRow) throws -> RecommendedGOTag {
        guard
            let tagString = row["tag"].string, let tag = GOTag(rawValue: tagString),
            let stateString = row["recommendation_state"].string,
            let state = TagRecommendationState(rawValue: stateString),
            let reason = row["reason"].string,
            let confirmationString = row["user_confirmation"].string,
            let confirmation = UserConfirmationState(rawValue: confirmationString),
            let createdString = row["created_at"].string, let createdAt = parseDate(createdString),
            let updatedString = row["updated_at"].string, let updatedAt = parseDate(updatedString),
            let sourceVersion = row["source_version"].string
        else { throw SQLiteError.execute("Invalid recommended tag row") }
        return RecommendedGOTag(
            tag: tag,
            state: state,
            reason: reason,
            appearsApplied: row["appears_applied"].int == 1,
            userConfirmation: confirmation,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourceVersion: sourceVersion
        )
    }

    private func loadSession(_ id: UUID) throws -> ScanSession {
        guard
            let row = try database.query(
                "SELECT * FROM scan_sessions WHERE id = ?", bindings: [.text(id.uuidString)]
            ).first,
            let sourceString = row["source"].string, let source = ScanSource(rawValue: sourceString),
            let statusString = row["status"].string, let status = ScanSessionStatus(rawValue: statusString),
            let startedString = row["started_at"].string, let startedAt = parseDate(startedString)
        else { throw SQLiteError.execute("Invalid scan session row") }
        return ScanSession(
            id: id,
            source: source,
            candidateRecordID: row["candidate_pokemon_id"].string.flatMap(UUID.init(uuidString:)),
            status: status,
            startedAt: startedAt,
            endedAt: row["ended_at"].string.flatMap(parseDate)
        )
    }

    private func stringSet(_ sql: String, id: String, column: String) throws -> Set<String> {
        Set(try database.query(sql, bindings: [.text(id)]).compactMap { $0[column].string })
    }

    private func observationProvenanceJSON(_ observation: PokemonObservation) throws -> String {
        let values: [FieldProvenance] = [
            observation.speciesID?.provenance, observation.formID?.provenance,
            observation.cp?.provenance, observation.hp?.provenance,
            observation.ivAttack?.provenance, observation.ivDefense?.provenance,
            observation.ivStamina?.provenance, observation.ivs?.provenance,
            observation.moves?.provenance, observation.traits?.provenance,
        ].compactMap { $0 }
        return try encodeString(values)
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        guard let result = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw SQLiteError.execute("Unable to encode JSON")
        }
        return result
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else { throw SQLiteError.execute("Invalid UTF-8 JSON") }
        return try decoder.decode(type, from: data)
    }

    private func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private func value(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }
    private func value(_ value: Int?) -> SQLiteValue { value.map { .integer(Int64($0)) } ?? .null }
    private func value(_ value: Double?) -> SQLiteValue { value.map(SQLiteValue.real) ?? .null }
}
