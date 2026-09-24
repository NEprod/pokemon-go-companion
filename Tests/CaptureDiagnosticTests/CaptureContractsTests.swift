import Foundation
import GOCompanionCapture
import GOCompanionScreenAnalysis
import Testing

private let mirroringWindow = CaptureWindow(
    id: 42, title: "Dale's iPhone", applicationName: "iPhone Mirroring",
    applicationBundleID: "com.apple.ScreenContinuity", widthPoints: 420,
    heightPoints: 900, isOnScreen: true)

@Test func mirroringSuggestionUsesBundleIdentityWithoutExactTitle() {
    #expect(MirroringWindowSuggestion.score(mirroringWindow) == 100)
    let unrelated = CaptureWindow(
        id: 43, title: "Notes", applicationName: "Notes",
        applicationBundleID: "com.apple.Notes", widthPoints: 420,
        heightPoints: 900, isOnScreen: true)
    #expect(MirroringWindowSuggestion.score(unrelated) == 0)
    let titleHint = CaptureWindow(
        id: 44, title: "iPhone Mirroring", applicationName: "Unknown",
        applicationBundleID: nil, widthPoints: 420,
        heightPoints: 900, isOnScreen: true)
    #expect(MirroringWindowSuggestion.score(titleHint) > 0)
}

@Test func frameDiagnosticsCountOnlyValidFramesWhileActive() {
    var diagnostics = CaptureDiagnostics()
    diagnostics.begin(window: mirroringWindow)
    let valid = CapturedFrameMetadata(
        widthPixels: 840, heightPixels: 1_800, presentationSeconds: 12.5,
        receivedAt: Date(timeIntervalSince1970: 100))
    diagnostics.receive(valid)
    diagnostics.didStart()
    diagnostics.receive(valid)
    diagnostics.receive(
        CapturedFrameMetadata(
            widthPixels: 0, heightPixels: 1_800, presentationSeconds: 13,
            receivedAt: Date(timeIntervalSince1970: 101)))
    #expect(diagnostics.frameCount == 2)
    #expect(diagnostics.latestFrame == valid)
    diagnostics.beginStop()
    diagnostics.didStop()
    diagnostics.receive(valid)
    #expect(diagnostics.frameCount == 2)
    #expect(diagnostics.state == .stopped)
}

@Test func newSessionClearsPriorErrorAndFrameCount() {
    var diagnostics = CaptureDiagnostics()
    diagnostics.begin(window: mirroringWindow)
    diagnostics.receive(
        CapturedFrameMetadata(
            widthPixels: 100, heightPixels: 100, presentationSeconds: 1,
            receivedAt: Date()))
    diagnostics.fail("Window closed")
    diagnostics.begin(window: mirroringWindow)
    #expect(diagnostics.state == .starting)
    #expect(diagnostics.frameCount == 0)
    #expect(diagnostics.latestFrame == nil)
    #expect(diagnostics.errorMessage == nil)
}

@Test func classifierReturnsFirstClassUnknownForUniformAndMalformedFrames() {
    let image = SyntheticImage(width: 96, height: 212, color: (32, 32, 32))
    let result = ScreenClassifier().classify(image.frame(id: 7))
    #expect(result.screenType == .unknown)
    #expect(result.confidence >= 0 && result.confidence <= 1)
    #expect(result.frameID == 7)
    #expect(CapturedImageFrame(width: 32, height: 32, rgbPixels: Data([0, 1]), frameID: 0, timestamp: Date()) == nil)
}

@Test func stabilizerRequiresCompatibleKnownFramesAndKeepsUnknownRaw() {
    var stabilizer = ScreenClassificationStabilizer()
    let map = syntheticClassification(.map, id: 1)
    let unknown = syntheticClassification(.unknown, id: 2)
    #expect(stabilizer.append(map) == nil)
    #expect(stabilizer.append(unknown) == nil)
    #expect(stabilizer.append(map) == .map)
    #expect(stabilizer.append(syntheticClassification(.pokemonStorage, id: 3)) == .map)
    #expect(stabilizer.append(unknown) == .map)
    #expect(stabilizer.append(syntheticClassification(.unknown, id: 4)) == .map)
    #expect(stabilizer.append(syntheticClassification(.unknown, id: 5)) == .unknown)
}

private func syntheticClassification(_ type: ScreenType, id: UInt64) -> ScreenClassification {
    ScreenClassification(
        screenType: type, confidence: 0.8,
        evidence: [.init(signal: "synthetic", strength: 0.8, explanation: "Synthetic test classification.")],
        frameID: id, timestamp: Date(timeIntervalSince1970: Double(id)))
}

private struct SyntheticImage {
    let width: Int
    let height: Int
    private var pixels: [UInt8]

    init(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) {
        self.width = width
        self.height = height
        pixels = Array(repeating: 0, count: width * height * 3)
        paint(x: 0, y: 0, width: width, height: height, color: color)
    }

    mutating func paint(x: Int, y: Int, width paintWidth: Int, height paintHeight: Int, color: (UInt8, UInt8, UInt8)) {
        for row in max(0, y)..<min(height, y + paintHeight) {
            for column in max(0, x)..<min(width, x + paintWidth) {
                let offset = (row * width + column) * 3
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
            }
        }
    }

    func frame(id: UInt64) -> CapturedImageFrame {
        CapturedImageFrame(
            width: width, height: height, rgbPixels: Data(pixels), frameID: id,
            timestamp: Date(timeIntervalSince1970: Double(id)))!
    }
}
