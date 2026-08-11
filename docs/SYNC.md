# Local-first sync design

## Scope and non-scope

Phase 0 chooses no backend and implements no sync. Phase 9 will synchronize private user entities: collection/archive/history, preferences/goals, plans, observed/applied tags, inventory/storage, pending mobile catches, and reconciliation state. Normalized reference/source data and derived caches refresh independently on each client and are not record-by-record sync payloads.

The local user database remains the operational source so the app works offline. Sync is an adapter over a canonical change protocol, never a CloudKit/Firebase model leaking into domain objects.

## Required local protocol

Every syncable entity uses stable UUID, schema version, logical revision, created/updated timestamps, origin device/op ID, and tombstone/archive semantics. A durable transactional outbox records idempotent mutations after local commits. Pull uses a server/change cursor. Applying remote changes and advancing the cursor is atomic. History assists audit and conflict recovery.

Conflicts are entity/field specific:

- append-only history merges by operation UUID;
- independent preference/resource fields can use versioned field merge with surfaced conflicts for concurrent manual edits;
- specimen identity/evolution/purification/archive and reconciliation conflicts require semantic resolution rather than blind last-write-wins;
- duplicate pending mobile/Mac observations are linked through reconciliation, never silently discarded;
- deletion is a tombstone/archive retained long enough for offline clients and restoration.

Clock time is diagnostic, not sole ordering. Schema negotiation blocks unsafe new-client data from being misread by an old client. Backups/export exist independently of sync.

## Backend options to re-evaluate in Phase 9

| Option | Apple clients | Windows | Offline/conflicts | Relational/querying | Cost/privacy/operations | Main trade-off |
|---|---|---|---|---|---|---|
| CloudKit + `CKSyncEngine` | Excellent native private database, scheduling, encryption options, Apple ID | No native Windows SDK; web/server bridge adds auth/ops | Good change-zone primitives; custom mapping/conflicts still needed | Record-oriented, not a relational backend | Low ops for personal Apple use; Apple-account dependency | Fastest Mac/iOS path but risks Windows lock-in |
| Supabase/Postgres | Good Swift SDK/HTTP | Good | Offline outbox/conflicts must be application-owned | Excellent relational model/RLS | Hosted/self-host cost and security/backup responsibility | Most portable and queryable, more engineering/operations |
| Firebase/Firestore | Mature Apple/Windows-accessible SDKs | Good | Strong client offline support; conflict semantics still need care | Document model may duplicate relational schema | Managed service and vendor pricing/privacy configuration | Quick sync but data-model impedance and lock-in |

CloudKit supports automatic Apple-platform sync, and `CKSyncEngine` offers custom participation, but the backend decision is deliberately deferred until cross-platform, cost, privacy, and identity requirements are clearer. If CloudKit is selected initially, the sync port/change model and full export must keep a later alternate backend possible.

## Security and privacy

Sync is opt-in, authenticated, encrypted in transit and at rest where the backend supports it, least-privilege, and private by default. Secrets/tokens live in Keychain or platform secure storage, never SQLite/logs/source. Screenshots are excluded unless a separate user-selected feature explicitly requires them. Provide account disconnect, remote-data deletion, export, and restore behavior.

## Test plan

Deterministic multi-client tests cover offline edits, retries/idempotency, reordered/duplicated operations, concurrent field changes, archive/restore and stale deletion, evolution/reconciliation conflicts, schema version mismatch, interrupted apply, cursor recovery, and migration across app versions. Backend contract tests run against an isolated test project with fake user data.
