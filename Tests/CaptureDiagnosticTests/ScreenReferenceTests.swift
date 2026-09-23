import AppKit
import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis
import Testing

private let referenceCategories: [(folder: String, type: ScreenType)] = [
    ("Map", .map),
    ("MainMenu", .mainMenu),
    ("Nearby", .nearby),
    ("PokemonStorage", .pokemonStorage),
    ("PokemonDetail", .pokemonDetail),
    ("Appraisal", .appraisal),
    ("Items", .items),
    ("Profile", .profile),
]

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func everyLocalScreenReferenceHasItsTopLevelType() throws {
    guard let root = localScreenReferenceRoot() else { return }
    var total = 0
    for category in referenceCategories {
        let directory = root.appendingPathComponent(category.folder, isDirectory: true)
        let images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpeg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!images.isEmpty, "Missing reference images for \(category.folder)")
        for image in images {
            let frame = try #require(referenceFrame(at: image))
            let result = ScreenClassifier().classify(frame)
            #expect(
                result.screenType == category.type,
                "\(category.folder)/\(image.lastPathComponent): got \(result.screenType.rawValue) (\(result.confidence)); \(result.evidence.map(\.signal))"
            )
            #expect(result.confidence >= 0.8)
            #expect(result.frameID == frame.frameID && result.timestamp == frame.timestamp)
            #expect(result.evidence.count >= 3)
            #expect(result.evidence.allSatisfy { !$0.explanation.isEmpty && (0...1).contains($0.strength) })
            #expect(result.candidateAssessments.filter { $0.supportScore == 1 }.count == 1)
            #expect(result.candidateAssessments.first?.supportingSignals.count == result.evidence.count)
            total += 1
        }
    }
    #expect(total == 20)
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func referenceScreensKeepTheirTypeAtAnotherPortraitResolution()
    throws
{
    guard let root = localScreenReferenceRoot() else { return }
    for category in referenceCategories {
        let directory = root.appendingPathComponent(category.folder, isDirectory: true)
        let images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpeg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for image in images {
            let frame = try #require(referenceFrame(at: image, maximumDimension: 320))
            let result = ScreenClassifier().classify(frame)
            #expect(
                result.screenType == category.type, "Higher-resolution \(category.folder)/\(image.lastPathComponent)")
        }
    }
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func referenceScreensAtLiveAnalysisDimensions() throws {
    guard let root = localScreenReferenceRoot() else { return }
    for category in referenceCategories {
        let directory = root.appendingPathComponent(category.folder, isDirectory: true)
        let images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpeg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for image in images {
            let frame = try #require(referenceFrame(at: image, targetSize: (58, 128)))
            let result = ScreenClassifier().classify(frame)
            #expect(result.screenType == category.type, "Live-sized \(category.folder)/\(image.lastPathComponent)")
        }
    }
}

@Test func featurelessFramesStayUnknown() {
    for color: (UInt8, UInt8, UInt8) in [(255, 255, 255), (80, 170, 165), (210, 100, 145)] {
        var pixels = [UInt8](repeating: 0, count: 58 * 128 * 3)
        for offset in stride(from: 0, to: pixels.count, by: 3) {
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
        }
        let frame = CapturedImageFrame(
            width: 58, height: 128, rgbPixels: Data(pixels), frameID: 17, timestamp: .distantPast)!
        let result = ScreenClassifier().classify(frame)
        #expect(result.screenType == .unknown)
        #expect(result.evidence.contains { $0.signal == "insufficient-structure" })
    }
}

@Test func unsupportedLandscapeFrameStaysUnknown() {
    let frame = CapturedImageFrame(
        width: 128, height: 58, rgbPixels: Data(repeating: 255, count: 128 * 58 * 3),
        frameID: 18, timestamp: .distantPast)!
    let result = ScreenClassifier().classify(frame)
    #expect(result.screenType == .unknown)
    #expect(result.confidence == 0)
    #expect(result.evidence.contains { $0.signal == "frame" })
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func exactRGBArchiveReplaysTheSameClassifierInputAndResult()
    throws
{
    guard let root = localScreenReferenceRoot() else { return }
    for relativePath in [
        "PokemonStorage/pokemon-storage-scrolled.jpeg",
        "Items/items-medicine-top.jpeg",
        "Profile/profile-top.jpeg",
    ] {
        let frame = try #require(referenceFrame(at: root.appendingPathComponent(relativePath)))
        let original = ScreenClassifier().classify(frame)
        let bytes = try JSONEncoder().encode(CapturedImageFrameArchive(frame: frame))
        let archive = try JSONDecoder().decode(CapturedImageFrameArchive.self, from: bytes)
        let replay = try #require(archive.restoredFrame())
        #expect(replay == frame)
        #expect(ScreenClassifier().classify(replay) == original)
    }
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func storageGridDoesNotBecomeDetailWhenHeaderColourChanges()
    throws
{
    guard let root = localScreenReferenceRoot() else { return }
    let frame = try #require(
        referenceFrame(at: root.appendingPathComponent("PokemonStorage/pokemon-storage-scrolled.jpeg")))
    let altered = recoloured(frame, x: 0...1, y: 0...0.21, rgb: (190, 190, 190))
    #expect(ScreenClassifier().classify(altered).screenType == .pokemonStorage)
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func optionalLightDetailPanelKeepsItsParentScreen() throws {
    guard let root = localScreenReferenceRoot() else { return }
    let frame = try #require(referenceFrame(at: root.appendingPathComponent("PokemonDetail/mewtwo-detail-moves.jpeg")))
    let altered = recoloured(frame, x: 0.10...0.90, y: 0.40...0.60, rgb: (190, 215, 200))
    #expect(ScreenClassifier().classify(altered).screenType == .pokemonDetail)
}

@Test func aWhitePageWithOneTealControlIsNotPokemonDetail() {
    let frame = CapturedImageFrame(
        width: 58, height: 128, rgbPixels: Data(repeating: 255, count: 58 * 128 * 3),
        frameID: 20, timestamp: .distantPast)!
    let altered = recoloured(frame, x: 0.78...0.98, y: 0.88...0.98, rgb: (25, 155, 165))
    #expect(ScreenClassifier().classify(altered).screenType == .unknown)
}

@Test func anUnsupportedLightTextListIsNotItems() {
    var pixels = [UInt8](repeating: 255, count: 58 * 128 * 3)
    for row in stride(from: 28, through: 100, by: 14) {
        for column in 17..<48 {
            let offset = (row * 58 + column) * 3
            pixels[offset] = 65
            pixels[offset + 1] = 65
            pixels[offset + 2] = 65
        }
    }
    let frame = CapturedImageFrame(
        width: 58, height: 128, rgbPixels: Data(pixels), frameID: 21, timestamp: .distantPast)!
    #expect(ScreenClassifier().classify(frame).screenType == .unknown)
}

@Test(.enabled(if: localScreenReferenceRoot() != nil))
func unknownProfileVariantReportsRelevantCandidateInsteadOfAppraisal() throws {
    guard let root = localScreenReferenceRoot() else { return }
    let frame = try #require(referenceFrame(at: root.appendingPathComponent("Profile/profile-top.jpeg")))
    let altered = recoloured(frame, x: 0...1, y: 0.05...0.15, rgb: (130, 130, 130))
    let result = ScreenClassifier().classify(altered)
    #expect(result.screenType == .unknown)
    #expect(result.candidateAssessments.first?.screenType == .profile)
    #expect(result.candidateAssessments.first?.missingSignals.contains { $0.contains("profile-tabs") } == true)
}

@Test(.enabled(if: localScreenReferenceRoot() != nil)) func referenceScreensTolerateSmallOverallBrightnessChanges()
    throws
{
    guard let root = localScreenReferenceRoot() else { return }
    for category in referenceCategories {
        let directory = root.appendingPathComponent(category.folder, isDirectory: true)
        let images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpeg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for image in images {
            let frame = try #require(referenceFrame(at: image))
            for delta in [-12, 12] {
                let result = ScreenClassifier().classify(brightnessAdjusted(frame, delta: delta))
                let expectedAssessment = result.candidateAssessments.first { $0.screenType == category.type }
                #expect(
                    result.screenType == category.type,
                    "Brightness \(delta): \(category.folder)/\(image.lastPathComponent) became \(result.screenType.rawValue); expected missing \(expectedAssessment?.missingSignals ?? [])"
                )
            }
        }
    }
}

private func brightnessAdjusted(_ frame: CapturedImageFrame, delta: Int) -> CapturedImageFrame {
    let pixels = [UInt8](frame.rgbPixels).map { UInt8(max(0, min(255, Int($0) + delta))) }
    return CapturedImageFrame(
        width: frame.width, height: frame.height, rgbPixels: Data(pixels),
        frameID: frame.frameID, timestamp: frame.timestamp)!
}

private func recoloured(
    _ frame: CapturedImageFrame, x: ClosedRange<Double>, y: ClosedRange<Double>, rgb: (UInt8, UInt8, UInt8)
) -> CapturedImageFrame {
    var pixels = [UInt8](frame.rgbPixels)
    for row in Int(y.lowerBound * Double(frame.height))..<Int(y.upperBound * Double(frame.height)) {
        for column in Int(x.lowerBound * Double(frame.width))..<Int(x.upperBound * Double(frame.width)) {
            let offset = (row * frame.width + column) * 3
            pixels[offset] = rgb.0
            pixels[offset + 1] = rgb.1
            pixels[offset + 2] = rgb.2
        }
    }
    return CapturedImageFrame(
        width: frame.width, height: frame.height, rgbPixels: Data(pixels),
        frameID: frame.frameID, timestamp: frame.timestamp)!
}

/// Private screenshots are read in place, never included in a SwiftPM resource bundle.
func localScreenReferenceRoot() -> URL? {
    let root: URL
    if let path = ProcessInfo.processInfo.environment["GO_COMPANION_SCREEN_REFERENCES_DIR"] {
        root = URL(fileURLWithPath: path, isDirectory: true)
    } else {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ScreenReferences", isDirectory: true)
    }
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: root.path, isDirectory: &directory) && directory.boolValue
        ? root : nil
}

func referenceFrame(
    at url: URL, maximumDimension: Int = 128, targetSize: (width: Int, height: Int)? = nil
) -> CapturedImageFrame? {
    guard let jpeg = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: jpeg),
        bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0
    else {
        return nil
    }
    let scale = min(1, Double(maximumDimension) / Double(max(bitmap.pixelsWide, bitmap.pixelsHigh)))
    let width = targetSize?.width ?? max(1, Int((Double(bitmap.pixelsWide) * scale).rounded()))
    let height = targetSize?.height ?? max(1, Int((Double(bitmap.pixelsHigh) * scale).rounded()))
    var rgb = Data(count: width * height * 3)
    let converted = rgb.withUnsafeMutableBytes { destination -> Bool in
        guard let output = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
        for y in 0..<height {
            let sourceY = min(bitmap.pixelsHigh - 1, y * bitmap.pixelsHigh / height)
            for x in 0..<width {
                let sourceX = min(bitmap.pixelsWide - 1, x * bitmap.pixelsWide / width)
                guard let color = bitmap.colorAt(x: sourceX, y: sourceY)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                let offset = (y * width + x) * 3
                output[offset] = UInt8((color.redComponent * 255).rounded())
                output[offset + 1] = UInt8((color.greenComponent * 255).rounded())
                output[offset + 2] = UInt8((color.blueComponent * 255).rounded())
            }
        }
        return true
    }
    guard converted else { return nil }
    return CapturedImageFrame(width: width, height: height, rgbPixels: rgb, frameID: 1, timestamp: .distantPast)
}
