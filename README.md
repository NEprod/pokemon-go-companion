# GO Account Companion

GO Account Companion is a private, local-first Pokémon GO account intelligence platform. It is designed to observe information a user deliberately shows or imports, maintain the user's own collection/resource records, cache versioned game knowledge, and derive explainable advice. It never controls Pokémon GO or performs gameplay actions.

## Current status

Phase 1 provides the Core Collection Engine: stable specimen UUIDs, transactional create/update/query/archive/restore workflows, immutable history, persisted observations with field-level confidence/provenance, internal tags, roles, recommended GO-tag state, and versioned JSON backup/full restore. Phase 0's three-database and provider-contract foundation remains intact.

There is still **no** UI, scanner, screen capture, production provider integration, PvP/raid calculation, complete recommendation engine, sync, or mobile app.

## Architecture at a glance

- Swift 6 packages hold platform-independent domain, knowledge contracts, and persistence adapters.
- `GOCompanionApplication` owns repository ports plus collection and backup use cases; SQLite implements those ports.
- Future macOS and iOS apps use native SwiftUI shells.
- Phase 3 macOS capture uses a ScreenCaptureKit adapter for a user-selected iPhone Mirroring window, with user-selected region capture as fallback. It is observation-only.
- User facts, normalized game knowledge, and disposable derived caches live in separate SQLite files.
- Providers and future sync backends are ports/adapters, not domain dependencies.

See [Architecture](docs/ARCHITECTURE.md) and [ADR 0001](docs/ADR/0001-native-swift-modular-monolith.md).

## Requirements

- macOS 14 or newer
- Swift 6 toolchain (Xcode 16 or compatible command-line tools)
- SQLite development headers/library (included with macOS; `libsqlite3-dev` on Linux)
- VS Code plus the recommended Swift extension, or Xcode

No credentials or network access are required through Phase 1.

## Build and test

```sh
swift build
swift test --parallel
swift format lint --recursive --strict Sources Tests Package.swift
```

To apply the formatter locally:

```sh
swift format --in-place --recursive Sources Tests Package.swift
```

GitHub Actions runs format lint, build, and tests on macOS. Opening the folder in VS Code loads the checked-in recommendations and settings. `swift package generate-xcodeproj` is intentionally unnecessary; open `Package.swift` directly in Xcode if desired.

## Repository map

```text
Sources/
  GOCompanionDomain/       typed user facts, observations, preferences, plans, recommendations
  GOCompanionApplication/  collection repository ports and lifecycle/backup use cases
  GOCompanionKnowledge/    replaceable provider and three-layer cache contracts
  GOCompanionPersistence/  SQLite adapter and forward migration runner
  CSQLite/                 minimal system-library bridge
Tests/GOCompanionTests/    domain, migration, cache-key tests and fake fixtures
docs/                      product and engineering source of truth
.github/workflows/         private-repository CI
```

## Configuration and data safety

Copy `.env.example` to `.env` only when a future integration needs local configuration. `.env`, SQLite databases, signing files, and build artifacts are ignored. Never put credentials in Swift source, fixtures, logs, or Git history.

Migrations are immutable after application. New schema work receives a new numbered migration and tests. Before destructive migrations are introduced, backup/export and recovery behavior must exist and be documented.

## Contributing workflow

1. Create a normal Git branch.
2. Read `AGENTS.md` and the relevant design documents.
3. Make a scoped change with tests and documentation.
4. Run the three commands above.
5. Review the diff, commit, and push to a private GitHub repository.

The JSON format and safe empty-database restore boundary are documented in [Backup Format](docs/BACKUP_FORMAT.md). The roadmap deliberately separates this collection engine from Phase 2 game knowledge; see [Roadmap](docs/ROADMAP.md).
