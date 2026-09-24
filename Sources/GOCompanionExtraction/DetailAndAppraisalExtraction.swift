import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis

public enum PokemonTextParser {
    public static func displayedName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 40,
            value.rangeOfCharacter(from: .letters) != nil,
            !value.localizedCaseInsensitiveContains(" CP ")
        else { return nil }
        return value  // A nickname is not a canonical species ID.
    }

    public static func cp(_ raw: String) -> Int? {
        let compact = raw.uppercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard compact.hasPrefix("CP") else { return nil }
        let digits = String(compact.dropFirst(2))
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits), (1...99_999).contains(value)
        else { return nil }
        return value
    }

    public static func hp(_ raw: String) -> (current: Int, maximum: Int)? {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        guard compact.hasSuffix("HP") else { return nil }
        let body = compact.dropLast(2)
        let components = body.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            let current = Int(components[0]), let maximum = Int(components[1]),
            (0...9_999).contains(current), (1...9_999).contains(maximum), current <= maximum
        else { return nil }
        return (current, maximum)
    }
}

public struct PokemonDetailExtractor: Sendable {
    public init() {}

    public func observations(
        from recognized: [ExtractionRegion: [TextCandidate]], frame: CapturedObservationFrame,
        sourceScreen: ScreenType = .pokemonDetail
    ) -> [FieldObservation] {
        guard sourceScreen == .pokemonDetail || sourceScreen == .appraisal else { return [] }
        var output: [FieldObservation] = []
        func add(
            _ field: ExtractionField, _ value: ExtractionValue, _ region: ExtractionRegion, _ candidate: TextCandidate
        ) {
            guard candidate.confidence >= 0.65,
                let observation = FieldObservation(
                    field: field, value: value, confidence: candidate.confidence, method: .visionText,
                    sourceScreen: sourceScreen, region: region, frameID: frame.frameID,
                    observedAt: frame.timestamp,
                    evidence:
                        "Raw Vision candidate: \(candidate.text); valid \(field.rawValue) parse in \(region.rawValue)",
                    sourceWindowID: frame.sourceWindowID)
            else { return }
            output.append(observation)
        }
        for candidate in recognized[.displayedName] ?? [] {
            if let name = PokemonTextParser.displayedName(candidate.text) {
                add(.displayedName, .text(name), .displayedName, candidate)
                break
            }
        }
        for candidate in recognized[.cp] ?? [] {
            if let cp = PokemonTextParser.cp(candidate.text) {
                add(.cp, .integer(cp), .cp, candidate)
                break
            }
        }
        for candidate in recognized[.hp] ?? [] {
            if let hp = PokemonTextParser.hp(candidate.text) {
                add(.hpCurrent, .integer(hp.current), .hp, candidate)
                add(.hpMaximum, .integer(hp.maximum), .hp, candidate)
                break
            }
        }
        return output
    }
}

/// Conservative visual detector. Emits only bars with a monotone, unambiguous 15-cell fill.
public struct AppraisalBarExtractor: Sendable {
    public init() {}

    private let bars: [(ExtractionRegion, ExtractionField)] = [
        (.appraisalAttack, .ivAttack), (.appraisalDefense, .ivDefense), (.appraisalHP, .ivHP),
    ]

    /// Locate the three repeated tracks as one group. Their vertical position shifts with
    /// the amount of Detail content behind Appraisal; fill length is not a layout signal.
    /// The same resolved rectangles are shown in the diagnostic and sampled for IVs.
    public func resolvedRegions(frame: CapturedObservationFrame) -> [(ExtractionRegion, PixelRect)] {
        let viewport = GameContentViewport(frame: frame)
        let bases = [PokemonExtractionLayout.regions, PokemonExtractionLayout.currentAppraisalRegions]
            .map { layout in
                bars.compactMap { region, _ in
                    layout[region].flatMap { viewport.pixelRect(for: $0) }.map { (region, $0) }
                }
            }.filter { $0.count == 3 }
        guard let fallback = bases.first else { return [] }
        let pixels = [UInt8](frame.rgbPixels)
        let lowerShift = -Int((Double(viewport.rect.height) * 0.04).rounded())
        let upperShift = Int((Double(viewport.rect.height) * 0.065).rounded())
        var best: (depth: Int, totalDepth: Int, displacement: Int, regions: [(ExtractionRegion, PixelRect)])?
        for base in bases {
            for shift in lowerShift...upperShift {
                let shifted = base.map { region, rect in
                    (
                        region,
                        PixelRect(x: rect.x, y: rect.y + shift, width: rect.width, height: rect.height)
                    )
                }
                guard shifted.allSatisfy({ $0.1.minY >= viewport.rect.minY && $0.1.maxY <= viewport.rect.maxY })
                else { continue }
                let tracks = shifted.map { trackSupport(frame: frame, rect: $0.1, pixels: pixels) }
                guard tracks.allSatisfy({ $0 >= 12 }) else { continue }
                let sideSupport = shifted.reduce(0) { $0 + lightCardSides(frame: frame, rect: $1.1, pixels: pixels) }
                guard sideSupport >= 3 else { continue }
                let depths = shifted.map { balancedTrackDepth(frame: frame, rect: $0.1, pixels: pixels) }
                let depth = depths.min() ?? 0
                let totalDepth = depths.reduce(0, +)
                let better: Bool
                if let best {
                    better =
                        depth > best.depth
                        || (depth == best.depth && totalDepth > best.totalDepth)
                        || (depth == best.depth && totalDepth == best.totalDepth
                            && abs(shift) < best.displacement)
                } else {
                    better = true
                }
                if better {
                    best = (depth, totalDepth, abs(shift), shifted)
                }
            }
        }
        return best?.regions ?? fallback
    }

    private func trackSupport(frame: CapturedObservationFrame, rect: PixelRect, pixels: [UInt8]) -> Int {
        trackSupport(frame: frame, rect: rect, y: rect.midY, pixels: pixels)
    }

    private func trackSupport(frame: CapturedObservationFrame, rect: PixelRect, y: Int, pixels: [UInt8]) -> Int {
        (0..<15).reduce(0) { count, cell in
            let x = min(frame.width - 1, rect.minX + Int((Double(cell) + 0.5) * Double(rect.width) / 15))
            let offset = (y * frame.width + x) * 3
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            let filled = red > 130 && red - green > 10 && red - blue > 25
            let empty = max(red, green, blue) - min(red, green, blue) < 18 && (145...244).contains(red)
            return count + ((filled || empty) ? 1 : 0)
        }
    }

    private func balancedTrackDepth(frame: CapturedObservationFrame, rect: PixelRect, pixels: [UInt8]) -> Int {
        var above = 0, below = 0
        for distance in 1...max(2, rect.height) {
            guard rect.midY - distance >= 0,
                trackSupport(frame: frame, rect: rect, y: rect.midY - distance, pixels: pixels) >= 12
            else { break }
            above += 1
        }
        for distance in 1...max(2, rect.height) {
            guard rect.midY + distance < frame.height,
                trackSupport(frame: frame, rect: rect, y: rect.midY + distance, pixels: pixels) >= 12
            else { break }
            below += 1
        }
        return min(above, below)
    }

    private func lightCardSides(frame: CapturedObservationFrame, rect: PixelRect, pixels: [UInt8]) -> Int {
        [rect.minX - 12, rect.maxX + 12].reduce(0) { count, x in
            guard (0..<frame.width).contains(x) else { return count }
            let offset = (rect.midY * frame.width + x) * 3
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            let light = min(red, green, blue) >= 218 && max(red, green, blue) - min(red, green, blue) <= 28
            return count + (light ? 1 : 0)
        }
    }

    public func observations(frame: CapturedObservationFrame) -> [FieldObservation] {
        let rectangles = Dictionary(uniqueKeysWithValues: resolvedRegions(frame: frame))
        return bars.compactMap { region, field in
            guard let rect = rectangles[region], let value = value(frame: frame, rect: rect)
            else { return nil }
            return FieldObservation(
                field: field, value: .integer(value), confidence: 0.75,
                method: .appraisalBarGeometry, sourceScreen: .appraisal, region: region,
                frameID: frame.frameID, observedAt: frame.timestamp,
                evidence: "Monotone warm fill across 15 appraisal cells; verify uncertain visual variants",
                sourceWindowID: frame.sourceWindowID)
        }
    }

    public func value(frame: CapturedObservationFrame, roi: NormalizedROI) -> Int? {
        guard let rect = GameContentViewport(frame: frame).pixelRect(for: roi) else { return nil }
        return value(frame: frame, rect: rect)
    }

    private func value(frame: CapturedObservationFrame, rect: PixelRect) -> Int? {
        guard rect.width >= 60,
            rect.height >= 4
        else { return nil }
        let pixels = [UInt8](frame.rgbPixels)
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let width = Int(rect.width), height = Int(rect.height)
        var states: [Bool] = []
        for cell in 0..<15 {
            let x = min(frame.width - 1, x0 + Int((Double(cell) + 0.5) * Double(width) / 15))
            let y = min(frame.height - 1, y0 + height / 2)
            let offset = (y * frame.width + x) * 3
            guard offset + 2 < pixels.count else { return nil }
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            let warm = red > 130 && red - green > 10 && red - blue > 25
            let empty = max(red, green, blue) - min(red, green, blue) < 18 && (145...244).contains(red)
            guard warm || empty else { return nil }
            states.append(warm)
        }
        let filled = states.prefix(while: { $0 }).count
        guard states.dropFirst(filled).allSatisfy({ !$0 }) else { return nil }
        return filled
    }
}
