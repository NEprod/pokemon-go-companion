import Foundation
import GOCompanionScreenAnalysis

public enum CandidateTransitionPhase: String, Sendable {
    case no, possible, corroborating, new, review
}

public struct CandidateRollover: Sendable {
    public let previousID: UUID
    public let nextID: UUID
    public let at: Date
}

/// One in-memory walkthrough can contain several one-Pokémon scan sessions. A change in
/// Appraisal never mutates the established session until independent identity fields agree
/// across multiple frames. No permanent specimen reconciliation is attempted here.
public struct PokemonWalkthroughCoordinator: Sendable {
    public let id: UUID
    public private(set) var assembler = ScanSessionAssembler()
    public private(set) var completed: [TemporaryPokemonScanSession] = []
    public private(set) var transitionPhase: CandidateTransitionPhase = .no
    public private(set) var transitionEvidence = "No candidate change observed."
    public private(set) var quarantinedObservationCount = 0
    public private(set) var lastRollover: CandidateRollover?
    private var pending: PendingTransition?

    public var current: TemporaryPokemonScanSession? { assembler.current }
    public var lastFinished: TemporaryPokemonScanSession? { assembler.lastFinished }
    public var candidateCount: Int { completed.count + (current == nil ? 0 : 1) }
    public var quarantinedSummary: [String] {
        guard let pending else { return [] }
        let grouped = Dictionary(grouping: pending.observations) {
            "\($0.field.rawValue)=\($0.value.description)"
        }
        return grouped.keys.sorted().prefix(8).map { key in
            "\(key) ×\(grouped[key]?.map(\.frameID).uniquedCount ?? 0) frame(s)"
        }
    }

    public init(id: UUID = UUID()) { self.id = id }

    public mutating func receive(
        stableScreen: ScreenType?, observations: [FieldObservation], at date: Date = Date(),
        actionMenuVisible: Bool = false
    ) {
        guard stableScreen == .appraisal, !actionMenuVisible, !observations.isEmpty,
            let established = assembler.current
        else {
            let priorID = assembler.current?.id
            assembler.receive(
                stableScreen: stableScreen, observations: observations, at: date,
                actionMenuVisible: actionMenuVisible)
            if priorID != nil, assembler.current == nil, let finished = assembler.lastFinished,
                completed.last?.id != finished.id
            {
                completed.append(finished)
                pending = nil
                transitionPhase = .no
                quarantinedObservationCount = 0
            }
            return
        }

        let reference = Dictionary(
            uniqueKeysWithValues: established.consensus.compactMap { result -> (ExtractionField, ExtractionValue)? in
                guard result.status == .corroborated, let value = result.value else { return nil }
                return (result.field, value)
            })
        let changed = observations.filter { item in
            item.confidence >= 0.65
                && (Self.identityFields.contains(item.field) || Self.ivFields.contains(item.field))
                && reference[item.field].map { $0 != item.value } == true
        }
        let returningToEstablished =
            pending != nil && changed.isEmpty
            && observations.contains { item in
                Self.identityFields.contains(item.field) && reference[item.field] == item.value
            }
        if returningToEstablished {
            pending = nil
            transitionPhase = .no
            transitionEvidence = "Changed value did not recur; established candidate retained."
            quarantinedObservationCount = 0
        }
        if transitionPhase == .review && !returningToEstablished {
            transitionEvidence = "Conflicting transition evidence remains quarantined for review."
            return
        }
        if pending == nil && changed.isEmpty {
            assembler.receive(stableScreen: .appraisal, observations: observations, at: date)
            if transitionPhase == .new { transitionPhase = .no }
            return
        }
        if pending == nil { pending = PendingTransition() }
        guard var hypothesis = pending else { return }
        let currentIdentity = observations.filter { Self.identityFields.contains($0.field) }
        let mixedWithEstablished =
            !changed.isEmpty
            && currentIdentity.contains { item in
                reference[item.field] == item.value
                    && hypothesis.changedValues[item.field].map { $0 != item.value } == true
            }
        let incompatible = changed.contains { item in
            hypothesis.changedValues[item.field].map { $0 != item.value } == true
        }
        if mixedWithEstablished || incompatible {
            hypothesis.append(observations, changed: [], safeIdentityFrame: false)
            transitionPhase = .review
            transitionEvidence = "Mixed or incompatible identity frames; no automatic rollover."
            quarantinedObservationCount = hypothesis.observations.count
            pending = hypothesis
            return
        }
        let safeIdentityFrame =
            changed.contains { Self.identityFields.contains($0.field) }
            && !currentIdentity.contains { item in
                hypothesis.changedValues[item.field].map { $0 != item.value } == true
                    || (reference[item.field] == item.value && hypothesis.changedValues[item.field] != nil)
            }
        hypothesis.append(observations, changed: changed, safeIdentityFrame: safeIdentityFrame)
        pending = hypothesis
        quarantinedObservationCount = hypothesis.observations.count
        let identityFrames = Dictionary(
            uniqueKeysWithValues: hypothesis.changedValues.compactMap {
                field, value -> (ExtractionField, Set<UInt64>)? in
                guard Self.identityFields.contains(field) else { return nil }
                return (field, hypothesis.frames(for: field, value: value))
            })
        let corroborated = identityFrames.filter { $0.value.count >= 2 }
        let ivTupleFrames = hypothesis.repeatedChangedIVTupleFrames(comparedTo: reference)
        let coherentIVAndIdentity = [ExtractionField.cp, .hpMaximum].contains { field in
            guard let frames = identityFrames[field] else { return false }
            return frames.intersection(ivTupleFrames).count >= 2
        }
        let coherentCPAndCurrentHP =
            hypothesis.repeatedChangedCurrentHPFrames(comparedTo: reference)
            .intersection(identityFrames[.cp] ?? []).count >= 3
        let confirmed =
            (corroborated.count >= 2 && hypothesis.safeIdentityFrames.count >= 2)
            || coherentIVAndIdentity || coherentCPAndCurrentHP
        transitionEvidence =
            "Changed identity: \(hypothesis.changedValues.keys.map(\.rawValue).sorted().joined(separator: ", ")); "
            + "\(corroborated.count) independently repeated field(s) across "
            + "\(hypothesis.safeIdentityFrames.count) compatible frame(s); "
            + "changed full IV tuple in \(ivTupleFrames.count) frame(s)."
        if confirmed {
            let promoted = hypothesis.promotableObservations()
            let previousID = established.id
            assembler.finishCurrent(at: date)
            if let finished = assembler.lastFinished { completed.append(finished) }
            assembler.beginConfirmedAppraisalCandidate(observations: promoted, at: date)
            if let nextID = assembler.current?.id {
                lastRollover = CandidateRollover(previousID: previousID, nextID: nextID, at: date)
            }
            transitionPhase = .new
            transitionEvidence = "Coherent multi-field change corroborated; compatible buffered observations promoted."
            pending = nil
            quarantinedObservationCount = 0
        } else if hypothesis.safeIdentityFrames.count >= 6 || hypothesis.observations.count >= 48 {
            transitionPhase = .review
            transitionEvidence += " Evidence stayed insufficient; review required."
        } else if hypothesis.safeIdentityFrames.count >= 2 {
            transitionPhase = .corroborating
        } else {
            transitionPhase = .possible
        }
    }

    private static let identityFields: Set<ExtractionField> = [.displayedName, .cp, .hpMaximum]
    private static let ivFields: Set<ExtractionField> = [.ivAttack, .ivDefense, .ivHP]
}

private struct PendingTransition: Sendable {
    var observations: [FieldObservation] = []
    var changedValues: [ExtractionField: ExtractionValue] = [:]
    var safeIdentityFrames: Set<UInt64> = []

    mutating func append(
        _ incoming: [FieldObservation], changed: [FieldObservation], safeIdentityFrame: Bool
    ) {
        for item in changed where [.displayedName, .cp, .hpMaximum].contains(item.field) {
            changedValues[item.field] = item.value
        }
        if safeIdentityFrame, let frameID = incoming.first?.frameID { safeIdentityFrames.insert(frameID) }
        observations.append(contentsOf: incoming)
        if observations.count > 48 { observations.removeFirst(observations.count - 48) }
    }

    func frames(for field: ExtractionField, value: ExtractionValue) -> Set<UInt64> {
        Set(observations.filter { $0.field == field && $0.value == value }.map(\.frameID))
            .intersection(safeIdentityFrames)
    }

    /// A complete tuple must occur in the same frame; separate bar counters are not a tuple.
    /// Only a single repeated changed tuple can corroborate a transition.
    func repeatedChangedIVTupleFrames(comparedTo reference: [ExtractionField: ExtractionValue]) -> Set<UInt64> {
        guard let baseline = IVTuple(values: reference) else { return [] }
        let byFrame = Dictionary(grouping: observations, by: \.frameID)
        let groups = Dictionary(
            grouping: byFrame.compactMap { frameID, items -> (IVTuple, UInt64)? in
                guard safeIdentityFrames.contains(frameID), let tuple = IVTuple(observations: items), tuple != baseline
                else { return nil }
                return (tuple, frameID)
            }, by: \.0)
        let recurring = groups.values.map { Set($0.map(\.1)) }.filter { $0.count >= 2 }
        return recurring.count == 1 ? recurring[0] : []
    }

    func repeatedChangedCurrentHPFrames(comparedTo reference: [ExtractionField: ExtractionValue]) -> Set<UInt64> {
        guard let old = reference[.hpCurrent] else { return [] }
        let groups = Dictionary(
            grouping: observations.filter {
                $0.field == .hpCurrent && $0.value != old && safeIdentityFrames.contains($0.frameID)
            }, by: \.value)
        let recurring = groups.values.map { Set($0.map(\.frameID)) }.filter { $0.count >= 2 }
        return recurring.count == 1 ? recurring[0] : []
    }

    func promotableObservations() -> [FieldObservation] {
        let verifiedIVs = Set(
            observations.filter { item in
                guard [.ivAttack, .ivDefense, .ivHP].contains(item.field) else { return false }
                let matching = observations.filter { $0.field == item.field && $0.value == item.value }
                return matching.map(\.frameID).uniquedCount >= 2
                    && matching.contains { safeIdentityFrames.contains($0.frameID) }
            }.map { IVKey(field: $0.field, value: $0.value) })
        return observations.filter { item in
            if let confirmedValue = changedValues[item.field], confirmedValue != item.value { return false }
            if [.ivAttack, .ivDefense, .ivHP].contains(item.field) {
                return verifiedIVs.contains(IVKey(field: item.field, value: item.value))
            }
            return safeIdentityFrames.contains(item.frameID)
        }
    }
}

private struct IVKey: Hashable {
    let field: ExtractionField
    let value: ExtractionValue
}

private struct IVTuple: Hashable {
    let attack: ExtractionValue
    let defense: ExtractionValue
    let hp: ExtractionValue

    init?(values: [ExtractionField: ExtractionValue]) {
        guard let attack = values[.ivAttack], let defense = values[.ivDefense], let hp = values[.ivHP]
        else { return nil }
        self.attack = attack
        self.defense = defense
        self.hp = hp
    }

    init?(observations: [FieldObservation]) {
        let groups = Dictionary(
            grouping: observations.filter {
                [.ivAttack, .ivDefense, .ivHP].contains($0.field)
            }, by: \.field)
        guard groups.values.allSatisfy({ Set($0.map(\.value)).count == 1 }) else { return nil }
        self.init(values: groups.compactMapValues { $0.first?.value })
    }
}

private extension Array where Element == UInt64 {
    var uniquedCount: Int { Set(self).count }
}
