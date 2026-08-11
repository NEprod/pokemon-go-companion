import Foundation
import GOCompanionApplication
import GOCompanionDomain
import GOCompanionPersistence

final class CollectionTestContext: @unchecked Sendable {
    let root: URL
    let databases: DatabaseSet
    let repository: SQLiteCollectionRepository
    let service: CollectionService
    let profile: UserProfile
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    init(createProfile: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("go-collection-tests-\(UUID().uuidString)", isDirectory: true)
        databases = try DatabaseSet(directory: root)
        repository = SQLiteCollectionRepository(database: databases.user)
        profile = UserProfile(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            displayName: "Fixture Trainer"
        )
        if createProfile { try repository.ensureProfile(profile) }
        let fixed = timestamp
        service = CollectionService(repository: repository, now: { fixed })
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func pokemon(
        id: UUID = UUID(),
        species: String = "pikachu",
        form: String = "normal",
        cp: Int = 742,
        traits: Set<PokemonTrait> = [],
        internalTags: Set<String> = [],
        roles: Set<PokemonRole> = [],
        recommended: [RecommendedGOTag] = []
    ) -> PokemonRecord {
        PokemonRecord(
            identity: PokemonIdentity(recordID: id, speciesID: species, formID: form, fingerprint: "fixture-\(id)"),
            cp: cp,
            ivs: try! IVs(attack: 10, defense: 11, stamina: 12),
            moves: MoveSet(fastMoveID: "thunder_shock", chargedMove1ID: "wild_charge"),
            traits: traits,
            internalTags: internalTags,
            roles: roles,
            recommendedGOTags: recommended,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}
