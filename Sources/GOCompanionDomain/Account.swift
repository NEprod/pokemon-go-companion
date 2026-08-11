import Foundation

public enum GoalArea: String, Codable, CaseIterable, Sendable {
    case raids, greatLeague, ultraLeague, masterLeague, maxBattles, collecting, trading, shinies
}

public struct UserGoal: Codable, Hashable, Sendable {
    public let area: GoalArea
    public let priority: Int

    public init(area: GoalArea, priority: Int) throws {
        guard (0...5).contains(priority) else { throw DomainError.invalidPriority(priority) }
        self.area = area
        self.priority = priority
    }
}

public struct UserProfile: Codable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var goals: [UserGoal]
    public var normalStorageBuffer: Int
    public var eventStorageBuffer: Int
    public var conservativeInvestment: Bool

    public init(
        id: UUID = UUID(), displayName: String, goals: [UserGoal] = [],
        normalStorageBuffer: Int = 100, eventStorageBuffer: Int = 250,
        conservativeInvestment: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.goals = goals
        self.normalStorageBuffer = normalStorageBuffer
        self.eventStorageBuffer = eventStorageBuffer
        self.conservativeInvestment = conservativeInvestment
    }
}

public struct ResourceAmount: Codable, Hashable, Sendable {
    public let resourceID: String
    public var quantity: Int
    public var observedAt: Date
    public var confidence: Confidence

    public init(resourceID: String, quantity: Int, observedAt: Date, confidence: Confidence) {
        self.resourceID = resourceID
        self.quantity = quantity
        self.observedAt = observedAt
        self.confidence = confidence
    }
}

public struct Inventory: Codable, Hashable, Sendable {
    public let profileID: UUID
    public var resources: [ResourceAmount]

    public init(profileID: UUID, resources: [ResourceAmount]) {
        self.profileID = profileID
        self.resources = resources
    }
}

public struct StorageProfile: Codable, Hashable, Sendable {
    public var pokemonUsed: Int
    public var pokemonCapacity: Int
    public var bagUsed: Int
    public var bagCapacity: Int
    public var observedAt: Date

    public init(
        pokemonUsed: Int,
        pokemonCapacity: Int,
        bagUsed: Int,
        bagCapacity: Int,
        observedAt: Date
    ) {
        self.pokemonUsed = pokemonUsed
        self.pokemonCapacity = pokemonCapacity
        self.bagUsed = bagUsed
        self.bagCapacity = bagCapacity
        self.observedAt = observedAt
    }
}

public struct BuildPlanStep: Codable, Hashable, Sendable {
    public let action: RecommendationAction
    public let resourceCosts: [String: Int]
    public var completed: Bool

    public init(action: RecommendationAction, resourceCosts: [String: Int], completed: Bool = false) {
        self.action = action
        self.resourceCosts = resourceCosts
        self.completed = completed
    }
}

public struct BuildPlan: Codable, Hashable, Sendable {
    public let id: UUID
    public let pokemonID: UUID
    public var title: String
    public var steps: [BuildPlanStep]
    public var createdAt: Date

    public init(id: UUID = UUID(), pokemonID: UUID, title: String, steps: [BuildPlanStep], createdAt: Date = Date()) {
        self.id = id
        self.pokemonID = pokemonID
        self.title = title
        self.steps = steps
        self.createdAt = createdAt
    }
}

public enum EventOpportunityType: String, Codable, Sendable {
    case exclusiveEvolutionMove, frustrationRemoval, raidAvailability, maxBattleAvailability
    case boostedSpawn, candyBonus, stardustBonus, megaOpportunity, other
}

public struct EventOpportunity: Codable, Hashable, Sendable {
    public let id: String
    public let type: EventOpportunityType
    public let speciesID: String?
    public let moveID: String?
    public let startsAt: Date
    public let endsAt: Date
    public let timezoneMode: String
    public let sourceURL: URL?
    public let confidence: Confidence
}
