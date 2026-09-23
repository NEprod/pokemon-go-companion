import Foundation
import GOCompanionKnowledge
import GOCompanionPersistence

enum FixtureError: Error { case requestedFailure, checksumMismatch }

struct SyntheticFixtureProvider: GameDataProvider {
    enum Failure: Sendable { case none, version, fetch, validation }

    let descriptor = ProviderDescriptor(
        name: "synthetic-fixture", parserVersion: "synthetic-json-v1", categories: [.gameMaster])
    let payload: ProviderPayload
    let failure: Failure

    init(data: Data, sourceVersion: String, normalizedHash: String? = nil, failure: Failure = .none) {
        payload = ProviderPayload(
            bytes: data,
            version: ProviderVersion(
                providerName: "synthetic-fixture",
                category: .gameMaster,
                sourceVersion: sourceVersion,
                parserVersion: "synthetic-json-v1",
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                contentHash: normalizedHash ?? "frozen-\(sourceVersion)"
            ),
            etag: "\"\(sourceVersion)\""
        )
        self.failure = failure
    }

    func checkVersion(for category: DataCategory) async throws -> String? {
        if failure == .version { throw FixtureError.requestedFailure }
        return payload.version.sourceVersion
    }

    func fetch(category: DataCategory, ifChangedFrom sourceVersion: String?) async throws -> ProviderPayload? {
        if failure == .fetch { throw FixtureError.requestedFailure }
        return payload.version.sourceVersion == sourceVersion ? nil : payload
    }

    func validate(_ payload: ProviderPayload, for category: DataCategory) throws {
        if failure == .validation { throw FixtureError.requestedFailure }
        guard !payload.bytes.isEmpty, category == .gameMaster else { throw FixtureError.checksumMismatch }
    }
}

final class KnowledgeTestContext: @unchecked Sendable {
    let root: URL
    let databases: DatabaseSet
    let store: SQLiteKnowledgeStore
    let derived: SQLiteDerivedAnalysisCache

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("go-knowledge-tests-\(UUID().uuidString)", isDirectory: true)
        databases = try DatabaseSet(directory: root)
        store = SQLiteKnowledgeStore(database: databases.knowledge)
        derived = SQLiteDerivedAnalysisCache(database: databases.derived)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func activate(dataset: KnowledgeDataset, sourceVersion: String) async throws {
        let data = try Self.encode(dataset)
        let provider = SyntheticFixtureProvider(data: data, sourceVersion: sourceVersion)
        try await store.recordSource(provider.payload, validation: .valid, error: nil)
        try await store.activate(dataset, from: provider.payload)
    }

    static func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.requestedFailure
        }
        return try Data(contentsOf: url)
    }

    static func fixtureDataset() throws -> KnowledgeDataset {
        try JSONDecoder().decode(
            KnowledgeDataset.self, from: fixtureData("synthetic_knowledge_v1"))
    }

    static func version2() throws -> KnowledgeDataset {
        let first = try fixtureDataset()
        return KnowledgeDataset(
            normalizedVersion: "synthetic-normalized-v2",
            types: first.types,
            speciesForms: first.speciesForms,
            evolutions: first.evolutions,
            moves: first.moves,
            movePools: first.movePools,
            cpMultipliers: first.cpMultipliers
        )
    }

    static func encode(_ dataset: KnowledgeDataset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(dataset)
    }
}
