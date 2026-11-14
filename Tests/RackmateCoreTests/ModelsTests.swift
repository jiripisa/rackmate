import Foundation
import Testing
@testable import RackmateCore

@Suite("Models")
struct ModelsTests {

    @Test func summaryNamesThePluginOfEachChannel() {
        var first = Channel.fixture()
        first.slot.displayName = "TB-303"
        var second = Channel.fixture(kind: .effect, effectRows: [[.fixture()]])
        second.slot.displayName = "Valhalla Reverb"
        #expect(Configuration.fixture(channels: [first, second]).summary == "TB-303, Valhalla Reverb")
    }

    @Test func summaryOfNoChannelsSaysEmpty() {
        #expect(Configuration.fixture(channels: []).summary == "Empty")
    }

    @Test func aSlotFromAnOlderFileIsNotACustomSound() throws {
        let json = #"{"plugin":{"type":"aufx","subtype":"test","manufacturer":"Test"},"displayName":"Old","state":"AQ=="}"#
        let slot = try JSONDecoder().decode(PluginSlot.self, from: Data(json.utf8))
        #expect(!slot.isCustomSound && slot.state == Data([1]))
    }

    @Test func aCustomSoundSurvivesTheFile() throws {
        var slot = PluginSlot.fixture()
        slot.isCustomSound = true
        let again = try JSONDecoder().decode(PluginSlot.self, from: JSONEncoder().encode(slot))
        #expect(again == slot)
    }

    @Test func followStartStopStartsOffOnAnInstrument() {
        #expect(!Channel.fixture(kind: .instrument).followsTransport)
        #expect(!Channel.fixture(kind: PluginKind(auType: "aumf")!).followsTransport)
    }

    @Test func followStartStopStartsOnOnAnEffect() {
        #expect(Channel.fixture(kind: .effect).followsTransport)
        #expect(Channel.fixture(kind: PluginKind(auType: "aufx")!).followsTransport)
        #expect(InsertEffect.fixture().followsTransport)
    }

    @Test func theSwitchOverridesTheDefault() {
        var instrument = Channel.fixture(kind: .instrument)
        instrument.slot.followsTransport = true
        #expect(instrument.followsTransport)

        var standalone = Channel.fixture(kind: .effect)
        standalone.slot.followsTransport = false
        #expect(!standalone.followsTransport)

        var effect = InsertEffect.fixture()
        effect.slot.followsTransport = false
        #expect(!effect.followsTransport)
    }

    @Test func aSlotFromAnOlderFileTakesTheDefault() throws {
        let json = #"{"plugin":{"type":"aufx","subtype":"test","manufacturer":"Test"},"displayName":"Old"}"#
        let slot = try JSONDecoder().decode(PluginSlot.self, from: Data(json.utf8))
        #expect(slot.followsTransport == nil)
    }

    @Test(arguments: [true, false])
    func theSwitchSurvivesTheFile(follows: Bool) throws {
        var slot = PluginSlot.fixture()
        slot.followsTransport = follows
        let again = try JSONDecoder().decode(PluginSlot.self, from: JSONEncoder().encode(slot))
        #expect(again == slot)
    }

    @Test func aSlotOnTheDefaultWritesNoSwitch() throws {
        let file = String(decoding: try JSONEncoder().encode(PluginSlot.fixture()), as: UTF8.self)
        #expect(!file.contains("followsTransport"))
    }

    @Test func anEffectFromAnOlderFileIsOn() throws {
        let effect = InsertEffect.fixture()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(effect)) as? [String: Any])
        object.removeValue(forKey: "isOn")
        let decoded = try JSONDecoder().decode(InsertEffect.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.isOn)
    }

    @Test(arguments: [true, false])
    func isOnSurvivesARoundTrip(isOn: Bool) throws {
        var effect = InsertEffect.fixture()
        effect.isOn = isOn
        let again = try JSONDecoder().decode(InsertEffect.self, from: JSONEncoder().encode(effect))
        #expect(again.isOn == isOn)
        #expect(again == effect)
    }

    @Test func aSlotFromBeforeMIDILearnHasNoControls() throws {
        let json = #"{"plugin":{"type":"aufx","subtype":"test","manufacturer":"Test"},"displayName":"Old","state":"AQ=="}"#
        #expect(try JSONDecoder().decode(PluginSlot.self, from: Data(json.utf8)).controls.isEmpty)
    }

    @Test func controlsSurviveTheFile() throws {
        var slot = PluginSlot.fixture()
        slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff", from: 0.6, to: 0.1))
        #expect(try JSONDecoder().decode(PluginSlot.self, from: JSONEncoder().encode(slot)) == slot)
    }

    @Test func movingAnEffectKeepsItsControls() {
        var effect = InsertEffect.fixture()
        effect.slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
        let other = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [
            Channel.fixture(effectRows: [[effect], [other]]), Channel.fixture(effectRows: [[InsertEffect.fixture()]]),
        ])
        let sameChannel = config.moveEffect(effect.id, to: .below(other.id))
        #expect(sameChannel)
        #expect(config.channels[0].effects[0].first { $0.id == effect.id }?.slot.controls == effect.slot.controls)
        let target = config.channels[1].effects[0][0]
        let otherChannel = config.moveEffect(effect.id, to: .after(target.id))
        #expect(otherChannel)
        #expect(config.channels[1].effects.flatMap { $0 }.first { $0.id == effect.id }?.slot.controls == effect.slot.controls)
    }

    @Test func replacingAPluginDropsItsControls() {
        var channel = Channel.fixture()
        channel.slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
        let other = PluginInfo(
            id: PluginID(type: "aumu", subtype: "Other", manufacturer: "Test"), name: "Other", vendor: "", kind: .instrument)
        #expect(AddPicker.replacing(channel, with: other, preset: .defaultSound, capabilities: nil).slot.controls.isEmpty)
    }

    @Test func pickingAPresetKeepsItsControls() {
        var slot = PluginSlot.fixture()
        slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
        let before = slot.controls
        slot.takePreset("Lead", state: Data([1]))
        #expect(slot.controls == before)
    }
}

@Suite("Plugin makers")
struct PluginMakerTests {
    private let plugin = PluginID(type: "aumu", subtype: "tb03", manufacturer: "Rlnd")

    @Test func anInstalledPluginGivesItsMaker() {
        let installed = [PluginInfo(id: plugin, name: "TB-303", vendor: "Roland", kind: .instrument)]
        #expect(installed.vendor(of: plugin) == "Roland")
    }

    @Test func aPluginWithNoMakerGivesNothing() {
        let installed = [PluginInfo(id: plugin, name: "TB-303", vendor: "", kind: .instrument)]
        #expect(installed.vendor(of: plugin) == nil)
    }

    @Test func aPluginNotInstalledGivesNothing() {
        #expect([PluginInfo]().vendor(of: plugin) == nil)
    }
}
