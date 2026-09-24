import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis

public struct PixelRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var midY: Int { y + height / 2 }
}

/// Top-left coordinates normalized within the game-content viewport, not the Mirroring window.
public struct NormalizedROI: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard [x, y, width, height].allSatisfy(\.isFinite), x >= 0, y >= 0,
            width > 0, height > 0, x + width <= 1, y + height <= 1
        else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func pixelRect(width imageWidth: Int, height imageHeight: Int) -> PixelRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let left = Int((x * Double(imageWidth)).rounded())
        let top = Int((y * Double(imageHeight)).rounded())
        let right = Int(((x + width) * Double(imageWidth)).rounded())
        let bottom = Int(((y + height) * Double(imageHeight)).rounded())
        return PixelRect(
            x: left, y: top,
            width: max(1, min(imageWidth, right) - left),
            height: max(1, min(imageHeight, bottom) - top))
    }
}

/// One transform from selected-window capture pixels to Pokémon GO content pixels.
/// The macOS screenshots show an 8-point side/bottom inset and a 38-point toolbar above
/// the rounded phone display. Window dimensions in points travel with ScreenCaptureKit frames;
/// imported game-only images have no window dimensions and use their entire frame.
public struct GameContentViewport: Equatable, Sendable {
    public enum Basis: Equatable, Sendable { case mirroringWindowChrome, fullFrame }

    public let rect: PixelRect
    public let basis: Basis

    public init(frame: CapturedObservationFrame) {
        if let windowWidth = frame.sourceWindowWidthPoints,
            let windowHeight = frame.sourceWindowHeightPoints
        {
            let scaleX = Double(frame.width) / windowWidth
            let scaleY = Double(frame.height) / windowHeight
            let left = Int((8 * scaleX).rounded())
            let right = Int((Double(frame.width) - 8 * scaleX).rounded())
            let top = Int((38 * scaleY).rounded())
            let bottom = Int((Double(frame.height) - 8 * scaleY).rounded())
            if right > left, bottom > top {
                rect = PixelRect(x: left, y: top, width: right - left, height: bottom - top)
                basis = .mirroringWindowChrome
                return
            }
        }
        rect = PixelRect(x: 0, y: 0, width: frame.width, height: frame.height)
        basis = .fullFrame
    }

    public func pixelRect(for roi: NormalizedROI) -> PixelRect? {
        guard let local = roi.pixelRect(width: rect.width, height: rect.height) else { return nil }
        return PixelRect(x: rect.x + local.x, y: rect.y + local.y, width: local.width, height: local.height)
    }
}

public enum ExtractionRegion: String, CaseIterable, Sendable {
    case displayedName, cp, hp, appraisalAttack, appraisalDefense, appraisalHP
}

public enum PokemonExtractionLayout {
    private static func roi(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedROI {
        NormalizedROI(x: x, y: y, width: width, height: height)!
    }

    public static let regions: [ExtractionRegion: NormalizedROI] = [
        // Calibrated within the game display at the natural, unscrolled Detail position.
        .displayedName: roi(0.30, 0.405, 0.40, 0.040),
        .cp: roi(0.32, 0.060, 0.36, 0.038),
        .hp: roi(0.39, 0.460, 0.24, 0.030),
        .appraisalAttack: roi(0.120, 0.768, 0.350, 0.018),
        .appraisalDefense: roi(0.120, 0.812, 0.350, 0.018),
        .appraisalHP: roi(0.120, 0.851, 0.350, 0.018),
    ]

    /// Current Mirroring screenshot places the appraisal card slightly higher than the older
    /// local game-only references. Both are game-relative layouts; one viewport transform applies.
    public static let currentAppraisalRegions: [ExtractionRegion: NormalizedROI] = [
        .appraisalAttack: roi(0.120, 0.744, 0.350, 0.012),
        .appraisalDefense: roi(0.120, 0.785, 0.350, 0.012),
        .appraisalHP: roi(0.120, 0.829, 0.350, 0.012),
    ]

    public static func pixelRect(for region: ExtractionRegion, frame: CapturedObservationFrame) -> PixelRect? {
        guard let roi = regions[region] else { return nil }
        return GameContentViewport(frame: frame).pixelRect(for: roi)
    }

    public static func regions(for screen: ScreenType) -> [(ExtractionRegion, NormalizedROI)] {
        let names: [ExtractionRegion] =
            screen == .pokemonDetail
            ? [.displayedName, .cp, .hp]
            : screen == .appraisal ? [.appraisalAttack, .appraisalDefense, .appraisalHP] : []
        return names.compactMap { name in regions[name].map { (name, $0) } }
    }

    /// Detail identity fields may remain visible through Appraisal, including during arrow paging.
    public static var appraisalIdentityRegions: [ExtractionRegion: NormalizedROI] {
        Dictionary(
            uniqueKeysWithValues: [ExtractionRegion.displayedName, .cp, .hp].compactMap { region in
                regions[region].map { (region, $0) }
            })
    }
}

public enum ExtractionField: String, CaseIterable, Sendable {
    case displayedName, cp, hpCurrent, hpMaximum, ivAttack, ivDefense, ivHP
}

public enum ExtractionValue: Hashable, Sendable, CustomStringConvertible {
    case text(String)
    case integer(Int)

    public var description: String {
        switch self {
        case .text(let text): text
        case .integer(let value): String(value)
        }
    }
}

public enum ExtractionMethod: String, Sendable {
    case visionText, appraisalBarGeometry
}

public struct FieldObservation: Identifiable, Sendable {
    public let id: UUID
    public let field: ExtractionField
    public let value: ExtractionValue
    /// Recognition-engine/visual-signal strength, NOT probability that the parsed field is true.
    /// Parser validity is guaranteed by initialization; corroboration is reported by FieldConsensus.
    public let confidence: Double
    public let method: ExtractionMethod
    public let sourceScreen: ScreenType
    public let region: ExtractionRegion
    public let frameID: UInt64
    public let sourceWindowID: UInt32?
    public let observedAt: Date
    public let evidence: String
    public let isDirectlyObserved: Bool
    public let methodVersion: String

    public init?(
        field: ExtractionField, value: ExtractionValue, confidence: Double, method: ExtractionMethod,
        sourceScreen: ScreenType, region: ExtractionRegion, frameID: UInt64, observedAt: Date,
        evidence: String, isDirectlyObserved: Bool = true, sourceWindowID: UInt32? = nil,
        methodVersion: String = "phase3c-1"
    ) {
        guard confidence.isFinite, (0...1).contains(confidence) else { return nil }
        switch (field, value) {
        case (.displayedName, .text(let name)) where !name.isEmpty: break
        case (.cp, .integer(let cp)) where (1...99_999).contains(cp): break
        case (.hpCurrent, .integer(let hp)) where (0...9_999).contains(hp): break
        case (.hpMaximum, .integer(let hp)) where (1...9_999).contains(hp): break
        case (.ivAttack, .integer(let iv)) where (0...15).contains(iv): break
        case (.ivDefense, .integer(let iv)) where (0...15).contains(iv): break
        case (.ivHP, .integer(let iv)) where (0...15).contains(iv): break
        default: return nil
        }
        self.id = UUID()
        self.field = field
        self.value = value
        self.confidence = confidence
        self.method = method
        self.sourceScreen = sourceScreen
        self.region = region
        self.frameID = frameID
        self.sourceWindowID = sourceWindowID
        self.observedAt = observedAt
        self.evidence = evidence
        self.isDirectlyObserved = isDirectlyObserved
        self.methodVersion = methodVersion
    }
}

public struct TextCandidate: Sendable {
    public let text: String
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

/// Platform-neutral contract. The macOS implementation alone imports Vision.
public protocol RegionTextRecognizer: Sendable {
    func recognize(
        frame: CapturedObservationFrame, regions: [ExtractionRegion: NormalizedROI]
    ) async throws -> [ExtractionRegion: [TextCandidate]]
}
