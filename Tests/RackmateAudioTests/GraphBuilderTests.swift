import AudioToolbox
import CRenderCore
import Foundation
import RackmateCore
import Testing
@testable import RackmateAudio

/// Never rendered or dereferenced: the builder only passes units along.
private func fakeUnit(_ address: Int, channels: UInt32 = 2) -> GraphUnit {
    GraphUnit(unit: AudioUnit(bitPattern: address)!, channels: channels)
}

private let slot = PluginSlot(plugin: PluginID(type: "aufx", subtype: "test", manufacturer: "Test"), displayName: "Test")
private let out01 = AudioChannels.stereo(left: 0, right: 1)

private func channel(
    audioIn: AudioChannels? = nil, sidechainIn: AudioChannels? = nil, audioOut: AudioChannels = out01,
    effects: [[InsertEffect]] = []
) -> Channel {
    Channel(kind: .effect, slot: slot, audioIn: audioIn, sidechainIn: sidechainIn, audioOut: audioOut, effects: effects)
}

private func effect(sidechainIn: AudioChannels? = nil, isOn: Bool = true) -> InsertEffect {
    InsertEffect(slot: slot, sidechainIn: sidechainIn, isOn: isOn)
}

@Suite("Graph builder")
struct GraphBuilderTests {
    private let builder = GraphBuilder(deviceInputs: 4, deviceOutputs: 4)

    @Test("A strip carries the routes, units and MIDI slot of its channel")
    func stripCarriesChannel() {
        let inserted = effect(sidechainIn: .mono(3))
        let source = channel(audioIn: .stereo(left: 0, right: 1), sidechainIn: .mono(2), audioOut: .stereo(left: 2, right: 3), effects: [[inserted]])
        let strips = builder.strips(
            for: [source], units: [source.id: fakeUnit(16, channels: 1), inserted.id: fakeUnit(32)], midiSlots: [source.id: 7]
        )
        #expect(strips == [
            GraphStrip(
                channel: source.id, source: fakeUnit(16, channels: 1), audioIn: .stereo(left: 0, right: 1), sidechain: .mono(2),
                rows: [[GraphEffect(unit: fakeUnit(32), sidechain: .mono(3))]], audioOut: .stereo(left: 2, right: 3), midiSlot: 7
            )
        ])
    }

    @Test("Strips keep the order of the channels")
    func stripsKeepChannelOrder() {
        let first = channel()
        let second = channel()
        let strips = builder.strips(for: [first, second], units: [first.id: fakeUnit(16), second.id: fakeUnit(32)], midiSlots: [:])
        #expect(strips.map(\.channel) == [first.id, second.id])
    }

    @Test("A channel without a unit has no strip, whatever its effects")
    func noUnitNoStrip() {
        let inserted = effect()
        let waiting = channel(effects: [[inserted]])
        #expect(builder.strips(for: [waiting], units: [inserted.id: fakeUnit(16)], midiSlots: [:]).isEmpty)
    }

    @Test("A channel whose output is not on the device has no strip")
    func outputBeyondDeviceHasNoStrip() {
        let partly = channel(audioOut: .stereo(left: 3, right: 4))
        let beyond = channel(audioOut: .mono(4))
        let strips = builder.strips(for: [partly, beyond], units: [partly.id: fakeUnit(16), beyond.id: fakeUnit(32)], midiSlots: [:])
        #expect(strips.isEmpty)
    }

    @Test("An input that is not on the device is off and the strip stays")
    func inputBeyondDeviceIsOff() {
        let inserted = effect(sidechainIn: .mono(4))
        let source = channel(audioIn: .stereo(left: 3, right: 4), sidechainIn: .mono(9), effects: [[inserted]])
        let strips = builder.strips(for: [source], units: [source.id: fakeUnit(16), inserted.id: fakeUnit(32)], midiSlots: [:])
        #expect(strips.count == 1)
        #expect(strips.first?.audioIn == nil)
        #expect(strips.first?.sidechain == nil)
        #expect(strips.first?.rows == [[GraphEffect(unit: fakeUnit(32), sidechain: nil)]])
    }

    @Test("An effect without a unit leaves its row, and an empty row goes")
    func missingEffectsAreLeftOut() {
        let kept = effect()
        let gone = effect()
        let alone = effect()
        let last = effect()
        let source = channel(effects: [[gone, kept], [alone], [last]])
        let strips = builder.strips(
            for: [source], units: [source.id: fakeUnit(16), kept.id: fakeUnit(32), last.id: fakeUnit(48)], midiSlots: [:]
        )
        #expect(strips.first?.rows == [
            [GraphEffect(unit: fakeUnit(32), sidechain: nil)],
            [GraphEffect(unit: fakeUnit(48), sidechain: nil)],
        ])
    }

    @Test("An effect that is off leaves a series chain")
    func anOffEffectInSeriesLeavesTheChain() {
        let before = effect()
        let off = effect(isOn: false)
        let after = effect()
        let source = channel(effects: [[before], [off], [after]])
        let strips = builder.strips(
            for: [source], units: [source.id: fakeUnit(16), before.id: fakeUnit(32), off.id: fakeUnit(48), after.id: fakeUnit(64)], midiSlots: [:]
        )
        #expect(strips.first?.rows == [
            [GraphEffect(unit: fakeUnit(32), sidechain: nil)],
            [GraphEffect(unit: fakeUnit(64), sidechain: nil)],
        ])
    }

    @Test("An effect that is off leaves its parallel stage")
    func anOffEffectLeavesItsParallelStage() {
        let kept = effect()
        let off = effect(isOn: false)
        let source = channel(effects: [[kept, off]])
        let strips = builder.strips(for: [source], units: [source.id: fakeUnit(16), kept.id: fakeUnit(32), off.id: fakeUnit(48)], midiSlots: [:])
        #expect(strips.first?.rows == [[GraphEffect(unit: fakeUnit(32), sidechain: nil)]])
    }

    @Test("A stage whose effects are all off is dropped")
    func aStageAllOffIsDropped() {
        let first = effect(isOn: false)
        let second = effect(isOn: false)
        let kept = effect()
        let source = channel(effects: [[first, second], [kept]])
        let strips = builder.strips(
            for: [source], units: [source.id: fakeUnit(16), first.id: fakeUnit(32), second.id: fakeUnit(48), kept.id: fakeUnit(64)], midiSlots: [:]
        )
        #expect(strips.first?.rows == [[GraphEffect(unit: fakeUnit(64), sidechain: nil)]])
    }

    @Test("A channel with every effect off keeps its strip and plays dry")
    func aChannelWithEveryEffectOffPlaysDry() {
        let first = effect(isOn: false)
        let second = effect(isOn: false)
        let source = channel(effects: [[first], [second]])
        let strips = builder.strips(for: [source], units: [source.id: fakeUnit(16), first.id: fakeUnit(32), second.id: fakeUnit(48)], midiSlots: [:])
        #expect(strips.count == 1)
        #expect(strips.first?.rows == [])
    }

    @Test("Strips keep their order when effects go off")
    func stripOrderDoesNotChangeWhenEffectsGoOff() {
        var first = channel(effects: [[effect()]])
        let second = channel()
        let third = channel()
        let units = [first.id: fakeUnit(16), first.effects[0][0].id: fakeUnit(32), second.id: fakeUnit(48), third.id: fakeUnit(64)]
        let on = builder.strips(for: [first, second, third], units: units, midiSlots: [:])
        first.effects[0][0].isOn = false
        let off = builder.strips(for: [first, second, third], units: units, midiSlots: [:])
        #expect(on.map(\.channel) == off.map(\.channel))
        #expect(on[0].rows.count == 1 && off[0].rows.isEmpty)
        #expect(Array(on.dropFirst()) == Array(off.dropFirst()))
    }

    @Test("The output is reported first, then the inputs in signal order")
    func missingRouteOrder() {
        let insertBeyond = effect(sidechainIn: .mono(6))
        #expect(builder.missingRoute(of: channel()) == nil)
        #expect(builder.missingRoute(of: channel(audioIn: .mono(3), sidechainIn: .mono(2), audioOut: .mono(3))) == nil)
        #expect(builder.missingRoute(of: channel(audioIn: .mono(9), audioOut: .stereo(left: 14, right: 15))) == "Out 15–16")
        #expect(builder.missingRoute(of: channel(audioIn: .mono(9), sidechainIn: .mono(5))) == "In 10")
        #expect(builder.missingRoute(of: channel(audioIn: .stereo(left: 3, right: 4))) == "In 4–5")
        #expect(builder.missingRoute(of: channel(sidechainIn: .mono(5), effects: [[insertBeyond]])) == "In 6")
        #expect(builder.missingRoute(of: channel(effects: [[effect()], [effect(), insertBeyond]])) == "In 7")
        #expect(builder.missingRoute(of: channel(effects: [[effect(sidechainIn: .mono(6), isOn: false)]])) == nil)
    }

    @Test("C strips hold every value and point at their own rows")
    func cStrips() {
        let strips = [
            GraphStrip(
                channel: UUID(), source: fakeUnit(16), audioIn: nil, sidechain: .mono(1),
                rows: [[GraphEffect(unit: fakeUnit(32), sidechain: nil)], [GraphEffect(unit: fakeUnit(48, channels: 1), sidechain: .stereo(left: 2, right: 3)), GraphEffect(unit: fakeUnit(64), sidechain: nil)]],
                audioOut: .stereo(left: 4, right: 5), midiSlot: 9
            ),
            GraphStrip(channel: UUID(), source: fakeUnit(80, channels: 1), audioIn: .stereo(left: 6, right: 7), sidechain: nil, rows: [], audioOut: .mono(2), midiSlot: nil),
            GraphStrip(
                channel: UUID(), source: fakeUnit(96), audioIn: nil, sidechain: nil,
                rows: [[GraphEffect(unit: fakeUnit(112), sidechain: nil)]], audioOut: .stereo(left: 0, right: 1), midiSlot: 0
            ),
        ]
        GraphBuilder.withCStrips(strips) { cStrips in
            #expect(cStrips.count == 3)
            let first = cStrips[0]
            #expect(first.source == fakeUnit(16).unit && first.sourceChannels == 2)
            #expect((first.audioIn.left, first.audioIn.right) == (-1, -1))
            #expect((first.sidechain.left, first.sidechain.right) == (1, -1))
            #expect((first.audioOut.left, first.audioOut.right) == (4, 5))
            #expect(first.midiSlot == 9)
            #expect(first.rowCount == 2)
            #expect(first.rows[0].count == 1)
            #expect(first.rows[0].effects[0].unit == fakeUnit(32).unit)
            #expect(first.rows[0].effects[0].sidechain.left == -1)
            #expect(first.rows[1].count == 2)
            #expect(first.rows[1].effects[0].unit == fakeUnit(48).unit && first.rows[1].effects[0].channels == 1)
            #expect((first.rows[1].effects[0].sidechain.left, first.rows[1].effects[0].sidechain.right) == (2, 3))
            #expect(first.rows[1].effects[1].unit == fakeUnit(64).unit && first.rows[1].effects[1].channels == 2)

            let second = cStrips[1]
            #expect(second.sourceChannels == 1)
            #expect((second.audioIn.left, second.audioIn.right) == (6, 7))
            #expect((second.audioOut.left, second.audioOut.right) == (2, -1))
            #expect(second.midiSlot == -1)
            #expect(second.rowCount == 0)

            let third = cStrips[2]
            #expect(third.midiSlot == 0)
            #expect(third.rowCount == 1)
            #expect(third.rows[0].effects[0].unit == fakeUnit(112).unit)
        }
    }

    @Test("No strips still give a call with an empty list")
    func noStrips() {
        var count: Int?
        GraphBuilder.withCStrips([]) { count = $0.count }
        #expect(count == 0)
    }
}
