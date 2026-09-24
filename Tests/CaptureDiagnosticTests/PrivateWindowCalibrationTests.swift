import AppKit
import Foundation
import GOCompanionCapture
import GOCompanionExtraction
import GOCompanionScreenAnalysis
import MacRecognitionAdapter
import Testing

private func calibrationRoot() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_CALIBRATION_DIR"] else {
        return nil
    }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
        return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
}

/// The private macOS captures are 2× display screenshots, with black background outside
/// the selected Mirroring window. Reconstruct the window-only 580×1280 capture locally.
private func windowFrame(_ name: String, in root: URL, frameID: UInt64 = 1) throws -> CapturedObservationFrame {
    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: root.appendingPathComponent(name))))
    #expect(bitmap.pixelsWide == 932 && bitmap.pixelsHigh == 1786)
    let windowX = 112, windowY = 76, windowWidth = 708, windowHeight = 1562
    let width = 580, height = 1280
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let sourceX = windowX + x * windowWidth / width
            let sourceY = windowY + y * windowHeight / height
            let color = bitmap.colorAt(x: sourceX, y: sourceY)!.usingColorSpace(.deviceRGB)!
            let offset = (y * width + x) * 3
            rgb[offset] = UInt8((color.redComponent * 255).rounded())
            rgb[offset + 1] = UInt8((color.greenComponent * 255).rounded())
            rgb[offset + 2] = UInt8((color.blueComponent * 255).rounded())
        }
    }
    return try #require(
        CapturedObservationFrame(
            width: width, height: height, rgbPixels: Data(rgb), frameID: frameID, timestamp: .distantPast,
            sourceWindowWidthPoints: Double(windowWidth) / 2,
            sourceWindowHeightPoints: Double(windowHeight) / 2))
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateIVCalibrationMatrix() throws {
    guard let root = calibrationRoot() else { return }
    let cases: [(String, [Int]?)] = [
        ("CAL-03-mewtwo-appraisal-intro.png", nil),
        ("IVCAL-mewtwo-hundo-15-15-15-PASS.png", [15, 15, 15]),
        ("IVCAL-oinkologne-1star-6-5-12-PASS.png", [6, 5, 12]),
        ("IVCAL-dragonite-3star-15-11-11-FAIL.png", [15, 11, 11]),
        ("IVCAL-flamingo-2star-10-6-15-FAIL.png", [10, 6, 15]),
        ("IVCAL-giratina-1star-12-9-6-FAIL.png", [12, 9, 6]),
        ("IVCAL-grookey-2star-12-13-11-FAIL.png", [12, 13, 11]),
        ("IVCAL-mareanie-nundo-0-0-0-FAIL.png", [0, 0, 0]),
    ]
    for (name, expected) in cases {
        let frame = try windowFrame(name, in: root)
        let extractor = AppraisalBarExtractor()
        let regions = extractor.resolvedRegions(frame: frame)
        let readiness = AppraisalIVReadiness(frame: frame, barRegions: regions)
        #expect(readiness.isReady == (expected != nil), "\(name): \(readiness.reason)")
        let observed = readiness.isReady ? extractor.observations(frame: frame).map(\.value) : []
        if let expected {
            #expect(observed == expected.map(ExtractionValue.integer), "\(name): \(readiness.reason)")
            #expect(readiness.cardLightFraction >= 0.38)
            #expect(readiness.trackCells.values.allSatisfy { $0 >= 12 })
        } else {
            #expect(observed.isEmpty)  // Ungated bar analysis can report spurious values on the intro.
            #expect(readiness.cardLightFraction < 0.38)
        }
        print(
            "IV MATRIX \(name): \(readiness.reason); y=\(regions.map { $0.1.midY }); "
                + "observed=\(observed)")
    }
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateJourneyAttachesVisibleAppraisalToDetailSession() async throws {
    guard let root = calibrationRoot() else { return }
    let detail = try windowFrame("CAL-01-mewtwo-detail.png", in: root, frameID: 1)
    let full = try windowFrame("CAL-04-mewtwo-apraisal-ivs.png", in: root, frameID: 4)
    let recognizer = VisionRegionTextRecognizer()
    let detailText = try await recognizer.recognize(
        frame: detail, regions: Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail)))
    let appraisalText = try await recognizer.recognize(
        frame: full, regions: PokemonExtractionLayout.appraisalIdentityRegions)
    let detailObservations = PokemonDetailExtractor().observations(from: detailText, frame: detail)
    let appraisalObservations =
        PokemonDetailExtractor().observations(
            from: appraisalText, frame: full, sourceScreen: .appraisal)
        + AppraisalBarExtractor().observations(frame: full)
    var assembler = ScanSessionAssembler()
    assembler.receive(stableScreen: .pokemonDetail, observations: detailObservations)
    let id = try #require(assembler.current?.id)
    assembler.receive(stableScreen: .map, observations: [], actionMenuVisible: true)
    assembler.receive(stableScreen: .appraisal, observations: [])
    #expect(assembler.current?.id == id)
    #expect(assembler.current?.consensus.contains { $0.field == .ivAttack } == false)
    assembler.receive(stableScreen: .appraisal, observations: appraisalObservations)
    print("PRIVATE JOURNEY: detail=\(detailObservations.map(\.field)) appraisal=\(appraisalObservations.map(\.field))")
    #expect(assembler.current?.id == id)
    #expect(assembler.current?.consensus.contains { $0.field == .ivAttack && $0.value == .integer(15) } == true)
    #expect(assembler.current?.consensus.contains { $0.field == .ivDefense && $0.value == .integer(15) } == true)
    #expect(assembler.current?.consensus.contains { $0.field == .ivHP && $0.value == .integer(15) } == true)
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateAppraisalJourneyStates() throws {
    guard let root = calibrationRoot() else { return }
    var stabilizer = ScreenClassificationStabilizer()
    for (index, name) in [
        "CAL-01-mewtwo-detail.png", "CAL-02-mewtwo-action-menu.png",
        "CAL-03-mewtwo-appraisal-intro.png", "CAL-04-mewtwo-apraisal-ivs.png",
    ].enumerated() {
        let frame = try windowFrame(name, in: root)
        let source = [UInt8](frame.rgbPixels)
        var pixels = [UInt8](repeating: 0, count: 58 * 128 * 3)
        for y in 0..<128 {
            for x in 0..<58 {
                let input = ((y * frame.height / 128) * frame.width + x * frame.width / 58) * 3
                let output = (y * 58 + x) * 3
                pixels[output] = source[input]
                pixels[output + 1] = source[input + 1]
                pixels[output + 2] = source[input + 2]
            }
        }
        let small = try #require(
            CapturedImageFrame(width: 58, height: 128, rgbPixels: Data(pixels), frameID: 1, timestamp: .distantPast))
        let result = ScreenClassifier().classify(small)
        let visual = PokemonJourneyVisualState(classifierFrame: small)
        let menu = visual.actionMenuVisible
        let extractor = AppraisalBarExtractor()
        let readiness = AppraisalIVReadiness(frame: frame, barRegions: extractor.resolvedRegions(frame: frame))
        print("JOURNEY \(name): \(result.screenType) menu=\(menu) ready=\(readiness.isReady) \(readiness.reason)")
        #expect(menu == (index == 1))
        if index == 0 { #expect(result.screenType == .pokemonDetail) }
        if index == 1 {
            #expect(result.screenType == .map)  // Existing classifier's raw false positive stays visible.
            #expect(visual.stabilizationInput(result).screenType == .unknown)
        }
        if index >= 2 { #expect(result.screenType == .appraisal) }
        let input = visual.stabilizationInput(result)
        for _ in 0..<(index == 1 ? 8 : 2) {
            let stable = stabilizer.append(input)
            #expect(stable != .map)
        }
        if index == 0 { #expect(stabilizer.append(input) == .pokemonDetail) }
        if index >= 2 { #expect(stabilizer.append(input) == .appraisal) }
        if index == 2 {
            #expect(!readiness.isReady)
            #expect(extractor.observations(frame: frame).count == 2)  // Ungated sampler would be wrong here.
            let mode = PokemonExtractionMode.resolve(
                stableScreen: .appraisal, hasSession: true, actionMenuVisible: false, appraisalIVReady: false)
            #expect(mode == .appraisalIntro)
            let emitted = mode == .appraisalIVs ? extractor.observations(frame: frame) : []
            #expect(emitted.isEmpty)
        }
        if index == 3 {
            #expect(readiness.isReady)
            #expect(
                PokemonExtractionMode.resolve(
                    stableScreen: .appraisal, hasSession: true, actionMenuVisible: false,
                    appraisalIVReady: readiness.isReady) == .appraisalIVs)
            #expect(extractor.observations(frame: frame).map(\.value) == [.integer(15), .integer(15), .integer(15)])
            let active = extractor.resolvedRegions(frame: frame)
            print("APPRAISAL ROIS \(active.map { "\($0.0.rawValue):\($0.1)" })")
            #expect(active.map(\.0) == [.appraisalAttack, .appraisalDefense, .appraisalHP])
            #expect(active.allSatisfy { $0.1.minX >= GameContentViewport(frame: frame).rect.minX })
        }
    }
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateMacWindowDetailGeometryAndOCR() async throws {
    guard let root = calibrationRoot() else { return }
    let frame = try windowFrame("CAL-mewtwo-natural-detail-mirroring-window.png", in: root)
    let viewport = GameContentViewport(frame: frame)
    #expect(viewport.basis == .mirroringWindowChrome)
    #expect(viewport.rect.x == 13 && viewport.rect.y == 62)
    #expect(viewport.rect.width == 554 && viewport.rect.height == 1205)
    let regions = Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail))
    let recognized = try await VisionRegionTextRecognizer().recognize(frame: frame, regions: regions)
    let fields = PokemonDetailExtractor().observations(from: recognized, frame: frame)
    print("PRIVATE WINDOW DETAIL: \(fields.map { "\($0.field.rawValue)=\($0.value)" })")
    let cp = PokemonExtractionLayout.pixelRect(for: .cp, frame: frame)!
    let name = PokemonExtractionLayout.pixelRect(for: .displayedName, frame: frame)!
    let hp = PokemonExtractionLayout.pixelRect(for: .hp, frame: frame)!
    // Measured landmarks after window crop/downscale: CP around y=140–170, name
    // around y=560–590, HP around y=625–640 in 580×1280 capture pixels.
    #expect(cp.minY < 140 && cp.maxY > 170)
    #expect(name.minY < 560 && name.maxY > 590)
    #expect(hp.minY < 625 && hp.maxY > 640)
    #expect(fields.contains { $0.field == .hpCurrent && $0.value == .integer(0) })
    #expect(fields.contains { $0.field == .hpMaximum && $0.value == .integer(177) })
    #expect(fields.contains { $0.field == .displayedName })
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateSecondNaturalDetailUsesTheSameViewport() async throws {
    guard let root = calibrationRoot() else { return }
    let frame = try windowFrame("CAL-zamazenta-natural-detail-mirroring-window.png", in: root)
    #expect(GameContentViewport(frame: frame).rect.y == 62)
    let regions = Dictionary(uniqueKeysWithValues: PokemonExtractionLayout.regions(for: .pokemonDetail))
    let recognized = try await VisionRegionTextRecognizer().recognize(frame: frame, regions: regions)
    let fields = PokemonDetailExtractor().observations(from: recognized, frame: frame)
    #expect(fields.contains { $0.field == .displayedName })
    #expect(fields.contains { $0.field == .hpCurrent && $0.value == .integer(138) })
    #expect(fields.contains { $0.field == .hpMaximum && $0.value == .integer(138) })
}

@Test(.enabled(if: calibrationRoot() != nil))
func optionalPrivateMacWindowAppraisalGeometry() async throws {
    guard let root = calibrationRoot() else { return }
    let frame = try windowFrame("CAL-mewtwo-appraisal-mirroring-window.png", in: root)
    let viewport = GameContentViewport(frame: frame)
    #expect(viewport.rect.x == 13 && viewport.rect.y == 62)
    let recognized = try await VisionRegionTextRecognizer().recognize(
        frame: frame, regions: PokemonExtractionLayout.appraisalIdentityRegions)
    #expect(recognized[.cp]?.contains { $0.text == "CP3999" } == true)
    let bars = AppraisalBarExtractor().observations(frame: frame)
    print("PRIVATE WINDOW APPRAISAL BARS: \(bars.map { "\($0.field.rawValue)=\($0.value)" })")
    #expect(bars.map(\.value) == [.integer(15), .integer(15), .integer(15)])
    let rectangles = AppraisalBarExtractor().resolvedRegions(frame: frame)
    #expect(rectangles.map(\.0) == [.appraisalAttack, .appraisalDefense, .appraisalHP])
}
