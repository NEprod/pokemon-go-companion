import Foundation
import GOCompanionScreenAnalysis
import Testing

private func observed(_ type: ScreenType, _ id: UInt64, confidence: Double = 0.8) -> ScreenClassification {
    ScreenClassification(
        screenType: type, confidence: confidence,
        evidence: [.init(signal: "test", strength: confidence, explanation: "Deterministic temporal input.")],
        frameID: id, timestamp: Date(timeIntervalSince1970: Double(id)))
}

@Test func detailSurvivesThreeAmbiguousFramesAndRecovers() {
    var stabilizer = ScreenClassificationStabilizer()
    #expect(stabilizer.append(observed(.pokemonDetail, 1)) == nil)
    #expect(stabilizer.append(observed(.pokemonDetail, 2)) == .pokemonDetail)
    for count in 1...3 {
        let raw = observed(.unknown, UInt64(count + 2), confidence: 0.25)
        #expect(raw.screenType == .unknown)
        #expect(stabilizer.append(raw) == .pokemonDetail)
        #expect(
            stabilizer.continuity
                == .retaining(screen: .pokemonDetail, ambiguousFrames: count, allowance: 3))
    }
    #expect(stabilizer.append(observed(.pokemonDetail, 6)) == .pokemonDetail)
    #expect(stabilizer.continuity == .none)
}

@Test func persistentUnknownExpiresEstablishedDetail() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.pokemonDetail, 1))
    _ = stabilizer.append(observed(.pokemonDetail, 2))
    for id in 3...5 { #expect(stabilizer.append(observed(.unknown, UInt64(id), confidence: 0.25)) == .pokemonDetail) }
    #expect(stabilizer.append(observed(.unknown, 6, confidence: 0.25)) == .unknown)
    #expect(stabilizer.continuity == .expired)
    #expect(stabilizer.append(observed(.unknown, 7, confidence: 0.25)) == .unknown)
    #expect(stabilizer.continuity == .expired)
}

@Test func detailTransitionsToMapOnTwoPositiveFrames() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.pokemonDetail, 1))
    _ = stabilizer.append(observed(.pokemonDetail, 2))
    #expect(stabilizer.append(observed(.map, 3)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.map, 4)) == .map)
    #expect(stabilizer.continuity == .none)
}

@Test func detailTransitionsToMoreSpecificAppraisal() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.pokemonDetail, 1))
    _ = stabilizer.append(observed(.pokemonDetail, 2))
    #expect(stabilizer.append(observed(.appraisal, 3)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.appraisal, 4)) == .appraisal)
}

@Test func mapTransitionsToMoreSpecificNearby() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.map, 1))
    _ = stabilizer.append(observed(.map, 2))
    #expect(stabilizer.append(observed(.nearby, 3)) == .map)
    #expect(stabilizer.append(observed(.nearby, 4)) == .nearby)
}

@Test func otherSupportedParentsSurviveBriefUnknown() {
    for type: ScreenType in [.items, .profile, .pokemonStorage] {
        var stabilizer = ScreenClassificationStabilizer()
        _ = stabilizer.append(observed(type, 1))
        #expect(stabilizer.append(observed(type, 2)) == type)
        #expect(stabilizer.append(observed(.unknown, 3, confidence: 0.25)) == type)
        #expect(stabilizer.append(observed(.unknown, 4, confidence: 0.25)) == type)
        #expect(stabilizer.append(observed(type, 5)) == type)
        #expect(stabilizer.continuity == .none)
    }
}

@Test func settingsLikePersistentUnknownCannotKeepOldScreenForever() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.items, 1))
    _ = stabilizer.append(observed(.items, 2))
    for id in 3...6 { _ = stabilizer.append(observed(.unknown, UInt64(id), confidence: 0.25)) }
    #expect(stabilizer.append(observed(.unknown, 7, confidence: 0.25)) == .unknown)
    #expect(stabilizer.continuity == .expired)
}

@Test func initialUnknownCannotInventSupportedScreen() {
    var stabilizer = ScreenClassificationStabilizer()
    #expect(stabilizer.append(observed(.unknown, 1, confidence: 0.25)) == nil)
    #expect(stabilizer.append(observed(.unknown, 2, confidence: 0.25)) == .unknown)
    #expect(stabilizer.append(observed(.pokemonDetail, 3)) == .unknown)
    #expect(stabilizer.append(observed(.pokemonDetail, 4)) == .pokemonDetail)
}

@Test func alternatingWeakAndUnknownEvidenceEventuallyExpires() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.pokemonDetail, 1))
    _ = stabilizer.append(observed(.pokemonDetail, 2))
    #expect(stabilizer.append(observed(.map, 3, confidence: 0.4)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.unknown, 4, confidence: 0.25)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.map, 5, confidence: 0.4)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.unknown, 6, confidence: 0.25)) == .unknown)
    #expect(stabilizer.continuity == .expired)
}

@Test func alternatingUnsupportedAndSingletonContradictionsCannotKeepStaleScreen() {
    var stabilizer = ScreenClassificationStabilizer()
    _ = stabilizer.append(observed(.pokemonDetail, 1))
    _ = stabilizer.append(observed(.pokemonDetail, 2))
    #expect(stabilizer.append(observed(.unknown, 3, confidence: 0.25)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.map, 4)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.unknown, 5, confidence: 0.25)) == .pokemonDetail)
    #expect(stabilizer.append(observed(.items, 6)) == .unknown)
}

@Test func compatibleVotesStillEstablishWithinThreeFrames() {
    var stabilizer = ScreenClassificationStabilizer()
    #expect(stabilizer.append(observed(.map, 1)) == nil)
    #expect(stabilizer.append(observed(.unknown, 2, confidence: 0.25)) == nil)
    #expect(stabilizer.append(observed(.map, 3)) == .map)
}
