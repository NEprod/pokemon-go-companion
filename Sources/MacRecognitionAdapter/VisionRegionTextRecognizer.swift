import CoreGraphics
import Foundation
import GOCompanionCapture
import GOCompanionExtraction
import ImageIO
import Vision

public enum RGBImageRenderer {
    public static func image(_ frame: CapturedObservationFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: frame.rgbPixels as CFData) else { return nil }
        return CGImage(
            width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: frame.width * 3, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The only Phase 3C type that imports Vision; OCR runs off the main actor.
public struct VisionRegionTextRecognizer: RegionTextRecognizer {
    public let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["en-US"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    public func recognize(
        frame: CapturedObservationFrame, regions: [ExtractionRegion: NormalizedROI]
    ) async throws -> [ExtractionRegion: [TextCandidate]] {
        try await Task.detached(priority: .utility) {
            guard let image = RGBImageRenderer.image(frame) else { return [:] }
            let viewport = GameContentViewport(frame: frame)
            var output: [ExtractionRegion: [TextCandidate]] = [:]
            for (region, roi) in regions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                guard let rectangle = viewport.pixelRect(for: roi),
                    let crop = image.cropping(
                        to: CGRect(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height))
                else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = recognitionLanguages
                request.minimumTextHeight = 0.07
                let handler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
                try handler.perform([request])
                output[region] = (request.results ?? []).flatMap { observation in
                    observation.topCandidates(2).map {
                        TextCandidate(text: $0.string, confidence: Double($0.confidence))
                    }
                }
            }
            return output
        }.value
    }
}
