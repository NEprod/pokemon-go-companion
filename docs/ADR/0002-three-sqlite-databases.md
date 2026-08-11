# ADR 0002: Separate user, knowledge, and derived SQLite databases

- Status: Accepted
- Date: 2026-08-11

## Context

User facts are private/syncable/irreplaceable, game knowledge is provider-refreshable/versioned, and derived analyses are disposable. A single schema makes it easier to sync or delete the wrong data and harder to replace large caches. Separate stores lose cross-database foreign keys and require explicit snapshot provenance.

## Decision

Use `user.sqlite`, `knowledge.sqlite`, and `derived.sqlite`, each with its own forward, checksummed migration catalog. User models reference canonical knowledge string IDs. Derived keys record input versions and engine version. Coordinated application snapshots—not database FKs—tie layers together.

SQLite is selected for robust transactions, portability, offline operation, inspection/export tooling, and mature platform support. Phase 0 uses a narrow C adapter without third-party dependencies; repository abstractions are added in Phase 1.

## Consequences

Backups and sync can include user data without huge/reference cache rows. A corrupt/stale derived store is safely deleted and rebuilt. Knowledge activation/rollback is independent. Cross-store consistency must be explicit and tested; recommendations show exact versions. Multi-database migrations must be handled independently and app versions must tolerate compatible knowledge lag.
