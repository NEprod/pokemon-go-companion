# Data sources and knowledge updates

## Policy

Use official Pokémon GO/Scopely Explore information where available, then openly licensed structured datasets/code, then established specialist sources with explicit permission or compatible terms. Do not scrape rendered sites, call undocumented/private game endpoints, use unofficial account credentials, reverse engineer the app, or assume public visibility grants reuse rights. Provider integration needs a documented source URL, owner, license/terms snapshot date, permitted use/redistribution, attribution, refresh strategy, parser owner/version, validation, and fallback before merge.

Phase 0 implements contracts only. No production source has been approved or imported.

## Candidate register

| Category | Candidate | Current finding | Decision before integration |
|---|---|---|---|
| Official news/events/mechanics | [Pokémon GO official site](https://pokemongolive.com/) and in-app/user-presented announcements | Best authority for announcements, dates, event move windows, Rocket restrictions; mostly prose and may vary by locale/timezone | Confirm terms for caching excerpts/structured facts; retain URL/verification timestamp; human-reviewed parser because prose changes |
| Service terms/safety | [Scopely Explore Terms](https://explore.scopely.com/terms) | Current terms prohibit unauthorized access, modified/unofficial software, cheating, location falsification, and reverse engineering; reinforces observation-only design | Legal review if scope/distribution changes; never access private game services |
| PvP mechanics/rankings | [PvPoke repository](https://github.com/pvpoke/pvpoke) | Public source contains simulator, game master, and locally generated ranking JSON; repository identifies an MIT license | Review exact LICENSE coverage for code **and data**, Pokémon IP/trademark implications, attribution, update cadence, and whether bundled/derived ranking redistribution is acceptable; prefer local compatible calculation over web scraping |
| Raid simulations/rankings | Pokébattler | Established specialist candidate, but no stable permitted API/data license has been established in Phase 0 | Obtain documented API/license/permission; otherwise compute locally from approved mechanics and do not scrape pages |
| Base game master/community datasets | To be selected in Phase 2 | Community mirrors can be technically useful but provenance and redistribution rights are uncertain; raw app extraction/private endpoints are out of bounds | Select only a lawful structured source after terms/license review; cross-check important fields and preserve source hash/version |
| Species names/artwork | Official Pokémon resources or separately licensed assets | Game facts and copyrighted media have different reuse risk | Keep canonical IDs independent of artwork; do not ship copyrighted artwork until license is documented |

Source terms can change; the register must be rechecked at integration and periodically afterward. The URLs above are research references, not blanket approval.

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

Each provider declares name, supported category, parser version, freshness policy, and source terms reference. Each payload receives source version, fetch time, content hash, validation result, and local path. Store validation errors safely without sensitive payload dumps.

Recommendations expose active game-master, ranking, raid, event, item/move-acquisition, and engine versions as applicable. A ranking must state cup rules and assumptions. Never conflate provider assertions, normalized facts, and locally calculated outputs.

## Three-layer update pipeline

1. **Source cache:** fetch only when changed/stale, validate bytes/schema/ranges/cross-references, hash, and retain current plus previous good. Raw data is never queried directly by recommendation code.
2. **Normalized knowledge:** map provider IDs into canonical stable IDs in staging. Run semantic validation and atomically activate a category/version. Provider-specific fields do not leak into domain use cases.
3. **Derived analysis:** calculate PvP IV tables, matchup matrices, raid counters, teams, and comparisons. Key by all semantic inputs plus engine version. It is disposable and selectively invalidated.

Startup never waits on network. It opens active local data, reports freshness, performs lightweight version checks asynchronously, downloads only needed categories, and continues with explicit stale status on failure. A failed download/parse/activation never wipes good data.

## Validation and test expectations

Use frozen, licensed or synthetic fixtures. Validate uniqueness, canonical references, IV/stat/level ranges, chronological event intervals, move kind/energy semantics, and cross-version activation. Provider changes require parser tests and critical recommendation regression tests. Manual spot checks against a second authoritative source are required for high-impact mechanics even when only one source is stored.

## Open legal/licensing questions

1. Does PvPoke's MIT license cover every ranking/game-master data file and permit bundling/redistributing derived results with required attribution?
2. Is there a documented Pokébattler API or license suitable for a private app and possible later distribution?
3. Which structured game-master source has defensible acquisition provenance, update reliability, and redistribution terms?
4. What official announcement content may be cached or transformed, and what attribution is required?
5. Which names, icons, sprites, and other media may be displayed/distributed? Keep media optional until answered.

These are release gates for affected integrations, not reasons to scrape or silently guess.
