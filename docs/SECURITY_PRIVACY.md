# Security and privacy

## Threat model and promises

Sensitive assets include collection/account facts, screenshots/OCR crops, catch location, preferences, plans, credentials/tokens, backups, and provider payloads. Threats include accidental broad capture, screenshot/log leakage, malicious provider data, secret commits, database corruption, sync account compromise, unsafe recommendations, and functionality drifting toward game automation.

The hard product boundary is observation and advice. There is no Pokémon GO login/token handling, private API access, input injection, gameplay control, location spoofing, botting, reverse engineering, or anti-cheat evasion. Design/code review must reject an adapter that can generate game input.

## Data handling

- Capture only the explicit user-selected window/region/image; show active state and stop controls.
- Process frames locally and ephemerally by default. Persist only structured observations unless the user deliberately saves a diagnostic fixture.
- Store private user facts separately from downloadable knowledge and disposable derived cache.
- Exclude SQLite/WAL, `.env`, signing credentials, screenshots, and crash captures from Git.
- Logs use IDs/error categories, not screenshots, OCR text, trainer names, exact catch locations, credentials, or full provider bodies. Diagnostics are opt-in and redact before export.
- Future sync/remote recognition clearly discloses fields, recipient, purpose, retention, and deletion; local operation remains available where practical.
- Backup/export is user-controlled, complete, versioned, and warns that exports contain private data.

## Secrets and platform security

Phase 0 has no secrets. Future public configuration has examples only; provider/sync tokens use Keychain or equivalent platform secure storage and are injected at composition roots. CI uses scoped encrypted secrets and untrusted pull requests cannot exfiltrate them. Rotate/revoke on exposure.

macOS Screen Recording, Photos, App Groups, iCloud, notifications, and network entitlements are requested only when their phase requires them, with purpose text and least privilege. Code signing/notarization and dependency review precede distribution.

## Integrity and availability

SQLite uses foreign keys, WAL, explicit transactions, immutable checksummed migrations, and later verified backup/restore. Provider inputs are untrusted: size limits, schema/range/reference validation, staging, hashes, atomic activation, previous-good rollback, and safe errors. Derived data can always be rebuilt.

Recommendation provenance supports audit. Confidence gating makes uncertain recognition fail toward Review/Hold. Transfer, Elite TM, evolution, and purification need increasingly strong evidence; every gameplay action remains manual. No recommendation may hide stale required knowledge.

## Dependency/provider/supply-chain controls

Prefer few mature dependencies, pinned/resolved versions, license review, GitHub dependency alerts, and CI tests. Do not execute downloaded provider content. Provider terms and attribution live in `DATA_SOURCES.md`; public data is not automatically licensed data.

## Incident and retention planning

Before production: document corrupt-database recovery, backup verification, credential revocation, provider compromise rollback, sync breach response, diagnostic retention/deletion, privacy export/deletion, and vulnerability reporting. A private personal deployment still deserves recoverability and data minimization.

## Phase 0 limitations

No app sandbox, signing entitlements, Keychain, encryption layer, sync, screenshots, or network providers exist yet. The foundation prevents secret/database commits and establishes boundaries, but it is not a completed security implementation.
