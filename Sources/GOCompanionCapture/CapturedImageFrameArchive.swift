import Foundation

/// Lossless local replay of the exact RGB bytes delivered to the classifier.
/// This is diagnostic data and may contain private screen contents.
public struct CapturedImageFrameArchive: Codable, Sendable {
    public let formatVersion: Int
    public let width: Int
    public let height: Int
    public let rgbPixels: Data
    public let frameID: UInt64
    public let timestamp: Date

    public init(frame: CapturedImageFrame) {
        formatVersion = 1
        width = frame.width
        height = frame.height
        rgbPixels = frame.rgbPixels
        frameID = frame.frameID
        timestamp = frame.timestamp
    }

    public func restoredFrame() -> CapturedImageFrame? {
        guard formatVersion == 1 else { return nil }
        return CapturedImageFrame(
            width: width, height: height, rgbPixels: rgbPixels,
            frameID: frameID, timestamp: timestamp)
    }
}
