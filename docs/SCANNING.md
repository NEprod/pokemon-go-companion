# Scanning and recognition

## Safety and scope

The scanner observes only content the user explicitly selects. It never sends taps/keys, manipulates the iPhone Mirroring window, controls Pokémon GO, captures an account in the background, accesses credentials, or bypasses security. The user performs every swipe and tap.

Phase 3's primary capture target is Apple's **iPhone Mirroring window on macOS**, because Pokémon GO runs on the iPhone—not natively on the Mac. Apple's ScreenCaptureKit exposes shareable windows (`SCWindow`) and a single-window content filter. The app will show the system permission and an explicit window picker; it must not silently capture the full display. If the Mirroring window cannot be selected, is protected, changes identity, or API restrictions prevent direct capture, offer a manually selected region fallback.

## Adapter boundary

`CaptureSource` (application-owned protocol) yields timestamped pixel frames and metadata. Planned adapters:

- `ScreenCaptureKitWindowSource`: selected window ID/application/title/frame, using `SCContentFilter(desktopIndependentWindow:)` where available;
- `ScreenCaptureKitRegionSource`: user-selected display region, clipped before recognition;
- `ScreenshotSource`: user-imported images on Mac/iOS;
- future `WindowsCaptureSource` using supported Windows graphics capture APIs.

Window-title/application matching is only discovery UI; the user confirms the exact target. The adapter handles window move/resize/scale, suspension, permission revocation, and disappearance as explicit states. Frames are throttled/deduplicated before OCR and are not retained by default.

## Recognition pipeline

1. Capture/import a frame selected by the user.
2. Normalize orientation/scale/color without altering evidence.
3. Classify the Pokémon GO screen (detail, appraisal overlay, moves, Max detail, tags, inventory, unknown).
4. Detect stable regions and run local Vision/OCR and icon/template classifiers where appropriate.
5. Parse and validate candidates against the active knowledge version.
6. Emit a `PokemonObservation` with **per-field** confidence, screen/region source, time, recognizer/model version, and unknown fields left nil.
7. Aggregate observations within a `ScanSession` and request the next needed manual screen.
8. Reconcile against the candidate/collection; accept facts only under policy or create Review.

Species/form, CP, HP, gender, size, moves, appraisal IV/stars, traits (shiny/Shadow/purified/lucky/Dynamax/Gigantamax/favourite/costume/buddy/Mega), tags, and useful catch details enter incrementally. Locale, display scale, accessibility settings, animations, overlays, and game UI updates are expected sources of uncertainty.

## Progressive scan and identity

A scan session starts from detail data, then may say “Open Appraisal,” “Scroll to Moves,” “Open Dynamax details,” or “Show Appraisal again.” These observations enrich one candidate; they do not create one record per screen. Session continuity uses selected source, temporal proximity, stable visual fields, and candidate fingerprint—not a single fragile value.

Reconciliation anticipates CP/HP/level changes, evolution, move/second move changes, purification, Mega progress, tags/favourite changes, and iOS pending catches. A weighted match can propose “likely existing specimen powered up” or “possible evolution,” but ambiguity creates a task with candidates and evidence. Fingerprints never replace UUIDs.

## Confidence and privacy

Critical confidence is field-specific. Cross-field validation can reduce confidence but cannot invent a value. Transfer and irreversible recommendations use the strict policy in `RECOMMENDATION_ENGINE.md`. The UI exposes uncertainty and lets the user correct every field manually.

Recognition is local/on-device where practical. Real collection screenshots, OCR crops, names, and catch locations are private and excluded from logs/source control. Regression fixtures are synthetic or anonymized unless the user explicitly approves otherwise. Any future cloud recognition feature is opt-in, explains exactly what leaves the device and retention, and is not required for core scanning.

## Phase 3A: iPhone Mirroring capture diagnostic

Phase 3A adds `GOCompanionCapture` contracts, a macOS-only `MacCaptureAdapter`, and a small SwiftUI diagnostic executable. The core capture types contain no ScreenCaptureKit types. `SCShareableContent` enumerates visible shareable windows. The operator selects one window by its session-lifetime `windowID`; the adapter resolves that ID again before starting and uses `SCContentFilter(desktopIndependentWindow:)`. A likely iPhone Mirroring badge uses the installed app's `com.apple.ScreenContinuity` bundle ID first, then application and title hints. A badge is never a substitute for manual selection.

The stream requests BGRA video only, at up to 5 frames per second, a maximum output dimension of 1,280 pixels, queue depth 3, and no audio or cursor. It counts only valid, complete sample buffers with a nonzero pixel buffer and finite timestamp. The diagnostic reports state, selected application/window, complete-frame count, pixel dimensions, stream presentation time, local receipt time, and capture errors. The operator may explicitly save one PNG frame with the Save button; frames are otherwise kept only in memory. Do not commit a saved frame or share it casually.

**Phase 3A status: VERIFIED WORKING.** On Dale's Mac, Screen Recording permission was granted, the iPhone Mirroring window was discovered and suggested, and Dale selected it. ScreenCaptureKit captured changing Pokémon GO frames at 580 × 1280 pixels with advancing frame count and timestamps. A user-saved frame was inspected and contained clear, usable Pokémon GO pixels rather than blank or protected content. No captured image is stored in this repository.

Build a stable local app bundle from the project root:

```sh
sh scripts/build-capture-diagnostic-app.sh
open .build/Phase3ACaptureDiagnostic.app
```

The script signs the local bundle ad hoc. macOS Screen Recording permission is tied to the app identity: use this bundle for the manual test rather than launching the executable through a terminal. If permission is missing, use the app's Request button, enable **GO Capture Diagnostic** in System Settings → Privacy & Security → Screen & System Audio Recording, quit the app, and reopen it. If a rebuilt bundle does not inherit permission, check the system permission entry again.

Manual verification on Dale's Mac:

1. Open Apple's iPhone Mirroring app and display Pokémon GO on the iPhone.
2. Launch the diagnostic app and grant Screen Recording permission if prompted; restart it if macOS requires that.
3. Refresh shareable windows. Locate iPhone Mirroring by application/bundle hint or choose the correct window manually.
4. Select the window and start capture. Confirm the state says `capturing`, the frame count increases, and the size is nonzero.
5. Navigate manually within Pokémon GO. Confirm the count and latest timestamp continue to advance. Optionally save one frame and inspect it locally to confirm the pixels show the mirrored window rather than black/blank content.
6. Stop capture and confirm the state becomes `stopped` and the count no longer advances.

Window IDs may change when iPhone Mirroring restarts; refresh and reselect. A window absent from ScreenCaptureKit's shareable list or protected/blank output needs a real-device finding. Compilation and automated tests cannot establish compatibility with iPhone Mirroring. The broader Phase 3 scanner criteria below remain future work.

## Phase 3 proof criteria

Prove permission/window selection, Mirroring-window frame delivery, fallback region selection, no input/control path, basic screen classification/species/CP/appraisal recognition, per-field confidence, and deterministic fixture regression tests. Do not call the scanner production-ready based on a handful of screenshots.
