import Foundation
import GOCompanionCapture

public enum ScreenType: String, CaseIterable, Sendable {
    case map, mainMenu, nearby, pokemonStorage, pokemonDetail, appraisal, items, profile, unknown
}

public struct ClassificationEvidence: Equatable, Sendable {
    public let signal: String
    public let strength: Double
    public let explanation: String

    public init(signal: String, strength: Double, explanation: String) {
        self.signal = signal
        self.strength = min(1, max(0, strength))
        self.explanation = explanation
    }
}

public struct ScreenClassification: Equatable, Sendable {
    public let screenType: ScreenType
    public let confidence: Double
    public let evidence: [ClassificationEvidence]
    public let frameID: UInt64
    public let timestamp: Date
    public let candidateAssessments: [ScreenCandidateAssessment]

    public init(
        screenType: ScreenType, confidence: Double, evidence: [ClassificationEvidence],
        frameID: UInt64, timestamp: Date, candidateAssessments: [ScreenCandidateAssessment] = []
    ) {
        self.screenType = screenType
        self.confidence = min(1, max(0, confidence))
        self.evidence = evidence
        self.frameID = frameID
        self.timestamp = timestamp
        self.candidateAssessments = candidateAssessments
    }
}

/// Diagnostic support ratio and failed gates; this is not a probability of screen identity.
public struct ScreenCandidateAssessment: Equatable, Sendable {
    public let screenType: ScreenType
    public let supportScore: Double
    public let matchedSignals: Int
    public let totalSignals: Int
    public let supportingSignals: [String]
    public let missingSignals: [String]
}

/// Local screen-family recognition from broad layout regions, without templates or text recognition.
public struct ScreenClassifier: Sendable {
    public init() {}

    public func classify(_ frame: CapturedImageFrame) -> ScreenClassification {
        guard let image = NormalizedImage(frame: frame) else {
            return result(
                .unknown, 0,
                [
                    .init(signal: "frame", strength: 0, explanation: "Frame dimensions or pixel data are unsupported.")
                ], frame)
        }
        // Specific overlays precede their underlying screen. Every match requires independent regions.
        let candidates = FrameFeatures(image: image).candidates
        let unsortedAssessments: [ScreenCandidateAssessment] = candidates.map { $0.assessment }
        let assessments = unsortedAssessments.sorted { lhs, rhs in
            if lhs.supportScore != rhs.supportScore { return lhs.supportScore > rhs.supportScore }
            return lhs.screenType.rawValue < rhs.screenType.rawValue
        }
        guard let winner = candidates.first(where: \.matches) else {
            let closest = assessments.first
            let missing =
                closest?.missingSignals.prefix(2).map {
                    ClassificationEvidence(signal: "missing-signal", strength: 0, explanation: "Missing \($0).")
                } ?? []
            let hint = closest.map {
                ClassificationEvidence(
                    signal: "strongest-partial-candidate", strength: $0.supportScore,
                    explanation:
                        "Strongest partial match: \($0.screenType.rawValue), \($0.matchedSignals)/\($0.totalSignals) signals; required evidence is incomplete."
                )
            }
            return result(
                .unknown, 0.25,
                [
                    .init(
                        signal: "insufficient-structure", strength: 0.25,
                        explanation: "No supported screen has enough independent layout evidence.")
                ] + (hint.map { [$0] } ?? []) + missing, frame, assessments)
        }
        let orderedAssessments =
            assessments.filter { $0.screenType == winner.type }
            + assessments.filter { $0.screenType != winner.type }
        return result(winner.type, winner.confidence, winner.evidence, frame, orderedAssessments)
    }

    private func result(
        _ type: ScreenType, _ confidence: Double, _ evidence: [ClassificationEvidence], _ frame: CapturedImageFrame,
        _ assessments: [ScreenCandidateAssessment] = []
    ) -> ScreenClassification {
        ScreenClassification(
            screenType: type, confidence: confidence, evidence: evidence,
            frameID: frame.frameID, timestamp: frame.timestamp, candidateAssessments: assessments)
    }
}

/// Why a stable supported screen differs from the current raw frame.
public enum ScreenContinuityState: Equatable, Sendable {
    case none
    case retaining(screen: ScreenType, ambiguousFrames: Int, allowance: Int)
    case expired
}

/// A majority of three positive frames establishes/changes a screen. An established screen
/// tolerates a short, bounded run of unconfirmed frames without changing the raw result.
public struct ScreenClassificationStabilizer: Sendable {
    private let capacity: Int
    private let unknownGraceFrames: Int
    private var recent: [ScreenType] = []
    private var stableType: ScreenType?
    private var unconfirmedFrames = 0
    public private(set) var continuity: ScreenContinuityState = .none

    public init(capacity: Int = 3, unknownGraceFrames: Int = 3) {
        self.capacity = max(1, capacity)
        self.unknownGraceFrames = max(0, unknownGraceFrames)
    }

    public mutating func append(_ classification: ScreenClassification) -> ScreenType? {
        // Current known classifier tiers start at 0.80. A weaker/unknown raw result is
        // ambiguous temporal evidence, never a positive vote for a supported screen.
        let positiveType: ScreenType =
            classification.screenType != .unknown && classification.confidence >= 0.80
            ? classification.screenType : .unknown
        recent.append(positiveType)
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
        let majority = Dictionary(grouping: recent, by: { $0 })
            .first { $0.key != .unknown && $0.value.count > capacity / 2 }?.key

        if let majority, positiveType == majority {
            stableType = majority
            unconfirmedFrames = 0
            continuity = .none
            return stableType
        }

        if let stableType, stableType != .unknown {
            if positiveType == stableType {
                // A fresh confident observation of the established screen renews continuity.
                unconfirmedFrames = 0
                continuity = .none
                return stableType
            }
            unconfirmedFrames += 1
            if unconfirmedFrames <= unknownGraceFrames {
                continuity =
                    positiveType == .unknown
                    ? .retaining(screen: stableType, ambiguousFrames: unconfirmedFrames, allowance: unknownGraceFrames)
                    : .none
                return stableType
            }
            self.stableType = .unknown
            continuity = positiveType == .unknown ? .expired : .none
            return .unknown
        }

        if recent.filter({ $0 == .unknown }).count > capacity / 2 {
            stableType = .unknown
        }
        if positiveType != .unknown { continuity = .none }
        return stableType
    }
}

private struct FrameFeatures {
    let nav: RegionStats
    let hero: RegionStats
    let center: RegionStats
    let lower: RegionStats
    let leftRail: RegionStats
    let bottomRight: RegionStats
    let topLeft: RegionStats
    let itemArtRail: RegionStats
    let itemText: RegionStats
    let gridRows: Int

    init(image: NormalizedImage) {
        nav = image.stats(x: 0.05, y: 0.05, width: 0.90, height: 0.10)
        hero = image.stats(x: 0.10, y: 0.20, width: 0.80, height: 0.20)
        center = image.stats(x: 0.10, y: 0.40, width: 0.80, height: 0.20)
        lower = image.stats(x: 0.10, y: 0.60, width: 0.80, height: 0.25)
        leftRail = image.stats(x: 0, y: 0.20, width: 0.055, height: 0.70)
        bottomRight = image.stats(x: 0.78, y: 0.88, width: 0.20, height: 0.10)
        topLeft = image.stats(x: 0.08, y: 0.065, width: 0.24, height: 0.085)
        itemArtRail = image.stats(x: 0.07, y: 0.25, width: 0.20, height: 0.60)
        itemText = image.stats(x: 0.29, y: 0.25, width: 0.49, height: 0.60)
        gridRows = image.threeColumnGridRows()
    }

    var candidates: [Candidate] {
        [
            Candidate(
                .appraisal,
                [
                    .atLeast("warm-overlay", lower.warm, 0.30, "Warm appraisal overlay covers the lower detail card."),
                    .atMost("covered-card", lower.white, 0.50, "The lower white detail card is covered by an overlay."),
                    .atLeast(
                        "detail-background", hero.saturated, 0.35, "A Pokémon detail hero remains behind the overlay."),
                    .atLeast(
                        "detail-card", center.white, 0.30,
                        "Part of the white detail card remains visible behind the overlay."),
                    .atMost("menu-obscured", bottomRight.teal, 0.20, "The detail menu control is obscured."),
                ]),
            Candidate(
                .profile,
                [
                    .atLeast(
                        "profile-rail", leftRail.visibleWarm, 0.55,
                        "A warm profile rail frames the content inside the dark capture border."),
                    .atLeast(
                        "profile-tabs", nav.visiblePale, 0.55,
                        "The light profile tab/header region is present inside the dark capture border."),
                    .atMost("no-detail-menu", bottomRight.teal, 0.20, "No Pokémon detail menu control is present."),
                    .atMost("not-appraisal", lower.warm, 0.20, "No broad appraisal overlay covers the lower panel."),
                ]),
            Candidate(
                .nearby,
                [
                    .atLeast("nearby-panel", lower.pale, 0.92, "A broad pale lower panel covers the map."),
                    .atLeast(
                        "nearby-grid", center.edge, 0.15, "The upper panel contains repeated nearby tile boundaries."),
                    .atLeast(
                        "map-edge", leftRail.visibleCool, 0.45,
                        "Blue-green map colour remains visible outside the panel, excluding dark window borders."),
                    .atLeast(
                        "map-header", nav.cool, 0.35,
                        "The blue-green map remains visible above the nearby panel."),
                ]),
            Candidate(
                .pokemonStorage,
                [
                    .atLeast(
                        "three-column-grid", Double(gridRows) / 4, 0.75,
                        "Three content columns repeat through several vertical bands."),
                    .atLeast(
                        "storage-grid-background", center.white, 0.50,
                        "Repeated grid cells sit on a broad light storage background."),
                    .atLeast("storage-control", bottomRight.teal, 0.35, "The lower-right storage control is present."),
                ]),
            Candidate(
                .items,
                [
                    .atLeast(
                        "items-header", nav.visiblePale, 0.80,
                        "The fixed light Items header is present inside the dark capture border."),
                    .atLeast("items-list", center.pale, 0.90, "A light scrolling item-list panel fills the center."),
                    .atLeast(
                        "item-icon-column", itemText.white - itemArtRail.white, 0.07,
                        "Repeated item artwork makes the left list column denser than the text column."),
                    .atLeast(
                        "items-header-left", topLeft.pale, 0.80, "The left header region remains clear above the list."
                    ),
                    .atMost("no-detail-menu", bottomRight.teal, 0.20, "No Pokémon detail menu control is present."),
                    .atMost("not-profile-rail", leftRail.warm, 0.25, "The left rail is not the warm Profile rail."),
                ]),
            Candidate(
                .pokemonDetail,
                [
                    .atLeast(
                        "detail-document-envelope", max(center.pale, min(hero.pale, lower.pale)), 0.65,
                        "A light Detail document is visible in the center or around a special embedded panel."),
                    .atLeast(
                        "detail-card-boundary", center.pale - leftRail.pale, 0.25,
                        "The central Detail document contrasts with its outer side rail."),
                    .atMost(
                        "not-storage-grid", Double(gridRows) / 4, 0.50,
                        "The content does not repeat as a three-column grid through the viewport."),
                    .atLeast(
                        "detail-menu", bottomRight.teal, 0.35, "The Pokémon detail menu control remains at lower right."
                    ),
                    .atLeast(
                        "detail-lower-card", lower.pale, 0.75,
                        "The light detail card continues through the lower region."),
                ]),
            Candidate(
                .mainMenu,
                [
                    .atLeast(
                        "menu-background", hero.pale, 0.88, "A broad pale menu background occupies the upper half."),
                    .atLeast("menu-center", center.pale, 0.88, "The pale menu panel continues through the center."),
                    .atMost("open-upper-panel", hero.edge, 0.04, "The upper panel has little list or grid structure."),
                    .atLeast("menu-controls", lower.edge, 0.035, "Separated menu controls appear in the lower panel."),
                    .atLeast(
                        "menu-lower-colour", bottomRight.saturated, 0.60,
                        "A colourful lower menu-control region distinguishes the menu from lists."),
                ]),
            Candidate(
                .map,
                [
                    .atLeast(
                        "world-upper", hero.cool, 0.50,
                        "Blue-green world colours fill the upper play region in day or night rendering."),
                    .atLeast(
                        "world-center", center.cool, 0.50,
                        "Blue-green world colours continue through the center."),
                    .atLeast(
                        "world-lower", lower.cool, 0.50,
                        "The world continues behind lower map controls."),
                    .atMost("no-content-card", center.white, 0.20, "No broad white content card covers the world."),
                    .atLeast(
                        "map-controls", lower.edge, 0.025, "Sparse map controls interrupt the lower world region."),
                ]),
        ]
    }
}

private struct Candidate {
    let type: ScreenType
    let signals: [Signal]
    init(_ type: ScreenType, _ signals: [Signal]) { self.type = type; self.signals = signals }
    var matches: Bool { signals.allSatisfy(\.matches) }
    var assessment: ScreenCandidateAssessment {
        // The first signal is the screen's defining layout anchor, so a missing anchor
        // is more consequential than one missing secondary cue.
        let totalWeight = Double(signals.count + 2)
        let matchedWeight = signals.enumerated().reduce(0.0) { total, element in
            total + (element.element.matches ? (element.offset == 0 ? 3 : 1) : 0)
        }
        return ScreenCandidateAssessment(
            screenType: type, supportScore: matchedWeight / totalWeight,
            matchedSignals: signals.filter(\.matches).count, totalSignals: signals.count,
            supportingSignals: signals.filter(\.matches).map(\.summary),
            missingSignals: signals.filter { !$0.matches }.map(\.missingSummary))
    }
    // Coarse evidence tiers, not calibrated probabilities.
    var confidence: Double { signals.count >= 5 ? 0.90 : 0.80 }
    var evidence: [ClassificationEvidence] { signals.map(\.evidence) }
}

private struct Signal {
    let name: String
    let value: Double
    let threshold: Double
    let minimum: Bool
    let explanation: String

    static func atLeast(_ name: String, _ value: Double, _ threshold: Double, _ explanation: String) -> Self {
        Self(name: name, value: value, threshold: threshold, minimum: true, explanation: explanation)
    }
    static func atMost(_ name: String, _ value: Double, _ threshold: Double, _ explanation: String) -> Self {
        Self(name: name, value: value, threshold: threshold, minimum: false, explanation: explanation)
    }
    var matches: Bool { minimum ? value >= threshold : value <= threshold }
    var evidence: ClassificationEvidence {
        .init(signal: name, strength: minimum ? value : 1 - value, explanation: explanation)
    }
    var missingSummary: String {
        summary
    }
    var summary: String {
        String(format: "%@ (observed %.2f; %@ %.2f)", name, value, minimum ? "needs ≥" : "needs ≤", threshold)
    }
}

private struct RegionStats {
    var white = 0.0
    var pale = 0.0
    var warm = 0.0
    var teal = 0.0
    var cool = 0.0
    var saturated = 0.0
    var edge = 0.0
    var dark = 0.0

    // Window-capture gutters and the status-area cutout should not count as missing content.
    private var visibleFraction: Double { max(0.01, 1 - dark) }
    var visiblePale: Double { min(1, pale / visibleFraction) }
    var visibleWarm: Double { min(1, warm / visibleFraction) }
    var visibleCool: Double { min(1, cool / visibleFraction) }
}

private struct NormalizedImage {
    let width: Int
    let height: Int
    let rgb: [UInt8]

    init?(frame: CapturedImageFrame) {
        guard frame.width >= 24, frame.height >= 32, frame.height > frame.width,
            frame.width <= 512, frame.height <= 512,
            frame.rgbPixels.count == frame.width * frame.height * 3
        else { return nil }
        let scale = min(1, 128.0 / Double(max(frame.width, frame.height)))
        width = max(1, Int((Double(frame.width) * scale).rounded()))
        height = max(1, Int((Double(frame.height) * scale).rounded()))
        let input = [UInt8](frame.rgbPixels)
        var output = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            let sourceY = min(frame.height - 1, y * frame.height / height)
            for x in 0..<width {
                let sourceX = min(frame.width - 1, x * frame.width / width)
                let source = (sourceY * frame.width + sourceX) * 3
                let target = (y * width + x) * 3
                output[target] = input[source]
                output[target + 1] = input[source + 1]
                output[target + 2] = input[source + 2]
            }
        }
        rgb = output
    }

    func stats(x: Double, y: Double, width regionWidth: Double, height regionHeight: Double) -> RegionStats {
        let startX = max(0, Int(x * Double(width)))
        let endX = min(width, Int((x + regionWidth) * Double(width)))
        let startY = max(0, Int(y * Double(height)))
        let endY = min(height, Int((y + regionHeight) * Double(height)))
        var stats = RegionStats()
        var sampleCount = 0.0
        for row in startY..<endY {
            for column in startX..<endX {
                let offset = (row * width + column) * 3
                let red = Int(rgb[offset]), green = Int(rgb[offset + 1]), blue = Int(rgb[offset + 2])
                sampleCount += 1
                if min(red, green, blue) > 225 { stats.white += 1 }
                if min(red, green, blue) > 180 { stats.pale += 1 }
                if red - green > 25, red - blue > 10, red > 130 { stats.warm += 1 }
                if green - red > 20, blue - red > 20, green > 70 { stats.teal += 1 }
                if blue - red > 15, blue >= 95 { stats.cool += 1 }
                if max(red, green, blue) - min(red, green, blue) > 55 { stats.saturated += 1 }
                if max(red, green, blue) < 95 { stats.dark += 1 }
                if column + 1 < self.width {
                    let right = offset + 3
                    let difference =
                        abs(red - Int(rgb[right])) + abs(green - Int(rgb[right + 1]))
                        + abs(blue - Int(rgb[right + 2]))
                    if difference > 120 { stats.edge += 1 }
                }
            }
        }
        guard sampleCount > 0 else { return stats }
        stats.white /= sampleCount; stats.pale /= sampleCount; stats.warm /= sampleCount
        stats.teal /= sampleCount; stats.cool /= sampleCount; stats.saturated /= sampleCount
        stats.edge /= sampleCount; stats.dark /= sampleCount
        return stats
    }

    func threeColumnGridRows() -> Int {
        let columns: [(Double, Double)] = [(0.06, 0.27), (0.365, 0.27), (0.67, 0.27)]
        let rowStarts: [Double] = [0.23, 0.38, 0.53, 0.68]
        return rowStarts.filter { row in
            let cells = columns.map { stats(x: $0.0, y: row, width: $0.1, height: 0.14) }
            let edgeSpread = cells.map(\.edge).max()! - cells.map(\.edge).min()!
            let paleSpread = cells.map(\.pale).max()! - cells.map(\.pale).min()!
            // Repeated Storage cells have similar structure and background in each column.
            // A wide Detail illustration or three-column action/text row does not.
            return cells.allSatisfy { $0.edge >= 0.055 } && edgeSpread <= 0.11 && paleSpread <= 0.20
        }.count
    }
}
