import Foundation
import GOCompanionCapture
import GOCompanionExtraction
import GOCompanionScreenAnalysis
import Testing

private struct SavedClassifierFrame: Decodable {
    let archive: CapturedImageFrameArchive
    let originalScreenType: String
    let originalConfidence: Double
    let originalEvidenceSignals: [String]
}

private let privateExpectations: [String: ScreenType] = [
    "FAIL-map-night-unknown.json": .map,
    "FAIL-nearby-unknown.json": .nearby,
    "FAIL-detail-kyurem-scrolled-fuse-unknown.json": .pokemonDetail,
    "FAIL-items-top-unknown.json": .items,
    "FAIL-items-scrolled-unknown.json": .items,
    "FAIL-profile-top-unknown.json": .profile,
    "FAIL-profile-scrolled-unknown.json": .profile,
    "FAIL-appraisal-fainted-mewtwo-unknown.json": .appraisal,
]

private let ambiguousDetailArchive = "FAIL-detail-zamazenta-form-panel-unknown.json"

/// Set GO_COMPANION_PRIVATE_RGB_DIR to opt into local, private live-frame regressions.
/// No personal frame is copied into the test bundle or printed by this test.
@Test(.enabled(if: privateRGBDirectoryExists())) func optionalPrivateLiveRGBFramesHaveTheirParentScreenType() throws {
    guard let path = ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_RGB_DIR"],
        FileManager.default.fileExists(atPath: path)
    else { return }

    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    #expect(Set(privateExpectations.keys).isSubset(of: Set(urls.map(\.lastPathComponent))))

    for url in urls where privateExpectations[url.lastPathComponent] != nil {
        let expected = try #require(privateExpectations[url.lastPathComponent])
        let saved = try JSONDecoder().decode(SavedClassifierFrame.self, from: Data(contentsOf: url))
        let frame = try #require(saved.archive.restoredFrame())
        #expect(!PokemonJourneyVisualState(classifierFrame: frame).actionMenuVisible)
        let result = ScreenClassifier().classify(frame)
        let candidate = result.candidateAssessments.first { $0.screenType == expected }
        print(
            "PRIVATE REPLAY \(url.lastPathComponent): saved=\(saved.originalScreenType) "
                + "result=\(result.screenType.rawValue) expected=\(expected.rawValue) "
                + "candidate=\(candidate?.matchedSignals ?? 0)/\(candidate?.totalSignals ?? 0) "
                + "supporting=\(candidate?.supportingSignals ?? []) "
                + "missing=\(candidate?.missingSignals ?? [])")
        #expect(saved.originalScreenType == ScreenType.unknown.rawValue)
        #expect(saved.originalConfidence == 0.25)
        #expect(saved.originalEvidenceSignals.contains("insufficient-structure"))
        #expect(result.frameID == frame.frameID && result.timestamp == frame.timestamp)
        #expect(result.screenType == expected, "\(url.lastPathComponent): \(candidate?.missingSignals ?? [])")
        for delta in [-12, 12] {
            let pixels = [UInt8](frame.rgbPixels).map { UInt8(max(0, min(255, Int($0) + delta))) }
            let adjusted = try #require(
                CapturedImageFrame(
                    width: frame.width, height: frame.height, rgbPixels: Data(pixels),
                    frameID: frame.frameID, timestamp: frame.timestamp))
            #expect(
                ScreenClassifier().classify(adjusted).screenType == expected,
                "\(url.lastPathComponent), brightness \(delta)")
        }
    }
}

@Test(.enabled(if: privateRGBDirectoryExists())) func optionalPrivateSpecialDetailPanelKeepsOnlyStableParent() throws {
    guard let path = ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_RGB_DIR"],
        FileManager.default.fileExists(atPath: path)
    else { return }

    let url = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(ambiguousDetailArchive)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let saved = try JSONDecoder().decode(SavedClassifierFrame.self, from: Data(contentsOf: url))
    let frame = try #require(saved.archive.restoredFrame())
    let raw = ScreenClassifier().classify(frame)
    #expect(saved.originalScreenType == ScreenType.unknown.rawValue)
    #expect(raw.screenType == .unknown)
    #expect(raw.candidateAssessments.first?.screenType == .pokemonDetail)
    #expect(raw.candidateAssessments.first?.missingSignals.contains { $0.contains("detail-lower-card") } == true)

    var stabilizer = ScreenClassificationStabilizer()
    let detail = ScreenClassification(
        screenType: .pokemonDetail, confidence: 0.90,
        evidence: [.init(signal: "detail", strength: 0.90, explanation: "Supported Detail frame.")],
        frameID: 1, timestamp: .distantPast)
    #expect(stabilizer.append(detail) == nil)
    #expect(stabilizer.append(detail) == .pokemonDetail)
    #expect(stabilizer.append(raw) == .pokemonDetail)
    #expect(stabilizer.continuity == .retaining(screen: .pokemonDetail, ambiguousFrames: 1, allowance: 3))
    #expect(raw.screenType == .unknown)
}

private func privateRGBDirectoryExists() -> Bool {
    guard let path = ProcessInfo.processInfo.environment["GO_COMPANION_PRIVATE_RGB_DIR"] else { return false }
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
}
