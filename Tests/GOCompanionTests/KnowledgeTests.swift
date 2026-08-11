import Foundation
import GOCompanionKnowledge
import Testing

@Test func derivedCacheKeysIncludeAllInvalidationInputs() {
    let key = DerivedCacheKey(
        kind: "pvp_iv_table",
        subject: "lanturn:normal:1500:level50",
        inputVersions: ["game_master": "v1", "league_rules": "season-42"],
        engineVersion: "iv-engine-1"
    )
    #expect(key.inputVersions.count == 2)
    #expect(key.engineVersion == "iv-engine-1")
}
