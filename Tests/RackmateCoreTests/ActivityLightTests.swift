import Testing
@testable import RackmateCore

struct ActivityLightTests {
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    @Test func theFirstCountIsNotAnEvent() {
        var light = ActivityLight()
        let isLit = light.update(eventCount: 120, at: at(0))
        #expect(!isLit)
    }

    @Test func aMovedCountLightsIt() {
        var light = ActivityLight()
        _ = light.update(eventCount: 3, at: at(0))
        let isLit = light.update(eventCount: 4, at: at(66))
        #expect(isLit)
    }

    @Test func itHoldsFor100Milliseconds() {
        var light = ActivityLight()
        _ = light.update(eventCount: 3, at: at(0))
        _ = light.update(eventCount: 4, at: at(66))
        let justBefore = light.update(eventCount: 4, at: at(165))
        let atTheEnd = light.update(eventCount: 4, at: at(166))
        #expect(justBefore)
        #expect(!atTheEnd)
    }

    @Test func aCountThatStaysLeavesItDark() {
        var light = ActivityLight()
        _ = light.update(eventCount: 3, at: at(0))
        let isLit = light.update(eventCount: 3, at: at(66))
        #expect(!isLit)
    }

    /// The count restarts at zero when a channel loses its route.
    @Test func aCountThatFallsAlsoMoved() {
        var light = ActivityLight()
        _ = light.update(eventCount: 3, at: at(0))
        let isLit = light.update(eventCount: 0, at: at(66))
        #expect(isLit)
    }

    @Test func signalLightsItAndItHoldsAfterTheSignalEnds() {
        var light = ActivityLight()
        let during = light.update(hasSignal: true, at: at(0))
        let justAfter = light.update(hasSignal: false, at: at(99))
        let later = light.update(hasSignal: false, at: at(100))
        #expect(during)
        #expect(justAfter)
        #expect(!later)
    }

    @Test func signalThatGoesOnKeepsItLit() {
        var light = ActivityLight()
        let readings = stride(from: 0, through: 660, by: 66).map { light.update(hasSignal: true, at: at($0)) }
        #expect(readings.allSatisfy { $0 })
    }

    @Test func noSignalLeavesItDark() {
        var light = ActivityLight()
        let isLit = light.update(hasSignal: false, at: at(0))
        #expect(!isLit)
    }
}
