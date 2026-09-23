import GOCompanionKnowledge
import Testing

@Test func pvpRankingEnumeratesAllIVsAndIsDeterministic() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    let form = try #require(dataset.speciesForm(.init(speciesID: "titan", formID: "normal")))
    let league = LeagueConfiguration(
        leagueID: "fixture-500", combatPowerCap: 500, maximumLevel: try PokemonLevel(3),
        allowsXL: true, allowsBestBuddy: true)
    let first = try PvPIVRanker().rank(
        speciesForm: form, league: league, multipliers: dataset.cpMultipliers,
        knowledgeVersion: dataset.normalizedVersion)
    let second = try PvPIVRanker().rank(
        speciesForm: form, league: league, multipliers: dataset.cpMultipliers,
        knowledgeVersion: dataset.normalizedVersion)
    #expect(first.entries.count == 4_096)
    #expect(first == second)
    #expect(first.entries.map(\.rank) == Array(1...4_096))
    #expect(first.entries[0].percentageOfRankOne == 100)
    #expect(first.entries[0].statProduct >= first.entries[1].statProduct)
}

@Test func standardLeaguesMasterAndArbitraryCapsAreRepresentable() throws {
    let max = try PokemonLevel(2.5)
    #expect(LeagueConfiguration.great(maximumLevel: max).combatPowerCap == 1_500)
    #expect(LeagueConfiguration.ultra(maximumLevel: max).combatPowerCap == 2_500)
    #expect(LeagueConfiguration.master(maximumLevel: max).combatPowerCap == nil)
    let custom = LeagueConfiguration(
        leagueID: "little", combatPowerCap: 500, maximumLevel: max, allowsXL: false)
    #expect(custom.combatPowerCap == 500)
    #expect(!custom.allowsXL)
}

@Test func greatUltraAndMasterConfigurationsProduceCompleteRankings() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    let titan = try #require(dataset.speciesForm(.init(speciesID: "titan", formID: "normal")))
    let maximum = try PokemonLevel(3)
    let leagues = [
        LeagueConfiguration.great(maximumLevel: maximum),
        LeagueConfiguration.ultra(maximumLevel: maximum),
        LeagueConfiguration.master(maximumLevel: maximum),
    ]
    for league in leagues {
        let table = try PvPIVRanker().rank(
            speciesForm: titan, league: league, multipliers: dataset.cpMultipliers,
            knowledgeVersion: dataset.normalizedVersion)
        #expect(table.entries.count == 4_096)
        if let cap = league.combatPowerCap {
            #expect(table.entries.allSatisfy { $0.combatPower <= cap })
        }
    }
}

@Test func highestLegalLevelTracksXLAndBestBuddyRules() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    let seedling = try #require(dataset.speciesForm(.init(speciesID: "seedling", formID: "normal")))
    let ranker = PvPIVRanker()
    let withoutBuddy = try ranker.rank(
        speciesForm: seedling,
        league: .init(
            leagueID: "uncapped-no-buddy", combatPowerCap: nil, maximumLevel: PokemonLevel(3),
            allowsXL: true, allowsBestBuddy: false),
        multipliers: dataset.cpMultipliers,
        knowledgeVersion: dataset.normalizedVersion)
    let xlLevel = try PokemonLevel(2.5)
    #expect(withoutBuddy.entries.allSatisfy { $0.level == xlLevel })
    #expect(withoutBuddy.entries.allSatisfy { $0.requiresXL })
    #expect(withoutBuddy.entries.allSatisfy { !$0.bestBuddyLevel })

    let withBuddy = try ranker.rank(
        speciesForm: seedling,
        league: .init(
            leagueID: "uncapped-buddy", combatPowerCap: nil, maximumLevel: PokemonLevel(3),
            allowsXL: true, allowsBestBuddy: true),
        multipliers: dataset.cpMultipliers,
        knowledgeVersion: dataset.normalizedVersion)
    let buddyLevel = try PokemonLevel(3)
    #expect(withBuddy.entries.allSatisfy { $0.level == buddyLevel })
    #expect(withBuddy.entries.allSatisfy { $0.bestBuddyLevel })
}

@Test func deterministicTieBreakProducesStableUniqueOrder() throws {
    let dataset = try KnowledgeTestContext.fixtureDataset()
    let tiny = try #require(dataset.speciesForm(.init(speciesID: "tiny", formID: "normal")))
    let table = try PvPIVRanker().rank(
        speciesForm: tiny,
        league: .init(
            leagueID: "tie", combatPowerCap: 10, maximumLevel: PokemonLevel(1),
            allowsXL: false),
        multipliers: dataset.cpMultipliers,
        knowledgeVersion: dataset.normalizedVersion)
    #expect(table.entries.count == 4_096)
    #expect(Set(table.entries.map(\.ivs)).count == 4_096)
    #expect(table.entries.map(\.rank) == Array(1...4_096))
}
