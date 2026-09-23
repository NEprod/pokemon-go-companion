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

## Planned recognition pipeline (field extraction is not implemented)

1. Capture/import a frame selected by the user.
2. Normalize orientation/scale/color without altering evidence.
3. Classify the Pokémon GO parent screen using the Phase 3B types below; moves and Max content remain Detail subsections.
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

## Phase 3B: local screen-family classification

`GOCompanionCapture` provides a platform-neutral, bounded RGB frame value. `MacCaptureAdapter` converts complete ScreenCaptureKit BGRA frames to a small row-major RGB image (longest edge at most 128 pixels); Apple capture types stay in the adapter. `GOCompanionScreenAnalysis` uses normalized image regions and returns `ScreenClassification` with top-level screen type, coarse evidence tier, reasons, frame identity, and timestamp. It has no persistence, OCR, knowledge, or recommendation dependency.

Supported top-level types are `map`, `mainMenu`, `nearby`, `pokemonStorage`, `pokemonDetail`, `appraisal`, `items`, and `profile`. `unknown` means a valid frame lacks enough evidence for a supported type (or the frame is unusable); it is not a game screen. Moves, Mega/Max controls, caught information, item sections, and Profile sections are visible content within their parent screen, **not** separate top-level types. No separate substate model is needed to decide these families yet.

The classifier downsamples larger input to a longest edge of 128 pixels and compares broad normalized header, hero, center, lower, side-rail, and bottom-control regions. It combines light-panel coverage, blue-green/warm colour groups, and repeated edge/layout structure; it does not compare whole screenshots or recognize text. Dark capture gutters/status cutouts are excluded from header and side-rail colour proportions. Appraisal requires a warm lower overlay *and* visible underlying Detail structure, and is checked before generic Detail. Nearby requires a broad pale panel with repeated tiles **and** exposed map colour above/outside it, and precedes Map. Storage requires three similarly structured columns repeating across vertical bands, a light grid background, and a lower-right control; Detail explicitly rejects that repeated grid. Detail instead requires a contrasting light document/card, a lower-right menu, and light content in its center **or surrounding an optional embedded panel**. Items requires a light fixed header/list and a repeated icon column visually denser than its text column; Profile requires its persistent warm rail and tab header. Main Menu has a broad pale upper panel with separate lower controls. Map requires an open blue-green world across regions plus lower map-control structure; this covers day and night without a separate type. Every candidate must satisfy its independent signals; otherwise the raw result is `unknown`.

Confidence is a **coarse evidence tier**, not a calibrated probability or measured live accuracy: the current three/four-signal candidates report 80%, five or more report 90%; `unknown` reports low/zero confidence. The diagnostic shows the winner or strongest partial candidate, a runner-up, their signal-support ratios, observed supporting signals, and missing gates with observed values and thresholds. The strongest partial candidate weights its defining layout anchor.

Raw classification always describes **this frame only**. The existing three-frame stabilizer establishes or changes a supported screen after two compatible positive frames; only a supported result with confidence at least 80% counts as positive temporal evidence. After establishment, stable classification retains that screen through at most **three unconfirmed frames** (nominally about 0.6 seconds at the diagnostic's five-frame-per-second capture rate). A fresh confident result for the same screen renews continuity; two positive frames for a different screen switch promptly, including Detail→Appraisal and Map→Nearby. A fourth unconfirmed frame expires the retained label to stable `unknown`. Weak/alternating candidates do not reset the allowance. Initial unknown frames cannot establish a supported screen. The diagnostic keeps raw and stable labels separate and shows the retention count or expiry. This bounded continuity is intentional: optional Detail sections may briefly yield raw `unknown` without requiring species- or mechanic-specific classifier rules. Persistent ambiguity, such as Settings, ultimately becomes stable `unknown`.

The optional local `Tests/CaptureDiagnosticTests/Fixtures/ScreenReferences/` library contains 20 real account screenshots across the eight types, including scrolled Detail, Storage, Items, and Profile views. Tests read these ignored files in place, never as SwiftPM resources, and check their top-level types at fixture and live-analysis dimensions. Set `GO_COMPANION_SCREEN_REFERENCES_DIR` to use an external directory instead. When absent, screenshot-dependent tests are skipped; a clean checkout builds and runs synthetic tests without private captures. Tests also compare the actual BGRA converter against fixture decoding for identical pixels, verify lossless RGB replay, and check adversarial Storage/Detail and unknown variants. Personal screenshots must not be uploaded or committed. The former invented synthetic layouts for `movesOrAttacks` and `maxRelated` were removed because those are not top-level screens and were not representative game images.

### Live capture discrepancy and exact replay

Dale's earlier live iPhone Mirroring tests found Main Menu, Storage, ordinary Detail, Mewtwo Adventure Effects, Max-related Detail, and Appraisal working after the first repair, but night Map, Nearby, Items, Profile, and a Kyurem Detail panel still returned `unknown`. The earlier Storage→Detail false positive arose because the circular lower-right Storage control resembled the Detail menu and the grid detector was too weak. The current grid detector requires repeated, similarly structured three-column rows; optional Detail content remains in its parent screen family. No species, move, item, or profile values are extracted.

The old **Save one frame…** exports the full ScreenCaptureKit pixel buffer as a Core Image PNG; that is useful for visual inspection but is not the exact downsampled RGB classified by the app. The diagnostic now offers **Save exact classifier RGB…**, producing a user-chosen local JSON file with the exact packed RGB bytes, dimensions, frame ID/time, and original raw classification. **Replay saved RGB…** restores those bytes and compares the new raw result with the recorded result. This file contains private screen pixels. Keep it local, untracked, and outside source control. A same-result replay shows the classifier is deterministic *after* RGB conversion; it does not alone rule out a difference in the live window pixels before conversion.

Seven exact failed 58 × 128 RGB frames are now available **locally outside the repository**. Their saved raw result was `unknown`, and replay before repair reproduced `unknown` for each. Inspection showed real visual differences that the original references did not cover: a dark night-map palette rather than teal, dark iPhone Mirroring borders/status cutout diluting header/side-rail measurements, and a large Kyurem Detail panel whose text/artwork falsely resembled three grid columns. Items also needed a true icon-column signal instead of a border edge. The repaired classifier now labels all seven **on local replay**, including small brightness perturbations, while the 20 references still pass. This demonstrates deterministic repair at the classifier-RGB boundary, **not** a fresh live-capture verification. A ScreenCaptureKit channel/stride conversion bug was not found: adapter and fixture decoding produced byte-identical RGB for identical test pixels, and the exact live RGB archives retained their failures on replay.

Set `GO_COMPANION_PRIVATE_RGB_DIR` to the local directory of exact-frame JSON archives when running Swift tests to enable their opt-in replay assertions. Without the directory, the private regression tests skip cleanly; the files are not packaged or copied into the repository. The original seven archives cover night Map, Nearby, Kyurem Detail, Items top/scrolled, and Profile top/scrolled. A later Zamazenta form-panel archive remains honestly raw `unknown`; its optional local test verifies that stable Detail bridges that isolated frame. This is generic temporal behaviour, not Zamazenta recognition. Dale's final live test confirmed both the original repairs and bounded continuity, including Detail→Appraisal, Map→Nearby, and eventual stable `unknown` on Settings.

Manual Phase 3B verification, using the existing diagnostic app and manual navigation only:

1. Build and open the diagnostic app using the Phase 3A procedure above; grant Screen Recording permission if needed.
2. Open iPhone Mirroring with Pokémon GO, refresh shareable windows, select its window, and start capture.
3. Manually visit day/night Map, Main Menu, Nearby, Pokémon Storage (top and scrolled), Pokémon Detail (top, moves, Max-related regions, Kyurem fusion-capable content, a Zamazenta form panel, and an optional embedded panel such as Adventure Effects), Appraisal, Items (top and scrolled), Profile (top and scrolled), and an unsupported screen such as Settings.
4. For each, watch raw type, confidence/evidence, candidate comparisons, stable type, and continuity status across animation and scrolling. At the narrow Zamazenta panel position, raw may be `unknown` while stable Detail is retained for up to three ambiguous frames; do not expect the raw classifier to invent a Detail label. Hold Settings long enough to confirm stable eventually becomes `unknown`, then confirm positively recognised Appraisal/Nearby transitions are not hidden.
5. On each failed raw classification, use **Save exact classifier RGB…** and then **Replay saved RGB…**. Record whether the replay matches; keep the JSON local and private. The separate PNG export can help visual inspection but is not the exact classifier input.
6. Stop capture. Fixture tests demonstrate local regression only, not live iPhone Mirroring classification accuracy.

**Phase 3B status: COMPLETE — VERIFIED WORKING.** Dale manually verified all supported screen families, Settings as unsupported, and the final continuity behaviour in the signed diagnostic using live iPhone Mirroring. Brief special-panel ambiguity retains stable Detail while raw remains truthful; persistent ambiguity expires. Dynamic overlays, weather/map variation, localization, UI updates, and device aspect ratios beyond the references can still cause raw `unknown` or incorrect labels. Future screen-specific extractors may consume a known type and emit observations, but no name/species, CP/HP/IV, move, item, profile, or other data extraction exists here.

## Phase 3 proof criteria

Prove permission/window selection, Mirroring-window frame delivery, fallback region selection, no input/control path, basic screen classification/species/CP/appraisal recognition, per-field confidence, and deterministic fixture regression tests. Do not call the scanner production-ready based on a handful of screenshots.
