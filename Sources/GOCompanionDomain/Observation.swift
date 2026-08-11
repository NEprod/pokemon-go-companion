import Foundation

public enum ScanSource: String, Codable, Sendable {
    case macWindow, macRegion, screenshotImport, manualEntry
}

public enum ScanSessionStatus: String, Codable, Sendable {
    case active, awaitingMoreInformation, completed, abandoned
}

public struct ScanSession: Codable, Hashable, Sendable {
    public let id: UUID
    public let source: ScanSource
    public var candidateRecordID: UUID?
    public var status: ScanSessionStatus
    public let startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(), source: ScanSource, candidateRecordID: UUID? = nil,
        status: ScanSessionStatus = .active, startedAt: Date = Date(), endedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.candidateRecordID = candidateRecordID
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct PokemonObservation: Codable, Hashable, Sendable {
    public let id: UUID
    public let scanSessionID: UUID
    public let observedAt: Date
    public var speciesID: Observed<String>?
    public var formID: Observed<String>?
    public var cp: Observed<Int>?
    public var hp: Observed<Int>?
    public var ivs: Observed<IVs>?
    public var moves: Observed<MoveSet>?
    public var traits: Observed<Set<PokemonTrait>>?

    public init(id: UUID = UUID(), scanSessionID: UUID, observedAt: Date = Date()) {
        self.id = id
        self.scanSessionID = scanSessionID
        self.observedAt = observedAt
        speciesID = nil
        formID = nil
        cp = nil
        hp = nil
        ivs = nil
        moves = nil
        traits = nil
    }
}

public enum ReconciliationKind: String, Codable, Sendable {
    case probableDuplicate, probablePowerUp, probableEvolution, conflictingObservation
}

public enum ReviewState: String, Codable, Sendable {
    case open, resolved, dismissed
}

public struct ReconciliationTask: Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: ReconciliationKind
    public let candidateRecordIDs: [UUID]
    public let observationID: UUID
    public let confidence: Confidence
    public var state: ReviewState
    public let createdAt: Date

    public init(
        id: UUID = UUID(), kind: ReconciliationKind, candidateRecordIDs: [UUID],
        observationID: UUID, confidence: Confidence, state: ReviewState = .open,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.candidateRecordIDs = candidateRecordIDs
        self.observationID = observationID
        self.confidence = confidence
        self.state = state
        self.createdAt = createdAt
    }
}
