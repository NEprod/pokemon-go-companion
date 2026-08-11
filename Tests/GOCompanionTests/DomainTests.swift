import Foundation
import GOCompanionDomain
import Testing

@Test func confidenceRejectsOutOfRangeValues() {
    #expect(throws: DomainError.invalidConfidence(1.1)) {
        _ = try Confidence(1.1)
    }
}

@Test func ivsAcceptEveryLegalBoundary() throws {
    let minimum = try IVs(attack: 0, defense: 0, stamina: 0)
    let maximum = try IVs(attack: 15, defense: 15, stamina: 15)
    #expect(minimum.attack == 0)
    #expect(maximum.stamina == 15)
    #expect(throws: DomainError.self) {
        _ = try IVs(attack: 16, defense: 0, stamina: 0)
    }
}

@Test func recommendationCarriesVersionsAndIsNotAStoredPokemonFact() throws {
    let pokemon = PokemonRecord(identity: PokemonIdentity(speciesID: "lanturn", formID: "normal"))
    let recommendation = Recommendation(
        subjectID: pokemon.identity.recordID,
        action: .keep,
        recommendedTags: [.greatLeague],
        reasons: [.init(code: "pvp.iv", summary: "Strong Great League IV spread")],
        nextAction: "Review build cost",
        confidence: try Confidence(0.99),
        provenance: .init(
            knowledgeVersions: [.init(category: "pvp", sourceVersion: "fixture-v1", activatedAt: .now)],
            engineVersion: "phase0-test",
            generatedAt: .now
        )
    )
    #expect(recommendation.subjectID == pokemon.identity.recordID)
    #expect(recommendation.provenance.engineVersion == "phase0-test")
    #expect(pokemon.appliedGOTags.isEmpty)
}

@Test func fixtureCoversRequiredRepresentativeCases() throws {
    let url = try #require(Bundle.module.url(forResource: "pokemon_records", withExtension: "json"))
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let records = try #require(object as? [[String: Any]])
    let names = Set(records.compactMap { $0["fixture"] as? String })
    #expect(records.count == 12)
    #expect(
        names.isSuperset(of: [
            "normal", "master-league", "pvp-iv", "shadow", "dynamax", "gigantamax", "mega-capable", "mega-unlocked",
            "poor-moves", "elite-tm", "transfer", "trade",
        ]))
}
