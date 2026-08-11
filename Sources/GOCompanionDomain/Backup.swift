import Foundation

public struct CollectionAggregate: Codable, Hashable, Sendable {
    public var pokemon: PokemonRecord
    public var scanSessions: [ScanSession]
    public var observations: [PokemonObservation]
    public var history: [CollectionHistoryEvent]

    public init(
        pokemon: PokemonRecord,
        scanSessions: [ScanSession] = [],
        observations: [PokemonObservation] = [],
        history: [CollectionHistoryEvent] = []
    ) {
        self.pokemon = pokemon
        self.scanSessions = scanSessions
        self.observations = observations
        self.history = history
    }
}

public struct UserBackup: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let userSchemaVersion: Int
    public let exportedAt: Date
    public let profile: UserProfile
    public let collection: [CollectionAggregate]
    public let inventory: Inventory?
    public let storageProfile: StorageProfile?
    public let buildPlans: [BuildPlan]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        userSchemaVersion: Int,
        exportedAt: Date = Date(),
        profile: UserProfile,
        collection: [CollectionAggregate],
        inventory: Inventory? = nil,
        storageProfile: StorageProfile? = nil,
        buildPlans: [BuildPlan] = []
    ) {
        self.formatVersion = formatVersion
        self.userSchemaVersion = userSchemaVersion
        self.exportedAt = exportedAt
        self.profile = profile
        self.collection = collection
        self.inventory = inventory
        self.storageProfile = storageProfile
        self.buildPlans = buildPlans
    }
}
