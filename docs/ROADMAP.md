# Roadmap

Status labels: **done foundation**, **next**, **planned**. A phase is complete only after implementation, documentation, automated tests, and truthful UX/error states.

## Phase 0 — architecture and repository (**done foundation**)

Technology evaluation/ADRs; repository and VS Code/Git/CI setup; durable product/docs; shared domain types; three-database schema and explicit migrations; provider/source/normalized/derived cache contracts; fake fixture coverage; initial tests and formatting. There is intentionally no product UI or later-phase behavior.

## Phase 1 — core collection engine (**implemented; review pending**)

Implemented repository/application use cases for Pokémon UUID records, accepted observations, transactional immutable history, manual create/edit, active/archive restoration, Transfer/Trade confirmation foundations, multiple roles, internal/recommended GO-tag persistence, safe versioned JSON export and empty-database restore, filters/pagination, optimistic revisions, and rollback/migration/safety tests.

CSV export, merge import, sophisticated reconciliation/duplicate matching, inventory/build-plan services, and production recommendation rules remain later work. They are not represented as complete.

## Phase 2 — game knowledge/cache (**planned**)

Provider update coordinator and file source cache; validation/staging/activation/rollback; canonical species/forms/stats/types/moves/evolutions/CP multipliers/costs; deterministic CP and 4,096-combination PvP IV calculations; versioned derived cache; licensed frozen provider fixtures and invalidation/fallback tests. Resolve source/license questions first.

## Phase 3 — macOS scanner proof of concept (**planned**)

Native SwiftUI macOS shell; Screen Recording permission and explicit iPhone Mirroring window chooser using ScreenCaptureKit; manual region fallback; frame throttling; Vision/OCR screen classifier and recognition for species/CP/detail/appraisal/IVs; field confidence and anonymized regression fixtures. No interaction/control.

## Phase 4 — live scan workflow (**planned**)

Progressive prompts and multi-screen session aggregation; moves/forms/Shadow/Shiny/Lucky/costume/buddy/Max/G-Max/tags; reconciliation; live recommendation card; uncertain scans to Review.

## Phase 5 — PvP and moves (**planned**)

GL/UL/ML and special cups; specimen IV vs species/meta ranks; local mechanics/simulation inputs; role/movesets; date-aware move acquisition and regular/Elite TM/event/Frustration guidance; build/wait explanations.

## Phase 6 — transfer/collection optimizer (**planned**)

Role-aware duplicate optimization; Transfer/Trade/Review queues; user-confirmed archive; undo/reconciliation; catch comparison; rigorous transfer safety tests.

## Phase 7 — raids, Mega, and Max (**planned**)

Verified current rotations; local counters and personal best-current/best-achievable teams; saved parties; Mega progression; separate Dynamax/Gigantamax/Max analysis; explained proposed investments.

## Phase 8 — account optimizer (**planned**)

Inventory scan/manual corrections; resources/build planner; adaptive storage advisor; explainable readiness/coverage; hunt goals; structured event intelligence; progressive Daily Command Centre.

## Phase 9 — sync foundation (**planned**)

Re-evaluate CloudKit, Supabase/Postgres, and Firebase against then-current requirements. Implement transport-neutral change log/outbox, authentication/encryption, offline conflicts, tombstones, migration compatibility, backup, duplicate prevention, and multi-client tests. Reference/derived stores remain independently refreshed.

## Phase 10 — iOS companion (**planned**)

Native field UI; Today/raids/teams/collection/detail/plans/Mega/inventory; Share Extension and Photos import for pending catches/appraisal prompt; quick add/update/transfer/trade/Mega confirmation; Mac reconciliation and sync. No background game access.

## Phase 11 — Windows desktop (**planned**)

Validate/port shared core and SQLite; add native Windows capture/window-region adapter and desktop UI; keep product rules/data formats and macOS behavior. Record the UI/toolchain decision in a new ADR after a Windows spike.
