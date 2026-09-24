import AppKit
import CoreVideo
import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis
import Testing

@testable import MacCaptureAdapter

@Test func bgraConverterPreservesOrientationChannelsAndPaddedRows() throws {
    let width = 37, height = 81
    let buffer = try makePixelBuffer(width: width, height: height)
    do {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        #expect(stride > width * 4)
        let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self))
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                bytes[offset] = UInt8((x * 7 + y) % 256)  // B
                bytes[offset + 1] = UInt8((y * 3) % 256)  // G
                bytes[offset + 2] = UInt8((x * 5) % 256)  // R
                bytes[offset + 3] = 255
            }
        }
    }
    let frame = try #require(BGRAFrameConverter.analysisFrame(from: buffer, frameID: 11, timestamp: .distantPast))
    let observation = try #require(
        BGRAFrameConverter.observationFrame(
            from: buffer, frameID: 11, timestamp: .distantPast, sourceWindowID: 77,
            sourceWindowWidthPoints: 22.5, sourceWindowHeightPoints: 48.5))
    #expect(observation.width == width && observation.height == height)
    #expect(observation.sourceWindowID == 77 && observation.frameID == 11)
    #expect(observation.sourceWindowWidthPoints == 22.5)
    #expect(observation.sourceWindowHeightPoints == 48.5)
    #expect(observation.rgbPixels == frame.rgbPixels)
    #expect(frame.width == width && frame.height == height)
    let rgb = [UInt8](frame.rgbPixels)
    for (x, y) in [(0, 0), (13, 29), (36, 80)] {
        let offset = (y * width + x) * 3
        #expect(rgb[offset] == UInt8((x * 5) % 256))
        #expect(rgb[offset + 1] == UInt8((y * 3) % 256))
        #expect(rgb[offset + 2] == UInt8((x * 7 + y) % 256))
    }
}

@Test(.enabled(if: localScreenReferenceRoot() != nil))
func fixtureDecoderAndBGRAAdapterProduceIdenticalRGBForSamePixels() throws {
    guard let root = localScreenReferenceRoot() else { return }
    let url = root.appendingPathComponent("PokemonStorage/pokemon-storage-scrolled.jpeg")
    let reference = try #require(referenceFrame(at: url))
    let image = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    let buffer = try makePixelBuffer(width: image.pixelsWide, height: image.pixelsHigh)
    do {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self))
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let offset = y * stride + x * 4
                bytes[offset] = UInt8((color.blueComponent * 255).rounded())
                bytes[offset + 1] = UInt8((color.greenComponent * 255).rounded())
                bytes[offset + 2] = UInt8((color.redComponent * 255).rounded())
                bytes[offset + 3] = 255
            }
        }
    }
    let converted = try #require(BGRAFrameConverter.analysisFrame(from: buffer, frameID: 12, timestamp: .distantPast))
    #expect(converted.width == reference.width && converted.height == reference.height)
    #expect(converted.rgbPixels == reference.rgbPixels)
    #expect(ScreenClassifier().classify(converted).screenType == ScreenClassifier().classify(reference).screenType)
}

private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferBytesPerRowAlignmentKey: 64]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
    #expect(status == kCVReturnSuccess)
    return try #require(buffer)
}
