import Foundation
import GOCompanionCapture
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
