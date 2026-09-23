import Foundation

public enum SourceValidation: String, Codable, Sendable { case valid, invalid }

public protocol KnowledgeStore: Sendable {
    func recordSource(_ payload: ProviderPayload, validation: SourceValidation, error: String?) async throws
    func sourcePayload(
        provider: String, category: DataCategory, sourceVersion: String, parserVersion: String
    ) async throws -> ProviderPayload?
    func activeVersion(category: DataCategory) async throws -> ProviderVersion?
    func activeDataset(category: DataCategory) async throws -> KnowledgeDataset?
    func activate(_ dataset: KnowledgeDataset, from payload: ProviderPayload) async throws
    func rollback(category: DataCategory) async throws -> KnowledgeDataset
    func recordFailure(provider: String, category: DataCategory, error: String) async throws
}

public enum UpdateFailureStage: String, Codable, Sendable {
    case versionCheck, fetch, sourceValidation, normalization, activation
}

public enum KnowledgeUpdateResult: Sendable, Equatable {
    case current(version: String?)
    case activated(previous: String?, current: String)
    case failedUsingLastKnownGood(stage: UpdateFailureStage, activeVersion: String?, message: String)
}

public struct KnowledgeUpdatePipeline: Sendable {
    private let store: any KnowledgeStore
    private let derivedCache: any DerivedAnalysisCache

    public init(store: any KnowledgeStore, derivedCache: any DerivedAnalysisCache) {
        self.store = store
        self.derivedCache = derivedCache
    }

    public func refresh<P: GameDataProvider, N: ProviderNormalizer>(
        provider: P,
        normalizer: N,
        category: DataCategory,
        freshnessPolicy: FreshnessPolicy,
        now: Date = Date()
    ) async -> KnowledgeUpdateResult where N.NormalizedBatch == KnowledgeDataset {
        guard provider.descriptor.categories.contains(category) else {
            return await failure(
                .versionCheck,
                active: nil,
                provider: provider,
                category: category,
                error: KnowledgeError.unsupportedCategory(category)
            )
        }
        let active: ProviderVersion?
        do {
            active = try await store.activeVersion(category: category)
        } catch {
            return await failure(.versionCheck, active: nil, provider: provider, category: category, error: error)
        }
        if let active, now.timeIntervalSince(active.fetchedAt) < freshnessPolicy.lightweightCheckInterval {
            return .current(version: active.sourceVersion)
        }

        let advertisedVersion: String?
        do {
            advertisedVersion = try await provider.checkVersion(for: category)
        } catch {
            return await failure(.versionCheck, active: active, provider: provider, category: category, error: error)
        }
        if let advertisedVersion, advertisedVersion == active?.sourceVersion {
            return .current(version: active?.sourceVersion)
        }
        if advertisedVersion == nil, let active,
            now.timeIntervalSince(active.fetchedAt) < freshnessPolicy.maximumAge
        {
            return .current(version: active.sourceVersion)
        }

        let payload: ProviderPayload
        do {
            guard
                let fetched = try await provider.fetch(
                    category: category, ifChangedFrom: active?.sourceVersion)
            else { return .current(version: active?.sourceVersion) }
            payload = fetched
        } catch {
            return await failure(.fetch, active: active, provider: provider, category: category, error: error)
        }

        do {
            guard
                payload.version.providerName == provider.descriptor.name,
                payload.version.category == category,
                payload.version.parserVersion == provider.descriptor.parserVersion,
                normalizer.providerName == provider.descriptor.name,
                normalizer.parserVersion == provider.descriptor.parserVersion
            else {
                throw KnowledgeError.invalidDataset("provider payload provenance does not match its descriptor")
            }
            try provider.validate(payload, for: category)
            try await store.recordSource(payload, validation: .valid, error: nil)
        } catch {
            try? await store.recordSource(
                payload, validation: .invalid, error: String(describing: error))
            return await failure(
                .sourceValidation, active: active, provider: provider, category: category, error: error)
        }

        let dataset: KnowledgeDataset
        do {
            dataset = try normalizer.normalize(payload, category: category)
            try KnowledgeValidator.validate(dataset)
        } catch {
            return await failure(.normalization, active: active, provider: provider, category: category, error: error)
        }

        do {
            try await store.activate(dataset, from: payload)
        } catch {
            return await failure(.activation, active: active, provider: provider, category: category, error: error)
        }
        try? await derivedCache.invalidate(
            affectedBy: category, newVersion: dataset.normalizedVersion)
        return .activated(previous: active?.sourceVersion, current: payload.version.sourceVersion)
    }

    public func rollback(category: DataCategory) async throws -> KnowledgeDataset {
        let restored = try await store.rollback(category: category)
        try await derivedCache.invalidate(
            affectedBy: category, newVersion: restored.normalizedVersion)
        return restored
    }

    private func failure<P: GameDataProvider>(
        _ stage: UpdateFailureStage,
        active: ProviderVersion?,
        provider: P,
        category: DataCategory,
        error: Error
    ) async -> KnowledgeUpdateResult {
        let message = String(describing: error)
        try? await store.recordFailure(
            provider: provider.descriptor.name, category: category, error: message)
        return .failedUsingLastKnownGood(
            stage: stage, activeVersion: active?.sourceVersion, message: message)
    }
}
