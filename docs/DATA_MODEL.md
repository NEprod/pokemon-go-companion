# Data model and persistence

## Four semantic layers

1. **User facts:** observed/manual collection, inventory, resources, status, tags, plans, and history.
2. **Game knowledge:** provider-derived canonical species/forms, mechanics, moves, availability, events, rankings, and versions.
3. **User preferences:** goals, collection priorities, buffers, and investment conservatism; stored with user facts but modeled separately.
4. **Recommendations:** derived snapshots from the first three, returned with explanations/confidence/provenance. They are not durable facts and are safe to regenerate.

The three physical SQLite databases reinforce the boundary: `user.sqlite` is private and syncable/backed up; `knowledge.sqlite` is locally refreshable reference/source metadata; `derived.sqlite` is disposable. A coordinated read snapshot records input versions rather than relying on cross-file foreign keys.

## Core conceptual models

- `PokemonIdentity`: internal UUID, canonical species/form keys, optional reconciliation fingerprint.
- `PokemonRecord`: current accepted user facts, moves, traits, applied GO tags, collection status, timestamps. It references knowledge by stable string IDs, not database FK across files.
- `PokemonForm`: canonical reference identity/display/type summary; detailed stats and mechanics belong in knowledge models.
- `PokemonObservation`: one screen/import's field-level values, confidence, regions, time, and scan session. Observations are evidence, not automatically accepted facts.
- `ScanSession`: groups progressive detail/appraisal/moves/Max screens and points at a candidate specimen.
- `Confidence` / `Observed<T>`: bounded optional 0–1 confidence, evidence kind, source/version, and optional source region. Manually confirmed values deliberately carry no fabricated numeric confidence. IV Attack/Defence/Stamina have independent observation fields.
- `MoveSet`: current observed Fast and up to two Charged move IDs.
- `PokemonTrait` and applied tags: facts such as Shadow/Dynamax/Mega unlocked and tags observed in GO. `GOTag` is the recommendation vocabulary, not automatically applied.
- `Recommendation`, `RecommendationReason`: ephemeral What/Why/Next Action, confidence, evidence references, knowledge versions, and engine version.
- `PokemonRole`: role assignment used for collection comparison, distinct from tags and rankings.
- `CollectionStatus`: Active, Pending Review, Pending Removal, Archived Transferred, Archived Traded, or Archived Other. A recommendation remains non-archived until manual confirmation.
- `CollectionHistoryEvent`: append-oriented audit of scans/changes/evolution/purification/Mega/tags/archive/reconciliation; payload supports before/after detail.
- `ReconciliationTask`: uncertain duplicate/power-up/evolution/conflict, candidate IDs, evidence confidence, and review state.
- `UserProfile`, `UserGoal`: preferences and weighted priority 0–5, storage buffers, investment style.
- `Inventory`, `ResourceAmount`, `StorageProfile`: quantities with observation time/confidence and Pokémon/bag usage/capacity.
- `BuildPlan`: ordered manual steps and resource costs; it never executes game actions.
- `ProviderVersion` / `KnowledgeVersion`: provider/category/source/parser/hash/fetch/activation metadata.
- `EventOpportunity`: machine-readable, time-scoped event benefit with source and confidence.

Later reference models include species/form stats and restrictions, evolution graph/requirements/costs, CP multipliers/levels/costs, complete move mechanics and availability rules, types/effectiveness, leagues/cups, meta ranks, raids, Mega, Max/G-Max, items, and events. PvP IV tables and simulations are derived models, not source facts.

## Initial schemas and relationships

### User database

`profiles 1--* pokemon`; Pokémon own observed GO tags, internal tags, multiple roles, recommended GO-tag states, immutable history, and plans. `scan_sessions 1--* observations`; observations optionally reference the candidate Pokémon and preserve the full field evidence payload. Observations may later create reconciliation tasks. Resources and storage belong to a profile. Records retain `archived_at` and history rather than deletion.

Important indexes: profile/status; profile/species/form; non-null fingerprint; internal tag; role; recommended tag/state; observation session/time and Pokémon/time; reconciliation state/time; history specimen/time. Later indexes will cover confidence/recency and filter-heavy move/trait projections once query patterns are proven (JSON fields may be normalized then).

### Knowledge database

Provider versions and source-cache metadata establish active/previous source provenance. Versioned `species_forms`, `moves`, move-availability rules, `events`, and structured opportunities are representative—not the final complete Phase 2 schema. Stable canonical IDs plus `source_version` allow staged activation and rollback.

Indexes prioritize active category versions, move acquisition lookup by species/form/move/time, and opportunity queries. Form distinctions with gameplay meaning receive distinct canonical IDs; display localization is separate later.

### Derived database

`derived_entries` is keyed by cache kind, subject/configuration, canonical input-version map, and engine version. `invalidation_log` explains version transitions. PvP keys must include species/form, league/cup cap and eligibility rules, level-cap/Best Buddy rules, game-data version, and calculation engine. Raid/team keys additionally include exact collection configuration and battle assumptions.

## Migration policy

Each database owns an ordered catalog and `schema_migrations(version, name, checksum, applied_at)`. Applied SQL files are immutable: a changed checksum fails. Add a new numbered migration for every change. Migrations run in an immediate transaction with foreign keys enabled and WAL mode.

Before any destructive rewrite, implement and test backup/export, space checks, failure rollback, and restoration. CI tests fresh migration, idempotence, and mutation detection now; later it must test supported-version upgrade paths with sanitized fixtures.

Migration 002 adds optimistic `revision`, observation ownership/provenance, structured history metadata, internal tags, roles, recommended GO tags, status validation, and database triggers that reject history update/delete. It does not rewrite migration 001.

## Identity, conflict, and deletion rules

Phase 1 update operations use optimistic revisions and atomically update the current record, replace its associations, and append one event. Create, observation, archive, transfer/trade confirmation, restore, and full import are transactions. Ordinary APIs expose no hard delete.

UUID is durable across devices. A fingerprint is a probabilistic lookup aid, never the primary key. Accepted mutable changes append history. Sync uses entity versions/timestamps, tombstones, device/op IDs, and deterministic conflict policy; see `SYNC.md`. Archives remain restorable. Knowledge/derived rows never own user records, so provider refresh cannot erase collection data.
