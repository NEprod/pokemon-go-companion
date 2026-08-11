import Foundation
import GOCompanionDomain

public struct CollectionService: Sendable {
    private let repository: any CollectionRepository
    private let now: @Sendable () -> Date

    public init(
        repository: any CollectionRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.now = now
    }

    public func create(_ draft: PokemonRecord, source: String = "manual") throws -> PokemonRecord {
        var record = draft
        let timestamp = now()
        record.status = .active
        record.revision = 1
        record.createdAt = timestamp
        record.updatedAt = timestamp
        let event = CollectionHistoryEvent(
            pokemonID: record.identity.recordID,
            type: .created,
            occurredAt: timestamp,
            reason: "Created collection record",
            source: source,
            provenance: .init(kind: .manuallyConfirmed, source: source)
        )
        try repository.create(record, event: event)
        return record
    }

    public func pokemon(id: UUID) throws -> PokemonRecord {
        guard let record = try repository.pokemon(id: id) else {
            throw CollectionEngineError.pokemonNotFound(id)
        }
        return record
    }

    public func list(_ query: CollectionQuery = .active) throws -> [PokemonRecord] {
        try repository.list(query)
    }

    public func update(
        _ revised: PokemonRecord,
        reason: String,
        source: String = "manual"
    ) throws -> PokemonRecord {
        let current = try pokemon(id: revised.identity.recordID)
        guard !current.status.isArchived else {
            throw CollectionEngineError.invalidTransition(from: current.status, to: revised.status)
        }
        var record = revised
        record.identity = PokemonIdentity(
            recordID: current.identity.recordID,
            speciesID: revised.identity.speciesID,
            formID: revised.identity.formID,
            fingerprint: revised.identity.fingerprint
        )
        record.status = current.status
        record.createdAt = current.createdAt
        record.updatedAt = now()
        record.revision = current.revision + 1
        let event = CollectionHistoryEvent(
            pokemonID: current.identity.recordID,
            type: .updated,
            occurredAt: record.updatedAt,
            reason: reason,
            source: source,
            changes: Self.changes(from: current, to: record),
            provenance: .init(kind: .manuallyConfirmed, source: source)
        )
        return try repository.save(record, expectedRevision: revised.revision, event: event)
    }

    public func markTransferRecommended(
        id: UUID,
        reason: String,
        recommendationVersion: String
    ) throws -> PokemonRecord {
        try markRemovalRecommended(
            id: id,
            tag: .transfer,
            eventType: .transferRecommended,
            reason: reason,
            recommendationVersion: recommendationVersion
        )
    }

    public func markTradeRecommended(
        id: UUID,
        reason: String,
        recommendationVersion: String
    ) throws -> PokemonRecord {
        try markRemovalRecommended(
            id: id,
            tag: .trade,
            eventType: .tradeRecommended,
            reason: reason,
            recommendationVersion: recommendationVersion
        )
    }

    public func confirmTransferred(id: UUID, reason: String? = nil) throws -> PokemonRecord {
        try transition(id: id, to: .archivedTransferred, eventType: .transferred, reason: reason)
    }

    public func confirmTraded(id: UUID, reason: String? = nil) throws -> PokemonRecord {
        try transition(id: id, to: .archivedTraded, eventType: .traded, reason: reason)
    }

    public func archiveOther(id: UUID, reason: String) throws -> PokemonRecord {
        try transition(id: id, to: .archivedOther, eventType: .archived, reason: reason)
    }

    public func restoreArchived(id: UUID, reason: String) throws -> PokemonRecord {
        let current = try pokemon(id: id)
        guard current.status.isArchived else {
            throw CollectionEngineError.invalidTransition(from: current.status, to: .active)
        }
        return try transition(id: id, to: .active, eventType: .restored, reason: reason)
    }

    public func recordObservation(
        session: ScanSession,
        observation: PokemonObservation,
        source: String
    ) throws {
        guard observation.scanSessionID == session.id else {
            throw CollectionEngineError.invalidBackup("observation and session identifiers differ")
        }
        if let pokemonID = observation.pokemonID {
            _ = try pokemon(id: pokemonID)
        }
        let event = observation.pokemonID.map {
            CollectionHistoryEvent(
                pokemonID: $0,
                type: .scanned,
                occurredAt: observation.observedAt,
                reason: "Observation recorded",
                source: source,
                provenance: .init(kind: .imported, source: source)
            )
        }
        try repository.addObservation(session: session, observation: observation, event: event)
    }

    public func history(for id: UUID) throws -> [CollectionHistoryEvent] {
        _ = try pokemon(id: id)
        return try repository.history(for: id)
    }

    public func observations(for id: UUID) throws -> [PokemonObservation] {
        _ = try pokemon(id: id)
        return try repository.observations(for: id)
    }

    private func markRemovalRecommended(
        id: UUID,
        tag: GOTag,
        eventType: HistoryEventType,
        reason: String,
        recommendationVersion: String
    ) throws -> PokemonRecord {
        let current = try pokemon(id: id)
        guard !current.status.isArchived else {
            throw CollectionEngineError.invalidTransition(from: current.status, to: .pendingRemoval)
        }
        var revised = current
        let timestamp = now()
        revised.status = .pendingRemoval
        revised.recommendedGOTags.removeAll { $0.tag == tag }
        revised.recommendedGOTags.append(
            RecommendedGOTag(
                tag: tag,
                reason: reason,
                createdAt: timestamp,
                updatedAt: timestamp,
                sourceVersion: recommendationVersion
            ))
        revised.updatedAt = timestamp
        revised.revision += 1
        let event = CollectionHistoryEvent(
            pokemonID: id,
            type: eventType,
            occurredAt: timestamp,
            reason: reason,
            source: "recommendation-framework",
            changes: [.init(field: "status", previousValue: current.status.rawValue, newValue: revised.status.rawValue)]
        )
        return try repository.save(revised, expectedRevision: current.revision, event: event)
    }

    private func transition(
        id: UUID,
        to status: CollectionStatus,
        eventType: HistoryEventType,
        reason: String?
    ) throws -> PokemonRecord {
        let current = try pokemon(id: id)
        if status.isArchived {
            guard !current.status.isArchived else {
                throw CollectionEngineError.invalidTransition(from: current.status, to: status)
            }
        }
        var revised = current
        revised.status = status
        revised.updatedAt = now()
        revised.revision += 1
        let event = CollectionHistoryEvent(
            pokemonID: id,
            type: eventType,
            occurredAt: revised.updatedAt,
            reason: reason,
            source: "manual-confirmation",
            changes: [.init(field: "status", previousValue: current.status.rawValue, newValue: status.rawValue)],
            provenance: .init(kind: .manuallyConfirmed, source: "manual-confirmation")
        )
        return try repository.save(revised, expectedRevision: current.revision, event: event)
    }

    private static func changes(from old: PokemonRecord, to new: PokemonRecord) -> [HistoryChange] {
        var result: [HistoryChange] = []
        func append(_ field: String, _ before: String?, _ after: String?) {
            if before != after { result.append(.init(field: field, previousValue: before, newValue: after)) }
        }
        append("speciesID", old.identity.speciesID, new.identity.speciesID)
        append("formID", old.identity.formID, new.identity.formID)
        append("cp", old.cp.map(String.init), new.cp.map(String.init))
        append("hp", old.hp.map(String.init), new.hp.map(String.init))
        append("nickname", old.nickname, new.nickname)
        append("moves", String(describing: old.moves), String(describing: new.moves))
        append(
            "traits", String(describing: old.traits.sorted { $0.rawValue < $1.rawValue }),
            String(describing: new.traits.sorted { $0.rawValue < $1.rawValue }))
        append(
            "internalTags", String(describing: old.internalTags.sorted()), String(describing: new.internalTags.sorted())
        )
        append(
            "roles", String(describing: old.roles.map(\.rawValue).sorted()),
            String(describing: new.roles.map(\.rawValue).sorted()))
        return result
    }
}
