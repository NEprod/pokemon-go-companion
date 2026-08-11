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
    /// Nil for explicitly confirmed values; numeric confidence is reserved for uncertain evidence.
    public let confidence: Confidence?
    public let provenance: FieldProvenance
    public let sourceRegion: String?

    public init(
        value: Value,
        confidence: Confidence?,
        provenance: FieldProvenance,
        sourceRegion: String? = nil
    ) {
        self.value = value
        self.confidence = confidence
        self.provenance = provenance
        self.sourceRegion = sourceRegion
    }

    public static func manuallyConfirmed(_ value: Value, source: String? = nil) -> Self {
        Self(value: value, confidence: nil, provenance: .init(kind: .manuallyConfirmed, source: source))
    }
}

public enum EvidenceKind: String, Codable, CaseIterable, Sendable {
    case manuallyConfirmed, scannerObserved, imported, inferred, unknown
}

public struct FieldProvenance: Codable, Hashable, Sendable {
    public let kind: EvidenceKind
    public let source: String?
    public let sourceVersion: String?

    public init(kind: EvidenceKind, source: String? = nil, sourceVersion: String? = nil) {
        self.kind = kind
        self.source = source
        self.sourceVersion = sourceVersion
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
