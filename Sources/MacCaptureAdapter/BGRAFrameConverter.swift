import CoreVideo
import Foundation
import GOCompanionCapture

/// Exact ScreenCaptureKit BGRA-to-analysis-RGB boundary; internal for adapter-level tests.
enum BGRAFrameConverter {
    static func analysisFrame(
        from pixelBuffer: CVPixelBuffer, frameID: UInt64, timestamp: Date
    ) -> CapturedImageFrame? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0,
            CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let scale = min(1.0, 128.0 / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var pixels = Data(count: width * height * 3)
        pixels.withUnsafeMutableBytes { destination in
            guard let output = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                let sourceY = min(sourceHeight - 1, y * sourceHeight / height)
                for x in 0..<width {
                    let sourceX = min(sourceWidth - 1, x * sourceWidth / width)
                    let inputOffset = sourceY * bytesPerRow + sourceX * 4
                    let outputOffset = (y * width + x) * 3
                    output[outputOffset] = source[inputOffset + 2]
                    output[outputOffset + 1] = source[inputOffset + 1]
                    output[outputOffset + 2] = source[inputOffset]
                }
            }
        }
        return CapturedImageFrame(
            width: width, height: height, rgbPixels: pixels,
            frameID: frameID, timestamp: timestamp)
    }
}
