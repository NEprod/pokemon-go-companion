# ADR 0003: Replaceable providers and three cache layers

- Status: Accepted
- Date: 2026-08-11

## Context

Game values, rankings, raids, events, and move availability change. Sources differ in licensing/reliability and can fail or disappear. The product must work offline, avoid brittle scraping, and never replace good data with a bad update.

## Decision

Providers implement category/version/fetch/validate contracts and map through provider-specific normalizers. Store validated source payloads, then canonical normalized knowledge, then disposable derived analysis. Stage and validate before atomic activation; retain previous-good source/normalized version. Startup uses local active data and checks freshness asynchronously. Derived keys contain all data/rule/engine versions.

No production provider is selected in Phase 0. Integrations require an entry in `DATA_SOURCES.md` documenting terms/license, attribution, provenance, parser version, fixtures, refresh/fallback, and approval.

## Consequences

Providers can change without domain churn and failures become visible stale states rather than outages/data loss. Storage and update orchestration are more involved. Normalization must define stable canonical IDs and semantic validation. Raw provider data cannot be queried by recommendations.
