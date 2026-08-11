# ADR 0004: Defer sync backend; define transport-neutral semantics

- Status: Accepted
- Date: 2026-08-11

## Context

Mac/iOS make CloudKit attractive, but required later Windows support and relational/offline conflict needs could make CloudKit lock-in costly. Supabase/Postgres and Firebase improve cross-platform access but add operational, privacy, cost, or model trade-offs. Sync is not needed until Phase 9.

## Decision

Do not choose or implement a backend in Phase 0. Model syncable user entities with UUIDs and history, and in Phase 9 add a transport-neutral change/outbox/conflict protocol before an adapter. Do not sync normalized knowledge or derived cache. Re-evaluate CloudKit/`CKSyncEngine`, Supabase/Postgres, Firebase, and credible alternatives using then-current needs and pricing/terms.

If CloudKit is chosen for the first personal Apple deployment, it must remain behind the sync port and support complete export so a Windows-capable backend can replace/coexist with it.

## Consequences

We avoid speculative cloud infrastructure and preserve privacy/local-first behavior. There is no cross-device experience before Phase 9/10. Phase 1 schemas must avoid backend-generated primary keys and destructive deletion. Conflict, tombstone, schema-version, and idempotency requirements remain mandatory regardless of backend.
