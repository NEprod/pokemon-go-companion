import AppKit
import GOCompanionCapture
import GOCompanionExtraction
import GOCompanionScreenAnalysis
import MacCaptureAdapter
import MacRecognitionAdapter
import SwiftUI

@MainActor
final class CaptureDiagnosticModel: ObservableObject {
    @Published var windows: [CaptureWindow] = []
    @Published var selectedWindowID: UInt32?
    @Published var diagnostics = CaptureDiagnostics()
    @Published var permissionGranted = false
    @Published var notice = ""
    @Published var rawClassification: ScreenClassification?
    @Published var stableClassification: ScreenType?
    @Published var continuityState: ScreenContinuityState = .none
    @Published var replaySummary: String?
    @Published var scanSession: TemporaryPokemonScanSession?
    @Published var lastFinishedScan: TemporaryPokemonScanSession?
    @Published var walkthroughID: UUID?
    @Published var candidateCount = 0
    @Published var completedCandidates: [TemporaryPokemonScanSession] = []
    @Published var transitionPhase: CandidateTransitionPhase = .no
    @Published var transitionEvidence = "No candidate change observed."
    @Published var quarantinedObservationCount = 0
    @Published var quarantinedSummary: [String] = []
    @Published var lastRollover: CandidateRollover?
    @Published var extractionNotice = "Waiting for a stable Detail screen."
    @Published var extractionMode = "Waiting for Detail"
    @Published var appraisalReadiness = "Not in Appraisal"
    @Published var showExtractionROIs = false
    @Published var extractionPreview: CGImage?
    @Published var extractionPreviewScreen: ScreenType?
    @Published var extractionPreviewViewport: GameContentViewport?
    @Published var extractionPreviewRegions: [(ExtractionRegion, PixelRect)] = []

    private let source: any CaptureSource = ScreenCaptureKitWindowSource()
    private let classifier = ScreenClassifier()
    private var stabilizer = ScreenClassificationStabilizer()
    private var latestClassifierFrame: CapturedImageFrame?
    private let textRecognizer: any RegionTextRecognizer = VisionRegionTextRecognizer()
    private let detailExtractor = PokemonDetailExtractor()
    private let appraisalExtractor = AppraisalBarExtractor()
    private var walkthrough = PokemonWalkthroughCoordinator()
    private var extractionInProgress = false
    private var actionMenuVisible = false
    private var captureGeneration = UUID()

    init() {
        permissionGranted = source.hasScreenRecordingPermission()
        if !permissionGranted { notice = CaptureError.permissionRequired.description }
    }

    func requestPermission() {
        permissionGranted = source.requestScreenRecordingPermission()
        notice =
            permissionGranted ? "Permission granted. Refresh windows." : CaptureError.permissionRequired.description
    }

    func refreshWindows() async {
        permissionGranted = source.hasScreenRecordingPermission()
        guard permissionGranted else {
            notice = CaptureError.permissionRequired.description
            return
        }
        do {
            windows = try await source.discoverWindows()
            if !windows.contains(where: { $0.id == selectedWindowID }) { selectedWindowID = nil }
            notice =
                windows.isEmpty
                ? "No shareable windows found. Open iPhone Mirroring and refresh."
                : "Select a window from the list. Suggestions are marked below."
        } catch {
            notice = error.localizedDescription
        }
    }

    func start() async {
        guard let window = windows.first(where: { $0.id == selectedWindowID }) else {
            notice = "Select a window first."
            return
        }
        diagnostics.begin(window: window)
        rawClassification = nil
        stableClassification = nil
        continuityState = .none
        replaySummary = nil
        latestClassifierFrame = nil
        stabilizer = ScreenClassificationStabilizer()
        walkthrough = PokemonWalkthroughCoordinator()
        scanSession = nil
        lastFinishedScan = nil
        extractionPreview = nil
        extractionPreviewScreen = nil
        extractionPreviewViewport = nil
        extractionPreviewRegions = []
        extractionNotice = "Waiting for a stable Detail screen."
        extractionMode = "Waiting for Detail"
        appraisalReadiness = "Not in Appraisal"
        actionMenuVisible = false
        captureGeneration = UUID()
        do {
            try await source.start(windowID: window.id) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .frame(let metadata): self.diagnostics.receive(metadata)
                    case .imageFrame(let image):
                        let classification = self.classifier.classify(image)
                        let visualState = PokemonJourneyVisualState(classifierFrame: image)
                        self.actionMenuVisible = visualState.actionMenuVisible
                        self.latestClassifierFrame = image
                        self.rawClassification = classification
                        self.stableClassification = self.stabilizer.append(
                            visualState.stabilizationInput(classification))
                        self.continuityState = self.stabilizer.continuity
                        self.walkthrough.receive(
                            stableScreen: self.stableClassification, observations: [], at: image.timestamp,
                            actionMenuVisible: self.actionMenuVisible)
                        if self.actionMenuVisible {
                            self.extractionMode = "Paused — Pokémon action menu"
                            self.appraisalReadiness = "Not in Appraisal"
                            self.extractionPreviewScreen = nil
                            self.extractionPreviewRegions = []
                            self.extractionNotice = "Existing scan session retained; no fields extracted from menu."
                        }
                        self.publishScanState()
                    case .observationFrame(let frame):
                        self.handleObservationFrame(frame)
                    case .stoppedWithError(let message):
                        self.diagnostics.fail(message)
                        self.notice = CaptureError.streamFailure(message).description
                    }
                }
            }
            diagnostics.didStart()
            notice = "Capturing the selected window. Navigate manually on the iPhone."
        } catch {
            diagnostics.fail(error.localizedDescription)
            notice = error.localizedDescription
        }
    }

    func stop() async {
        guard diagnostics.state == .capturing || diagnostics.state == .starting || diagnostics.state == .failed else {
            return
        }
        diagnostics.beginStop()
        captureGeneration = UUID()
        do {
            try await source.stop()
            diagnostics.didStop()
            notice = "Capture stopped."
        } catch {
            diagnostics.fail(error.localizedDescription)
            notice = error.localizedDescription
        }
    }

    private func publishScanState() {
        scanSession = walkthrough.current
        lastFinishedScan = walkthrough.lastFinished
        walkthroughID = walkthrough.id
        candidateCount = walkthrough.candidateCount
        completedCandidates = walkthrough.completed
        transitionPhase = walkthrough.transitionPhase
        transitionEvidence = walkthrough.transitionEvidence
        quarantinedObservationCount = walkthrough.quarantinedObservationCount
        quarantinedSummary = walkthrough.quarantinedSummary
        lastRollover = walkthrough.lastRollover
    }

    private func handleObservationFrame(_ frame: CapturedObservationFrame) {
        guard diagnostics.state == .capturing else { return }
        extractionPreview = RGBImageRenderer.image(frame)
        let viewport = GameContentViewport(frame: frame)
        extractionPreviewViewport = viewport
        extractionPreviewScreen = nil
        extractionPreviewRegions = []
        let screen = stableClassification
        let bars = screen == .appraisal ? appraisalExtractor.resolvedRegions(frame: frame) : []
        let readiness = screen == .appraisal ? AppraisalIVReadiness(frame: frame, barRegions: bars) : nil
        let mode = PokemonExtractionMode.resolve(
            stableScreen: screen, hasSession: walkthrough.current != nil,
            actionMenuVisible: actionMenuVisible, appraisalIVReady: readiness?.isReady == true)
        appraisalReadiness = readiness?.reason ?? "Not in Appraisal"
        switch mode {
        case .pausedActionMenu:
            extractionMode = "Paused — Pokémon action menu"
            return
        case .waitingForSession:
            extractionMode = "Paused — no established Detail/Appraisal session"
            return
        case .appraisalIntro:
            extractionMode = "Appraisal intro — IV extraction paused"
            extractionNotice = "Appraisal context retained; waiting for visible three-row IV card."
            return
        case .appraisalIVs:
            extractionPreviewRegions = bars
            extractionMode = "Appraisal IV bars"
        case .detail:
            extractionPreviewRegions = PokemonExtractionLayout.regions(for: .pokemonDetail).compactMap { region, roi in
                viewport.pixelRect(for: roi).map { (region, $0) }
            }
            extractionMode = "Detail name / CP / HP"
        }
        guard let screen else { return }
        extractionPreviewScreen = screen
        guard !extractionInProgress else { return }
        extractionInProgress = true
        let generation = captureGeneration
        let sessionID = walkthrough.current?.id
        Task { [weak self] in
            guard let self else { return }
            defer { self.extractionInProgress = false }
            do {
                let regions =
                    screen == .pokemonDetail
                    ? Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail))
                    : PokemonExtractionLayout.appraisalIdentityRegions
                let recognized = try await self.textRecognizer.recognize(frame: frame, regions: regions)
                guard generation == self.captureGeneration, sessionID == self.walkthrough.current?.id,
                    self.stableClassification == screen, !self.actionMenuVisible,
                    self.extractionPreviewScreen == screen
                else { return }
                let textObservations = self.detailExtractor.observations(
                    from: recognized, frame: frame, sourceScreen: screen)
                let observations =
                    screen == .appraisal
                    ? textObservations + self.appraisalExtractor.observations(frame: frame)
                    : textObservations
                self.walkthrough.receive(stableScreen: screen, observations: observations, at: frame.timestamp)
                self.publishScanState()
                if screen == .appraisal {
                    let pending =
                        self.walkthrough.quarantinedObservationCount
                        + (self.walkthrough.current?.unverifiedAppraisalObservations.count ?? 0)
                    self.extractionNotice =
                        pending > 0
                        ? "Appraisal observations quarantined pending corroborated identity; not joined to prior Pokémon."
                        : "Appraisal: \(observations.filter { [.ivAttack, .ivDefense, .ivHP].contains($0.field) }.count)/3 provisional IVs linked by visible identity."
                } else {
                    self.extractionNotice =
                        observations.isEmpty
                        ? "Targeted text was not resolved; check ROI overlay and OCR language."
                        : "Detail: \(observations.count) field observations from frame #\(frame.frameID)."
                }
            } catch {
                self.extractionNotice = "Targeted text recognition failed: \(error.localizedDescription)"
            }
        }
    }

    func saveOneFrame() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "capture-diagnostic.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try source.saveLatestFrame(to: url)
            notice = "Saved one frame to \(url.lastPathComponent). Keep it private."
        } catch {
            notice = error.localizedDescription
        }
    }

    func saveExactClassifierFrame() {
        guard let frame = latestClassifierFrame, let classification = rawClassification,
            frame.frameID == classification.frameID
        else {
            notice = "No matching classifier frame is available yet."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "capture-classifier-frame-\(frame.frameID).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let record = ClassifierReplayRecord(frame: frame, classification: classification)
        do {
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            notice =
                "Saved exact classifier RGB bytes locally to \(url.lastPathComponent). Contains private screen content."
        } catch {
            notice = error.localizedDescription
        }
    }

    func replayExactClassifierFrame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let record = try JSONDecoder().decode(ClassifierReplayRecord.self, from: Data(contentsOf: url))
            guard let frame = record.archive.restoredFrame() else {
                notice = "The saved classifier frame is invalid or unsupported."
                return
            }
            let replay = classifier.classify(frame)
            let identical =
                replay.screenType.rawValue == record.originalScreenType
                && replay.confidence == record.originalConfidence
                && replay.evidence.map(\.signal) == record.originalEvidenceSignals
            replaySummary =
                "Saved raw: \(record.originalScreenType) · replay: \(replay.screenType.rawValue) · "
                + "\(identical ? "same classification" : "DIFFERENT classification") · "
                + "exact RGB \(frame.width)×\(frame.height) px, frame #\(frame.frameID)"
            notice = "Replayed one local classifier frame. No capture or game input was performed."
        } catch {
            notice = "Could not replay that classifier frame: \(error.localizedDescription)"
        }
    }
}

private struct ClassifierReplayRecord: Codable {
    let archive: CapturedImageFrameArchive
    let originalScreenType: String
    let originalConfidence: Double
    let originalEvidenceSignals: [String]

    init(frame: CapturedImageFrame, classification: ScreenClassification) {
        archive = CapturedImageFrameArchive(frame: frame)
        originalScreenType = classification.screenType.rawValue
        originalConfidence = classification.confidence
        originalEvidenceSignals = classification.evidence.map(\.signal)
    }
}

struct CaptureDiagnosticView: View {
    @StateObject private var model = CaptureDiagnosticModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("iPhone Mirroring capture diagnostic").font(.title2)
                Text("Screen Recording permission: \(model.permissionGranted ? "granted" : "required")")
                if !model.permissionGranted {
                    Button("Request Screen Recording Permission") { model.requestPermission() }
                    Text(
                        "If macOS asks, allow this diagnostic app in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen it."
                    )
                    .font(.caption)
                }
                Button("Refresh shareable windows") { Task { await model.refreshWindows() } }
                    .disabled(!model.permissionGranted)

                List(selection: $model.selectedWindowID) {
                    ForEach(model.windows) { window in
                        HStack {
                            Text(window.label)
                            if MirroringWindowSuggestion.score(window) > 0 {
                                Text("Likely iPhone Mirroring").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(window.id)
                    }
                }
                .frame(minHeight: 170)

                HStack {
                    Button("Start selected-window capture") { Task { await model.start() } }
                        .disabled(
                            model.selectedWindowID == nil || !model.permissionGranted
                                || model.diagnostics.state == .capturing || model.diagnostics.state == .starting)
                    Button("Stop") { Task { await model.stop() } }
                        .disabled(model.diagnostics.state != .capturing && model.diagnostics.state != .starting)
                    Button("Save one frame…") { model.saveOneFrame() }
                        .disabled(model.diagnostics.latestFrame == nil || model.diagnostics.state != .capturing)
                    Button("Save exact classifier RGB…") { model.saveExactClassifierFrame() }
                        .disabled(model.rawClassification == nil)
                    Button("Replay saved RGB…") { model.replayExactClassifierFrame() }
                }
                Text("Exact RGB replay files contain private screen pixels. Keep them local and out of Git.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("State: \(model.diagnostics.state.rawValue)")
                Text("Selected: \(model.diagnostics.selectedWindow?.label ?? "none")")
                Text("Complete frames: \(model.diagnostics.frameCount)")
                if let frame = model.diagnostics.latestFrame {
                    Text(
                        "Latest frame: \(frame.widthPixels)×\(frame.heightPixels) px; stream time \(frame.presentationSeconds.formatted(.number.precision(.fractionLength(3)))) s; received \(frame.receivedAt.formatted(date: .omitted, time: .standard))"
                    )
                }
                if let classification = model.rawClassification {
                    Text(
                        "Raw screen: \(classification.screenType.rawValue) · confidence \(classification.confidence.formatted(.percent.precision(.fractionLength(0))))"
                    )
                    if let stable = model.stableClassification {
                        Text("Stable screen: \(stable.rawValue)")
                    }
                    switch model.continuityState {
                    case .none:
                        EmptyView()
                    case .retaining(let screen, let count, let allowance):
                        Text("Continuity: retaining \(screen.rawValue) through ambiguous frame \(count)/\(allowance)")
                            .font(.caption).foregroundStyle(.secondary)
                    case .expired:
                        Text("Continuity: expired; persistent ambiguity is stable unknown")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(classification.evidence.prefix(5).enumerated()), id: \.offset) { _, item in
                        Text("• \(item.explanation)").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(classification.candidateAssessments.prefix(2).enumerated()), id: \.offset) {
                        _, candidate in
                        Text(
                            "Candidate \(candidate.screenType.rawValue): \(candidate.matchedSignals)/\(candidate.totalSignals) signals; support \(candidate.supportScore.formatted(.percent.precision(.fractionLength(0))))"
                        )
                        .font(.caption)
                        if let support = candidate.supportingSignals.first {
                            Text("  Support: \(support)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let missing = candidate.missingSignals.first {
                            Text("  Contradiction: \(missing)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Screen classification: waiting for a complete frame")
                }
                if let replay = model.replaySummary { Text(replay).font(.caption) }
                Divider()
                Text("Temporary Pokémon scan preview").font(.headline)
                if let walkthroughID = model.walkthroughID {
                    Text(
                        "Walkthrough: \(walkthroughID.uuidString.prefix(8)) · "
                            + "temporary candidates: \(model.candidateCount)"
                    )
                    Text(
                        "Transition: \(model.transitionPhase.rawValue) · quarantined observations: \(model.quarantinedObservationCount)"
                    )
                    .font(.caption)
                    Text(model.transitionEvidence).font(.caption).foregroundStyle(.secondary)
                    ForEach(model.quarantinedSummary, id: \.self) { line in
                        Text("Held: \(line)").font(.caption).foregroundStyle(.orange)
                    }
                    if let rollover = model.lastRollover {
                        Text(
                            "Last rollover: \(rollover.previousID.uuidString.prefix(8)) → "
                                + "\(rollover.nextID.uuidString.prefix(8))"
                        )
                        .font(.caption).foregroundStyle(.green)
                    }
                    ForEach(Array(model.completedCandidates.suffix(5).reversed())) { candidate in
                        let summary = candidate.consensus.compactMap { result in
                            result.value.map { "\(result.field.rawValue)=\($0.description)" }
                        }.joined(separator: " · ")
                        Text("Completed \(candidate.id.uuidString.prefix(8)): \(summary)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let session = model.scanSession ?? model.lastFinishedScan {
                    Text(
                        "Scan session: \(session.id.uuidString.prefix(8)) · \(session.endedAt == nil ? "active" : "finished")"
                    )
                    Text(
                        "Recent observations: \(session.observations.count) · possible new Pokémon: \(session.possibleNewPokemon ? "review" : "no")"
                    )
                    ForEach(session.consensus, id: \.field) { result in
                        Text(
                            "\(result.field.rawValue): \(result.value?.description ?? "unresolved") · \(result.status.rawValue) · \(result.supportingFrames) frame(s)"
                                + (result.alternatives.isEmpty
                                    ? ""
                                    : " · alternatives: \(result.alternatives.map(\.description).joined(separator: ", "))")
                        )
                        .font(.caption)
                    }
                    if !session.quarantinedIdentityObservations.isEmpty {
                        Text(
                            "Identity variants held for review: \(session.quarantinedIdentityObservations.count) distinct, "
                                + "\(session.quarantinedIdentityObservations.reduce(0) { $0 + $1.occurrences }) observations"
                        )
                        .font(.caption).foregroundStyle(.orange)
                        ForEach(Array(session.quarantinedIdentityObservations.prefix(4).enumerated()), id: \.offset) {
                            _, variant in
                            Text(
                                "  \(variant.field.rawValue)=\(variant.value.description) ×\(variant.occurrences) · "
                                    + "frames \(variant.first.frameID)…\(variant.latest.frameID)"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if session.overflowedVariantOccurrences > 0 {
                        Text(
                            "Additional distinct variants: \(session.overflowedVariantOccurrences) observations; review required"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                    if !session.unverifiedAppraisalObservations.isEmpty {
                        Text(
                            "Unverified Appraisal IVs (not joined): \(session.unverifiedAppraisalObservations.map { "\($0.field.rawValue)=\($0.value.description) ×\($0.occurrences)" }.joined(separator: ", "))"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(Array(session.observations.suffix(6).reversed()), id: \.observation.id) { entry in
                        let item = entry.observation
                        Text(
                            "Frame #\(item.frameID) · \(item.field.rawValue)=\(item.value.description) · "
                                + "\(item.method == .visionText ? "Vision candidate" : "bar signal") "
                                + "\(item.confidence.formatted(.percent.precision(.fractionLength(0)))) · parser valid · \(item.sourceScreen.rawValue)"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                            "  \(item.region.rawValue) · window \(item.sourceWindowID.map(String.init) ?? "—") · \(item.observedAt.formatted(date: .omitted, time: .standard)) · \(item.methodVersion) · \(item.evidence)"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No Detail scan session established yet.").font(.caption)
                }
                Text("Extraction mode: \(model.extractionMode)").font(.caption)
                Text("Appraisal IV readiness: \(model.appraisalReadiness)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.extractionNotice).font(.caption)
                Toggle("Show extraction ROI preview", isOn: $model.showExtractionROIs)
                if model.showExtractionROIs, let preview = model.extractionPreview,
                    let viewport = model.extractionPreviewViewport
                {
                    let previewWidth = 180.0
                    let previewHeight = previewWidth * Double(preview.height) / Double(preview.width)
                    let scaleX = previewWidth / Double(preview.width)
                    let scaleY = previewHeight / Double(preview.height)
                    Text(
                        "Active ROI set: \(model.extractionPreviewScreen == nil ? "none — extraction paused" : model.extractionMode)"
                    )
                    .font(.caption)
                    Text("Capture frame: \(preview.width) × \(preview.height) px")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(
                        "Game content: x=\(viewport.rect.x) y=\(viewport.rect.y) w=\(viewport.rect.width) h=\(viewport.rect.height) · \(viewport.basis == .mirroringWindowChrome ? "Mirroring chrome" : "full frame")"
                    )
                    .font(.caption).foregroundStyle(.cyan)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: preview, scale: 1)
                            .resizable().frame(width: previewWidth, height: previewHeight)
                        Rectangle().stroke(.cyan, lineWidth: 2)
                            .frame(
                                width: Double(viewport.rect.width) * scaleX,
                                height: Double(viewport.rect.height) * scaleY
                            )
                            .position(
                                x: (Double(viewport.rect.x) + Double(viewport.rect.width) / 2) * scaleX,
                                y: (Double(viewport.rect.y) + Double(viewport.rect.height) / 2) * scaleY)
                        ForEach(Array(model.extractionPreviewRegions.enumerated()), id: \.offset) {
                            _, entry in
                            let region = entry.0, rect = entry.1
                            Rectangle().stroke(.yellow, lineWidth: 2)
                                .frame(width: Double(rect.width) * scaleX, height: Double(rect.height) * scaleY)
                                .position(
                                    x: (Double(rect.x) + Double(rect.width) / 2) * scaleX,
                                    y: (Double(rect.y) + Double(rect.height) / 2) * scaleY)
                            Text(region.rawValue).font(.system(size: 9)).foregroundStyle(.yellow)
                                .position(x: Double(rect.x) * scaleX + 28, y: Double(rect.y) * scaleY)
                        }
                    }
                    .frame(width: previewWidth, height: previewHeight)
                    ForEach(Array(model.extractionPreviewRegions.enumerated()), id: \.offset) {
                        _, entry in
                        let rect = entry.1
                        Text(
                            "\(entry.0.rawValue): x=\(rect.x) y=\(rect.y) w=\(rect.width) h=\(rect.height)"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(
                        "Cyan = game-content viewport; yellow = extraction crop. Preview preserves frame aspect ratio."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.diagnostics.errorMessage {
                    Text("Error: \(error)").foregroundStyle(.red)
                }
                Text(model.notice).font(.caption)
            }
            .padding()
            .frame(minWidth: 760, minHeight: 520)
        }
        .onAppear { Task { await model.refreshWindows() } }
        .onDisappear { Task { await model.stop() } }
    }
}

@main
struct CaptureDiagnosticApp: App {
    var body: some Scene {
        WindowGroup { CaptureDiagnosticView() }
    }
}
