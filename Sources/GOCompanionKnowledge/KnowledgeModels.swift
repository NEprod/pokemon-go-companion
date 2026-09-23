import Foundation

public struct PokemonLevel: Codable, Hashable, Comparable, Sendable {
    public let halfSteps: Int

    public init(halfSteps: Int) throws {
        guard halfSteps >= 2 else { throw KnowledgeError.invalidLevel(Double(halfSteps) / 2) }
        self.halfSteps = halfSteps
    }

    public init(_ value: Double) throws {
        let scaled = value * 2
        guard value.isFinite, scaled.rounded() == scaled, scaled >= 2 else {
            throw KnowledgeError.invalidLevel(value)
        }
        halfSteps = Int(scaled)
    }

    public var value: Double { Double(halfSteps) / 2 }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.halfSteps < rhs.halfSteps }
}

public struct SpeciesFormID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let speciesID: String
    public let formID: String

    public init(speciesID: String, formID: String) {
        self.speciesID = speciesID
        self.formID = formID
    }

    public var description: String { "\(speciesID):\(formID)" }
}

public struct BaseStats: Codable, Hashable, Sendable {
    public let attack: Int
    public let defense: Int
    public let stamina: Int

    public init(attack: Int, defense: Int, stamina: Int) {
        self.attack = attack
        self.defense = defense
        self.stamina = stamina
    }
}

public struct FormCapabilities: Codable, Hashable, Sendable {
    public let shadow: Bool
    public let mega: Bool
    public let dynamax: Bool
    public let gigantamax: Bool

    public init(shadow: Bool = false, mega: Bool = false, dynamax: Bool = false, gigantamax: Bool = false) {
        self.shadow = shadow
        self.mega = mega
        self.dynamax = dynamax
        self.gigantamax = gigantamax
    }
}

public struct SpeciesFormKnowledge: Codable, Hashable, Sendable {
    public let id: SpeciesFormID
    public let displayName: String
    public let types: [String]
    public let baseStats: BaseStats
    public let evolutionFamilyID: String
    public let capabilities: FormCapabilities

    public init(
        id: SpeciesFormID,
        displayName: String,
        types: [String],
        baseStats: BaseStats,
        evolutionFamilyID: String,
        capabilities: FormCapabilities = .init()
    ) {
        self.id = id
        self.displayName = displayName
        self.types = types
        self.baseStats = baseStats
        self.evolutionFamilyID = evolutionFamilyID
        self.capabilities = capabilities
    }
}

public struct EvolutionBranch: Codable, Hashable, Sendable {
    public let from: SpeciesFormID
    public let to: SpeciesFormID
    public let candyCost: Int
    public let requirements: [String]

    public init(from: SpeciesFormID, to: SpeciesFormID, candyCost: Int, requirements: [String] = []) {
        self.from = from
        self.to = to
        self.candyCost = candyCost
        self.requirements = requirements
    }
}

public enum MoveKind: String, Codable, Hashable, Sendable { case fast, charged }

public struct PvEMoveStats: Codable, Hashable, Sendable {
    public let power: Int
    public let durationMilliseconds: Int
    public let energyDelta: Int

    public init(power: Int, durationMilliseconds: Int, energyDelta: Int) {
        self.power = power
        self.durationMilliseconds = durationMilliseconds
        self.energyDelta = energyDelta
    }
}

public struct PvPMoveStats: Codable, Hashable, Sendable {
    public let power: Int
    public let energyDelta: Int
    public let turns: Int
    public let buffTarget: String?
    public let attackStages: Int
    public let defenseStages: Int
    public let buffChance: Double

    public init(
        power: Int,
        energyDelta: Int,
        turns: Int,
        buffTarget: String? = nil,
        attackStages: Int = 0,
        defenseStages: Int = 0,
        buffChance: Double = 0
    ) {
        self.power = power
        self.energyDelta = energyDelta
        self.turns = turns
        self.buffTarget = buffTarget
        self.attackStages = attackStages
        self.defenseStages = defenseStages
        self.buffChance = buffChance
    }
}

public struct MoveKnowledge: Codable, Hashable, Sendable {
    public let moveID: String
    public let displayName: String
    public let kind: MoveKind
    public let typeID: String
    public let pve: PvEMoveStats
    public let pvp: PvPMoveStats

    public init(
        moveID: String, displayName: String, kind: MoveKind, typeID: String,
        pve: PvEMoveStats, pvp: PvPMoveStats
    ) {
        self.moveID = moveID
        self.displayName = displayName
        self.kind = kind
        self.typeID = typeID
        self.pve = pve
        self.pvp = pvp
    }
}

public enum MoveAvailability: String, Codable, Hashable, Sendable {
    case current, legacy, eventExclusive, eliteOnly
}

public struct MovePoolEntry: Codable, Hashable, Sendable {
    public let speciesForm: SpeciesFormID
    public let moveID: String
    public let availability: MoveAvailability

    public init(speciesForm: SpeciesFormID, moveID: String, availability: MoveAvailability) {
        self.speciesForm = speciesForm
        self.moveID = moveID
        self.availability = availability
    }
}

public struct CPMultiplier: Codable, Hashable, Sendable {
    public let level: PokemonLevel
    public let multiplier: Double
    public let stardustCost: Int
    public let candyCost: Int
    public let xlCandyCost: Int
    public let requiresXL: Bool
    public let bestBuddyOnly: Bool

    public init(
        level: PokemonLevel, multiplier: Double, stardustCost: Int = 0, candyCost: Int = 0,
        xlCandyCost: Int = 0, requiresXL: Bool = false, bestBuddyOnly: Bool = false
    ) {
        self.level = level
        self.multiplier = multiplier
        self.stardustCost = stardustCost
        self.candyCost = candyCost
        self.xlCandyCost = xlCandyCost
        self.requiresXL = requiresXL
        self.bestBuddyOnly = bestBuddyOnly
    }
}

public struct KnowledgeDataset: Codable, Hashable, Sendable {
    public let normalizedVersion: String
    public let types: [String]
    public let speciesForms: [SpeciesFormKnowledge]
    public let evolutions: [EvolutionBranch]
    public let moves: [MoveKnowledge]
    public let movePools: [MovePoolEntry]
    public let cpMultipliers: [CPMultiplier]

    public init(
        normalizedVersion: String, types: [String], speciesForms: [SpeciesFormKnowledge],
        evolutions: [EvolutionBranch], moves: [MoveKnowledge], movePools: [MovePoolEntry],
        cpMultipliers: [CPMultiplier]
    ) {
        self.normalizedVersion = normalizedVersion
        self.types = types
        self.speciesForms = speciesForms
        self.evolutions = evolutions
        self.moves = moves
        self.movePools = movePools
        self.cpMultipliers = cpMultipliers
    }

    public func speciesForm(_ id: SpeciesFormID) -> SpeciesFormKnowledge? {
        speciesForms.first { $0.id == id }
    }
}

public enum KnowledgeError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLevel(Double)
    case invalidIV(Int)
    case unknownLevel(PokemonLevel)
    case unknownSpeciesForm(SpeciesFormID)
    case invalidDataset(String)
    case noActiveKnowledge(DataCategory)
    case unsupportedCategory(DataCategory)
    case corruptStoredData(String)

    public var description: String {
        switch self {
        case .invalidLevel(let value): "Invalid Pokémon level \(value)"
        case .invalidIV(let value): "IV must be between 0 and 15; got \(value)"
        case .unknownLevel(let level): "No CP multiplier for level \(level.value)"
        case .unknownSpeciesForm(let id): "Unknown species/form \(id)"
        case .invalidDataset(let message): "Invalid knowledge dataset: \(message)"
        case .noActiveKnowledge(let category): "No active knowledge for \(category.rawValue)"
        case .unsupportedCategory(let category): "Unsupported category \(category.rawValue)"
        case .corruptStoredData(let message): "Corrupt stored knowledge: \(message)"
        }
    }
}

public enum KnowledgeValidator {
    public static func validate(_ dataset: KnowledgeDataset) throws {
        guard !dataset.normalizedVersion.isEmpty else {
            throw KnowledgeError.invalidDataset("normalized version is empty")
        }
        let typeSet = Set(dataset.types)
        guard typeSet.count == dataset.types.count, !typeSet.contains("") else {
            throw KnowledgeError.invalidDataset("type IDs must be non-empty and unique")
        }
        let speciesIDs = Set(dataset.speciesForms.map(\.id))
        guard speciesIDs.count == dataset.speciesForms.count else {
            throw KnowledgeError.invalidDataset("species/form IDs must be unique")
        }
        for form in dataset.speciesForms {
            guard !form.id.speciesID.isEmpty, !form.id.formID.isEmpty, !form.displayName.isEmpty else {
                throw KnowledgeError.invalidDataset("species/form identity is incomplete")
            }
            guard (1...2).contains(form.types.count), form.types.allSatisfy(typeSet.contains) else {
                throw KnowledgeError.invalidDataset("invalid types for \(form.id)")
            }
            guard form.baseStats.attack > 0, form.baseStats.defense > 0, form.baseStats.stamina > 0 else {
                throw KnowledgeError.invalidDataset("base stats must be positive for \(form.id)")
            }
        }
        let moveIDs = Set(dataset.moves.map(\.moveID))
        guard moveIDs.count == dataset.moves.count else {
            throw KnowledgeError.invalidDataset("move IDs must be unique")
        }
        for move in dataset.moves {
            guard
                !move.moveID.isEmpty, typeSet.contains(move.typeID),
                move.pve.durationMilliseconds > 0, move.pvp.turns > 0,
                (0...1).contains(move.pvp.buffChance)
            else {
                throw KnowledgeError.invalidDataset("invalid move \(move.moveID)")
            }
            if move.kind == .fast, move.pvp.energyDelta < 0 {
                throw KnowledgeError.invalidDataset("fast move cannot consume PvP energy: \(move.moveID)")
            }
            if move.kind == .charged, move.pvp.energyDelta >= 0 {
                throw KnowledgeError.invalidDataset("charged move must consume PvP energy: \(move.moveID)")
            }
        }
        for pool in dataset.movePools where !speciesIDs.contains(pool.speciesForm) || !moveIDs.contains(pool.moveID) {
            throw KnowledgeError.invalidDataset("move pool contains an unknown reference")
        }
        for evolution in dataset.evolutions {
            guard speciesIDs.contains(evolution.from), speciesIDs.contains(evolution.to), evolution.candyCost >= 0
            else {
                throw KnowledgeError.invalidDataset("evolution contains an invalid reference or cost")
            }
        }
        let levels = dataset.cpMultipliers.map(\.level)
        guard !levels.isEmpty, Set(levels).count == levels.count, levels == levels.sorted() else {
            throw KnowledgeError.invalidDataset("CP multiplier levels must be non-empty, unique, and sorted")
        }
        guard
            dataset.cpMultipliers.allSatisfy({
                $0.multiplier > 0 && $0.multiplier <= 1 && $0.stardustCost >= 0 && $0.candyCost >= 0
                    && $0.xlCandyCost >= 0
            })
        else {
            throw KnowledgeError.invalidDataset("CP multiplier or cost is out of range")
        }
    }
}

public struct SyntheticJSONNormalizer: ProviderNormalizer {
    public let providerName: String
    public let parserVersion: String

    public init(providerName: String = "synthetic-fixture", parserVersion: String = "synthetic-json-v1") {
        self.providerName = providerName
        self.parserVersion = parserVersion
    }

    public func normalize(_ payload: ProviderPayload, category: DataCategory) throws -> KnowledgeDataset {
        guard category == .gameMaster else { throw KnowledgeError.unsupportedCategory(category) }
        let dataset = try JSONDecoder().decode(KnowledgeDataset.self, from: payload.bytes)
        try KnowledgeValidator.validate(dataset)
        return dataset
    }
}
