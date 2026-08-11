import Foundation
import GOCompanionApplication
import GOCompanionDomain
import GOCompanionPersistence
import Testing

@Test func createRetrieveUpdateAndUUIDStability() throws {
    let context = try CollectionTestContext()
    let id = UUID()
    let created = try context.service.create(context.pokemon(id: id))
    #expect(created.identity.recordID == id)
    #expect(try context.service.pokemon(id: id) == created)

    var revised = created
    revised.cp = 801
    revised.nickname = "Sparky"
    revised.traits = [.shiny, .lucky]
    revised.roles = [.greatLeague, .raid]
    revised.internalTags = ["favourite-build", "compare-later"]
    revised.appliedGOTags = ["GL", "Raid"]
    let updated = try context.service.update(revised, reason: "Manual correction")

    #expect(updated.identity.recordID == id)
    #expect(updated.cp == 801)
    #expect(updated.revision == 2)
    #expect(try context.service.pokemon(id: id).traits == [.shiny, .lucky])
    #expect(try context.service.pokemon(id: id).appliedGOTags == ["GL", "Raid"])
    #expect(try context.service.history(for: id).map(\.type) == [.created, .updated])
    #expect(try context.service.history(for: id).last?.changes.contains { $0.field == "cp" } == true)
}

@Test func duplicateCreationIsRejectedWithoutAppendingHistory() throws {
    let context = try CollectionTestContext()
    let record = context.pokemon()
    _ = try context.service.create(record)
    #expect(throws: CollectionEngineError.duplicatePokemon(record.identity.recordID)) {
        _ = try context.service.create(record)
    }
    #expect(try context.service.list(.active).count == 1)
    #expect(try context.service.history(for: record.identity.recordID).map(\.type) == [.created])
}

@Test func staleUpdatesAreRejectedWithoutOverwritingCurrentState() throws {
    let context = try CollectionTestContext()
    let original = try context.service.create(context.pokemon())
    var first = original
    first.cp = 800
    _ = try context.service.update(first, reason: "First edit")
    var stale = original
    stale.cp = 900
    #expect(throws: CollectionEngineError.self) {
        _ = try context.service.update(stale, reason: "Stale edit")
    }
    #expect(try context.service.pokemon(id: original.identity.recordID).cp == 800)
}

@Test func transferLifecycleSeparatesAdviceConfirmationAndArchive() throws {
    let context = try CollectionTestContext()
    let created = try context.service.create(context.pokemon())
    let recommended = try context.service.markTransferRecommended(
        id: created.identity.recordID,
        reason: "Fixture recommendation only",
        recommendationVersion: "phase1-fixture"
    )
    #expect(recommended.status == .pendingRemoval)
    #expect(recommended.recommendedGOTags.map(\.tag).contains(.transfer))
    #expect(try context.service.list(.active).map(\.identity.recordID).contains(created.identity.recordID))

    let archived = try context.service.confirmTransferred(id: created.identity.recordID)
    #expect(archived.status == .archivedTransferred)
    #expect(try context.service.list(.active).isEmpty)
    #expect(try context.service.list(.archived).map(\.identity.recordID) == [created.identity.recordID])

    let restored = try context.service.restoreArchived(id: created.identity.recordID, reason: "Incorrect confirmation")
    #expect(restored.status == .active)
    #expect(
        try context.service.history(for: created.identity.recordID).map(\.type) == [
            .created, .transferRecommended, .transferred, .restored,
        ])
}

@Test func tradeAndOtherArchiveLifecyclesRemainDistinct() throws {
    let context = try CollectionTestContext()
    let trade = try context.service.create(context.pokemon(species: "tauros"))
    _ = try context.service.markTradeRecommended(
        id: trade.identity.recordID,
        reason: "Regional trade fixture",
        recommendationVersion: "phase1-fixture"
    )
    #expect(try context.service.confirmTraded(id: trade.identity.recordID).status == .archivedTraded)

    let other = try context.service.create(context.pokemon(species: "missingno"))
    #expect(
        try context.service.archiveOther(id: other.identity.recordID, reason: "Fixture cleanup").status
            == .archivedOther)
    #expect(Set(try context.service.list(.archived).map(\.status)) == [.archivedTraded, .archivedOther])
}

@Test func collectionQueriesFilterTagsSpeciesFormsStatusAndPagination() throws {
    let context = try CollectionTestContext()
    let recommendation = RecommendedGOTag(
        tag: .greatLeague,
        reason: "Persisted structure fixture",
        appearsApplied: true,
        userConfirmation: .confirmedApplied,
        sourceVersion: "phase1-fixture"
    )
    _ = try context.service.create(
        context.pokemon(
            species: "charizard", form: "normal", cp: 1498,
            internalTags: ["candidate"], roles: [.greatLeague, .raid], recommended: [recommendation]
        ))
    _ = try context.service.create(context.pokemon(species: "charizard", form: "party_hat", cp: 500))
    _ = try context.service.create(context.pokemon(species: "venusaur", cp: 1500))

    #expect(try context.service.list(.init(speciesID: "charizard")).count == 2)
    #expect(try context.service.list(.init(speciesID: "charizard", formID: "party_hat")).count == 1)
    #expect(try context.service.list(.init(internalTag: "candidate")).count == 1)
    #expect(try context.service.list(.init(recommendedGOTag: .greatLeague)).count == 1)
    let tagged = try #require(try context.service.list(.init(recommendedGOTag: .greatLeague)).first)
    #expect(tagged.recommendedGOTags.first?.appearsApplied == true)
    #expect(tagged.recommendedGOTags.first?.userConfirmation == .confirmedApplied)
    #expect(try context.service.list(.init(sort: .cpDescending, limit: 2)).map(\.cp) == [1500, 1498])
    #expect(try context.service.list(.init(sort: .cpDescending, limit: 2, offset: 2)).map(\.cp) == [500])
}

@Test func observationsPreserveFieldConfidenceAndProvenance() throws {
    let context = try CollectionTestContext()
    let pokemon = try context.service.create(context.pokemon())
    let session = ScanSession(source: .manualEntry, candidateRecordID: pokemon.identity.recordID, status: .completed)
    var observation = PokemonObservation(scanSessionID: session.id, pokemonID: pokemon.identity.recordID)
    observation.speciesID = .manuallyConfirmed("pikachu", source: "user")
    observation.cp = Observed(
        value: 742,
        confidence: try Confidence(0.99),
        provenance: .init(kind: .imported, source: "fixture", sourceVersion: "1")
    )
    observation.moves = Observed(
        value: MoveSet(fastMoveID: "thunder_shock", chargedMove1ID: "wild_charge"),
        confidence: try Confidence(0.82),
        provenance: .init(kind: .scannerObserved, source: "future-scanner-fixture")
    )
    observation.ivAttack = .manuallyConfirmed(0, source: "appraisal-entry")
    observation.ivDefense = Observed(
        value: 15,
        confidence: try Confidence(0.98),
        provenance: .init(kind: .imported, source: "appraisal-fixture")
    )
    observation.ivStamina = Observed(
        value: 14,
        confidence: try Confidence(0.96),
        provenance: .init(kind: .scannerObserved, source: "future-scanner-fixture")
    )
    try context.service.recordObservation(session: session, observation: observation, source: "phase1-test")

    let restored = try #require(try context.service.observations(for: pokemon.identity.recordID).first)
    #expect(restored.speciesID?.confidence == nil)
    #expect(restored.speciesID?.provenance.kind == .manuallyConfirmed)
    #expect(restored.cp?.confidence?.value == 0.99)
    #expect(restored.cp?.provenance.kind == .imported)
    #expect(restored.moves?.confidence?.value == 0.82)
    #expect(restored.ivAttack?.confidence == nil)
    #expect(restored.ivDefense?.confidence?.value == 0.98)
    #expect(restored.ivStamina?.confidence?.value == 0.96)
}

@Test func historyIsOrderedAndDatabaseEnforcesImmutability() throws {
    let context = try CollectionTestContext()
    let pokemon = try context.service.create(context.pokemon())
    var revised = pokemon
    revised.cp = 800
    _ = try context.service.update(revised, reason: "Later change")
    let history = try context.service.history(for: pokemon.identity.recordID)
    #expect(history.map(\.type) == [.created, .updated])
    #expect(throws: SQLiteError.self) {
        try context.databases.user.execute("UPDATE collection_history SET reason = 'tampered'")
    }
    #expect(throws: SQLiteError.self) {
        try context.databases.user.execute("DELETE FROM collection_history")
    }
    #expect(try context.service.history(for: pokemon.identity.recordID).count == 2)
}

@Test func archiveTransactionRollsBackWhenHistoryAppendFails() throws {
    let context = try CollectionTestContext()
    let pokemon = try context.service.create(context.pokemon())
    _ = try context.service.markTransferRecommended(
        id: pokemon.identity.recordID,
        reason: "Rollback fixture",
        recommendationVersion: "phase1-fixture"
    )
    try context.databases.user.execute(
        """
        CREATE TEMP TRIGGER fail_transferred_history
        BEFORE INSERT ON collection_history WHEN NEW.event_type = 'transferred'
        BEGIN SELECT RAISE(ABORT, 'injected history failure'); END;
        """)
    #expect(throws: SQLiteError.self) {
        _ = try context.service.confirmTransferred(id: pokemon.identity.recordID)
    }
    #expect(try context.service.pokemon(id: pokemon.identity.recordID).status == .pendingRemoval)
    #expect(
        try context.service.history(for: pokemon.identity.recordID).map(\.type) == [.created, .transferRecommended])
}
