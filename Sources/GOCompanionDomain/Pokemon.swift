import Foundation

public struct PokemonIdentity: Codable, Hashable, Sendable {
    public let recordID: UUID
    public var speciesID: String
    public var formID: String
    public var fingerprint: String?

    public init(recordID: UUID = UUID(), speciesID: String, formID: String, fingerprint: String? = nil) {
        self.recordID = recordID
        self.speciesID = speciesID
        self.formID = formID
        self.fingerprint = fingerprint
    }
}

public struct PokemonForm: Codable, Hashable, Sendable {
    public let speciesID: String
    public let formID: String
    public let displayName: String
    public let types: [String]

    public init(speciesID: String, formID: String, displayName: String, types: [String]) {
        self.speciesID = speciesID
        self.formID = formID
        self.displayName = displayName
        self.types = types
    }
}

public struct MoveSet: Codable, Hashable, Sendable {
    public var fastMoveID: String?
    public var chargedMove1ID: String?
    public var chargedMove2ID: String?

    public init(fastMoveID: String? = nil, chargedMove1ID: String? = nil, chargedMove2ID: String? = nil) {
        self.fastMoveID = fastMoveID
        self.chargedMove1ID = chargedMove1ID
        self.chargedMove2ID = chargedMove2ID
    }
}

public enum PokemonTrait: String, Codable, CaseIterable, Sendable {
    case shiny, shadow, purified, lucky, dynamax, gigantamax, megaCapable, megaUnlocked
    case favorite, costume, buddy
}

public enum CollectionStatus: String, Codable, Sendable {
    case active, pendingReview, pendingRemoval
    case archivedTransferred, archivedTraded, archivedOther

    public var isArchived: Bool {
        switch self {
        case .archivedTransferred, .archivedTraded, .archivedOther: true
        case .active, .pendingReview, .pendingRemoval: false
        }
    }
}

public enum PokemonRole: String, Codable, CaseIterable, Sendable {
    case greatLeague, ultraLeague, masterLeague, raid, maxBattle, mega, collection, trade
    case luckyCheapBuild, futureEventHold
}

public enum GOTag: String, Codable, CaseIterable, Sendable {
    case transfer = "Transfer"
    case greatLeague = "GL"
    case ultraLeague = "UL"
    case masterLeague = "ML"
    case raid = "Raid"
    case max = "Max"
    case mega = "Mega"
    case megaNew = "MegaNew"
    case trade = "Trade"
    case evolve = "Evolve"
    case powerUp = "PowerUp"
    case needsTM = "NeedsTM"
    case eliteTM = "EliteTM"
    case hold = "Hold"
}

public struct PokemonRecord: Codable, Hashable, Sendable {
    public var identity: PokemonIdentity
    public var nickname: String?
    public var cp: Int?
    public var hp: Int?
    public var level: Double?
    public var ivs: IVs?
    public var moves: MoveSet
    public var traits: Set<PokemonTrait>
    public var appliedGOTags: Set<String>
    public var internalTags: Set<String>
    public var roles: Set<PokemonRole>
    public var recommendedGOTags: [RecommendedGOTag]
    public var status: CollectionStatus
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        identity: PokemonIdentity,
        nickname: String? = nil,
        cp: Int? = nil,
        hp: Int? = nil,
        level: Double? = nil,
        ivs: IVs? = nil,
        moves: MoveSet = MoveSet(),
        traits: Set<PokemonTrait> = [],
        appliedGOTags: Set<String> = [],
        internalTags: Set<String> = [],
        roles: Set<PokemonRole> = [],
        recommendedGOTags: [RecommendedGOTag] = [],
        status: CollectionStatus = .active,
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identity = identity
        self.nickname = nickname
        self.cp = cp
        self.hp = hp
        self.level = level
        self.ivs = ivs
        self.moves = moves
        self.traits = traits
        self.appliedGOTags = appliedGOTags
        self.internalTags = internalTags
        self.roles = roles
        self.recommendedGOTags = recommendedGOTags
        self.status = status
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum TagRecommendationState: String, Codable, Sendable {
    case recommended, withdrawn
}

public enum UserConfirmationState: String, Codable, Sendable {
    case unknown, confirmedApplied, confirmedNotApplied
}

public struct RecommendedGOTag: Codable, Hashable, Sendable {
    public let tag: GOTag
    public var state: TagRecommendationState
    public var reason: String
    public var appearsApplied: Bool
    public var userConfirmation: UserConfirmationState
    public let createdAt: Date
    public var updatedAt: Date
    public var sourceVersion: String

    public init(
        tag: GOTag,
        state: TagRecommendationState = .recommended,
        reason: String,
        appearsApplied: Bool = false,
        userConfirmation: UserConfirmationState = .unknown,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceVersion: String
    ) {
        self.tag = tag
        self.state = state
        self.reason = reason
        self.appearsApplied = appearsApplied
        self.userConfirmation = userConfirmation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceVersion = sourceVersion
    }
}
