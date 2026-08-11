import Foundation
import GOCompanionApplication
import GOCompanionDomain
import GOCompanionPersistence
import Testing

@Test func jsonBackupAndRestorePreserveCollectionEvidenceAndUUIDs() throws {
    let source = try CollectionTestContext()
    let recommendation = RecommendedGOTag(
        tag: .hold,
        reason: "Wait for fixture event",
        sourceVersion: "phase1-fixture"
    )
    let pokemon = try source.service.create(
        source.pokemon(
            species: "eevee",
            traits: [.shiny, .lucky],
            internalTags: ["event-hold"],
            roles: [.ultraLeague, .futureEventHold],
            recommended: [recommendation]
        ))
    let session = ScanSession(
        source: .screenshotImport, candidateRecordID: pokemon.identity.recordID, status: .completed)
    var observation = PokemonObservation(scanSessionID: session.id, pokemonID: pokemon.identity.recordID)
    observation.cp = Observed(
        value: 742,
        confidence: try Confidence(0.97),
        provenance: .init(kind: .imported, source: "synthetic-fixture")
    )
    try source.service.recordObservation(session: session, observation: observation, source: "synthetic-fixture")
    try source.databases.user.execute(
        "INSERT INTO resources(profile_id, resource_id, quantity, observed_at, confidence) VALUES(?, ?, ?, ?, ?)",
        bindings: [
            .text(source.profile.id.uuidString), .text("stardust"), .integer(123_456),
            .text("2023-11-14T22:13:20Z"), .real(1),
        ]
    )
    try source.databases.user.execute(
        """
        INSERT INTO storage_profiles(profile_id, pokemon_used, pokemon_capacity, bag_used, bag_capacity, observed_at)
        VALUES(?, 1400, 1500, 2300, 2500, ?)
        """,
        bindings: [.text(source.profile.id.uuidString), .text("2023-11-14T22:13:20Z")]
    )
    try source.databases.user.execute(
        """
        INSERT INTO build_plans(id, profile_id, pokemon_id, title, steps_json, created_at, updated_at)
        VALUES(?, ?, ?, 'Fixture build', ?, ?, ?)
        """,
        bindings: [
            .text(UUID().uuidString), .text(source.profile.id.uuidString), .text(pokemon.identity.recordID.uuidString),
            .text("[{\"action\":\"powerUp\",\"completed\":false,\"resourceCosts\":{\"stardust\":1000}}]"),
            .text("2023-11-14T22:13:20Z"), .text("2023-11-14T22:13:20Z"),
        ]
    )

    let data = try BackupService(repository: source.repository).exportJSON(exportedAt: source.timestamp)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"formatVersion\" : 1"))
    #expect(!json.localizedCaseInsensitiveContains("apiKey"))

    let target = try CollectionTestContext(createProfile: false)
    try BackupService(repository: target.repository).restoreJSON(data)
    let restored = try target.service.pokemon(id: pokemon.identity.recordID)
    #expect(restored.identity.recordID == pokemon.identity.recordID)
    #expect(restored.traits == [.shiny, .lucky])
    #expect(restored.roles == [.ultraLeague, .futureEventHold])
    #expect(restored.internalTags == ["event-hold"])
    #expect(restored.recommendedGOTags.map(\.tag) == [.hold])
    #expect(try target.service.observations(for: pokemon.identity.recordID).first?.cp?.confidence?.value == 0.97)
    #expect(try target.service.history(for: pokemon.identity.recordID).map(\.type) == [.created, .scanned])
    #expect(try target.repository.inventory()?.resources.first?.quantity == 123_456)
    #expect(try target.repository.storageProfile()?.bagCapacity == 2500)
    #expect(try target.repository.buildPlans().first?.pokemonID == pokemon.identity.recordID)
}

@Test func restoreRejectsMalformedIncompatibleAndDuplicateImports() throws {
    let empty = try CollectionTestContext(createProfile: false)
    let backupService = BackupService(repository: empty.repository)
    #expect(throws: CollectionEngineError.self) {
        try backupService.restoreJSON(Data("not-json".utf8))
    }

    let source = try CollectionTestContext()
    let pokemon = try source.service.create(source.pokemon())
    var object = try #require(
        JSONSerialization.jsonObject(with: BackupService(repository: source.repository).exportJSON()) as? [String: Any]
    )
    object["formatVersion"] = 999
    #expect(throws: CollectionEngineError.unsupportedBackupVersion(999)) {
        try backupService.restoreJSON(try JSONSerialization.data(withJSONObject: object))
    }
    object["formatVersion"] = 1
    object["userSchemaVersion"] = 999
    #expect(throws: CollectionEngineError.incompatibleUserSchemaVersion(exported: 999, supported: 2)) {
        try backupService.restoreJSON(try JSONSerialization.data(withJSONObject: object))
    }
    object["userSchemaVersion"] = 2
    let originalCollection = try #require(object["collection"] as? [[String: Any]])
    object["collection"] = originalCollection + originalCollection
    #expect(throws: CollectionEngineError.self) {
        try backupService.restoreJSON(try JSONSerialization.data(withJSONObject: object))
    }

    let nonEmpty = try CollectionTestContext()
    _ = try nonEmpty.service.create(nonEmpty.pokemon(species: "bulbasaur"))
    let validData = try BackupService(repository: source.repository).exportJSON()
    #expect(throws: CollectionEngineError.restoreRequiresEmptyDatabase) {
        try BackupService(repository: nonEmpty.repository).restoreJSON(validData)
    }
    #expect(try nonEmpty.service.list(.active).map(\.identity.speciesID) == ["bulbasaur"])
    #expect(try source.service.pokemon(id: pokemon.identity.recordID).identity.recordID == pokemon.identity.recordID)
}

@Test func restoreRollsBackCompletelyOnDatabaseFailure() throws {
    let source = try CollectionTestContext()
    _ = try source.service.create(source.pokemon(species: "pikachu"))
    _ = try source.service.create(source.pokemon(species: "failmon"))
    let data = try BackupService(repository: source.repository).exportJSON()

    let target = try CollectionTestContext(createProfile: false)
    try target.databases.user.execute(
        """
        CREATE TEMP TRIGGER fail_restore
        BEFORE INSERT ON pokemon WHEN NEW.species_id = 'failmon'
        BEGIN SELECT RAISE(ABORT, 'injected restore failure'); END;
        """)
    #expect(throws: SQLiteError.self) {
        try BackupService(repository: target.repository).restoreJSON(data)
    }
    #expect(try target.databases.user.scalarInt("SELECT COUNT(*) FROM pokemon") == 0)
    #expect(try target.databases.user.scalarInt("SELECT COUNT(*) FROM collection_history") == 0)
    #expect(try target.databases.user.scalarInt("SELECT COUNT(*) FROM profiles") == 0)
}
