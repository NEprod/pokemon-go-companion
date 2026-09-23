import Foundation
import GOCompanionDomain

public enum DataCategory: String, Codable, CaseIterable, Sendable {
    case gameMaster, pvpRankings, raidData, events, items, moveAcquisition
}

public struct ProviderDescriptor: Codable, Hashable, Sendable {
    public let name: String
    public let parserVersion: String
    public let categories: Set<DataCategory>

    public init(name: String, parserVersion: String, categories: Set<DataCategory>) {
        self.name = name
        self.parserVersion = parserVersion
        self.categories = categories
    }
}

public struct ProviderVersion: Codable, Hashable, Sendable {
    public let providerName: String
    public let category: DataCategory
    public let sourceVersion: String
    public let parserVersion: String
    public let fetchedAt: Date
    public let contentHash: String

    public init(
        providerName: String, category: DataCategory, sourceVersion: String,
        parserVersion: String, fetchedAt: Date, contentHash: String
    ) {
        self.providerName = providerName
        self.category = category
        self.sourceVersion = sourceVersion
        self.parserVersion = parserVersion
        self.fetchedAt = fetchedAt
        self.contentHash = contentHash
    }
}

public struct FreshnessPolicy: Codable, Hashable, Sendable {
    public let maximumAge: TimeInterval
    public let lightweightCheckInterval: TimeInterval

    public init(maximumAge: TimeInterval, lightweightCheckInterval: TimeInterval) {
        self.maximumAge = maximumAge
        self.lightweightCheckInterval = lightweightCheckInterval
    }
}

public enum UpdateStatus: String, Codable, Sendable {
    case neverFetched, current, stale, checking, failed
}

public struct ProviderState: Codable, Hashable, Sendable {
    public let descriptor: ProviderDescriptor
    public let category: DataCategory
    public var activeVersion: ProviderVersion?
    public var previousGoodVersion: ProviderVersion?
    public var status: UpdateStatus
    public var lastError: String?
}

public struct ProviderPayload: Sendable {
    public let bytes: Data
    public let version: ProviderVersion
    public let etag: String?

    public init(bytes: Data, version: ProviderVersion, etag: String? = nil) {
        self.bytes = bytes
        self.version = version
        self.etag = etag
    }
}

public protocol GameDataProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func checkVersion(for category: DataCategory) async throws -> String?
    func fetch(category: DataCategory, ifChangedFrom sourceVersion: String?) async throws -> ProviderPayload?
    func validate(_ payload: ProviderPayload, for category: DataCategory) throws
}

public protocol ProviderNormalizer: Sendable {
    associatedtype NormalizedBatch: Sendable
    var providerName: String { get }
    var parserVersion: String { get }
    func normalize(_ payload: ProviderPayload, category: DataCategory) throws -> NormalizedBatch
}
