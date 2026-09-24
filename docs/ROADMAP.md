# Roadmap

Status labels: **done foundation**, **next**, **planned**. A phase is complete only after implementation, documentation, automated tests, and truthful UX/error states.

## Phase 0 — architecture and repository (**done foundation**)

Technology evaluation/ADRs; repository and VS Code/Git/CI setup; durable product/docs; shared domain types; three-database schema and explicit migrations; provider/source/normalized/derived cache contracts; fake fixture coverage; initial tests and formatting. There is intentionally no product UI or later-phase behavior.

## Phase 1 — core collection engine (**done**)

Implemented repository/application use cases for Pokémon UUID records, accepted observations, transactional immutable history, manual create/edit, active/archive restoration, Transfer/Trade confirmation foundations, multiple roles, internal/recommended GO-tag persistence, safe versioned JSON export and empty-database restore, filters/pagination, optimistic revisions, and rollback/migration/safety tests.

CSV export, merge import, sophisticated reconciliation/duplicate matching, inventory/build-plan services, and production recommendation rules remain later work. They are not represented as complete.

## Phase 2 — game knowledge/cache (**implemented; review pending**)

Implemented provider update pipeline and raw SQLite source cache; validation/staging/activation/rollback; canonical species/forms/stats/types/moves/evolutions/CP multipliers/costs; deterministic CP/HP/reverse-level and 4,096-combination PvP IV calculations; versioned derived cache; synthetic frozen fixtures; and invalidation/fallback tests. No production source passed the current license/provenance review, so there is deliberately no live provider. Species/meta ranking, battle simulation, raids and event-aware move acquisition remain later work.

## Phase 3 — macOS scanner proof of concept (**3A–3C done; broader scanner planned**)

The completed diagnostic covers native macOS selected-window capture, frame throttling, local screen classification, targeted Detail text recognition, Appraisal IV analysis, and temporary walkthroughs. Region fallback, broader screen/field extraction, and a production scanner remain future work. No interaction/control.

Phase 3A capture feasibility is **VERIFIED WORKING** on Dale's Mac with Apple's iPhone Mirroring and Pokémon GO. Selected-window capture delivered changing 580 × 1280 frames, and an explicitly saved frame had clear, usable pixels. Region fallback and the broader scanner remain planned.

Phase 3B screen classification and bounded temporal continuity are **complete — VERIFIED WORKING** through Dale's final live test. Supported families are Map, Main Menu, Nearby, Storage, Detail, Appraisal, Items, Profile, and `unknown`, with conservative raw evidence and a separate stable result. Moves, Max, Adventure Effects, and form panels remain Detail content, not top-level screens. Optional private screenshot/RGB regressions are not required to build or test a clean checkout. No Pokémon, item, or profile field extraction is included.

Phase 3C Detail/Appraisal extraction and temporary Appraisal walkthroughs are **complete — LIVE VALIDATED**. The diagnostic observes displayed name (not canonical species), CP, current/maximum HP, and independently measured 0–15 Attack/Defense/HP IVs. It distinguishes Appraisal Intro from an extraction-ready IV card, keeps one temporary specimen UUID through Detail → menu → Appraisal, quarantines uncertain arrow transitions, and assigns a new UUID to each corroborated candidate, including same-species neighbours. Dale completed a 12-Pokémon live Appraisal walkthrough in which all 12 worked, including consecutive Mewtwo and consecutive Dragonite. This does not write permanent collection facts or control the game.

**Next milestone: Scan Report + Game Knowledge Foundation (planned only).** Establish reviewed/versioned current species/form base stats, CP multipliers/levels, and evolution-family branches. Use these to distinguish exact specimen IV percentage, derived level (CP/IV with HP validation), projected evolution CP/level, and local 4,096-spread PvP IV results for eligible stages in Great, Ultra, and Master League. A first Scan Report/info card should separate IV percentage, PvP IV rank, species/meta usefulness, account value, and investment value; it should not present these as one score. Design explainable suggested roles (GL, UL, ML, Raid, Max, Mega) and actions/status (Evolve, PowerUp, NeedsTM, EliteTM, Trade, Review, Potential, Pokédex), without claiming live meta rankings or implementing those suggestions in Phase 3C.

Future Pokédex advice optimizes **registration completion**, not a living dex: being the only currently owned specimen is not by itself a Keep reason. A missing reachable registration may justify Keep/Evolve; an already registered family does not gain a Pokédex Keep reason merely from current ownership. Tests can inject known registration state before a future account-state scanner exists. After Scan Report foundations are proven, deliberate Lock/Keep may assign permanent app UUIDs; later mass appraisal and explicit Update by Scan must reconcile safely across power-up, evolution, move/second-move, and other progression. Matching must never rely on species + IV alone, and deep move extraction need not run on every temporary mass-appraisal candidate. None of this next-milestone or later work is implemented here.

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
