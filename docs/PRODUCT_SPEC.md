# Product specification

## Purpose and safety boundary

GO Account Companion is a private/personal, local-first account intelligence platform for Pokémon GO. It answers four separate questions:

1. What information is the user deliberately presenting through a selected screen/window, screenshot, or manual entry?
2. What Pokémon, items, resources, plans, and storage state does the user own?
3. What is currently useful or available according to versioned game knowledge?
4. Given those facts and the user's goals, what should the user do, why, and what is the next manual action?

It observes and advises only. It must never log into Pokémon GO through unofficial means; automate or bot gameplay; simulate taps; control an iPhone or Pokémon GO; spoof location; perform transfers, trades, evolutions, power-ups, or other gameplay; or evade security/anti-cheat. All gameplay remains manual.

## Product principles

- Facts, reference knowledge, preferences, and recommendations remain separate.
- Recommendations are recalculated, explainable outputs, not permanent facts.
- Local cached data works offline; update failure retains last-known-good data.
- Every recognized field has confidence and source provenance. Missing data stays missing.
- Irreversible/high-impact advice is conservative. Low confidence produces a prompt, Hold, or Review—not Transfer.
- Collection history is retained; transfer/trade only archives after user confirmation.
- The user can correct data manually, export/backup it, inspect the code, and leave the product.
- The initial interface is for a player: decision first, concise why, then next action and details.

## Product surfaces

### macOS desktop (first priority)

Conceptual navigation: Dashboard, Live Scan, Collection, Transfer, PvP, Raids, Teams, Investments, Pokédex, plus Review Queue, Tag Setup, Account/Goals, Inventory/Storage, and Settings/Data Updates.

The first scanner target is the Apple iPhone Mirroring window. The user selects a window or fallback region, manually navigates Pokémon GO, and the companion only reads frames. Progressive scans link detail, appraisal, moves, and Max screens into one scan session/specimen.

### iOS field companion (future)

Home/Today, current raids, personal raid teams, collection/detail, build plans, daily Mega, inventory/storage, quick updates, and Today's Catches. A Share Extension or Photos import receives user-selected detail/appraisal screenshots, creates a pending catch, requests missing screens, compares it with the collection, and later reconciles with a Mac observation. It never reads or controls Pokémon GO in the background.

### Windows desktop (future)

Reuse domain/data contracts and implement Windows UI/capture adapters without changing product rules or data formats.

## Collection intelligence

Each specimen has an internal UUID, canonical species/form identifiers, observed mutable facts, traits (shiny, Shadow, purified, lucky, Dynamax, Gigantamax, Mega progress, costume, buddy, favourite), moves, tags, catch information where useful, observation confidence, and history. Identity reconciliation uses stable/semi-stable fingerprints but understands power-ups, evolution, move changes, purification, Mega progress, tag/favourite changes, and mobile pending catches. Uncertain matches create a reconciliation task.

Collection states are Active, Pending/Review, Transfer Queue, Trade Queue, and Archive. Nothing important is hard-deleted by default. A recommendation to transfer remains Active until the user manually transfers in Pokémon GO and confirms it; then it is archived and excluded from active calculations, with restoration/reconciliation supported.

Duplicate analysis assigns roles rather than comparing IV percentage alone: Great/Ultra/Master League, raid, Shadow, Mega, Dynamax/Gigantamax, shiny/collection, lucky build, and trade. A new catch comparison identifies newly best role specimens and sends displaced candidates to Review, never automatic transfer.

## Smart tags

Internal classifications may be extensive. The initial manageable recommended Pokémon GO vocabulary is:

- `Transfer`: no identified meaningful role; safe to remove only when storage is needed and evidence is sufficiently certain.
- `GL`, `UL`, `ML`: worth keeping/building for the named league.
- `Raid`, `Max`: useful for raids or Max Battles.
- `Mega`: unlocked and worth progressing; `MegaNew`: useful Mega candidate not initially unlocked.
- `Trade`, `Evolve`, `PowerUp`: worthwhile manual action/candidate.
- `NeedsTM`: useful specimen with a poor move; `EliteTM`: worthwhile target requires a scarce route.
- `Hold`: defer due to uncertainty, future event/move/evolution, or strategy.

Do not require redundant tags for inherently searchable traits such as Shiny/Shadow. Every recommendation explains why and the next action. Existing GO tags are observed facts; recommendations do not assume the player applied them and may identify missing or stale tags.

## Analysis capabilities retained for later phases

### PvP and teams

Support Great (1500), Ultra (2500), Master (current uncapped rules), Master Premier where relevant, and arbitrary special cups. For each eligible species/form/cup, deterministically evaluate all 4,096 IV triplets, legal level, CP and battle stats, stat product, IV rank, percentage of rank 1, Best Buddy/XL needs, and build cost. Cache by game-data version, species/form, cap/rules, level cap, and engine version. Specimen IV rank and species/meta rank are different measures and must always be labeled separately.

Cache/version league rankings, roles, move recommendations, and simulation assumptions where licensing permits. Team building uses the user's actual specimens and analyzes lead/safe swap/closer, coverage, weaknesses, matchups, and substitutions; simple type coverage must not be presented as a full simulation.

### Moves and acquisition

Moves are first-class, with distinct PvP, raid, and Max recommendations. Reference data models Fast/Charged, types, PvE/PvP power/energy/duration/turns/effects, pools, legacy/exclusive state, Frustration/Return, Max/G-Max relationships, and date/version-aware acquisition rules. Acquisition methods include regular/Elite TMs, evolution/event evolution, Community/Raid Day, research/rewards, special events, and Frustration removal. Advice includes current availability, prerequisites, scarce-item cost, alternative/upcoming routes, performance benefit, and whether waiting is sensible.

### Raids, Mega, and Max Battles

Raid analysis locally derives teams from cached stats, moves, types, STAB, effectiveness, weather, Shadow/Mega bonuses, tier/boss mechanics, friendship, and Party Power assumptions. Current raid rotation is explicitly different from possible bosses and includes form/tier/Mega/Shadow/Max/shiny eligibility, time/region/event, source, and verification time. Display best current configuration and best achievable team with explained TM/power-up/Mega changes.

Mega knowledge covers energy, costs, cooldown/rest, levels/progression/bonuses, forms/stats/types; user-specific progress is user data. Dynamax/Gigantamax and Max Attack/Guard/Spirit, upgrade costs, Max/G-Max moves, battle mechanics, investment, and current bosses form a separate analysis mode from raids.

Shadow and purification advice is explicit and conservative because purification is irreversible and Frustration is restricted.

### Resources, investments, storage, events

Inventory supports Stardust, species/XL/Rare Candy, TMs including Elite, balls, healing, berries, evolution items, passes, boosts, incubators, Mega Energy, Max resources, and other useful items. Build plans aggregate costs, protect planned resources, and answer what is affordable and the best use of current resources.

Evolution advice is Evolve Now, Wait, or Do Not Evolve based on branches, projected CP/league use, requirements/costs, and event-exclusive moves. Storage advice considers actual useful collection, queues, collecting goals, event holds/buffers, bag composition, and recoverable space—not trainer-level folklore. Account-strength/readiness dimensions are explainable and show gaps.

Event records become structured opportunities (exclusive move, Frustration removal, raid/Max availability, spawn/resource bonuses). Before/during/end-of-event and “what should I hunt?” advice cross-references account gaps and goals. The Daily Command Centre progressively surfaces only the most important Mega, event, raid, storage, build, move, evolution, and catch actions.

### Collection and Pokédex discovery

Collection filters eventually cover identity, CP/level/IV, traits/forms, moves/legacy, roles/tags, confidence, recency, queues, and expressions such as `GL rank < 100`, `needsTM & raid`, `mega & ready`, or `duplicate > 3`. Normal filtering never needs an LLM. Species pages show evolution, moves, role viability, target PvP IVs, rankings, owned specimens, best owned roles, and missing builds/forms.

## Knowledge/update requirements

The versioned offline cache must cover species/forms/stats/types/evolution, CP multipliers and cost rules, moves/pools/acquisition, Shadow/Purified, Mega, Dynamax/Gigantamax, leagues/cups/rankings, PvP/raid mechanics, current raids/events, items/resources, and availability where legally obtainable. Values are never scattered as code constants.

Each provider records name/category, fetch timestamp, source and parser versions, freshness/status/error, content hash, and previous-good version. Startup opens immediately, checks freshness asynchronously, fetches only changed/stale categories, validates and normalizes in staging, atomically activates, invalidates affected derived results, and retains rollback data. The UI distinguishes Current, last update, Stale with timestamp, and failure while continuing offline.

Three cache layers are mandatory: validated raw source cache; canonical normalized knowledge database; disposable derived analysis cache. Derived outputs record all source-data versions and analysis-engine version.

## Sync, export, and privacy

Synchronize user collection/history, preferences, plans, tags, resources/storage, pending catches, and reconciliation state—not normalized reference rows. Use UUIDs, versions/timestamps, tombstones/history, deterministic conflict rules, offline outbox, schema compatibility, duplicate prevention, encryption, and authenticated private storage. CloudKit must not become an unabstracted dependency that blocks Windows; alternatives are evaluated before Phase 9.

Future JSON/CSV export, full backup/restore, and migrations prevent lock-in. Collection data is private. Screenshots remain local unless the user deliberately selects a documented remote feature; logs exclude images, credentials, and sensitive location/account content.

## Success and non-goals by phase

Phase 0 produces only architecture, docs, contracts, schema/migrations, fixtures, tests, formatting, and CI. Later success includes accurate reconciliation, useful offline analysis, explainable safe recommendations, local capture/import, and robust sync. No phase introduces gameplay control or unofficial account access. See `ROADMAP.md` for the implementation sequence and honest current status.
