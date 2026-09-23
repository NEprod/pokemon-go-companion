import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import GOCompanionCapture
@preconcurrency import ScreenCaptureKit

@MainActor
public final class ScreenCaptureKitWindowSource: CaptureSource {
    private var stream: SCStream?
    private var sink: FrameSink?

    public init() {}

    public func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func discoverWindows() async throws -> [CaptureWindow] {
        guard hasScreenRecordingPermission() else { throw CaptureError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true)
        return content.windows
            .filter { $0.windowLayer == 0 && $0.frame.width > 0 && $0.frame.height > 0 }
            .map(Self.describe)
            .sorted {
                let lhs = MirroringWindowSuggestion.score($0)
                let rhs = MirroringWindowSuggestion.score($1)
                return lhs == rhs ? $0.label < $1.label : lhs > rhs
            }
    }

    public func start(windowID: UInt32, onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws {
        guard hasScreenRecordingPermission() else { throw CaptureError.permissionRequired }
        if stream != nil { try await stop() }

        // Resolve the ID again immediately before starting; a refreshed list may contain a new window.
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowUnavailable(windowID)
        }
        guard window.frame.width > 0, window.frame.height > 0 else {
            throw CaptureError.invalidWindowSize
        }

        let maximumDimension = 1_280.0
        let scale = min(2.0, maximumDimension / max(window.frame.width, window.frame.height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let frameSink = FrameSink(onEvent: onEvent)
        let captureStream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: frameSink)
        try captureStream.addStreamOutput(
            frameSink, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "GOCompanion.CaptureDiagnostic.frames"))
        sink = frameSink
        stream = captureStream
        do {
            try await captureStream.startCapture()
        } catch {
            try? captureStream.removeStreamOutput(frameSink, type: .screen)
            sink = nil
            stream = nil
            throw error
        }
    }

    public func stop() async throws {
        guard let stream else { return }
        defer {
            self.stream = nil
            self.sink = nil
        }
        try await stream.stopCapture()
        if let sink { try? stream.removeStreamOutput(sink, type: .screen) }
    }

    public func saveLatestFrame(to url: URL) throws {
        guard let buffer = sink?.latestPixelBuffer() else { throw CaptureError.noFrameAvailable }
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard
            let png = context.pngRepresentation(
                of: image, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        else { throw CaptureError.streamFailure("Could not encode the latest frame") }
        try png.write(to: url, options: .atomic)
    }

    private static func describe(_ window: SCWindow) -> CaptureWindow {
        CaptureWindow(
            id: window.windowID,
            title: window.title,
            applicationName: window.owningApplication?.applicationName ?? "Unknown application",
            applicationBundleID: window.owningApplication?.bundleIdentifier,
            widthPoints: Int(window.frame.width),
            heightPoints: Int(window.frame.height),
            isOnScreen: window.isOnScreen)
    }
}

private final class FrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let onEvent: @Sendable (CaptureEvent) -> Void

    init(onEvent: @escaping @Sendable (CaptureEvent) -> Void) {
        self.onEvent = onEvent
    }

    func latestPixelBuffer() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let statusValue = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusValue) == .complete,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let metadata = CapturedFrameMetadata(
            widthPixels: CVPixelBufferGetWidth(buffer),
            heightPixels: CVPixelBufferGetHeight(buffer),
            presentationSeconds: timestamp,
            receivedAt: Date())
        guard metadata.widthPixels > 0, metadata.heightPixels > 0, timestamp.isFinite else { return }
        lock.lock()
        latest = buffer
        lock.unlock()
        onEvent(.frame(metadata))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onEvent(.stoppedWithError(error.localizedDescription))
    }
}
