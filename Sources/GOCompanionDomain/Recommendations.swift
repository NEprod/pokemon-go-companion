import Foundation

public enum RecommendationAction: String, Codable, Sendable {
    case keep, transfer, trade, evolve, powerUp, changeMove, wait, review, megaUnlock, maxUpgrade
}

public struct RecommendationReason: Codable, Hashable, Sendable {
    public let code: String
    public let summary: String
    public let factReferences: [String]

    public init(code: String, summary: String, factReferences: [String] = []) {
        self.code = code
        self.summary = summary
        self.factReferences = factReferences
    }
}

public struct Recommendation: Codable, Hashable, Sendable {
    public let subjectID: UUID
    public let action: RecommendationAction
    public let recommendedTags: Set<GOTag>
    public let reasons: [RecommendationReason]
    public let nextAction: String?
    public let confidence: Confidence
    public let provenance: AnalysisProvenance

    public init(
        subjectID: UUID, action: RecommendationAction, recommendedTags: Set<GOTag>,
        reasons: [RecommendationReason], nextAction: String?, confidence: Confidence,
        provenance: AnalysisProvenance
    ) {
        self.subjectID = subjectID
        self.action = action
        self.recommendedTags = recommendedTags
        self.reasons = reasons
        self.nextAction = nextAction
        self.confidence = confidence
        self.provenance = provenance
    }
}

public enum HistoryEventType: String, Codable, Sendable {
    case created, scanned, updated, poweredUp, evolved, moveChanged, secondMoveUnlocked
    case purified, megaUnlocked, megaProgressed, tagChanged, recommendedTagChanged
    case transferRecommended, tradeRecommended, transferred, traded, archived, reconciled, restored
}

public struct HistoryChange: Codable, Hashable, Sendable {
    public let field: String
    public let previousValue: String?
    public let newValue: String?

    public init(field: String, previousValue: String? = nil, newValue: String? = nil) {
        self.field = field
        self.previousValue = previousValue
        self.newValue = newValue
    }
}

public struct CollectionHistoryEvent: Codable, Hashable, Sendable {
    public let id: UUID
    public let pokemonID: UUID
    public let type: HistoryEventType
    public let occurredAt: Date
    public let reason: String?
    public let source: String
    public let changes: [HistoryChange]
    public let provenance: FieldProvenance?
    public let correlationID: UUID

    public init(
        id: UUID = UUID(), pokemonID: UUID, type: HistoryEventType,
        occurredAt: Date = Date(), reason: String? = nil, source: String,
        changes: [HistoryChange] = [], provenance: FieldProvenance? = nil,
        correlationID: UUID = UUID()
    ) {
        self.id = id
        self.pokemonID = pokemonID
        self.type = type
        self.occurredAt = occurredAt
        self.reason = reason
        self.source = source
        self.changes = changes
        self.provenance = provenance
        self.correlationID = correlationID
    }
}
