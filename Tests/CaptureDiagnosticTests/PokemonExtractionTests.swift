import AppKit
import Foundation
import GOCompanionCapture
import GOCompanionExtraction
import GOCompanionScreenAnalysis
import MacRecognitionAdapter
import Testing

private func frame(id: UInt64 = 1, sourceWindowID: UInt32? = nil) -> CapturedObservationFrame {
    CapturedObservationFrame(
        width: 360, height: 782, rgbPixels: Data(repeating: 255, count: 360 * 782 * 3),
        frameID: id, timestamp: Date(timeIntervalSince1970: Double(id)), sourceWindowID: sourceWindowID)!
}

private func observed(
    _ field: ExtractionField, _ value: ExtractionValue, frameID: UInt64,
    screen: ScreenType = .pokemonDetail, confidence: Double = 0.85
) -> FieldObservation {
    let isIV = [.ivAttack, .ivDefense, .ivHP].contains(field)
    return FieldObservation(
        field: field, value: value, confidence: confidence,
        method: isIV ? .appraisalBarGeometry : .visionText,
        sourceScreen: screen, region: isIV ? .appraisalAttack : .displayedName,
        frameID: frameID, observedAt: Date(timeIntervalSince1970: Double(frameID)),
        evidence: "Synthetic direct observation")!
}

@Test func textParsingPreservesNicknameAndRejectsMalformedNumbers() {
    #expect(PokemonTextParser.displayedName("  Sparkles  ") == "Sparkles")
    #expect(PokemonTextParser.displayedName("12345") == nil)
    #expect(PokemonTextParser.cp("CP 4,036") == 4036)
    #expect(PokemonTextParser.cp("CP4036") == 4036)
    #expect(PokemonTextParser.cp("CP 4O36") == nil)
    #expect(PokemonTextParser.cp("4036") == nil)
    #expect(PokemonTextParser.hp("135 / 150 HP")?.current == 135)
    #expect(PokemonTextParser.hp("135/150 HP")?.maximum == 150)
    #expect(PokemonTextParser.hp("150/135 HP") == nil)
    #expect(PokemonTextParser.hp("135 HP") == nil)
    #expect(PokemonTextParser.hp("0 / 177 HP")?.current == 0)
    #expect(PokemonTextParser.hp("0 / 177 HP")?.maximum == 177)
}

@Test func detailExtractionRetainsFieldEvidenceAndDoesNotInferSpecies() {
    let result = PokemonDetailExtractor().observations(
        from: [
            .displayedName: [.init(text: "Sparkles", confidence: 0.91)],
            .cp: [.init(text: "CP 2353", confidence: 0.86)],
            .hp: [.init(text: "135 / 135 HP", confidence: 0.89)],
        ], frame: frame(id: 44, sourceWindowID: 789))
    #expect(result.count == 4)
    #expect(result.first?.field == .displayedName)
    #expect(result.first?.value == .text("Sparkles"))
    #expect(result.first?.confidence == 0.91)
    #expect(result.first?.sourceWindowID == 789)
    #expect(result.first?.methodVersion == "phase3c-1")
    #expect(result.allSatisfy { $0.frameID == 44 && $0.sourceScreen == .pokemonDetail && $0.isDirectlyObserved })
    #expect(result.allSatisfy { $0.method == .visionText && !$0.evidence.isEmpty })
}

@Test func roiGeometryScalesAndRejectsInvalidCoordinates() {
    #expect(NormalizedROI(x: 0.9, y: 0.2, width: 0.2, height: 0.1) == nil)
    for (width, height) in [(360, 782), (580, 1280), (430, 932)] {
        for (_, roi) in PokemonExtractionLayout.regions(for: .pokemonDetail)
            + PokemonExtractionLayout.regions(for: .appraisal)
        {
            let rect = roi.pixelRect(width: width, height: height)!
            #expect(rect.minX >= 0 && rect.minY >= 0)
            #expect(rect.maxX <= width + 1 && rect.maxY <= height + 1)
        }
    }
}

@Test func naturalTopDetailRegionsUseTheSamePixelCoordinatesForCropAndPreview() {
    for (width, height) in [(360, 782), (580, 1280), (430, 932)] {
        let detail = PokemonExtractionLayout.regions(for: .pokemonDetail)
        #expect(detail.map(\.0) == [.displayedName, .cp, .hp])
        let cp = PokemonExtractionLayout.regions[.cp]!.pixelRect(width: width, height: height)!
        let name = PokemonExtractionLayout.regions[.displayedName]!.pixelRect(width: width, height: height)!
        let hp = PokemonExtractionLayout.regions[.hp]!.pixelRect(width: width, height: height)!
        // These are unscrolled Detail header, card name, and HP-row bands, not a scrolled offset.
        #expect(Double(cp.minY) / Double(height) >= 0.055)
        #expect(Double(cp.maxY) / Double(height) <= 0.105)
        #expect(cp.maxY < name.minY)
        #expect(name.maxY <= hp.minY + 1)
        #expect(hp.maxY < Int(0.51 * Double(height)))
        // The UI and Vision adapter both consume this exact rounded PixelRect.
        for (_, roi) in detail {
            let rect = roi.pixelRect(width: width, height: height)!
            #expect(rect.maxX <= width && rect.maxY <= height)
        }
    }
}

@Test func mirroringWindowViewportSeparatesToolbarFromGameAtSeveralResolutions() {
    for (width, height, pointsWide, pointsHigh) in [
        (580, 1280, 354.0, 781.0), (430, 932, 354.0, 781.0), (360, 782, 354.0, 781.0),
    ] {
        let captured = CapturedObservationFrame(
            width: width, height: height, rgbPixels: Data(repeating: 0, count: width * height * 3),
            frameID: 1, timestamp: .distantPast, sourceWindowWidthPoints: pointsWide,
            sourceWindowHeightPoints: pointsHigh)!
        let viewport = GameContentViewport(frame: captured)
        #expect(viewport.basis == .mirroringWindowChrome)
        #expect(Double(viewport.rect.x) / Double(width) > 0.02)
        #expect(Double(viewport.rect.y) / Double(height) > 0.045)
        #expect(viewport.rect.maxX < width && viewport.rect.maxY < height)
        for (region, roi) in PokemonExtractionLayout.regions(for: .pokemonDetail) {
            #expect(PokemonExtractionLayout.pixelRect(for: region, frame: captured) == viewport.pixelRect(for: roi))
        }
    }
    let liveSize = CapturedObservationFrame(
        width: 580, height: 1280, rgbPixels: Data(repeating: 0, count: 580 * 1280 * 3),
        frameID: 2, timestamp: .distantPast, sourceWindowWidthPoints: 354,
        sourceWindowHeightPoints: 781)!
    let viewport = GameContentViewport(frame: liveSize)
    #expect(viewport.rect.x == 13 && viewport.rect.y == 62)
    #expect(viewport.rect.width == 554 && viewport.rect.height == 1205)
    let cp = PokemonExtractionLayout.pixelRect(for: .cp, frame: liveSize)!
    #expect(cp.minY <= 140 && cp.maxY >= 170)
    #expect(cp.minY > viewport.rect.minY)
    #expect(GameContentViewport(frame: frame()).basis == .fullFrame)
    #expect(
        CapturedObservationFrame(
            width: 100, height: 220, rgbPixels: Data(repeating: 0, count: 100 * 220 * 3),
            frameID: 1, timestamp: .distantPast, sourceWindowWidthPoints: 354) == nil)
}

@Test func visionCropUsesTheSameTopLeftViewportRectangleAsPreview() throws {
    let width = 116, height = 256
    var pixels = [UInt8](repeating: 0, count: width * height * 3)
    let blank = CapturedObservationFrame(
        width: width, height: height, rgbPixels: Data(pixels), frameID: 1, timestamp: .distantPast,
        sourceWindowWidthPoints: 70.8, sourceWindowHeightPoints: 156.2)!
    let target = PokemonExtractionLayout.pixelRect(for: .cp, frame: blank)!
    for y in target.minY..<target.maxY {
        for x in target.minX..<target.maxX {
            let offset = (y * width + x) * 3
            pixels[offset] = 240
        }
    }
    let marked = CapturedObservationFrame(
        width: width, height: height, rgbPixels: Data(pixels), frameID: 2, timestamp: .distantPast,
        sourceWindowWidthPoints: 70.8, sourceWindowHeightPoints: 156.2)!
    let rendered = try #require(RGBImageRenderer.image(marked))
    let crop = try #require(
        rendered.cropping(to: CGRect(x: target.x, y: target.y, width: target.width, height: target.height)))
    let bitmap = NSBitmapImageRep(cgImage: crop)
    let color = try #require(bitmap.colorAt(x: target.width / 2, y: target.height / 2)?.usingColorSpace(.deviceRGB))
    #expect(color.redComponent > 0.9 && color.greenComponent < 0.1)
    #expect(target.minY < marked.height / 2)  // No bottom-left Y inversion.
}

@Test func visionStrengthIsNotFieldTruthAndConflictingNamesRemainVisible() {
    let extractor = PokemonDetailExtractor()
    let first = extractor.observations(
        from: [.displayedName: [.init(text: "Mewtwn", confidence: 1)]], frame: frame(id: 1))
    let second = extractor.observations(
        from: [.displayedName: [.init(text: "Mewtin", confidence: 1)]], frame: frame(id: 2))
    #expect(first.first?.confidence == 1)
    #expect(first.first?.evidence.contains("Raw Vision candidate: Mewtwn") == true)
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: first)
    assembler.receive(stableScreen: .pokemonDetail, observations: second)
    #expect(assembler.current?.consensus.first?.status == .conflict)
    #expect(assembler.current?.consensus.first?.value == nil)
    #expect(assembler.current?.observations.last?.observation.confidence == 1)
}

@Test func recurringIdentityVariantsAggregateAndDominantConsensusCanRecover() {
    var assembler = ScanSessionAssembler()
    assembler.receive(
        stableScreen: .pokemonDetail,
        observations: [observed(.displayedName, .text("Mewtwn"), frameID: 1, confidence: 1)])
    for id in 2...101 {
        let value = id.isMultiple(of: 5) ? "Mewtin" : "Mewtwo"
        assembler.receive(
            stableScreen: .pokemonDetail,
            observations: [observed(.displayedName, .text(value), frameID: UInt64(id), confidence: 1)])
    }
    let session = assembler.current!
    #expect(session.observations.count <= TemporaryPokemonScanSession.recentObservationLimit)
    #expect(session.quarantinedIdentityObservations.count == 1)
    #expect(session.quarantinedIdentityObservations.reduce(0) { $0 + $1.occurrences } == 20)
    let recurring = session.quarantinedIdentityObservations.first { $0.value == .text("Mewtin") }
    #expect(recurring?.occurrences == 20)
    #expect(recurring?.first.frameID == 5)
    #expect(recurring?.latest.frameID == 100)
    #expect(session.possibleNewPokemon)
    #expect(session.consensus.first?.value == .text("Mewtwo"))
    #expect(session.consensus.first?.alternatives.contains(.text("Mewtin")) == true)
}

@Test func recurringUnverifiedIVsRemainBoundedAndRetainCounts() {
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.cp, .integer(3999), frameID: 1)])
    for id in 2...80 {
        assembler.receive(
            stableScreen: .appraisal,
            observations: [observed(.ivAttack, .integer(15), frameID: UInt64(id), screen: .appraisal)])
    }
    #expect(assembler.current?.unverifiedAppraisalObservations.count == 1)
    #expect(assembler.current?.unverifiedAppraisalObservations.first?.occurrences == 79)
    #expect(assembler.current?.unverifiedAppraisalObservations.first?.first.frameID == 2)
    #expect(assembler.current?.unverifiedAppraisalObservations.first?.latest.frameID == 80)
}

@Test func distinctOCRNoiseUsesBoundedEvidenceAndRemainsUnresolved() {
    var assembler = ScanSessionAssembler()
    for id in 1...80 {
        assembler.receive(
            stableScreen: .pokemonDetail,
            observations: [observed(.displayedName, .text("Variant\(id)"), frameID: UInt64(id))])
    }
    let session = assembler.current!
    #expect(session.observations.count <= TemporaryPokemonScanSession.recentObservationLimit)
    #expect(session.quarantinedIdentityObservations.count <= TemporaryPokemonScanSession.variantLimitPerField)
    #expect(session.overflowedVariantOccurrences > 0)
    #expect(session.consensus.first?.value == nil)
}

@Test func stableAppraisalRoutesToThreeBarsAndKeepsDetailSessionUntilUnknownExpires() {
    func classification(_ type: ScreenType, _ id: UInt64) -> ScreenClassification {
        ScreenClassification(
            screenType: type, confidence: type == .unknown ? 0.25 : 0.90,
            evidence: [], frameID: id, timestamp: Date(timeIntervalSince1970: Double(id)))
    }
    var stabilizer = ScreenClassificationStabilizer()
    var assembler = ScanSessionAssembler()
    for id in 1...2 {
        let stable = stabilizer.append(classification(.pokemonDetail, UInt64(id)))
        assembler.receive(stableScreen: stable, observations: [])
    }
    let sessionID = assembler.current!.id
    #expect(PokemonExtractionLayout.regions(for: .pokemonDetail).map(\.0) == [.displayedName, .cp, .hp])
    for id in 3...4 {
        let stable = stabilizer.append(classification(.appraisal, UInt64(id)))
        assembler.receive(stableScreen: stable, observations: [])
    }
    #expect(assembler.current?.id == sessionID)
    #expect(
        PokemonExtractionLayout.regions(for: stabilizer.append(classification(.appraisal, 5))!).map(\.0)
            == [.appraisalAttack, .appraisalDefense, .appraisalHP])
    for id in 6...8 {
        let stable = stabilizer.append(classification(.unknown, UInt64(id)))
        assembler.receive(stableScreen: stable, observations: [])
        #expect(assembler.current?.id == sessionID)
    }
    let expired = stabilizer.append(classification(.unknown, 9))
    assembler.receive(stableScreen: expired, observations: [])
    #expect(expired == .unknown)
    #expect(assembler.current == nil)
    #expect(assembler.lastFinished?.id == sessionID)
}

private func barFrame(values: [Int], currentLayout: Bool = false, verticalShift: Int = 0) -> CapturedObservationFrame {
    let width = 360, height = 782
    var pixels = [UInt8](repeating: 255, count: width * height * 3)
    for (index, region) in [ExtractionRegion.appraisalAttack, .appraisalDefense, .appraisalHP].enumerated() {
        let layout = currentLayout ? PokemonExtractionLayout.currentAppraisalRegions : PokemonExtractionLayout.regions
        let rect = layout[region]!.pixelRect(width: width, height: height)!
        for y in (rect.minY + verticalShift)..<(rect.maxY + verticalShift) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let cell = min(14, (x - rect.minX) * 15 / rect.width)
                let offset = (y * width + x) * 3
                let filled = cell < values[index]
                pixels[offset] = filled ? 230 : 210
                pixels[offset + 1] = filled ? 110 : 210
                pixels[offset + 2] = filled ? 70 : 210
            }
        }
    }
    return CapturedObservationFrame(
        width: width, height: height, rgbPixels: Data(pixels), frameID: 7, timestamp: .distantPast)!
}

@Test func appraisalTrackGroupMovesTogetherWithoutChangingIVQuantisation() {
    let extractor = AppraisalBarExtractor()
    for (values, shift) in [([0, 0, 0], 18), ([6, 5, 12], 18), ([15, 11, 11], 18), ([15, 15, 15], -12)] {
        let captured = barFrame(values: values, verticalShift: shift)
        let regions = extractor.resolvedRegions(frame: captured)
        #expect(regions.count == 3)
        #expect(AppraisalIVReadiness(frame: captured, barRegions: regions).isReady)
        #expect(extractor.observations(frame: captured).map(\.value) == values.map(ExtractionValue.integer))
        let base = PokemonExtractionLayout.regions[.appraisalAttack]!.pixelRect(width: 360, height: 782)!
        #expect(regions[0].1.midY == base.midY + shift)
    }
}

@Test func appraisalBarsResolveIndependentIntegerValuesAndBoundaries() {
    let extractor = AppraisalBarExtractor()
    let observations = extractor.observations(frame: barFrame(values: [0, 5, 15]))
    #expect(observations.map(\.field) == [.ivAttack, .ivDefense, .ivHP])
    #expect(observations.map(\.value) == [.integer(0), .integer(5), .integer(15)])
    #expect(observations.allSatisfy { $0.sourceScreen == .appraisal && $0.method == .appraisalBarGeometry })
    #expect(
        extractor.observations(frame: barFrame(values: [10, 11, 12])).map(\.value)
            == [.integer(10), .integer(11), .integer(12)])
    let current = barFrame(values: [15, 15, 15], currentLayout: true)
    #expect(
        extractor.observations(frame: current).map(\.value)
            == [.integer(15), .integer(15), .integer(15)])
    #expect(
        extractor.resolvedRegions(frame: current).first?.1
            == GameContentViewport(frame: current).pixelRect(
                for: PokemonExtractionLayout.currentAppraisalRegions[.appraisalAttack]!))
    #expect(
        extractor.observations(frame: barFrame(values: [15, 15, 15])).map(\.value)
            == [.integer(15), .integer(15), .integer(15)])
    #expect(
        FieldObservation(
            field: .ivAttack, value: .integer(16), confidence: 0.8,
            method: .appraisalBarGeometry, sourceScreen: .appraisal, region: .appraisalAttack,
            frameID: 1, observedAt: .distantPast, evidence: "invalid") == nil)
}

@Test func featurelessOrBrokenBarsRemainUnresolved() {
    let extractor = AppraisalBarExtractor()
    #expect(extractor.observations(frame: frame()).isEmpty)
    var pixels = [UInt8](barFrame(values: [7, 8, 9]).rgbPixels)
    let roi = PokemonExtractionLayout.regions[.appraisalDefense]!
    let rect = roi.pixelRect(width: 360, height: 782)!
    let x = rect.minX + 25 * rect.width / 30, y = rect.midY
    let offset = (y * 360 + x) * 3
    pixels[offset] = 20; pixels[offset + 1] = 20; pixels[offset + 2] = 240
    let broken = CapturedObservationFrame(
        width: 360, height: 782, rgbPixels: Data(pixels), frameID: 8, timestamp: .distantPast)!
    #expect(extractor.observations(frame: broken).map(\.field) == [.ivAttack, .ivHP])
}

@Test func sessionJoinsDetailAndAppraisalButNotUnrelatedScreens() {
    var assembler = ScanSessionAssembler()
    assembler.receive(
        stableScreen: .appraisal, observations: [observed(.ivAttack, .integer(15), frameID: 1, screen: .appraisal)])
    #expect(assembler.current == nil)
    assembler.receive(
        stableScreen: .pokemonDetail, observations: [observed(.displayedName, .text("Mewtwo"), frameID: 2)])
    let firstID = assembler.current!.id
    assembler.receive(stableScreen: .pokemonDetail, observations: [])
    assembler.receive(
        stableScreen: .appraisal,
        observations: [
            observed(.displayedName, .text("Mewtwo"), frameID: 3, screen: .appraisal),
            observed(.ivAttack, .integer(15), frameID: 3, screen: .appraisal),
        ])
    #expect(assembler.current?.id == firstID)
    #expect(assembler.current?.observations.count == 3)
    #expect(assembler.current?.observations.allSatisfy { $0.sessionID == firstID } == true)
    assembler.receive(stableScreen: .map, observations: [])
    #expect(assembler.current == nil)
    #expect(assembler.lastFinished?.id == firstID)
    assembler.receive(stableScreen: .pokemonDetail, observations: [])
    #expect(assembler.current?.id != firstID)
}

@Test func appraisalWithoutMatchingIdentityStaysUnverified() {
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.cp, .integer(2300), frameID: 1)])
    let id = assembler.current!.id
    assembler.receive(
        stableScreen: .appraisal, observations: [observed(.ivAttack, .integer(14), frameID: 2, screen: .appraisal)])
    #expect(assembler.current?.id == id)
    #expect(assembler.current?.consensus.contains { $0.field == .ivAttack } == false)
    #expect(assembler.current?.unverifiedAppraisalObservations.count == 1)
    assembler.receive(
        stableScreen: .appraisal,
        observations: [
            observed(.cp, .integer(2400), frameID: 3, screen: .appraisal),
            observed(.ivDefense, .integer(13), frameID: 3, screen: .appraisal),
        ])
    #expect(assembler.current?.possibleNewPokemon == true)
    #expect(assembler.current?.unverifiedAppraisalObservations.count == 2)
}

@Test func consensusPrefersRepeatedEvidenceAndExposesConflicts() {
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.cp, .integer(2353), frameID: 1)])
    #expect(assembler.current?.consensus.first?.status == .provisional)
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.cp, .integer(2353), frameID: 2)])
    assembler.receive(
        stableScreen: .pokemonDetail, observations: [observed(.cp, .integer(2358), frameID: 3, confidence: 0.3)])
    #expect(assembler.current?.consensus.first?.value == .integer(2353))
    #expect(assembler.current?.consensus.first?.status == .corroborated)
    var second = ScanSessionAssembler()
    second.receive(
        stableScreen: .pokemonDetail,
        observations: [observed(.ivAttack, .integer(14), frameID: 1, screen: .pokemonDetail)])
    second.receive(
        stableScreen: .pokemonDetail,
        observations: [observed(.ivAttack, .integer(15), frameID: 2, screen: .pokemonDetail)])
    #expect(second.current?.consensus.first?.value == nil)
    #expect(second.current?.consensus.first?.status == .conflict)
    #expect(Set(second.current?.consensus.first?.alternatives ?? []) == [.integer(14), .integer(15)])
}

@Test func changedIdentityIsQuarantinedForReview() {
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.displayedName, .text("One"), frameID: 1)])
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.displayedName, .text("One"), frameID: 2)])
    assembler.receive(stableScreen: .pokemonDetail, observations: [observed(.displayedName, .text("Two"), frameID: 3)])
    #expect(assembler.current?.possibleNewPokemon == true)
    #expect(assembler.current?.observations.count == 2)
    #expect(assembler.current?.quarantinedIdentityObservations.count == 1)
}

@Test(.enabled(if: localScreenReferenceRoot() != nil))
func optionalLocalDetailReferenceExercisesTargetedVision() async throws {
    guard let root = localScreenReferenceRoot() else { return }
    let url = root.appendingPathComponent("PokemonDetail/mewtwo-detail-top.jpeg")
    let captured = try localObservationFrame(at: url)
    #expect(RGBImageRenderer.image(captured) != nil)
    let regions = Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail))
    let result = try await VisionRegionTextRecognizer().recognize(frame: captured, regions: regions)
    let observations = PokemonDetailExtractor().observations(from: result, frame: captured)
    #expect(observations.contains { $0.field == .displayedName })
    #expect(observations.contains { $0.field == .cp })
    #expect(observations.contains { $0.field == .hpCurrent })
    #expect(observations.contains { $0.field == .hpMaximum })
}

@Test(.enabled(if: localScreenReferenceRoot() != nil))
func optionalNaturalTopDetailReferencesKeepTargetFieldsInTheirROIs() async throws {
    guard let root = localScreenReferenceRoot() else { return }
    let regions = Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail))
    for name in ["mewtwo-detail-top.jpeg", "machamp-detail-top.jpeg", "gyarados-dynamax-top.jpeg"] {
        let frame = try localObservationFrame(at: root.appendingPathComponent("PokemonDetail/\(name)"))
        let recognized = try await VisionRegionTextRecognizer().recognize(frame: frame, regions: regions)
        let fields = Set(PokemonDetailExtractor().observations(from: recognized, frame: frame).map(\.field))
        #expect(fields.contains(.displayedName), "\(name): name ROI missed the unscrolled name")
        #expect(fields.contains(.cp), "\(name): CP ROI missed the unscrolled header")
        #expect(fields.contains(.hpCurrent) && fields.contains(.hpMaximum), "\(name): HP ROI missed the row")
    }
}

@Test(.enabled(if: localScreenReferenceRoot() != nil))
func optionalLocalAppraisalReferencesExposeThreeIndependentBars() async throws {
    guard let root = localScreenReferenceRoot() else { return }
    for name in ["mewtwo-appraisal.jpeg", "groudon-appraisal.jpeg"] {
        let frame = try localObservationFrame(at: root.appendingPathComponent("Appraisal/\(name)"))
        let fields = AppraisalBarExtractor().observations(frame: frame).map(\.field)
        #expect(fields == [.ivAttack, .ivDefense, .ivHP], "\(name): unresolved bar geometry")
        let recognized = try await VisionRegionTextRecognizer().recognize(
            frame: frame, regions: PokemonExtractionLayout.appraisalIdentityRegions)
        let identity = PokemonDetailExtractor().observations(
            from: recognized, frame: frame, sourceScreen: .appraisal)
        #expect(identity.contains { [.displayedName, .cp].contains($0.field) }, "\(name): no correlating name or CP")
    }
}

/// Opt in with a user-saved full-resolution local PNG/JPEG; classifier RGB (58×128) is too small for IV cells.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_HUNDO_FRAME"] != nil))
func optionalPrivateFullResolutionHundoBars() throws {
    guard let path = ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_HUNDO_FRAME"] else { return }
    let captured = try localObservationFrame(at: URL(fileURLWithPath: path))
    #expect(
        AppraisalBarExtractor().observations(frame: captured).map(\.value)
            == [.integer(15), .integer(15), .integer(15)])
}

private func localObservationFrame(at url: URL) throws -> CapturedObservationFrame {
    let image = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    let width = image.pixelsWide, height = image.pixelsHigh
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            let offset = (y * width + x) * 3
            rgb[offset] = UInt8((color.redComponent * 255).rounded())
            rgb[offset + 1] = UInt8((color.greenComponent * 255).rounded())
            rgb[offset + 2] = UInt8((color.blueComponent * 255).rounded())
        }
    }
    return try #require(
        CapturedObservationFrame(
            width: width, height: height, rgbPixels: Data(rgb), frameID: 1, timestamp: .distantPast))
}

@Test func appraisalReadinessRequiresVisibleCardNotJustAppraisalContext() {
    let width = 360, height = 782
    var pixels = [UInt8](repeating: 0, count: width * height * 3)
    for offset in stride(from: 0, to: pixels.count, by: 3) {
        pixels[offset] = 190
        pixels[offset + 1] = 80
        pixels[offset + 2] = 90
    }
    func captured() -> CapturedObservationFrame {
        CapturedObservationFrame(
            width: width, height: height, rgbPixels: Data(pixels), frameID: 1, timestamp: .distantPast)!
    }
    let extractor = AppraisalBarExtractor()
    let intro = captured()
    #expect(!AppraisalIVReadiness(frame: intro, barRegions: extractor.resolvedRegions(frame: intro)).isReady)
    let card = GameContentViewport(frame: intro).pixelRect(
        for: NormalizedROI(x: 0.07, y: 0.70, width: 0.45, height: 0.17)!)!
    for y in card.minY..<card.maxY {
        for x in card.minX..<card.maxX {
            let offset = (y * width + x) * 3
            pixels[offset] = 248
            pixels[offset + 1] = 248
            pixels[offset + 2] = 248
        }
    }
    let blankCard = captured()
    #expect(!AppraisalIVReadiness(frame: blankCard, barRegions: extractor.resolvedRegions(frame: blankCard)).isReady)
    for (_, rect) in extractor.resolvedRegions(frame: blankCard) {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                let offset = (y * width + x) * 3
                pixels[offset] = 190
                pixels[offset + 1] = 190
                pixels[offset + 2] = 190
            }
        }
    }
    let full = captured()
    #expect(AppraisalIVReadiness(frame: full, barRegions: extractor.resolvedRegions(frame: full)).isReady)
    #expect(
        PokemonExtractionMode.resolve(
            stableScreen: .appraisal, hasSession: true, actionMenuVisible: false, appraisalIVReady: false)
            == .appraisalIntro)
    #expect(
        PokemonExtractionMode.resolve(
            stableScreen: .appraisal, hasSession: true, actionMenuVisible: false, appraisalIVReady: true)
            == .appraisalIVs)
    #expect(
        PokemonExtractionMode.resolve(
            stableScreen: .pokemonDetail, hasSession: true, actionMenuVisible: false, appraisalIVReady: false)
            == .detail)
    #expect(
        PokemonExtractionMode.resolve(
            stableScreen: .pokemonDetail, hasSession: true, actionMenuVisible: true, appraisalIVReady: false)
            == .pausedActionMenu)
}

@Test func actionMenuBridgeRetainsOneSessionUntilAppraisalObservations() {
    var assembler = ScanSessionAssembler()
    assembler.receive(
        stableScreen: .pokemonDetail,
        observations: [
            observed(.displayedName, .text("Example"), frameID: 1),
            observed(.cp, .integer(3999), frameID: 1),
            observed(.hpCurrent, .integer(0), frameID: 1),
            observed(.hpMaximum, .integer(177), frameID: 1),
        ])
    let sessionID = assembler.current?.id
    for _ in 0..<8 {
        assembler.receive(stableScreen: .map, observations: [], actionMenuVisible: true)
        #expect(assembler.current?.id == sessionID)
    }
    // The classifier may still retain its false Map decision while Appraisal settles.
    assembler.receive(stableScreen: .map, observations: [])
    assembler.receive(stableScreen: .map, observations: [])
    assembler.receive(stableScreen: .appraisal, observations: [])  // Intro has no IV card.
    #expect(assembler.current?.id == sessionID)
    #expect(assembler.current?.consensus.contains { $0.field == .ivAttack } == false)
    assembler.receive(
        stableScreen: .appraisal,
        observations: [
            observed(.displayedName, .text("Example"), frameID: 9, screen: .appraisal),
            observed(.cp, .integer(3999), frameID: 9, screen: .appraisal),
            observed(.ivAttack, .integer(15), frameID: 9, screen: .appraisal),
            observed(.ivDefense, .integer(15), frameID: 9, screen: .appraisal),
            observed(.ivHP, .integer(15), frameID: 9, screen: .appraisal),
        ])
    #expect(assembler.current?.id == sessionID)
    #expect(assembler.current?.consensus.contains { $0.field == .ivAttack && $0.value == .integer(15) } == true)
    #expect(assembler.current?.consensus.contains { $0.field == .ivDefense && $0.value == .integer(15) } == true)
    #expect(assembler.current?.consensus.contains { $0.field == .ivHP && $0.value == .integer(15) } == true)
}

@Test func actionMenuBridgeIsBoundedAndOtherScreensStillFinish() {
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: [])
    let sessionID = assembler.current?.id
    assembler.receive(stableScreen: .unknown, observations: [], actionMenuVisible: true)
    for _ in 0..<ScanSessionAssembler.actionMenuTransitionAllowance {
        assembler.receive(stableScreen: .map, observations: [])
        #expect(assembler.current?.id == sessionID)
    }
    assembler.receive(stableScreen: .map, observations: [])
    #expect(assembler.current == nil)
    #expect(assembler.lastFinished?.id == sessionID)
}
