import Foundation
import GOCompanionDomain

public enum CollectionEngineError: Error, Equatable, CustomStringConvertible {
    case pokemonNotFound(UUID)
    case duplicatePokemon(UUID)
    case profileMissing
    case invalidTransition(from: CollectionStatus, to: CollectionStatus)
    case staleRevision(expected: Int, actual: Int)
    case invalidBackup(String)
    case unsupportedBackupVersion(Int)
    case incompatibleUserSchemaVersion(exported: Int, supported: Int)
    case restoreRequiresEmptyDatabase

    public var description: String {
        switch self {
        case .pokemonNotFound(let id): "Pokémon \(id) was not found"
        case .duplicatePokemon(let id): "Pokémon \(id) already exists"
        case .profileMissing: "No user profile exists"
        case .invalidTransition(let from, let to):
            "Invalid collection transition from \(from.rawValue) to \(to.rawValue)"
        case .staleRevision(let expected, let actual):
            "The record changed concurrently (expected revision \(expected), current \(actual))"
        case .invalidBackup(let reason): "Invalid backup: \(reason)"
        case .unsupportedBackupVersion(let version): "Unsupported backup format version \(version)"
        case .incompatibleUserSchemaVersion(let exported, let supported):
            "Backup user schema \(exported) is newer than supported schema \(supported)"
        case .restoreRequiresEmptyDatabase: "Full restore requires an empty user database"
        }
    }
}

public enum CollectionSort: String, Codable, Sendable {
    case updatedNewest, updatedOldest, speciesAscending, cpDescending
}

public struct CollectionQuery: Hashable, Sendable {
    public var archived: Bool?
    public var statuses: Set<CollectionStatus>
    public var speciesID: String?
    public var formID: String?
    public var internalTag: String?
    public var recommendedGOTag: GOTag?
    public var sort: CollectionSort
    public var limit: Int
    public var offset: Int

    public init(
        archived: Bool? = nil,
        statuses: Set<CollectionStatus> = [],
        speciesID: String? = nil,
        formID: String? = nil,
        internalTag: String? = nil,
        recommendedGOTag: GOTag? = nil,
        sort: CollectionSort = .updatedNewest,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.archived = archived
        self.statuses = statuses
        self.speciesID = speciesID
        self.formID = formID
        self.internalTag = internalTag
        self.recommendedGOTag = recommendedGOTag
        self.sort = sort
        self.limit = min(max(limit, 1), 500)
        self.offset = max(offset, 0)
    }

    public static var active: Self { Self(archived: false) }
    public static var archived: Self { Self(archived: true) }
}

public protocol CollectionRepository: Sendable {
    func ensureProfile(_ profile: UserProfile) throws
    func profile() throws -> UserProfile
    func create(_ record: PokemonRecord, event: CollectionHistoryEvent) throws
    func save(_ record: PokemonRecord, expectedRevision: Int, event: CollectionHistoryEvent) throws -> PokemonRecord
    func pokemon(id: UUID) throws -> PokemonRecord?
    func list(_ query: CollectionQuery) throws -> [PokemonRecord]
    func addObservation(
        session: ScanSession,
        observation: PokemonObservation,
        event: CollectionHistoryEvent?
    ) throws
    func observations(for pokemonID: UUID) throws -> [PokemonObservation]
    func history(for pokemonID: UUID) throws -> [CollectionHistoryEvent]
    func allAggregates() throws -> [CollectionAggregate]
    func inventory() throws -> Inventory?
    func storageProfile() throws -> StorageProfile?
    func buildPlans() throws -> [BuildPlan]
    func currentUserSchemaVersion() throws -> Int
    func restoreEmptyDatabase(from backup: UserBackup) throws
}

public struct SystemDateProvider: Sendable {
    public init() {}
    public func now() -> Date { Date() }
}
