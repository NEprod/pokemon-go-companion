import Foundation
import GOCompanionKnowledge
import GOCompanionPersistence
import Testing

private let alwaysCheck = FreshnessPolicy(maximumAge: 0, lightweightCheckInterval: 0)

@Test func sourceNormalizeActivateAndRollbackPreservePreviousGood() async throws {
    let context = try KnowledgeTestContext()
    let first = try KnowledgeTestContext.fixtureDataset()
    let second = try KnowledgeTestContext.version2()
    try await context.activate(dataset: first, sourceVersion: "source-v1")
    try await context.activate(dataset: second, sourceVersion: "source-v2")
    #expect(
        try await context.store.activeDataset(category: .gameMaster)?.normalizedVersion == "synthetic-normalized-v2")
    #expect(
        try context.databases.knowledge.scalarInt(
            "SELECT COUNT(*) FROM source_payloads WHERE lifecycle_state = 'active'") == 1)
    #expect(
        try context.databases.knowledge.scalarInt(
            "SELECT COUNT(*) FROM source_payloads WHERE lifecycle_state = 'previous'") == 1)

    let priorResult = DerivedCacheKey(
        kind: "pvp-iv-ranking", subject: "prior", inputVersions: ["gameMaster": "v2"],
        engineVersion: "engine")
    try await context.derived.store(Data("prior".utf8), for: priorResult)
    let restored = try await KnowledgeUpdatePipeline(
        store: context.store, derivedCache: context.derived
    ).rollback(category: .gameMaster)
    #expect(restored.normalizedVersion == "synthetic-normalized-v1")
    #expect(try await context.store.activeVersion(category: .gameMaster)?.sourceVersion == "source-v1")
    #expect(try await context.derived.data(for: priorResult) == nil)
}

@Test func sourceCacheRoundTripsRawPayloadAndProvenance() async throws {
    let context = try KnowledgeTestContext()
    let bytes = try KnowledgeTestContext.fixtureData("synthetic_knowledge_v1")
    let provider = SyntheticFixtureProvider(data: bytes, sourceVersion: "source-v1")
    try await context.store.recordSource(provider.payload, validation: .valid, error: nil)
    let stored = try #require(
        try await context.store.sourcePayload(
            provider: "synthetic-fixture", category: .gameMaster, sourceVersion: "source-v1",
            parserVersion: "synthetic-json-v1"))
    #expect(stored.bytes == bytes)
    #expect(stored.etag == "\"source-v1\"")
    #expect(stored.version.contentHash == "frozen-source-v1")
}

@Test func pipelineActivatesAValidatedFrozenPayloadAndInvalidatesDerivedCache() async throws {
    let context = try KnowledgeTestContext()
    let data = try KnowledgeTestContext.fixtureData("synthetic_knowledge_v1")
    let provider = SyntheticFixtureProvider(data: data, sourceVersion: "source-v1")
    let staleKey = DerivedCacheKey(
        kind: "pvp-iv-ranking", subject: "stale", inputVersions: ["gameMaster": "old"],
        engineVersion: "old-engine")
    try await context.derived.store(Data("old".utf8), for: staleKey)

    let result = await KnowledgeUpdatePipeline(store: context.store, derivedCache: context.derived)
        .refresh(
            provider: provider,
            normalizer: SyntheticJSONNormalizer(),
            category: .gameMaster,
            freshnessPolicy: alwaysCheck,
            now: Date(timeIntervalSince1970: 1_800_000_000))
    guard case .activated(previous: nil, current: "source-v1") = result else {
        Issue.record("Expected initial activation")
        return
    }
    #expect(
        try await context.store.activeDataset(category: .gameMaster)?.normalizedVersion == "synthetic-normalized-v1")
    #expect(try await context.derived.data(for: staleKey) == nil)
    #expect(try context.databases.derived.scalarInt("SELECT COUNT(*) FROM invalidation_log") == 1)
}

@Test func fetchFailureKeepsLastKnownGoodActive() async throws {
    let context = try KnowledgeTestContext()
    let dataset = try KnowledgeTestContext.fixtureDataset()
    try await context.activate(dataset: dataset, sourceVersion: "source-v1")
    let provider = SyntheticFixtureProvider(
        data: try KnowledgeTestContext.encode(try KnowledgeTestContext.version2()),
        sourceVersion: "source-v2",
        failure: .fetch)
    let result = await KnowledgeUpdatePipeline(store: context.store, derivedCache: context.derived)
        .refresh(
            provider: provider, normalizer: SyntheticJSONNormalizer(), category: .gameMaster,
            freshnessPolicy: alwaysCheck,
            now: Date(timeIntervalSince1970: 1_800_000_000))
    guard case .failedUsingLastKnownGood(stage: .fetch, activeVersion: "source-v1", _) = result else {
        Issue.record("Expected a fetch failure with source-v1 retained")
        return
    }
    #expect(
        try await context.store.activeDataset(category: .gameMaster)?.normalizedVersion == dataset.normalizedVersion)
}

@Test func validationAndNormalizationFailuresNeverReplaceActiveKnowledge() async throws {
    let context = try KnowledgeTestContext()
    let active = try KnowledgeTestContext.fixtureDataset()
    try await context.activate(dataset: active, sourceVersion: "source-v1")
    let pipeline = KnowledgeUpdatePipeline(store: context.store, derivedCache: context.derived)
    let validBytes = try KnowledgeTestContext.encode(try KnowledgeTestContext.version2())

    let validation = await pipeline.refresh(
        provider: SyntheticFixtureProvider(
            data: validBytes, sourceVersion: "source-v2", failure: .validation),
        normalizer: SyntheticJSONNormalizer(), category: .gameMaster,
        freshnessPolicy: alwaysCheck, now: Date(timeIntervalSince1970: 1_800_000_000))
    guard case .failedUsingLastKnownGood(stage: .sourceValidation, _, _) = validation else {
        Issue.record("Expected source validation failure")
        return
    }
    #expect(
        try context.databases.knowledge.scalarInt(
            "SELECT COUNT(*) FROM source_payloads WHERE validation_status = 'invalid'") == 1)

    let normalization = await pipeline.refresh(
        provider: SyntheticFixtureProvider(
            data: try KnowledgeTestContext.fixtureData("synthetic_knowledge_invalid"),
            sourceVersion: "source-v3"),
        normalizer: SyntheticJSONNormalizer(), category: .gameMaster,
        freshnessPolicy: alwaysCheck, now: Date(timeIntervalSince1970: 1_800_000_000))
    guard case .failedUsingLastKnownGood(stage: .normalization, _, _) = normalization else {
        Issue.record("Expected normalization failure")
        return
    }
    #expect(try await context.store.activeDataset(category: .gameMaster)?.normalizedVersion == active.normalizedVersion)
}

@Test func failedTransactionalActivationLeavesActivePointerAndRowsIntact() async throws {
    let context = try KnowledgeTestContext()
    let first = try KnowledgeTestContext.fixtureDataset()
    try await context.activate(dataset: first, sourceVersion: "source-v1")

    // A changed source that reuses an immutable normalized version must fail inside activation.
    let duplicateVersionPayload = SyntheticFixtureProvider(
        data: try KnowledgeTestContext.encode(first), sourceVersion: "source-v2")
    try await context.store.recordSource(
        duplicateVersionPayload.payload, validation: .valid, error: nil)
    do {
        try await context.store.activate(first, from: duplicateVersionPayload.payload)
        Issue.record("Expected duplicate normalized version activation to fail")
    } catch {}
    #expect(try await context.store.activeVersion(category: .gameMaster)?.sourceVersion == "source-v1")
    #expect(
        try context.databases.knowledge.scalarInt(
            "SELECT COUNT(*) FROM knowledge_datasets WHERE lifecycle_state = 'active'") == 1)
}

@Test func derivedKeysSeparateKnowledgeAndEngineVersionsAndInvalidate() async throws {
    let context = try KnowledgeTestContext()
    let v1 = DerivedCacheKey(
        kind: "pvp-iv-ranking", subject: "seedling|great",
        inputVersions: ["gameMaster": "v1"], engineVersion: "engine-1")
    let v2 = DerivedCacheKey(
        kind: "pvp-iv-ranking", subject: "seedling|great",
        inputVersions: ["gameMaster": "v2"], engineVersion: "engine-1")
    let engine2 = DerivedCacheKey(
        kind: "pvp-iv-ranking", subject: "seedling|great",
        inputVersions: ["gameMaster": "v1"], engineVersion: "engine-2")
    try await context.derived.store(Data("one".utf8), for: v1)
    #expect(try await context.derived.data(for: v2) == nil)
    #expect(try await context.derived.data(for: engine2) == nil)
    try await context.derived.invalidate(affectedBy: .gameMaster, newVersion: "v2")
    #expect(try await context.derived.data(for: v1) == nil)
}

@Test func rankingServiceReusesSQLiteDerivedCache() async throws {
    let context = try KnowledgeTestContext()
    let dataset = try KnowledgeTestContext.fixtureDataset()
    try await context.activate(dataset: dataset, sourceVersion: "source-v1")
    let service = PvPIVRankingService(knowledge: context.store, cache: context.derived)
    let league = LeagueConfiguration(
        leagueID: "fixture", combatPowerCap: 500, maximumLevel: try PokemonLevel(3),
        allowsXL: true, allowsBestBuddy: true)
    let id = SpeciesFormID(speciesID: "titan", formID: "normal")
    let first = try await service.ranking(for: id, league: league)
    let second = try await service.ranking(for: id, league: league)
    #expect(first == second)
    #expect(try context.databases.derived.scalarInt("SELECT COUNT(*) FROM derived_entries") == 1)
    #expect(try context.databases.derived.scalarInt("SELECT COUNT(*) FROM pvp_iv_cache_metadata") == 1)
}

@Test func knowledgeAndDerivedDataRemainOutsideUserDatabase() throws {
    let context = try KnowledgeTestContext()
    #expect(
        try context.databases.user.scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'knowledge_datasets'") == 0)
    #expect(
        try context.databases.knowledge.scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'knowledge_datasets'") == 1)
    #expect(
        try context.databases.derived.scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'derived_entries'") == 1)
}
