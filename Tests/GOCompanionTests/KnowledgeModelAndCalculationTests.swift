import Foundation
import GOCompanionKnowledge
import Testing

@Test func syntheticFixtureCoversCanonicalKnowledgeAndIntegrity() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    try KnowledgeValidator.validate(dataset)
    #expect(dataset.speciesForms.count == 6)
    #expect(dataset.speciesForms.filter { $0.id.speciesID == "shellmon" }.count == 2)
    #expect(dataset.evolutions.count == 1)
    #expect(dataset.moves.contains { $0.kind == .fast })
    #expect(dataset.moves.contains { $0.kind == .charged && $0.pvp.buffChance > 0 })
    #expect(dataset.movePools.contains { $0.availability == .legacy })
    #expect(dataset.speciesForms.contains { $0.capabilities.gigantamax })
    #expect(dataset.cpMultipliers.contains { $0.requiresXL })
    #expect(dataset.cpMultipliers.contains { $0.bestBuddyOnly })
}

@Test func invalidFixtureFailsSemanticValidation() throws {
    let data = try KnowledgeTestContext.fixtureData("synthetic_knowledge_invalid")
    let dataset = try JSONDecoder().decode(KnowledgeDataset.self, from: data)
    #expect(throws: KnowledgeError.self) { try KnowledgeValidator.validate(dataset) }
}

@Test func validatorRejectsDanglingMoveReference() throws {
    let first = try KnowledgeTestContext.fixtureDataset()
    let broken = KnowledgeDataset(
        normalizedVersion: "dangling-move",
        types: first.types,
        speciesForms: first.speciesForms,
        evolutions: first.evolutions,
        moves: first.moves,
        movePools: [
            MovePoolEntry(
                speciesForm: first.speciesForms[0].id,
                moveID: "missing-move",
                availability: .current)
        ],
        cpMultipliers: first.cpMultipliers
    )
    #expect(throws: KnowledgeError.self) { try KnowledgeValidator.validate(broken) }
}

@Test func combatPowerAndHitPointsUsePokemonGOFloorRules() throws {
    let level = try PokemonLevel(2)
    let engine = CombatPowerEngine(
        multipliers: [CPMultiplier(level: level, multiplier: 0.5)])
    let stats = try engine.stats(
        base: BaseStats(attack: 100, defense: 100, stamina: 100),
        ivs: IndividualValues(attack: 0, defense: 0, stamina: 0),
        level: level
    )
    #expect(stats.combatPower == 250)
    #expect(stats.hitPoints == 50)
}

@Test func combatPowerFloorAndReverseResolutionReturnEveryCandidate() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    let tiny = try #require(dataset.speciesForm(.init(speciesID: "tiny", formID: "normal")))
    let ivs = try IndividualValues(attack: 0, defense: 0, stamina: 0)
    let engine = CombatPowerEngine(multipliers: dataset.cpMultipliers)
    let low = try engine.stats(base: tiny.baseStats, ivs: ivs, level: PokemonLevel(1))
    #expect(low.combatPower == 10)
    #expect(low.hitPoints == 10)
    let matches = try engine.levels(matchingCombatPower: 10, base: tiny.baseStats, ivs: ivs)
    #expect(matches.count == dataset.cpMultipliers.count)
    #expect(matches.map(\.level) == dataset.cpMultipliers.map(\.level))
}

@Test func calculationRejectsInvalidIVAndUnknownLevel() throws {
    #expect(throws: KnowledgeError.invalidIV(16)) {
        _ = try IndividualValues(attack: 16, defense: 0, stamina: 0)
    }
    let engine = CombatPowerEngine(multipliers: [])
    #expect(throws: KnowledgeError.self) {
        _ = try engine.stats(
            base: BaseStats(attack: 1, defense: 1, stamina: 1),
            ivs: IndividualValues(attack: 0, defense: 0, stamina: 0),
            level: PokemonLevel(1))
    }
}
