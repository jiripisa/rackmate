import Testing
@testable import RackmateCore

@Suite("ControlMapping")
struct ControlMappingTests {
    @Test func aKnobReadsAsDeviceChannelAndController() {
        #expect(ControlKnob(source: "OXI E16", channel: 1, controller: 74).label == "OXI E16 · CH 1 · CC 74")
    }

    @Test func percentagesAreWholeAndClamped() {
        var mapping = ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff")
        #expect(mapping.fromPercent == 0 && mapping.toPercent == 100)
        mapping.fromPercent = 30
        mapping.toPercent = 140
        #expect(mapping.from == 0.3 && mapping.to == 1)
        mapping.to = 0.704
        #expect(mapping.toPercent == 70)
    }

    @Test func learningTheSameKnobAndParameterKeepsTheRange() {
        var slot = PluginSlot.fixture()
        var first = ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff")
        first.fromPercent = 30
        slot.learn(first)
        slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
        #expect(slot.controls == [first])
    }

    @Test func oneKnobCanDriveSeveralParameters() {
        var slot = PluginSlot.fixture()
        slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
        slot.learn(ControlMapping(knob: .fixture(), parameter: 4, parameterName: "Mix"))
        #expect(slot.controls.map(\.parameter) == [3, 4])
    }
}
