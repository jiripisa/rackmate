import Testing
@testable import RackmateCore

@Suite("Takeover")
struct TakeoverTests {
    /// `#expect` cannot call a mutating method, so the call goes through here.
    private func take(_ takeover: inout Takeover, knob: UInt8, currentFraction: Double, from: Double, to: Double) -> Bool {
        takeover.follow(knob: knob, currentFraction: currentFraction, from: from, to: to)
    }

    @Test func waitsUntilTheKnobCrossesTheValue() {
        var takeover = Takeover()
        #expect(!take(&takeover, knob: 10, currentFraction: 0.5, from: 0, to: 1))
        #expect(!take(&takeover, knob: 40, currentFraction: 0.5, from: 0, to: 1))
        #expect(take(&takeover, knob: 70, currentFraction: 0.5, from: 0, to: 1))   // crossed 63.5
        #expect(take(&takeover, knob: 20, currentFraction: 0.9, from: 0, to: 1))   // follows from now on
    }

    @Test func landingOnTheValueTakesOver() {
        var takeover = Takeover()
        #expect(take(&takeover, knob: 64, currentFraction: 0.5, from: 0, to: 1))
    }

    @Test func rearmWaitsAgain() {
        var takeover = Takeover()
        _ = takeover.follow(knob: 64, currentFraction: 0.5, from: 0, to: 1)
        takeover.rearm()
        #expect(!take(&takeover, knob: 0, currentFraction: 0.5, from: 0, to: 1))
    }

    @Test func rearmForgetsThePreviousKnobValue() {
        var takeover = Takeover()
        _ = takeover.follow(knob: 40, currentFraction: 0.5, from: 0, to: 1)
        takeover.rearm()
        // Without the forgotten 40, 70 has no earlier position to cross from.
        #expect(!take(&takeover, knob: 70, currentFraction: 0.5, from: 0, to: 1))
    }

    @Test func aValueOutsideTheRangeTakesOverAtTheNearerEnd() {
        var takeover = Takeover()   // range 0–50 %, parameter at 90 %: the end at knob 127
        #expect(!take(&takeover, knob: 100, currentFraction: 0.9, from: 0, to: 0.5))
        #expect(take(&takeover, knob: 127, currentFraction: 0.9, from: 0, to: 0.5))
    }

    @Test func anInvertedRangeTakesOverWhereItsValueIs() {
        var takeover = Takeover()   // 60 % → 10 %, parameter at 35 %: knob 63.5
        #expect(!take(&takeover, knob: 0, currentFraction: 0.35, from: 0.6, to: 0.1))
        #expect(take(&takeover, knob: 80, currentFraction: 0.35, from: 0.6, to: 0.1))
    }

    @Test func anInvertedRangeClampsAValueOutsideItToTheNearerEnd() {
        var takeover = Takeover()   // 60 % → 10 %, parameter at 90 %: clamps to 60 %, knob 0
        #expect(!take(&takeover, knob: 50, currentFraction: 0.9, from: 0.6, to: 0.1))
        #expect(take(&takeover, knob: 0, currentFraction: 0.9, from: 0.6, to: 0.1))
    }

    @Test func equalEndsTakeOverAtTheFirstMove() {
        var takeover = Takeover()
        #expect(take(&takeover, knob: 5, currentFraction: 0.9, from: 0.4, to: 0.4))
    }
}
