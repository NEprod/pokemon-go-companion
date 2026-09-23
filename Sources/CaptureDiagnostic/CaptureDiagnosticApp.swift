import AppKit
import GOCompanionCapture
import GOCompanionScreenAnalysis
import MacCaptureAdapter
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

    private let source: any CaptureSource = ScreenCaptureKitWindowSource()
    private let classifier = ScreenClassifier()
    private var stabilizer = ScreenClassificationStabilizer()
    private var latestClassifierFrame: CapturedImageFrame?

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
        do {
            try await source.start(windowID: window.id) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .frame(let metadata): self.diagnostics.receive(metadata)
                    case .imageFrame(let image):
                        let classification = self.classifier.classify(image)
                        self.latestClassifierFrame = image
                        self.rawClassification = classification
                        self.stableClassification = self.stabilizer.append(classification)
                        self.continuityState = self.stabilizer.continuity
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
        do {
            try await source.stop()
            diagnostics.didStop()
            notice = "Capture stopped."
        } catch {
            diagnostics.fail(error.localizedDescription)
            notice = error.localizedDescription
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
            if let error = model.diagnostics.errorMessage {
                Text("Error: \(error)").foregroundStyle(.red)
            }
            Text(model.notice).font(.caption)
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
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
