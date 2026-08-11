# GO Account Companion agent guide

Read `README.md`, `docs/ARCHITECTURE.md`, and relevant docs/ADRs before changing code.

- This application observes user-selected content and advises. Never automate gameplay, taps, account access, location, transfers, trades, evolutions, power-ups, or anti-cheat/security bypasses.
- Keep `GOCompanionDomain` platform-independent. UI depends on application/domain services; domain code never imports UI, ScreenCaptureKit, OCR, providers, or concrete databases.
- Keep platform capture adapters separate from recognition; keep recognition/observations separate from recommendations.
- User facts, game/reference knowledge, preferences, and derived recommendations are distinct. Never persist recommendations as durable user facts. User, knowledge, and disposable derived data use separate SQLite databases.
- Every recognized field carries confidence and provenance. Never fabricate missing values. High-impact advice needs high confidence; Transfer and irreversible-action advice must fail safely to Review/Hold.
- Treat provider input as untrusted: validate, version, retain source provenance and previous-good data, activate atomically, and continue offline after failures. Providers must remain replaceable behind contracts.
- Use explicit, forward-only migrations. Never edit an applied migration or perform a destructive migration without a tested migration plan and recoverable backup/export path.
- Add or update tests with behavior. Required areas include domain invariants, calculations, recommendation/tag safety, migrations, reconciliation, frozen provider fixtures, cache invalidation, and scanner regression fixtures when those features exist.
- Prefer small typed modules and dependency injection; avoid giant services, global mutable state, silent errors, sensitive logs, and premature microservices.
- Do not commit secrets, real credentials, private collection databases, or real screenshots. Use `.env.example`, Keychain/secure storage, and fake/anonymized fixtures.
- Update `/docs` when behavior or contracts change. Add or supersede an ADR for consequential architecture, persistence, sync, provider, security, or platform decisions.
- Preserve ordinary VS Code, Swift Package Manager, Git branch, review, build, and test workflows. Run `swift format lint --recursive --strict Sources Tests Package.swift` and `swift test` before handoff.
- Do not claim roadmap features work until implemented and verified. Phase boundaries in `docs/ROADMAP.md` are authoritative.
