import Foundation
import GOCompanionScreenAnalysis

public struct SessionFieldObservation: Sendable {
    public let sessionID: UUID
    public let observation: FieldObservation
}

public struct FieldConsensus: Sendable {
    public let field: ExtractionField
    public let value: ExtractionValue?
    public let supportingFrames: Int
    public let alternatives: [ExtractionValue]
    public let status: Status

    public enum Status: String, Sendable { case provisional, corroborated, conflict }
}

/// Bounded per-value evidence. The examples retain provenance without retaining every video frame.
public struct ObservationAggregate: Sendable {
    public let field: ExtractionField
    public let value: ExtractionValue
    public private(set) var occurrences: Int
    public private(set) var sourceStrengthSum: Double
    public let first: FieldObservation
    public private(set) var latest: FieldObservation

    fileprivate init(_ observation: FieldObservation) {
        field = observation.field
        value = observation.value
        occurrences = 1
        sourceStrengthSum = observation.confidence
        first = observation
        latest = observation
    }

    fileprivate mutating func record(_ observation: FieldObservation) {
        guard observation.frameID != latest.frameID else { return }
        occurrences += 1
        sourceStrengthSum += observation.confidence
        latest = observation
    }
}

public struct TemporaryPokemonScanSession: Identifiable, Sendable {
    public static let recentObservationLimit = 48
    public static let variantLimitPerField = 12
    public let id: UUID
    public let startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var observations: [SessionFieldObservation] = []
    public private(set) var quarantinedIdentityObservations: [ObservationAggregate] = []
    public private(set) var unverifiedAppraisalObservations: [ObservationAggregate] = []
    public private(set) var overflowedVariantOccurrencesByField: [ExtractionField: Int] = [:]
    public private(set) var possibleNewPokemon = false
    private var acceptedEvidence: [ObservationAggregate] = []

    public var overflowedVariantOccurrences: Int {
        overflowedVariantOccurrencesByField.values.reduce(0, +)
    }

    public init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }

    public var consensus: [FieldConsensus] {
        ExtractionField.allCases.compactMap { consensus(for: $0) }
    }

    private func consensus(for field: ExtractionField) -> FieldConsensus? {
        let candidates = (acceptedEvidence + quarantinedIdentityObservations).filter { $0.field == field }
        guard !candidates.isEmpty else { return nil }
        let groups: [(value: ExtractionValue, frames: Int, weight: Double)] = Dictionary(
            grouping: candidates, by: \.value
        ).map { value, entries in
            let frames = entries.reduce(0) { $0 + $1.occurrences }
            // Repetition is corroboration, not a calibrated probability of correctness.
            let weight = entries.reduce(0.0) { $0 + $1.sourceStrengthSum }
            return (value, frames, weight)
        }.sorted { $0.weight == $1.weight ? $0.value.description < $1.value.description : $0.weight > $1.weight }
        let first = groups[0]
        let resolved =
            overflowedVariantOccurrencesByField[field] == nil
            && (groups.count == 1 || (first.frames >= 2 && first.weight >= groups[1].weight + 0.5))
        return FieldConsensus(
            field: field, value: resolved ? first.value : nil, supportingFrames: first.frames,
            alternatives: (resolved ? Array(groups.dropFirst()) : groups).map(\.value),
            status: resolved ? (first.frames >= 2 ? .corroborated : .provisional) : .conflict)
    }

    fileprivate mutating func append(_ incoming: [FieldObservation]) {
        for item in incoming {
            guard
                !(acceptedEvidence + quarantinedIdentityObservations).contains(where: {
                    $0.field == item.field && $0.latest.frameID == item.frameID
                })
            else { continue }
            if [.displayedName, .cp, .hpMaximum].contains(item.field),
                let established = consensus.first(where: { $0.field == item.field }),
                established.status == .corroborated,
                let prior = established.value,
                prior != item.value, item.confidence >= 0.75
            {
                possibleNewPokemon = true
                if !Self.store(item, in: &quarantinedIdentityObservations) { recordOverflow(for: item.field) }
                continue
            }
            if !Self.store(item, in: &acceptedEvidence) { recordOverflow(for: item.field) }
            observations.append(.init(sessionID: id, observation: item))
            if observations.count > Self.recentObservationLimit {
                observations.removeFirst(observations.count - Self.recentObservationLimit)
            }
        }
    }

    fileprivate mutating func appendAppraisal(_ incoming: [FieldObservation]) {
        let identity = incoming.filter { [.displayedName, .cp].contains($0.field) }
        let established = consensus.filter { [.displayedName, .cp].contains($0.field) }
        let matched = identity.contains { item in
            established.contains { $0.field == item.field && $0.value == item.value }
        }
        let contradicted = identity.contains { item in
            established.contains { $0.field == item.field && $0.value != nil && $0.value != item.value }
        }
        guard matched && !contradicted else {
            if contradicted { possibleNewPokemon = true }
            for item in identity {
                if !Self.store(item, in: &quarantinedIdentityObservations) { recordOverflow(for: item.field) }
            }
            for item in incoming where [.ivAttack, .ivDefense, .ivHP].contains(item.field) {
                if !Self.store(item, in: &unverifiedAppraisalObservations) { recordOverflow(for: item.field) }
            }
            return
        }
        append(incoming)
    }

    @discardableResult
    private static func store(_ item: FieldObservation, in entries: inout [ObservationAggregate]) -> Bool {
        if let index = entries.firstIndex(where: { $0.field == item.field && $0.value == item.value }) {
            entries[index].record(item)
            return true
        } else if entries.filter({ $0.field == item.field }).count < Self.variantLimitPerField {
            entries.append(ObservationAggregate(item))
            return true
        } else {
            // Preserve that additional distinct values occurred without retaining unbounded OCR noise.
            return false
        }
    }

    private mutating func recordOverflow(for field: ExtractionField) {
        overflowedVariantOccurrencesByField[field, default: 0] += 1
    }

    fileprivate mutating func finish(at date: Date) { endedAt = date }
}

/// In-memory assembly only. No collection repository or permanent specimen UUID is involved.
public struct ScanSessionAssembler: Sendable {
    public private(set) var current: TemporaryPokemonScanSession?
    public private(set) var lastFinished: TemporaryPokemonScanSession?
    public private(set) var actionMenuTransitionFramesRemaining = 0

    /// Allows the two positive frames needed to establish Appraisal after the menu closes.
    /// A genuinely different supported screen still ends the session once this short bridge expires.
    public static let actionMenuTransitionAllowance = 3

    public init() {}

    /// Called only after a walkthrough has corroborated a different visible identity.
    /// The new UUID is a temporary specimen candidate, never a collection specimen ID.
    public mutating func beginConfirmedAppraisalCandidate(
        observations: [FieldObservation], at date: Date = Date()
    ) {
        precondition(current == nil)
        current = TemporaryPokemonScanSession(startedAt: date)
        current?.append(observations.filter { $0.sourceScreen == .appraisal })
        actionMenuTransitionFramesRemaining = 0
    }

    public mutating func finishCurrent(at date: Date = Date()) {
        guard current != nil else { return }
        current?.finish(at: date)
        lastFinished = current
        current = nil
        actionMenuTransitionFramesRemaining = 0
    }

    public mutating func receive(
        stableScreen: ScreenType?, observations: [FieldObservation], at date: Date = Date(),
        actionMenuVisible: Bool = false
    ) {
        if actionMenuVisible {
            if current != nil { actionMenuTransitionFramesRemaining = Self.actionMenuTransitionAllowance }
            return
        }
        if stableScreen == .pokemonDetail || stableScreen == .appraisal {
            actionMenuTransitionFramesRemaining = 0
        } else if current != nil && actionMenuTransitionFramesRemaining > 0 {
            actionMenuTransitionFramesRemaining -= 1
            return
        }
        switch stableScreen {
        case .pokemonDetail:
            if current == nil { current = TemporaryPokemonScanSession(startedAt: date) }
            current?.append(observations.filter { $0.sourceScreen == .pokemonDetail })
        case .appraisal:
            // Appraisal joins only an already established Detail session with matching visible identity.
            current?.appendAppraisal(observations.filter { $0.sourceScreen == .appraisal })
        case nil:
            break
        default:
            finishCurrent(at: date)
        }
    }
}
