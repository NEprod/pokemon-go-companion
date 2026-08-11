import Foundation
import GOCompanionDomain

public struct SourceCacheKey: Codable, Hashable, Sendable {
    public let provider: String
    public let category: DataCategory
    public let sourceVersion: String
}

public protocol SourceCache: Sendable {
    func storeValidated(_ payload: ProviderPayload, key: SourceCacheKey) async throws
    func payload(for key: SourceCacheKey) async throws -> ProviderPayload?
    func markActive(_ key: SourceCacheKey, retainingPrevious: Bool) async throws
}

public protocol NormalizedKnowledgeStore: Sendable {
    func activateStagedVersion(category: DataCategory, version: ProviderVersion) async throws
    func activeVersion(category: DataCategory) async throws -> ProviderVersion?
    func rollback(category: DataCategory) async throws
}

public struct DerivedCacheKey: Codable, Hashable, Sendable {
    public let kind: String
    public let subject: String
    public let inputVersions: [String: String]
    public let engineVersion: String

    public init(kind: String, subject: String, inputVersions: [String: String], engineVersion: String) {
        self.kind = kind
        self.subject = subject
        self.inputVersions = inputVersions
        self.engineVersion = engineVersion
    }
}

public protocol DerivedAnalysisCache: Sendable {
    func data(for key: DerivedCacheKey) async throws -> Data?
    func store(_ data: Data, for key: DerivedCacheKey) async throws
    func invalidate(affectedBy category: DataCategory, newVersion: String) async throws
    func rebuildableDataMayBeDiscarded() async throws
}

public protocol KnowledgeUpdateCoordinator: Sendable {
    /// Opens with local data; all freshness work must occur off the startup-critical path.
    func refreshStaleCategories() async
    func state(for category: DataCategory) async -> ProviderState?
}
