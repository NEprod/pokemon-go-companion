# Roadmap

Status labels: **done foundation**, **next**, **planned**. A phase is complete only after implementation, documentation, automated tests, and truthful UX/error states.

## Phase 0 — architecture and repository (**done foundation**)

Technology evaluation/ADRs; repository and VS Code/Git/CI setup; durable product/docs; shared domain types; three-database schema and explicit migrations; provider/source/normalized/derived cache contracts; fake fixture coverage; initial tests and formatting. There is intentionally no product UI or later-phase behavior.

## Phase 1 — core collection engine (**done**)

Implemented repository/application use cases for Pokémon UUID records, accepted observations, transactional immutable history, manual create/edit, active/archive restoration, Transfer/Trade confirmation foundations, multiple roles, internal/recommended GO-tag persistence, safe versioned JSON export and empty-database restore, filters/pagination, optimistic revisions, and rollback/migration/safety tests.

CSV export, merge import, sophisticated reconciliation/duplicate matching, inventory/build-plan services, and production recommendation rules remain later work. They are not represented as complete.

## Phase 2 — game knowledge/cache (**implemented; review pending**)

Implemented provider update pipeline and raw SQLite source cache; validation/staging/activation/rollback; canonical species/forms/stats/types/moves/evolutions/CP multipliers/costs; deterministic CP/HP/reverse-level and 4,096-combination PvP IV calculations; versioned derived cache; synthetic frozen fixtures; and invalidation/fallback tests. No production source passed the current license/provenance review, so there is deliberately no live provider. Species/meta ranking, battle simulation, raids and event-aware move acquisition remain later work.

## Phase 3 — macOS scanner proof of concept (**in progress**)

Broader planned scope: native macOS diagnostics, selected-window capture, frame throttling, local screen classification, then screen-specific field recognition/confidence and anonymized regression fixtures. Region fallback and Vision/OCR extraction remain future work. No interaction/control.

Phase 3A capture feasibility is **VERIFIED WORKING** on Dale's Mac with Apple's iPhone Mirroring and Pokémon GO. Selected-window capture delivered changing 580 × 1280 frames, and an explicitly saved frame had clear, usable pixels. Region fallback, recognition, OCR, observations, and the broader scanner remain planned.

Phase 3B screen classification and bounded temporal continuity are **complete — VERIFIED WORKING** through Dale's final live test. Supported families are Map, Main Menu, Nearby, Storage, Detail, Appraisal, Items, Profile, and `unknown`, with conservative raw evidence and a separate stable result. Moves, Max, Adventure Effects, and form panels remain Detail content, not top-level screens. Optional private screenshot/RGB regressions are not required to build or test a clean checkout. No Pokémon, item, or profile field extraction is included.

Next planned stage: Phase 3C Pokémon Detail/Appraisal extraction behind the screen-analysis boundary. Not implemented; Phase 4 has not started.

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
