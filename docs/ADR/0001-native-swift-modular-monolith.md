# ADR 0001: Native Swift modular monolith

- Status: Accepted
- Date: 2026-08-11

## Context

macOS is first and must capture a user-selected Apple iPhone Mirroring window; iOS follows; Windows is desirable. Shared logic, local SQLite, offline use, quality UI, testing, and maintainability matter. A premature cross-platform UI could make the most platform-specific requirement harder, while Apple-only framework coupling could make Windows prohibitively expensive.

We compared native Swift/SwiftUI, Kotlin Multiplatform with Compose/native Apple adapters, and .NET MAUI/Avalonia. See `docs/ARCHITECTURE.md` for the decision matrix.

## Decision

Use Swift 6 packages in a modular monolith and native SwiftUI app shells. Keep domain/application/knowledge contracts free of SwiftUI, ScreenCaptureKit, Vision, CloudKit, and provider DTOs. ScreenCaptureKit is a macOS adapter. SQLite and external providers implement ports. No microservices.

Use the same shared Swift packages for macOS/iOS. Before Windows implementation, spike Swift core/SQLite support on Windows. If a dependency is impractical, port against the canonical schema and service contracts rather than compromising Mac capture today.

## Consequences

Mac capture, permissions, accessibility, performance, signing, and iOS integration are direct and native; Phase 0 builds with the installed toolchain and few dependencies. Mac/iOS share nearly all non-UI logic. Windows UI and possibly a persistence/core subset require later work; the adapter boundary and open formats contain that cost. Kotlin would improve Windows sharing but introduces Apple bridge/build complexity now. .NET offers excellent Windows sharing but makes ScreenCaptureKit/Apple-native lifecycle work less direct and adds a toolchain not present in the repository.

Revisit only after a measured capture prototype or Windows core spike, and supersede this ADR rather than editing its history.
