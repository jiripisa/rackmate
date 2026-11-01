import CoreGraphics
import Testing
@testable import RackmateCore

struct EffectDragScrollTests {
    private let top: CGFloat = 60
    private let bottom: CGFloat = 700

    private func step(_ pointerY: CGFloat) -> CGFloat {
        EffectDragScroll.step(pointerY: pointerY, top: top, bottom: bottom)
    }

    @Test func theMiddleOfTheRackStaysStill() {
        #expect(step(380) == 0)
    }

    @Test func nearTheTopItScrollsUp() {
        #expect(step(top + 10) < 0)
    }

    @Test func nearTheBottomItScrollsDown() {
        #expect(step(bottom - 10) > 0)
    }

    @Test func thePaceIsTheSameAcrossTheBand() {
        #expect(step(bottom - 39) == step(bottom - 1))
        #expect(step(top + 39) == step(top + 1))
    }

    @Test func bothDirectionsRunAtOnePace() {
        #expect(step(top + 10) == -step(bottom - 10))
    }

    @Test func theBandEndsFortyPointsInside() {
        #expect(step(top + 40) != 0)
        #expect(step(top + 40.5) == 0)
        #expect(step(bottom - 40) != 0)
        #expect(step(bottom - 40.5) == 0)
    }

    /// The pointer may run over the top bar or off the window while it is still near the edge.
    @Test func theBandReachesFortyPointsPastTheEdge() {
        #expect(step(top - 40) < 0)
        #expect(step(top - 40.5) == 0)
        #expect(step(bottom + 40) > 0)
        #expect(step(bottom + 40.5) == 0)
    }
}
