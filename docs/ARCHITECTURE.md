# Architecture

## Decision summary

The system is a native-first modular monolith in a monorepo:

- Swift 6 shared packages for domain models/rules, application ports, knowledge/provider contracts, and persistence adapters.
- Native SwiftUI macOS and iOS application shells in later phases.
- ScreenCaptureKit/Vision adapters compiled only into the macOS target.
- Three local SQLite files: private user facts, normalized game knowledge, and disposable derived analysis.
- Provider and sync backends behind protocols; no remote backend selected in Phase 0.
- A future Windows client reuses platform-neutral Swift packages where practical and can reimplement stable service/data contracts where a dependency is not Windows-ready.

This prioritizes the hardest first-platform requirement—reliable user-selected macOS window capture—while maximizing iOS reuse and keeping Windows from contaminating the core. See ADRs.

## Technology options evaluated

| Criterion | Native Swift + SwiftUI (selected) | Kotlin Multiplatform + Compose/native adapters | .NET + MAUI/Avalonia |
|---|---|---|---|
| macOS and UI quality | First-class AppKit/SwiftUI, accessibility, signing | Good Compose desktop; native integration bridge | Good cross-platform UI, Mac Catalyst/native binding complexity |
| iPhone Mirroring capture | Direct ScreenCaptureKit, `SCWindow`, permissions | Swift/Obj-C bridge required around JVM/native boundary | P/Invoke/binding and Mac entitlement work |
| Windows potential | Swift core is increasingly portable; Windows UI/capture is a later adapter/possible core port | Strong JVM desktop reuse and Compose Windows | Strongest shared Windows/macOS code |
| iOS | Native SwiftUI and Apple frameworks | Mature KMP shared logic; Kotlin/Native bridge and optional Compose | Supported, but toolchain/AOT/binding complexity |
| Shared domain logic | Full Mac/iOS; pure Swift modules avoid Apple UI/capture | Excellent across all target platforms | Excellent across all targets |
| SQLite/local-first | Mature SQLite C library; repository abstraction | SQLDelight is strong multiplatform option | Microsoft.Data.Sqlite/SQLite ecosystem mature |
| Offline operation | Straightforward native files/tasks | Straightforward | Straightforward |
| Cloud sync | CloudKit native; backend port permits alternatives | Custom backend easiest cross-platform; CloudKit bridge | Azure/Firebase/Supabase/custom; CloudKit less native |
| Testing | Swift Testing/XCTest; native capture tests on macOS | Strong Kotlin test ecosystem; platform test matrix | Strong .NET test ecosystem |
| Complexity | Lowest for Mac+iOS and capture; later Windows cost | More build/interop layers now; better Windows sharing later | Single language, but Apple capture/signing integration less direct |
| Ecosystem maturity | Very strong Apple ecosystem; weaker Windows UI | Mature and improving multiplatform ecosystem | Mature .NET; MAUI lifecycle/upgrades and Catalyst trade-offs |

Apple documents ScreenCaptureKit window filtering through `SCShareableContent`, `SCWindow`, and `SCContentFilter(desktopIndependentWindow:)`. Kotlin's documentation supports shared native/desktop/iOS logic and SwiftUI integration; .NET supports iOS, Mac Catalyst/macOS, and Windows, but native Apple integration still requires bindings. These were evaluated rather than assuming “Apple means Swift” or “future Windows means cross-platform UI.”

Decision checkpoint: before Phase 11, prove the pure domain package and SQLite adapter on Swift for Windows. If ecosystem limitations are material, preserve canonical schemas/contracts and port the Windows adapter/core subset. Do not distort the macOS scanner to avoid that possible port.

## Dependency rule

```text
macOS/iOS UI -> application use cases -> domain
                                      -> repository/provider/sync ports

adapters (SQLite, provider, capture, OCR, sync) -> their ports + domain
domain -> Foundation value types only

capture -> frames
recognition -> observations + confidence
reconciliation -> user facts/history or review tasks
recommendation -> user facts + knowledge + preferences -> ephemeral advice
```

UI never queries SQLite directly. Domain never imports SwiftUI, ScreenCaptureKit, Vision, CloudKit, or provider-specific DTOs. Capture does not recognize; recognition does not recommend; recommendations do not mutate the game or silently mutate user facts.

## Current modules and planned growth

Current package targets are `GOCompanionDomain`, `GOCompanionApplication`, `GOCompanionKnowledge`, `GOCompanionPersistence`, and `CSQLite`. Application owns collection repository contracts and use cases; persistence depends inward and implements those ports. Later targets should add `GOCompanionRecognition`, `GOCompanionRecommendation`, `MacCaptureAdapter`, `MacApp`, and `iOSApp` only when their phase begins. App targets are composition roots for dependency injection.

Prefer actors/structured concurrency at I/O boundaries, small value types, protocols owned by the consumer, and explicit error states. Avoid global containers and giant services. External JSON is decoded to provider DTOs, validated, then mapped to canonical models in a transaction.

## Runtime data flow

At startup, open all local stores and show last-known-good state immediately. An asynchronous update coordinator checks category freshness/version hints, fetches only changed sources, validates source data, retains raw bytes, normalizes into staged version rows, and activates atomically. It records failure/staleness without replacing good rows. Activation emits category/version invalidation events for disposable derived results and recommendation refresh.

A scan session receives frames from the chosen adapter, classifies screen type, creates field-level observations, and aggregates multiple screens. Reconciliation compares the candidate with active/pending records. High-confidence confirmed changes append history and update facts transactionally; ambiguity creates Review. Recommendation use cases read a consistent snapshot of facts, knowledge versions, and preferences and return explanations/provenance.

## Quality attributes

- **Safety:** observation-only adapters; confidence gates; irreversible advice conservative and manual.
- **Availability:** local-first startup; previous-good knowledge; provider and network failure do not block use.
- **Correctness:** typed models, FK/check constraints, migration checksums, frozen fixtures, versioned calculations.
- **Privacy:** local screenshots by default; separately syncable user DB; derived/reference data excluded from sync/backup as appropriate.
- **Maintainability:** SPM modules, explicit dependency direction, ADRs, Git/VS Code/CI, replaceable adapters.
- **Auditability:** UUIDs, append-oriented history, provider/version provenance, explicit errors and stale state.

## Phase 1 implementation truth

The code now provides collection repository/application boundaries, a transactional SQLite implementation, optimistic record revisions, lifecycle/history/observation/tag/role persistence, paginated filters, and versioned JSON export/full restore. Database triggers make collection history append-only, and rollback is tested.

The recommended-tag data structure and “mark recommended” lifecycle are foundations, not a production recommendation engine. No UI, screen capture, OCR, game-data provider, PvP/raid calculation, cloud sync, or gameplay interaction exists.
