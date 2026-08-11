# Phase 1 JSON backup format

## Purpose and boundary

`BackupService` exports private user-owned Phase 1 collection data as deterministic, human-readable JSON. It excludes game/reference data, derived caches, screenshots, provider payloads, credentials, secrets, and API keys. Treat the resulting file as sensitive because it contains collection details.

The top-level document contains:

- `formatVersion`: currently `1`; incompatible values are rejected.
- `userSchemaVersion`: highest applied `user.sqlite` migration; imports newer than the running app are rejected.
- `exportedAt`: ISO-8601 timestamp.
- `profile`: current user profile/preferences.
- `collection`: one aggregate per stable Pokémon UUID.
- `inventory`, `storageProfile`, and `buildPlans`: existing user-owned planning/resource rows when present.

Each aggregate contains the current `PokemonRecord`, associated scan sessions and field-level observations, and ordered immutable history. The record includes species/form keys, mutable specimen facts, traits, current moves, observed GO tags, internal tags, multiple roles, recommended GO-tag state, collection status, revision, and timestamps.

## Restore semantics

Phase 1 deliberately implements **full restore into an empty user database**, not merge. Before writing, the service decodes and validates the entire document, format/schema compatibility, unique Pokémon/history/observation UUIDs, positive revisions, ownership references, and scan-session references. A non-empty database is rejected rather than silently duplicating or overwriting data.

The repository restores profile, records, associations, sessions, observations, history, inventory, storage, and build plans in one SQLite transaction. Any constraint, trigger, or write failure rolls everything back. UUIDs and event history are preserved. Reference and derived databases are untouched.

Sophisticated merge, conflict resolution, partial selection, inventory/build-plan management services, encrypted archive packaging, and migration from future formats are not implemented in Phase 1. Until those exist, users should restore only into a new/empty user store and retain the original backup.
