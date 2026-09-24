import Foundation
import GOCompanionExtraction
import GOCompanionScreenAnalysis
import Testing

private func sample(
    _ field: ExtractionField, _ value: ExtractionValue, _ frame: UInt64,
    screen: ScreenType = .appraisal
) -> FieldObservation {
    FieldObservation(
        field: field, value: value, confidence: 0.9,
        method: [.ivAttack, .ivDefense, .ivHP].contains(field) ? .appraisalBarGeometry : .visionText,
        sourceScreen: screen, region: .displayedName, frameID: frame,
        observedAt: Date(timeIntervalSince1970: Double(frame)), evidence: "Synthetic paging observation")!
}

private func identity(_ name: String, _ cp: Int, _ hp: Int, frame: UInt64, screen: ScreenType = .appraisal)
    -> [FieldObservation]
{
    [
        sample(.displayedName, .text(name), frame, screen: screen),
        sample(.cp, .integer(cp), frame, screen: screen),
        sample(.hpCurrent, .integer(hp), frame, screen: screen),
        sample(.hpMaximum, .integer(hp), frame, screen: screen),
    ]
}

private func ivs(_ values: [Int], frame: UInt64) -> [FieldObservation] {
    zip([ExtractionField.ivAttack, .ivDefense, .ivHP], values).map { field, value in
        sample(field, .integer(value), frame)
    }
}

private func establishedWalkthrough() -> PokemonWalkthroughCoordinator {
    var walkthrough = PokemonWalkthroughCoordinator()
    for frame in 1...2 {
        walkthrough.receive(
            stableScreen: .pokemonDetail,
            observations: identity("Alpha", 2713, 138, frame: UInt64(frame), screen: .pokemonDetail)
        )
    }
    for frame in 3...4 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: identity("Alpha", 2713, 138, frame: UInt64(frame))
                + ivs([15, 11, 15], frame: UInt64(frame)))
    }
    return walkthrough
}

@Test func appraisalPagingCreatesDistinctCandidatesWithoutCrossPokemonFields() {
    var walkthrough = establishedWalkthrough()
    let firstID = walkthrough.current!.id
    walkthrough.receive(stableScreen: .appraisal, observations: ivs([14, 9, 14], frame: 5))
    #expect(walkthrough.transitionPhase == .possible)
    #expect(walkthrough.current?.id == firstID)
    #expect(walkthrough.current?.consensus.first { $0.field == .ivAttack }?.value == .integer(15))
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: identity("Beta", 2703, 164, frame: 6) + ivs([14, 9, 14], frame: 6))
    #expect(walkthrough.current?.id == firstID)
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: identity("Beta", 2703, 164, frame: 7) + ivs([14, 9, 14], frame: 7))
    #expect(walkthrough.transitionPhase == .new)
    #expect(walkthrough.candidateCount == 2)
    #expect(walkthrough.completed.first?.id == firstID)
    #expect(walkthrough.current?.id != firstID)
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .cp }?.value == .integer(2713))
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .ivAttack }?.value == .integer(15))
    #expect(walkthrough.current?.consensus.first { $0.field == .cp }?.value == .integer(2703))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivAttack }?.value == .integer(14))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivDefense }?.value == .integer(9))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivHP }?.value == .integer(14))
    #expect(walkthrough.lastRollover?.previousID == firstID)
    #expect(walkthrough.lastRollover?.nextID == walkthrough.current?.id)
}

@Test func singleFrameNameOrCPErrorCannotRollOver() {
    for error in [sample(.displayedName, .text("Alphx"), 5), sample(.cp, .integer(27), 5)] {
        var walkthrough = establishedWalkthrough()
        let id = walkthrough.current!.id
        walkthrough.receive(stableScreen: .appraisal, observations: [error])
        #expect(walkthrough.current?.id == id)
        walkthrough.receive(stableScreen: .appraisal, observations: identity("Alpha", 2713, 138, frame: 6))
        #expect(walkthrough.transitionPhase == .no)
        #expect(walkthrough.current?.id == id)
        #expect(walkthrough.candidateCount == 1)
    }
}

@Test func changedIVAloneIsQuarantinedAndCannotRollOver() {
    var walkthrough = establishedWalkthrough()
    let id = walkthrough.current!.id
    for frame in 5...9 {
        walkthrough.receive(stableScreen: .appraisal, observations: ivs([0, 0, 0], frame: UInt64(frame)))
    }
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.candidateCount == 1)
    #expect(walkthrough.quarantinedObservationCount > 0)
    #expect(walkthrough.current?.consensus.first { $0.field == .ivAttack }?.value == .integer(15))
}

@Test func mixedIdentityFramesRequireReviewNotForcedRollover() {
    var walkthrough = establishedWalkthrough()
    walkthrough.receive(stableScreen: .appraisal, observations: identity("Beta", 2703, 164, frame: 5))
    walkthrough.receive(stableScreen: .appraisal, observations: identity("Gamma", 2702, 166, frame: 6))
    #expect(walkthrough.transitionPhase == .review)
    #expect(walkthrough.candidateCount == 1)
    #expect(walkthrough.quarantinedSummary.contains { $0.contains("Beta") })
    #expect(walkthrough.quarantinedSummary.contains { $0.contains("Gamma") })
    #expect(walkthrough.current?.consensus.first { $0.field == .displayedName }?.value == .text("Alpha"))
}

@Test func repeatedSameSpecimenAndDetailMenuIntroStayOneCandidate() {
    var walkthrough = establishedWalkthrough()
    let id = walkthrough.current!.id
    walkthrough.receive(stableScreen: .map, observations: [], actionMenuVisible: true)
    walkthrough.receive(stableScreen: .appraisal, observations: [])  // Intro has no IV fields.
    for frame in 5...7 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: identity("Alpha", 2713, 138, frame: UInt64(frame))
                + ivs([15, 11, 15], frame: UInt64(frame)))
    }
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.candidateCount == 1)
    #expect(walkthrough.transitionPhase == .no)
    walkthrough.receive(stableScreen: .map, observations: [])
    #expect(walkthrough.current == nil)
    #expect(walkthrough.completed.first?.id == id)
}

@Test func pagingThreeTimesAndReturningCreatesNewTemporaryUUIDs() {
    var walkthrough = establishedWalkthrough()
    let first = walkthrough.current!.id
    for frame in 5...6 {
        walkthrough.receive(stableScreen: .appraisal, observations: identity("Beta", 2703, 164, frame: UInt64(frame)))
    }
    let second = walkthrough.current!.id
    for frame in 7...8 {
        walkthrough.receive(stableScreen: .appraisal, observations: identity("Gamma", 2300, 120, frame: UInt64(frame)))
    }
    let third = walkthrough.current!.id
    for frame in 9...10 {
        walkthrough.receive(stableScreen: .appraisal, observations: identity("Alpha", 2713, 138, frame: UInt64(frame)))
    }
    #expect(Set([first, second, third, walkthrough.current!.id]).count == 4)
    #expect(walkthrough.candidateCount == 4)
    #expect(walkthrough.completed.map(\.id) == [first, second, third])
}

@Test func animationIVsAreNotPromotedWithoutRepeatingOnNewIdentityFrames() {
    var walkthrough = establishedWalkthrough()
    // The first visually changed identity frame still has the old bar artwork.
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: identity("Beta", 2703, 164, frame: 5) + ivs([15, 11, 15], frame: 5))
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: identity("Beta", 2703, 164, frame: 6) + ivs([14, 9, 14], frame: 6))
    #expect(walkthrough.candidateCount == 2)
    #expect(walkthrough.current?.consensus.first { $0.field == .displayedName }?.value == .text("Beta"))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivAttack } == nil)
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .ivAttack }?.value == .integer(15))
}

@Test func rapidIncompatiblePagingRemainsReviewAndDoesNotInventIntermediateCandidate() {
    var walkthrough = establishedWalkthrough()
    let first = walkthrough.current!.id
    walkthrough.receive(stableScreen: .appraisal, observations: identity("Beta", 2703, 164, frame: 5))
    walkthrough.receive(stableScreen: .appraisal, observations: identity("Gamma", 2300, 120, frame: 6))
    walkthrough.receive(stableScreen: .appraisal, observations: identity("Gamma", 2300, 120, frame: 7))
    #expect(walkthrough.transitionPhase == .review)
    #expect(walkthrough.current?.id == first)
    #expect(walkthrough.candidateCount == 1)
}

@Test func recurringSingleChangedFieldRemainsBoundedAndCannotEstablishIdentity() {
    var walkthrough = establishedWalkthrough()
    let id = walkthrough.current!.id
    for frame in 5...80 {
        walkthrough.receive(
            stableScreen: .appraisal, observations: [sample(.cp, .integer(2703), UInt64(frame))])
    }
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.transitionPhase == .review)
    #expect(walkthrough.quarantinedObservationCount <= 48)
    #expect(walkthrough.candidateCount == 1)
}

private func establishedDragonite() -> PokemonWalkthroughCoordinator {
    var walkthrough = PokemonWalkthroughCoordinator()
    for frame in 1...2 {
        walkthrough.receive(
            stableScreen: .pokemonDetail,
            observations: [
                sample(.displayedName, .text("Dragonite"), UInt64(frame), screen: .pokemonDetail),
                sample(.cp, .integer(3031), UInt64(frame), screen: .pokemonDetail),
                sample(.hpCurrent, .integer(0), UInt64(frame), screen: .pokemonDetail),
                sample(.hpMaximum, .integer(156), UInt64(frame), screen: .pokemonDetail),
            ])
    }
    for frame in 3...4 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [
                sample(.displayedName, .text("Dragonite"), UInt64(frame)),
                sample(.cp, .integer(3031), UInt64(frame)),
                sample(.hpCurrent, .integer(0), UInt64(frame)),
                sample(.hpMaximum, .integer(156), UInt64(frame)),
            ] + ivs([15, 11, 11], frame: UInt64(frame)))
    }
    return walkthrough
}

@Test func sameSpeciesLiveDragoniteFingerprintRollsOverWithoutSecondCPRead() {
    var walkthrough = establishedDragonite()
    let firstID = walkthrough.current!.id
    for frame in 5...10 {
        var observations =
            [
                sample(.displayedName, .text("Dragonite"), UInt64(frame)),
                sample(.hpCurrent, .integer(155), UInt64(frame)),
                sample(.hpMaximum, .integer(155), UInt64(frame)),
            ] + ivs([15, 12, 15], frame: UInt64(frame))
        if frame == 5 { observations.append(sample(.cp, .integer(2905), UInt64(frame))) }
        walkthrough.receive(stableScreen: .appraisal, observations: observations)
    }
    #expect(walkthrough.transitionPhase == .new || walkthrough.candidateCount == 2)
    #expect(walkthrough.candidateCount == 2)
    #expect(walkthrough.completed.first?.id == firstID)
    #expect(walkthrough.current?.id != firstID)
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .cp }?.value == .integer(3031))
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .hpMaximum }?.value == .integer(156))
    #expect(walkthrough.completed.first?.consensus.first { $0.field == .ivDefense }?.value == .integer(11))
    #expect(walkthrough.current?.consensus.first { $0.field == .displayedName }?.value == .text("Dragonite"))
    #expect(walkthrough.current?.consensus.first { $0.field == .cp }?.value == .integer(2905))
    #expect(walkthrough.current?.consensus.first { $0.field == .hpCurrent }?.value == .integer(155))
    #expect(walkthrough.current?.consensus.first { $0.field == .hpMaximum }?.value == .integer(155))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivAttack }?.value == .integer(15))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivDefense }?.value == .integer(12))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivHP }?.value == .integer(15))
}

@Test func sameSpeciesSingleBadCPOrMaximumHPDoesNotRollOver() {
    for anomaly in [
        sample(.cp, .integer(2905), 5), sample(.hpMaximum, .integer(155), 5),
    ] {
        var walkthrough = establishedDragonite()
        let id = walkthrough.current!.id
        walkthrough.receive(stableScreen: .appraisal, observations: [anomaly])
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [
                sample(.displayedName, .text("Dragonite"), 6),
                sample(.cp, .integer(3031), 6),
                sample(.hpMaximum, .integer(156), 6),
            ] + ivs([15, 11, 11], frame: 6))
        #expect(walkthrough.current?.id == id)
        #expect(walkthrough.candidateCount == 1)
        #expect(walkthrough.transitionPhase == .no)
    }
}

@Test func sameSpeciesRepeatedChangedIVTupleAloneCannotRollOver() {
    var walkthrough = establishedDragonite()
    let id = walkthrough.current!.id
    for frame in 5...10 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [sample(.displayedName, .text("Dragonite"), UInt64(frame))]
                + ivs([0, 0, 0], frame: UInt64(frame)))
    }
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.candidateCount == 1)
    #expect(walkthrough.current?.consensus.first { $0.field == .ivDefense }?.value == .integer(11))
}

@Test func sameSpeciesRepeatedMaximumHPAndCompleteIVTupleRollOverWithoutCPOCR() {
    var walkthrough = establishedDragonite()
    let oldID = walkthrough.current!.id
    for frame in 5...6 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [
                sample(.displayedName, .text("Dragonite"), UInt64(frame)),
                sample(.hpMaximum, .integer(155), UInt64(frame)),
            ]
                + ivs([15, 12, 15], frame: UInt64(frame)))
    }
    #expect(walkthrough.candidateCount == 2)
    #expect(walkthrough.current?.id != oldID)
    #expect(walkthrough.current?.consensus.first { $0.field == .hpMaximum }?.value == .integer(155))
    #expect(walkthrough.current?.consensus.first { $0.field == .ivDefense }?.value == .integer(12))
}

@Test func sameSpeciesRepeatedCPAndChangedCurrentHPRequireThreeCompatibleFrames() {
    var walkthrough = establishedDragonite()
    let oldID = walkthrough.current!.id
    for frame in 5...6 {
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [
                sample(.displayedName, .text("Dragonite"), UInt64(frame)),
                sample(.cp, .integer(2905), UInt64(frame)),
                sample(.hpCurrent, .integer(155), UInt64(frame)),
                sample(.hpMaximum, .integer(156), UInt64(frame)),
            ] + ivs([15, 11, 11], frame: UInt64(frame)))
    }
    #expect(walkthrough.current?.id == oldID)
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: [sample(.cp, .integer(2905), 7), sample(.hpCurrent, .integer(155), 7)])
    #expect(walkthrough.candidateCount == 2)
    #expect(walkthrough.current?.id != oldID)
    #expect(walkthrough.current?.consensus.first { $0.field == .cp }?.value == .integer(2905))
    #expect(walkthrough.current?.consensus.first { $0.field == .hpCurrent }?.value == .integer(155))
}

@Test func sameSpeciesOneBadMaximumHPWithRepeatedIVChangeStillCannotRollOver() {
    var walkthrough = establishedDragonite()
    let id = walkthrough.current!.id
    for frame in 5...10 {
        let maximum = frame == 5 ? 155 : 156
        walkthrough.receive(
            stableScreen: .appraisal,
            observations: [sample(.hpMaximum, .integer(maximum), UInt64(frame))]
                + ivs([15, 12, 15], frame: UInt64(frame)))
    }
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.candidateCount == 1)
}

@Test func oneFrameRapidPagingFragmentsRemainQuarantined() {
    var walkthrough = establishedDragonite()
    let id = walkthrough.current!.id
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: [
            sample(.displayedName, .text("Garchomp"), 5),
            sample(.cp, .integer(2713), 5),
            sample(.hpCurrent, .integer(138), 5),
            sample(.hpMaximum, .integer(138), 5),
            sample(.ivAttack, .integer(11), 5),
        ])
    walkthrough.receive(
        stableScreen: .appraisal,
        observations: [
            sample(.displayedName, .text("Zamazenta"), 6),
            sample(.hpCurrent, .integer(68), 6),
            sample(.hpMaximum, .integer(168), 6),
        ])
    #expect(walkthrough.current?.id == id)
    #expect(walkthrough.candidateCount == 1)
    #expect(walkthrough.transitionPhase == .review)
    #expect(walkthrough.completed.isEmpty)
}
