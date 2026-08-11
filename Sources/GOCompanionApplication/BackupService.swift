import Foundation
import GOCompanionDomain

public struct BackupService: Sendable {
    private let repository: any CollectionRepository

    public init(repository: any CollectionRepository) {
        self.repository = repository
    }

    public func exportJSON(exportedAt: Date = Date()) throws -> Data {
        let backup = UserBackup(
            userSchemaVersion: try repository.currentUserSchemaVersion(),
            exportedAt: exportedAt,
            profile: try repository.profile(),
            collection: try repository.allAggregates(),
            inventory: try repository.inventory(),
            storageProfile: try repository.storageProfile(),
            buildPlans: try repository.buildPlans()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    public func restoreJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: UserBackup
        do {
            backup = try decoder.decode(UserBackup.self, from: data)
        } catch {
            throw CollectionEngineError.invalidBackup("malformed JSON or schema: \(error.localizedDescription)")
        }
        guard backup.formatVersion == UserBackup.currentFormatVersion else {
            throw CollectionEngineError.unsupportedBackupVersion(backup.formatVersion)
        }
        try Self.validate(backup)
        let supportedSchema = try repository.currentUserSchemaVersion()
        guard backup.userSchemaVersion <= supportedSchema else {
            throw CollectionEngineError.incompatibleUserSchemaVersion(
                exported: backup.userSchemaVersion,
                supported: supportedSchema
            )
        }
        try repository.restoreEmptyDatabase(from: backup)
    }

    private static func validate(_ backup: UserBackup) throws {
        guard backup.userSchemaVersion > 0 else {
            throw CollectionEngineError.invalidBackup("user schema version must be positive")
        }
        if let inventory = backup.inventory, inventory.profileID != backup.profile.id {
            throw CollectionEngineError.invalidBackup("inventory belongs to another profile")
        }
        let ids = backup.collection.map { $0.pokemon.identity.recordID }
        guard Set(ids).count == ids.count else {
            throw CollectionEngineError.invalidBackup("duplicate Pokémon UUID")
        }
        let allHistoryIDs = backup.collection.flatMap { $0.history.map(\.id) }
        guard Set(allHistoryIDs).count == allHistoryIDs.count else {
            throw CollectionEngineError.invalidBackup("duplicate history event UUID")
        }
        let allObservationIDs = backup.collection.flatMap { $0.observations.map(\.id) }
        guard Set(allObservationIDs).count == allObservationIDs.count else {
            throw CollectionEngineError.invalidBackup("duplicate observation UUID")
        }
        for aggregate in backup.collection {
            let id = aggregate.pokemon.identity.recordID
            guard aggregate.pokemon.revision > 0 else {
                throw CollectionEngineError.invalidBackup("invalid record revision for \(id)")
            }
            guard aggregate.history.allSatisfy({ $0.pokemonID == id }) else {
                throw CollectionEngineError.invalidBackup("history references another Pokémon")
            }
            guard aggregate.observations.allSatisfy({ $0.pokemonID == id }) else {
                throw CollectionEngineError.invalidBackup("observation references another Pokémon")
            }
            let sessionIDs = Set(aggregate.scanSessions.map(\.id))
            guard aggregate.observations.allSatisfy({ sessionIDs.contains($0.scanSessionID) }) else {
                throw CollectionEngineError.invalidBackup("observation references a missing scan session")
            }
            let historyIDs = aggregate.history.map(\.id)
            guard Set(historyIDs).count == historyIDs.count else {
                throw CollectionEngineError.invalidBackup("duplicate history event UUID")
            }
        }
        let pokemonIDs = Set(ids)
        guard backup.buildPlans.allSatisfy({ pokemonIDs.contains($0.pokemonID) }) else {
            throw CollectionEngineError.invalidBackup("build plan references a missing Pokémon")
        }
    }
}
