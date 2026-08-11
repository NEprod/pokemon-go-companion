# Recommendation engine

## Contract

Recommendations are pure, regeneratable evaluations of a versioned snapshot:

```text
accepted user facts + active game knowledge + user preferences + policy/engine version
    -> action + recommended GO tags + reasons + next action + confidence + provenance
```

They are not written back as Pokémon facts. Applied GO tags, queue status, and user-confirmed actions are facts; a new balance/ranking/provider/goal version triggers recalculation without rescanning.

## Output language

Every card answers:

- **What:** Keep, Transfer Candidate, Trade, Evolve Now, Wait, Power Up, Change Move, Review, Mega Unlock, Max Upgrade, or another explicit manual choice.
- **Why:** short evidence-based reasons, including personal role/duplicate comparison and uncertainty.
- **What next:** exact manual action, target move/evolution, needed screen, cost, or wait window.

Show species/meta rank separately from specimen IV rank. Show different best moves for PvP, raid, and Max roles. Scores/readiness dimensions need named inputs and gaps; no mystery composite scores.

## Rule architecture

Small rules declare required facts/knowledge, goal relevance, evidence, candidate actions/tags, and safety level. An orchestrator evaluates applicable rules over an immutable snapshot. A policy layer resolves competing roles and resource constraints. An explanation composer formats structured reason codes; UI only presents output.

Examples of reason codes: `pvp.specimen.iv_rank`, `pvp.species.meta_rank`, `raid.type_coverage_gap`, `duplicate.role_redundant`, `move.elite_tm.low_gain`, `event.exclusive_evolution_upcoming`, `shadow.purification_irreversible`, `confidence.appraisal_missing`.

Role allocation asks whether this specimen uniquely or more efficiently fills GL/UL/ML/raid/Max/Mega/collection/trade roles. IV percentage alone cannot select duplicates. Costs and scarcity can favor a Lucky build while preserving a stronger expensive long-term candidate.

## Confidence and irreversible actions

Recognition policy is centrally configured and versioned. Initial design targets (to validate with scanner data) are:

- ordinary low-impact advice may surface at field confidence >= 0.90 with uncertainty displayed;
- investment/evolution/TM guidance requires all critical identity/IV/move fields >= 0.97 or explicit manual confirmation;
- Transfer candidate requires species/form/traits/IV appraisal and role-relevant data >= 0.995, complete collection comparison, no Hold reason, and no conflicting observation;
- purification always requires an explicit conservative warning and manual confirmation regardless of confidence.

These are not scanner claims; they are planned policy defaults. Missing/ambiguous critical data yields “More information required,” Hold, or Review. Confidence is not averaged in a way that hides one weak critical field.

Transfer has two independent steps: advice can nominate a candidate; only the user can manually transfer in Pokémon GO and confirm, causing a database archive event. The app never acts in the game. Trade is analogous.

## Move/investment/event reasoning

A move recommendation includes current and target move, role, gain estimate/assumptions, acquisition rules valid at evaluation time, item scarcity, Frustration/Return restrictions, event alternatives, cost, and wait recommendation. A small Elite TM gain can be low priority; a unique high-impact role can justify it. An event evolution route should suppress wasteful Elite TM advice.

Build plans aggregate steps and resources, reserve scarce inventory, and compare achievable benefit. Evolution evaluates branches, projected CP/league legality, costs, current and upcoming exclusive windows. Event reasoning consumes normalized `EventOpportunity` objects rather than repeatedly parsing prose.

## Provenance, cache, and invalidation

Every output records subject/user-fact version, relevant category versions, engine/policy version, generation time, and structured fact references. Derived caches key all inputs. Changes to specimen, moves, level, status, preferences, collection competition, provider data, league rules, battle mechanics, event time, or algorithm invalidate only affected outputs.

The debug view should eventually state: game data X, PvP Y, raids Z, events E, recommendation engine N, and any stale inputs.

## Testing

Use table-driven unit tests for each rule and conflicts; property/boundary tests for calculations; frozen golden explanations; role-aware duplicate scenarios; resource and event alternatives; stale knowledge; and adversarial missing/low-confidence observations. Transfer tests are mandatory fail-safe tests: any uncertain critical fact, protected trait/role, unresolved duplicate, or stale required knowledge must prevent a Transfer recommendation.

Phase 1 persists recommended GO-tag state, explanation, apparent application, user confirmation, timestamps, and source version. It also implements manual lifecycle foundations for marking Transfer/Trade advice separately from confirmation. No production ranking, duplicate, Transfer-safety, or other recommendation rules are implemented.
