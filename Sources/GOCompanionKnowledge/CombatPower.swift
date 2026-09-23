import Foundation

public struct IndividualValues: Codable, Hashable, Sendable {
    public let attack: Int
    public let defense: Int
    public let stamina: Int

    public init(attack: Int, defense: Int, stamina: Int) throws {
        for value in [attack, defense, stamina] where !(0...15).contains(value) {
            throw KnowledgeError.invalidIV(value)
        }
        self.attack = attack
        self.defense = defense
        self.stamina = stamina
    }

    public var total: Int { attack + defense + stamina }
}

public struct CombatStats: Codable, Hashable, Sendable {
    public let combatPower: Int
    public let hitPoints: Int
    public let attack: Double
    public let defense: Double
    public let stamina: Double
}

public struct LevelResolution: Codable, Hashable, Sendable {
    public let level: PokemonLevel
    public let stats: CombatStats
}

public struct CombatPowerEngine: Sendable {
    public static let version = "cp-hp-v1"
    private let multipliers: [PokemonLevel: CPMultiplier]

    public init(multipliers: [CPMultiplier]) {
        self.multipliers = Dictionary(uniqueKeysWithValues: multipliers.map { ($0.level, $0) })
    }

    public func stats(base: BaseStats, ivs: IndividualValues, level: PokemonLevel) throws -> CombatStats {
        guard base.attack > 0, base.defense > 0, base.stamina > 0 else {
            throw KnowledgeError.invalidDataset("base stats must be positive")
        }
        guard let cpm = multipliers[level]?.multiplier else { throw KnowledgeError.unknownLevel(level) }
        let attack = Double(base.attack + ivs.attack) * cpm
        let defense = Double(base.defense + ivs.defense) * cpm
        let stamina = Double(base.stamina + ivs.stamina) * cpm
        let rawCP =
            Double(base.attack + ivs.attack)
            * sqrt(Double(base.defense + ivs.defense))
            * sqrt(Double(base.stamina + ivs.stamina))
            * cpm * cpm / 10
        return CombatStats(
            combatPower: max(10, Int(floor(rawCP))),
            hitPoints: max(10, Int(floor(stamina))),
            attack: attack,
            defense: defense,
            stamina: stamina
        )
    }

    public func levels(
        matchingCombatPower combatPower: Int, base: BaseStats, ivs: IndividualValues,
        allowedLevels: ClosedRange<PokemonLevel>? = nil
    ) throws -> [LevelResolution] {
        try multipliers.keys.sorted().compactMap { level in
            guard allowedLevels?.contains(level) ?? true else { return nil }
            let result = try stats(base: base, ivs: ivs, level: level)
            return result.combatPower == combatPower ? LevelResolution(level: level, stats: result) : nil
        }
    }
}
