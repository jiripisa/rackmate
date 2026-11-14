import Foundation
import Testing
@testable import RackmateCore

@Suite("ControlLearning")
struct ControlLearningTests {
    private let a = PluginLocation(channel: UUID())
    private let b = PluginLocation(channel: UUID(), effect: UUID())

    @Test func aKnobBeforeAnyTouchLearnsNothing() {
        var learning = ControlLearning()
        learning.start(at: a)
        #expect(learning.receive(.fixture()) == nil)
    }

    @Test func touchThenKnobMakesAMapping() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.touch(at: a, parameter: 3, name: "Cutoff")
        let learned = learning.receive(.fixture())
        #expect(learned?.location == a)
        #expect(learned?.mapping == ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff", from: 0, to: 1))
        #expect(learning.pending(at: a) == nil)
        #expect(learning.isOn(at: a))
    }

    @Test func aTouchWithLearnOffIsIgnored() {
        var learning = ControlLearning()
        learning.touch(at: a, parameter: 3, name: "Cutoff")
        #expect(learning.pending(at: a) == nil)
    }

    @Test func aLaterTouchReplacesThePendingParameter() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.touch(at: a, parameter: 3, name: "Cutoff")
        learning.touch(at: a, parameter: 4, name: "Resonance")
        #expect(learning.receive(.fixture())?.mapping.parameter == 4)
    }

    @Test func aKnobHeardBeforeATouchDoesNotCompleteIt() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.touch(at: a, parameter: 3, name: "Cutoff")
        let earlier = learning.touch(at: a, parameter: 4, name: "Resonance", after: .fixture())
        #expect(earlier?.location == a)
        #expect(earlier?.mapping.parameter == 3)
        #expect(learning.pending(at: a)?.parameter == 4)
    }

    @Test func aKnobHeardBeforeTheFirstTouchIsDropped() {
        var learning = ControlLearning()
        learning.start(at: a)
        #expect(learning.touch(at: a, parameter: 3, name: "Cutoff", after: .fixture()) == nil)
        #expect(learning.pending(at: a)?.parameter == 3)
    }

    @Test func aKnobHeardBeforeATouchGoesToTheNewestPendingWindow() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.start(at: b)
        learning.touch(at: b, parameter: 2, name: "Two")
        let earlier = learning.touch(at: a, parameter: 1, name: "One", after: .fixture())
        #expect(earlier?.location == b)
        #expect(learning.pending(at: a)?.parameter == 1)
        #expect(learning.pending(at: b) == nil)
    }

    @Test func theNewestPendingWindowTakesTheKnob() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.start(at: b)
        learning.touch(at: a, parameter: 1, name: "One")
        learning.touch(at: b, parameter: 2, name: "Two")
        #expect(learning.receive(.fixture())?.location == b)
        #expect(learning.receive(.fixture())?.location == a)
    }

    @Test func stoppingDropsThePendingParameter() {
        var learning = ControlLearning()
        learning.start(at: a)
        learning.touch(at: a, parameter: 3, name: "Cutoff")
        learning.stop(at: a)
        #expect(learning.receive(.fixture()) == nil)
        #expect(!learning.isAnyOn)
    }
}
