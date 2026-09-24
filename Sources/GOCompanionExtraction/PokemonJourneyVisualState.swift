import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis

/// Visual context for the Detail-to-Appraisal journey, not a top-level screen type.
public struct PokemonJourneyVisualState: Sendable {
    public let actionMenuVisible: Bool

    public init(classifierFrame: CapturedImageFrame) {
        let bytes = [UInt8](classifierFrame.rgbPixels)
        let columns = [0.22, 0.31, 0.40, 0.50, 0.60, 0.69, 0.78]
        let rows = [0.23, 0.36, 0.49, 0.62, 0.75, 0.86]
        var matchingRows = 0
        var matchingPixels = 0
        for row in rows {
            var rowMatches = 0
            for column in columns {
                let x = min(classifierFrame.width - 1, Int(column * Double(classifierFrame.width)))
                let y = min(classifierFrame.height - 1, Int(row * Double(classifierFrame.height)))
                let offset = (y * classifierFrame.width + x) * 3
                let red = Int(bytes[offset]), green = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
                if green >= 75 && blue >= 70 && green - red >= 25 && blue - red >= 15 {
                    rowMatches += 1
                    matchingPixels += 1
                }
            }
            if rowMatches >= 5 { matchingRows += 1 }
        }
        var menuEntryBands = 0
        for center in [0.31, 0.39, 0.47, 0.55, 0.63, 0.70, 0.77, 0.85] {
            let centerY = Int(center * Double(classifierFrame.height))
            var brightPixels = 0
            for y in max(0, centerY - 2)...min(classifierFrame.height - 1, centerY + 2) {
                for x in Int(0.50 * Double(classifierFrame.width))..<Int(0.86 * Double(classifierFrame.width)) {
                    let offset = (y * classifierFrame.width + x) * 3
                    if bytes[offset] >= 160 && bytes[offset + 1] >= 175 && bytes[offset + 2] >= 155 {
                        brightPixels += 1
                    }
                }
            }
            if brightPixels >= 2 { menuEntryBands += 1 }
        }
        // The management menu is a nearly full-height teal sheet; a few teal controls or
        // a changing map are insufficient. Repeated right-hand entry bands distinguish
        // it from an otherwise featureless teal frame without reading menu text.
        actionMenuVisible = matchingRows >= 5 && matchingPixels >= 33 && menuEntryBands >= 5
    }

    /// Keep the classifier's raw result visible, but do not treat a recognized management
    /// overlay as positive evidence for an unrelated stable screen (notably false Map).
    public func stabilizationInput(_ raw: ScreenClassification) -> ScreenClassification {
        guard actionMenuVisible else { return raw }
        return ScreenClassification(
            screenType: .unknown, confidence: 0.25,
            evidence: [
                .init(
                    signal: "pokemon-action-menu", strength: 1,
                    explanation: "Pokémon management overlay pauses screen-family stabilization.")
            ], frameID: raw.frameID, timestamp: raw.timestamp)
    }
}

public struct AppraisalIVReadiness: Sendable {
    public let isReady: Bool
    public let reason: String
    public let cardLightFraction: Double
    public let trackCells: [ExtractionRegion: Int]

    public init(frame: CapturedObservationFrame, barRegions: [(ExtractionRegion, PixelRect)]) {
        let required: Set<ExtractionRegion> = [.appraisalAttack, .appraisalDefense, .appraisalHP]
        guard Set(barRegions.map(\.0)) == required, barRegions.count == 3 else {
            isReady = false
            reason = "Three Appraisal bar regions are not available."
            cardLightFraction = 0
            trackCells = [:]
            return
        }
        let viewport = GameContentViewport(frame: frame)
        guard
            let card = NormalizedROI(x: 0.07, y: 0.70, width: 0.45, height: 0.17),
            let cardRect = viewport.pixelRect(for: card)
        else {
            isReady = false
            reason = "Appraisal card region is outside the game viewport."
            cardLightFraction = 0
            trackCells = [:]
            return
        }
        let pixels = [UInt8](frame.rgbPixels)
        var lightNeutral = 0
        var samples = 0
        for y in stride(from: cardRect.minY + 5, to: cardRect.maxY - 5, by: 8) {
            for x in stride(from: cardRect.minX + 5, to: cardRect.maxX - 5, by: 8) {
                let offset = (y * frame.width + x) * 3
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                if min(red, green, blue) >= 218 && max(red, green, blue) - min(red, green, blue) <= 28 {
                    lightNeutral += 1
                }
                samples += 1
            }
        }
        let cardFraction = samples == 0 ? 0 : Double(lightNeutral) / Double(samples)
        cardLightFraction = cardFraction
        var observedTracks: [ExtractionRegion: Int] = [:]
        for (region, rect) in barRegions {
            guard rect.width >= 60 else {
                observedTracks[region] = 0
                continue
            }
            var trackSamples = 0
            for cell in 0..<15 {
                let x = min(frame.width - 1, rect.minX + Int((Double(cell) + 0.5) * Double(rect.width) / 15))
                let y = min(frame.height - 1, rect.midY)
                let offset = (y * frame.width + x) * 3
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                let filled = red > 130 && red - green > 10 && red - blue > 25
                let empty = max(red, green, blue) - min(red, green, blue) < 18 && (145...244).contains(red)
                if filled || empty { trackSamples += 1 }
            }
            observedTracks[region] = trackSamples
        }
        trackCells = observedTracks
        let threeTracksVisible = required.allSatisfy { observedTracks[$0, default: 0] >= 12 }
        // Both the light IV card and all three bar tracks must be visible. Track presence
        // does not require full bars, a particular badge, or a specific Pokémon.
        isReady = cardFraction >= 0.38 && threeTracksVisible
        let cardSummary = "light card \(Int((cardFraction * 100).rounded()))%\(cardFraction >= 0.38 ? "" : " <38%")"
        let tracks = [ExtractionRegion.appraisalAttack, .appraisalDefense, .appraisalHP].map { region in
            let label = region == .appraisalAttack ? "A" : region == .appraisalDefense ? "D" : "H"
            let count = observedTracks[region, default: 0]
            return "\(label) \(count)/15\(count >= 12 ? "" : " <12")"
        }.joined(separator: ", ")
        reason = "\(isReady ? "READY" : "NOT READY") · \(cardSummary); tracks \(tracks)"
    }
}

/// Extraction routing is separate from both top-level classification and scan identity.
public enum PokemonExtractionMode: Equatable, Sendable {
    case waitingForSession
    case pausedActionMenu
    case detail
    case appraisalIntro
    case appraisalIVs

    public static func resolve(
        stableScreen: ScreenType?, hasSession: Bool, actionMenuVisible: Bool, appraisalIVReady: Bool
    ) -> Self {
        if actionMenuVisible { return .pausedActionMenu }
        guard hasSession else { return .waitingForSession }
        switch stableScreen {
        case .pokemonDetail: return .detail
        case .appraisal: return appraisalIVReady ? .appraisalIVs : .appraisalIntro
        default: return .waitingForSession
        }
    }
}
