# Data sources and knowledge updates

## Policy

Use official Pokémon GO/Scopely Explore information where available, then openly licensed structured datasets/code, then established specialist sources with explicit permission or compatible terms. Do not scrape rendered sites, call undocumented/private game endpoints, use unofficial account credentials, reverse engineer the app, or assume public visibility grants reuse rights. Provider integration needs a documented source URL, owner, license/terms snapshot date, permitted use/redistribution, attribution, refresh strategy, parser owner/version, validation, and fallback before merge.

Phase 2 implements the provider/cache pipeline using frozen synthetic fixtures. No production source has been approved or imported. This decision was re-evaluated on **2026-08-11** and is an intentional release gate, not a reason to scrape or use private endpoints.

## Candidate register

| Category | Candidate | Current finding | Decision before integration |
|---|---|---|---|
| Official news/events/mechanics | [Pokémon GO official site](https://pokemongolive.com/) and in-app/user-presented announcements | Best authority for announcements, dates, event move windows, Rocket restrictions; mostly prose and may vary by locale/timezone | Confirm terms for caching excerpts/structured facts; retain URL/verification timestamp; human-reviewed parser because prose changes |
| Service terms/safety | [Scopely Explore Terms](https://explore.scopely.com/terms) | Current terms prohibit unauthorized access, modified/unofficial software, cheating, location falsification, and reverse engineering; reinforces observation-only design | Legal review if scope/distribution changes; never access private game services |
| PvP mechanics/rankings | [PvPoke repository](https://github.com/pvpoke/pvpoke) | Repository has an MIT LICENSE and documents a simulator, `gamemaster.json`, and locally generated rankings. MIT is suitable for studying/reusing covered code with notice, but the repository license does not by itself resolve upstream Pokémon/game-data rights or prove official provenance. | **Approved only as an attributed algorithm/reference candidate; not approved as a production data feed.** Phase 2 computes specimen IV rank locally and imports no PvPoke data or species/meta ranks. Recheck attribution and data provenance before copying code/data. |
| Raid simulations/rankings | [Pokébattler](https://www.pokebattler.com/) | Established specialist site. Research found no public, documented API or data license suitable for this integration. | **Not approved.** Do not integrate or scrape rendered pages. Obtain a documented API/license/permission or compute locally from separately approved mechanics later. |
| Base game master/community datasets | [PokeMiners game_masters](https://github.com/PokeMiners/game_masters) | Structured JSON is technically useful, but the repository describes obfuscated fields, labels use as educational, attributes content to Pokémon/Niantic, and exposes no repository LICENSE in the reviewed root. | **Not approved.** Acquisition provenance and reuse/redistribution terms are insufficient. |
| Base game master/community datasets | [pokemongo-dev-contrib game master](https://github.com/pokemongo-dev-contrib/pokemongo-game-master) | Repository is MIT-labelled and distributes decoded GAME_MASTER protobuf files. The repository license covers its contribution, but decoded-game-data acquisition and underlying content rights remain unresolved under current service terms. | **Not approved as production data.** Do not fetch or bundle until provenance and rights are reviewed. |
| Species/forms/stats, CPMs, moves, evolutions, move pools, costs | No approved structured source | Official announcements do not provide a complete structured reference dataset; community Game Master mirrors above have unresolved provenance/rights. | Use the clearly labelled frozen synthetic fixture only. Approve a provider in a later checkpoint before shipping real values. |
| Events, move acquisition, raids and items | Official announcements first | Official pages are authoritative for selected facts but are prose, locale/time-zone sensitive, incomplete as a general API, and copyrighted. | No automatic parser in Phase 2. Future human-reviewed normalization may store facts plus URL/verification time after terms review; never scrape rendered output. |
| Species names/artwork | Official Pokémon resources or separately licensed assets | Game facts and copyrighted media have different reuse risk | Keep canonical IDs independent of artwork; do not ship copyrighted artwork until license is documented |

Source terms can change; the register must be rechecked at integration and periodically afterward. The Scopely Explore terms reviewed on 2026-08-11 were last modified 2026-07-15 and expressly address unauthorized access and unofficial software. The URLs above are research references, not blanket approval. No official public Pokémon GO Game Master/developer data API was identified in this review.

## Phase 2 fixture decision

`synthetic_knowledge_v1.json` is invented, deterministic test data. Its names, stats, multiplier curve, costs and moves are not a live Pokémon GO dataset and must never be presented as current game facts. It covers single/multiple forms, evolution, dual typing, capability flags, move mechanics/pools, XL/Best Buddy level metadata, and CP ambiguity solely to verify architecture and calculations.

The production adapter remains deliberately absent. Adding one requires a new source-register approval with owner, exact license/terms snapshot, attribution, acquisition provenance, refresh/fallback behavior, and frozen parser tests. Provider payloads are untrusted regardless of source.

## Required knowledge categories

Canonical cache design must eventually support:

- species/forms, gameplay distinctions, stats/types, evolution graphs/costs/requirements/restrictions, Shadow/purification, Mega, Dynamax/Gigantamax;
- valid levels/half-levels, CP multipliers, power-up Candy/XL/Stardust, Lucky/Shadow/Purified/Best Buddy modifiers;
- Fast/Charged move PvE and PvP mechanics, buffs/debuffs/probability, pools and Max/G-Max mapping;
- date/version-aware normal TM, evolution/event, legacy/exclusive/Elite TM, Community/Raid Day, research, Frustration removal, and other acquisition rules;
- type effectiveness and versioned PvP/raid/Max battle mechanics;
- GL/UL/ML and arbitrary cup configuration/eligibility, species/meta ranks/roles/movesets and assumptions;
- raid boss rotations with “possible” vs “currently available,” tier/form/Mega/Shadow/Max/shiny/time/region/event/verification;
- items/resource effects, acquisition/scarcity/current availability; Mega energy and Max costs;
- current/upcoming events converted into time-zone-aware structured opportunities.

## Provider contract and provenance

Each provider declares name, supported category, parser version, freshness policy, and source terms reference. Each payload receives source version, optional ETag, fetch time, checksum/content hash, parser version, validation result, and retained bytes. Store validation errors safely without sensitive payload dumps. The SQLite source cache retains candidate, active, previous-good, inactive, and invalid lifecycle states.

Recommendations expose active game-master, ranking, raid, event, item/move-acquisition, and engine versions as applicable. A ranking must state cup rules and assumptions. Never conflate provider assertions, normalized facts, and locally calculated outputs.

## Three-layer update pipeline

1. **Source cache:** fetch only when changed/stale, validate bytes/schema/ranges/cross-references, hash, and retain current plus previous good. Raw data is never queried directly by recommendation code.
2. **Normalized knowledge:** map provider IDs into canonical stable IDs in staging. Run semantic validation and atomically activate a category/version. Provider-specific fields do not leak into domain use cases.
3. **Derived analysis:** calculate PvP IV tables, matchup matrices, raid counters, teams, and comparisons. Key by all semantic inputs plus engine version. It is disposable and selectively invalidated.

Startup never waits on network. It opens active local data, reports freshness, performs lightweight version checks asynchronously, downloads only needed categories, and continues with explicit stale status on failure. A failed download/parse/activation never wipes good data.

## Validation and test expectations

Use frozen, licensed or synthetic fixtures. Validate uniqueness, canonical references, IV/stat/level ranges, chronological event intervals, move kind/energy semantics, and cross-version activation. Provider changes require parser tests and critical recommendation regression tests. Manual spot checks against a second authoritative source are required for high-impact mechanics even when only one source is stored.

## Open legal/licensing questions

1. What upstream provenance/IP constraints apply to PvPoke's ranking/game-master data even though the repository is MIT licensed, and what attribution is required for any copied algorithm?
2. Is there a documented Pokébattler API or license suitable for a private app and possible later distribution?
3. Which structured game-master source has defensible acquisition provenance, update reliability, and redistribution terms, given the unresolved status of both reviewed community mirrors?
4. What official announcement content may be cached or transformed, and what attribution is required?
5. Which names, icons, sprites, and other media may be displayed/distributed? Keep media optional until answered.

These are release gates for affected integrations, not reasons to scrape or silently guess.
