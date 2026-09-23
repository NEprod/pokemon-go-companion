import Foundation

public struct CaptureWindow: Identifiable, Hashable, Sendable {
    /// ScreenCaptureKit window IDs identify a window for its current lifetime, not across launches.
    public let id: UInt32
    public let title: String?
    public let applicationName: String
    public let applicationBundleID: String?
    public let widthPoints: Int
    public let heightPoints: Int
    public let isOnScreen: Bool

    public init(
        id: UInt32, title: String?, applicationName: String, applicationBundleID: String?,
        widthPoints: Int, heightPoints: Int, isOnScreen: Bool
    ) {
        self.id = id
        self.title = title
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.isOnScreen = isOnScreen
    }

    public var label: String {
        let detail = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
        return "\(applicationName) — \(detail) (#\(id), \(widthPoints)×\(heightPoints) pt)"
    }
}

public enum MirroringWindowSuggestion {
    /// Metadata is only a hint. The operator always selects a window explicitly.
    public static func score(_ window: CaptureWindow) -> Int {
        let bundle = window.applicationBundleID?.lowercased() ?? ""
        let app = window.applicationName.lowercased()
        let title = window.title?.lowercased() ?? ""
        if bundle == "com.apple.screencontinuity" { return 100 }
        if app.contains("iphone mirroring") { return 80 }
        if app.contains("iphone") && app.contains("mirror") { return 60 }
        if title.contains("iphone mirroring") { return 40 }
        return 0
    }
}

public enum CaptureSessionState: String, Sendable {
    case idle, starting, capturing, stopping, stopped, failed
}

public struct CapturedFrameMetadata: Equatable, Sendable {
    public let widthPixels: Int
    public let heightPixels: Int
    /// Presentation time on the stream clock, not wall-clock time.
    public let presentationSeconds: Double
    public let receivedAt: Date

    public init(widthPixels: Int, heightPixels: Int, presentationSeconds: Double, receivedAt: Date) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.presentationSeconds = presentationSeconds
        self.receivedAt = receivedAt
    }
}

public struct CaptureDiagnostics: Sendable {
    public private(set) var state: CaptureSessionState = .idle
    public private(set) var selectedWindow: CaptureWindow?
    public private(set) var frameCount = 0
    public private(set) var latestFrame: CapturedFrameMetadata?
    public private(set) var errorMessage: String?

    public init() {}

    public mutating func begin(window: CaptureWindow) {
        selectedWindow = window
        frameCount = 0
        latestFrame = nil
        errorMessage = nil
        state = .starting
    }

    public mutating func didStart() { state = .capturing }

    public mutating func receive(_ frame: CapturedFrameMetadata) {
        guard state == .starting || state == .capturing else { return }
        guard frame.widthPixels > 0, frame.heightPixels > 0,
            frame.presentationSeconds.isFinite
        else { return }
        frameCount += 1
        latestFrame = frame
    }

    public mutating func beginStop() { state = .stopping }
    public mutating func didStop() { state = .stopped }

    public mutating func fail(_ message: String) {
        errorMessage = message
        state = .failed
    }
}

public enum CaptureError: Error, Equatable, CustomStringConvertible, Sendable {
    case permissionRequired
    case windowUnavailable(UInt32)
    case invalidWindowSize
    case noFrameAvailable
    case streamFailure(String)

    public var description: String {
        switch self {
        case .permissionRequired:
            "Screen Recording permission is required. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then restart this app."
        case .windowUnavailable(let id): "Selected window #\(id) is no longer shareable. Refresh the window list."
        case .invalidWindowSize: "The selected window has no usable dimensions."
        case .noFrameAvailable: "No complete image frame has arrived yet."
        case .streamFailure(let message): "Capture stopped: \(message)"
        }
    }
}

public enum CaptureEvent: Sendable {
    case frame(CapturedFrameMetadata)
    case stoppedWithError(String)
}

@MainActor
public protocol CaptureSource: AnyObject {
    func hasScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func discoverWindows() async throws -> [CaptureWindow]
    func start(windowID: UInt32, onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws
    func stop() async throws
    func saveLatestFrame(to url: URL) throws
}
