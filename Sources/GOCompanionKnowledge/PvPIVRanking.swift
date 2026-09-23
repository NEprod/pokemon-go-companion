import Foundation

public struct LeagueConfiguration: Codable, Hashable, Sendable {
    public let leagueID: String
    public let combatPowerCap: Int?
    public let maximumLevel: PokemonLevel
    public let allowsXL: Bool
    public let allowsBestBuddy: Bool

    public init(
        leagueID: String, combatPowerCap: Int?, maximumLevel: PokemonLevel,
        allowsXL: Bool = true, allowsBestBuddy: Bool = false
    ) {
        self.leagueID = leagueID
        self.combatPowerCap = combatPowerCap
        self.maximumLevel = maximumLevel
        self.allowsXL = allowsXL
        self.allowsBestBuddy = allowsBestBuddy
    }

    public static func great(maximumLevel: PokemonLevel) -> Self {
        .init(leagueID: "great", combatPowerCap: 1_500, maximumLevel: maximumLevel)
    }

    public static func ultra(maximumLevel: PokemonLevel) -> Self {
        .init(leagueID: "ultra", combatPowerCap: 2_500, maximumLevel: maximumLevel)
    }

    public static func master(maximumLevel: PokemonLevel) -> Self {
        .init(leagueID: "master", combatPowerCap: nil, maximumLevel: maximumLevel)
    }
}

public struct PvPIVRankEntry: Codable, Hashable, Sendable {
    public let rank: Int
    public let ivs: IndividualValues
    public let level: PokemonLevel
    public let combatPower: Int
    public let hitPoints: Int
    public let attack: Double
    public let defense: Double
    public let statProduct: Double
    public let percentageOfRankOne: Double
    public let requiresXL: Bool
    public let bestBuddyLevel: Bool
}

public struct PvPIVRankingTable: Codable, Hashable, Sendable {
    public let speciesForm: SpeciesFormID
    public let league: LeagueConfiguration
    public let knowledgeVersion: String
    public let engineVersion: String
    public let entries: [PvPIVRankEntry]
}

public struct PvPIVRanker: Sendable {
    public static let engineVersion = "pvp-iv-product-v1+\(CombatPowerEngine.version)"

    public init() {}

    public func rank(
        speciesForm: SpeciesFormKnowledge,
        league: LeagueConfiguration,
        multipliers: [CPMultiplier],
        knowledgeVersion: String
    ) throws -> PvPIVRankingTable {
        let eligibleLevels = multipliers.filter {
            $0.level <= league.maximumLevel && (league.allowsXL || !$0.requiresXL)
                && (league.allowsBestBuddy || !$0.bestBuddyOnly)
        }
        guard !eligibleLevels.isEmpty else {
            throw KnowledgeError.invalidDataset("league rules contain no eligible levels")
        }
        let cpEngine = CombatPowerEngine(multipliers: eligibleLevels)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(4_096)

        for attack in 0...15 {
            for defense in 0...15 {
                for stamina in 0...15 {
                    let ivs = try IndividualValues(attack: attack, defense: defense, stamina: stamina)
                    var best: (CPMultiplier, CombatStats)?
                    for multiplier in eligibleLevels {
                        let stats = try cpEngine.stats(
                            base: speciesForm.baseStats, ivs: ivs, level: multiplier.level)
                        if let cap = league.combatPowerCap, stats.combatPower > cap { continue }
                        if best == nil || multiplier.level > best!.0.level { best = (multiplier, stats) }
                    }
                    guard let best else { continue }
                    candidates.append(
                        Candidate(
                            ivs: ivs,
                            multiplier: best.0,
                            stats: best.1,
                            statProduct: best.1.attack * best.1.defense * Double(best.1.hitPoints)
                        ))
                }
            }
        }

        guard candidates.count == 4_096 else {
            throw KnowledgeError.invalidDataset(
                "league cap and level rules do not admit all 4,096 IV spreads for \(speciesForm.id)"
            )
        }
        candidates.sort(by: Self.precedes)
        let bestProduct = candidates.first?.statProduct ?? 0
        let entries = candidates.enumerated().map { offset, candidate in
            PvPIVRankEntry(
                rank: offset + 1,
                ivs: candidate.ivs,
                level: candidate.multiplier.level,
                combatPower: candidate.stats.combatPower,
                hitPoints: candidate.stats.hitPoints,
                attack: candidate.stats.attack,
                defense: candidate.stats.defense,
                statProduct: candidate.statProduct,
                percentageOfRankOne: bestProduct == 0 ? 0 : candidate.statProduct / bestProduct * 100,
                requiresXL: candidate.multiplier.requiresXL,
                bestBuddyLevel: candidate.multiplier.bestBuddyOnly
            )
        }
        return PvPIVRankingTable(
            speciesForm: speciesForm.id,
            league: league,
            knowledgeVersion: knowledgeVersion,
            engineVersion: Self.engineVersion,
            entries: entries
        )
    }

    /// Deterministic ties: product, attack, defense, HP, lower level, then A/D/S IV lexicographically.
    private static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.statProduct != rhs.statProduct { return lhs.statProduct > rhs.statProduct }
        if lhs.stats.attack != rhs.stats.attack { return lhs.stats.attack > rhs.stats.attack }
        if lhs.stats.defense != rhs.stats.defense { return lhs.stats.defense > rhs.stats.defense }
        if lhs.stats.hitPoints != rhs.stats.hitPoints { return lhs.stats.hitPoints > rhs.stats.hitPoints }
        if lhs.multiplier.level != rhs.multiplier.level { return lhs.multiplier.level < rhs.multiplier.level }
        if lhs.ivs.attack != rhs.ivs.attack { return lhs.ivs.attack < rhs.ivs.attack }
        if lhs.ivs.defense != rhs.ivs.defense { return lhs.ivs.defense > rhs.ivs.defense }
        return lhs.ivs.stamina > rhs.ivs.stamina
    }

    private struct Candidate {
        let ivs: IndividualValues
        let multiplier: CPMultiplier
        let stats: CombatStats
        let statProduct: Double
    }
}

public struct PvPIVRankingService: Sendable {
    private let knowledge: any KnowledgeStore
    private let cache: any DerivedAnalysisCache

    public init(knowledge: any KnowledgeStore, cache: any DerivedAnalysisCache) {
        self.knowledge = knowledge
        self.cache = cache
    }

    public func ranking(for id: SpeciesFormID, league: LeagueConfiguration) async throws -> PvPIVRankingTable {
        guard let dataset = try await knowledge.activeDataset(category: .gameMaster) else {
            throw KnowledgeError.noActiveKnowledge(.gameMaster)
        }
        guard let form = dataset.speciesForm(id) else { throw KnowledgeError.unknownSpeciesForm(id) }
        let key = Self.cacheKey(
            speciesForm: id, league: league, knowledgeVersion: dataset.normalizedVersion)
        if let cached = try await cache.data(for: key) {
            return try JSONDecoder().decode(PvPIVRankingTable.self, from: cached)
        }
        let table = try PvPIVRanker().rank(
            speciesForm: form,
            league: league,
            multipliers: dataset.cpMultipliers,
            knowledgeVersion: dataset.normalizedVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try await cache.store(try encoder.encode(table), for: key)
        return table
    }

    public static func cacheKey(
        speciesForm: SpeciesFormID, league: LeagueConfiguration, knowledgeVersion: String
    ) -> DerivedCacheKey {
        let cap = league.combatPowerCap.map(String.init) ?? "uncapped"
        let subject = [
            speciesForm.description, league.leagueID, "cap=\(cap)",
            "maxHalfSteps=\(league.maximumLevel.halfSteps)", "xl=\(league.allowsXL)",
            "buddy=\(league.allowsBestBuddy)",
        ].joined(separator: "|")
        return DerivedCacheKey(
            kind: "pvp-iv-ranking",
            subject: subject,
            inputVersions: ["gameMaster": knowledgeVersion],
            engineVersion: PvPIVRanker.engineVersion
        )
    }
}
