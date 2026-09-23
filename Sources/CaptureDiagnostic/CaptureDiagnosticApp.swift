import AppKit
import GOCompanionCapture
import MacCaptureAdapter
import SwiftUI

@MainActor
final class CaptureDiagnosticModel: ObservableObject {
    @Published var windows: [CaptureWindow] = []
    @Published var selectedWindowID: UInt32?
    @Published var diagnostics = CaptureDiagnostics()
    @Published var permissionGranted = false
    @Published var notice = ""

    private let source: any CaptureSource = ScreenCaptureKitWindowSource()

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
        do {
            try await source.start(windowID: window.id) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .frame(let metadata): self.diagnostics.receive(metadata)
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
            }

            Text("State: \(model.diagnostics.state.rawValue)")
            Text("Selected: \(model.diagnostics.selectedWindow?.label ?? "none")")
            Text("Complete frames: \(model.diagnostics.frameCount)")
            if let frame = model.diagnostics.latestFrame {
                Text(
                    "Latest frame: \(frame.widthPixels)×\(frame.heightPixels) px; stream time \(frame.presentationSeconds.formatted(.number.precision(.fractionLength(3)))) s; received \(frame.receivedAt.formatted(date: .omitted, time: .standard))"
                )
            }
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
