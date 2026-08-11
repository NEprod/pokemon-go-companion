import Foundation

public struct Confidence: Codable, Hashable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard (0...1).contains(value), value.isFinite else {
            throw DomainError.invalidConfidence(value)
        }
        self.value = value
    }

    public static let certain = try! Confidence(1)
}

public struct Observed<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let value: Value
    public let confidence: Confidence
    public let sourceRegion: String?

    public init(value: Value, confidence: Confidence, sourceRegion: String? = nil) {
        self.value = value
        self.confidence = confidence
        self.sourceRegion = sourceRegion
    }
}

public enum DomainError: Error, Equatable {
    case invalidConfidence(Double)
    case invalidIV(Int)
    case invalidPriority(Int)
}

public struct IVs: Codable, Hashable, Sendable {
    public let attack: Int
    public let defense: Int
    public let stamina: Int

    public init(attack: Int, defense: Int, stamina: Int) throws {
        guard [attack, defense, stamina].allSatisfy((0...15).contains) else {
            throw DomainError.invalidIV(max(attack, defense, stamina))
        }
        self.attack = attack
        self.defense = defense
        self.stamina = stamina
    }
}

public struct KnowledgeVersion: Codable, Hashable, Sendable {
    public let category: String
    public let sourceVersion: String
    public let activatedAt: Date

    public init(category: String, sourceVersion: String, activatedAt: Date) {
        self.category = category
        self.sourceVersion = sourceVersion
        self.activatedAt = activatedAt
    }
}

public struct AnalysisProvenance: Codable, Hashable, Sendable {
    public let knowledgeVersions: [KnowledgeVersion]
    public let engineVersion: String
    public let generatedAt: Date

    public init(knowledgeVersions: [KnowledgeVersion], engineVersion: String, generatedAt: Date) {
        self.knowledgeVersions = knowledgeVersions
        self.engineVersion = engineVersion
        self.generatedAt = generatedAt
    }
}
