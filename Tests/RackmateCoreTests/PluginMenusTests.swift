import Foundation
import Testing
@testable import RackmateCore

struct PluginMenusTests {
    private let plugin = PluginSlot.fixture().plugin

    private func titles<Action>(_ entries: [MenuEntry<Action>]) -> [String] {
        entries.map { entry in
            switch entry {
            case .legend(let text): "legend: \(text)"
            case .hint(let text): "hint: \(text)"
            case .separator: "---"
            case .item(let title, _, _, _): title
            case .grid(let columns, let cells): "grid \(columns): \(cells.map(\.title).joined(separator: " "))"
            }
        }
    }

    private func currentCells<Action>(_ entries: [MenuEntry<Action>]) -> [String] {
        entries.flatMap { entry -> [String] in
            guard case .grid(_, let cells) = entry else { return [] }
            return cells.filter(\.isCurrent).map(\.title)
        }
    }

    private func effectMenu(
        rowSize: Int = 1, rowIndex: Int = 0, isOpen: Bool = false, isHosted: Bool = true, isOn: Bool = true, isFailed: Bool = false,
        sidechain: String? = nil, followsTransport: Bool = true
    ) -> [MenuEntry<EffectMenuAction>] {
        PluginMenus.effect(
            rowSize: rowSize, rowIndex: rowIndex, isOpen: isOpen, isHosted: isHosted, isOn: isOn, isFailed: isFailed, presetLabel: "Default sound",
            sidechain: sidechain, followsTransport: followsTransport
        )
    }

    private func isEnabled<Action>(_ title: String, in entries: [MenuEntry<Action>]) -> Bool? {
        for case .item(let name, _, _, let enabled) in entries where name == title { return enabled }
        return nil
    }

    @Test func anEffectAloneInItsRowCanGoParallelButNotToSeries() {
        #expect(titles(effectMenu()) == ["Open plugin", "Turn effect off", "Presets: Default sound", "Follow Start/Stop: On", "---", "Add parallel effect", "Remove"])
    }

    @Test func anEffectMenuOffersTurningOff() {
        #expect(effectMenu()[1] == .item("Turn effect off", action: .toggleEffect))
    }

    @Test func anOffEffectMenuOffersTurningOn() {
        #expect(effectMenu(isOn: false)[1] == .item("Turn effect on", action: .toggleEffect))
    }

    @Test func aFailedEffectOffersOnlyRemove() {
        let menu = effectMenu(rowSize: 2, isHosted: false, isFailed: true, sidechain: "Off")
        #expect(menu == [.item("Remove", action: .remove)])
    }

    @Test func anOpenWindowOffersToCloseIt() {
        #expect(titles(effectMenu(isOpen: true)).first == "Close plugin")
    }

    @Test func aRowOfTwoOffersBothWays() {
        #expect(titles(effectMenu(rowSize: 2)) == ["Open plugin", "Turn effect off", "Presets: Default sound", "Follow Start/Stop: On", "---", "Add parallel effect", "Move to series", "Remove"])
    }

    @Test func aFullRowTakesNoMoreEffects() {
        #expect(titles(effectMenu(rowSize: Channel.maxParallel)) == ["Open plugin", "Turn effect off", "Presets: Default sound", "Follow Start/Stop: On", "---", "Move to series", "Remove"])
    }

    @Test func aPluginWithASidechainShowsItsInput() {
        #expect(titles(effectMenu(sidechain: "Off"))[3] == "Sidechain in: Off")
        #expect(titles(effectMenu(sidechain: "In 3–4"))[3] == "Sidechain in: In 3–4")
    }

    @Test func followStartStopComesAfterPresetsAndSidechainAndShowsTheSwitch() {
        #expect(titles(effectMenu(sidechain: "Off"))[2...4] == ["Presets: Default sound", "Sidechain in: Off", "Follow Start/Stop: On"])
        #expect(titles(effectMenu(followsTransport: false))[3] == "Follow Start/Stop: Off")
        #expect(effectMenu()[3] == .item("Follow Start/Stop: On", action: .toggleFollowsTransport))
    }

    @Test func addParallelNamesTheRow() {
        #expect(effectMenu(rowIndex: 4).contains { entry in
            if case .item(_, let action, _, _) = entry { return action == .addParallel(row: 4) }
            return false
        })
    }

    @Test func aPluginThatDoesNotRunCanOnlyBeMovedOrRemoved() {
        let menu = effectMenu(rowSize: 2, isHosted: false, sidechain: "Off")
        #expect(isEnabled("Open plugin", in: menu) == false)
        #expect(isEnabled("Turn effect off", in: menu) == true)
        #expect(isEnabled("Presets: Default sound", in: menu) == false)
        #expect(isEnabled("Sidechain in: Off", in: menu) == true)
        #expect(isEnabled("Follow Start/Stop: On", in: menu) == true)
        #expect(isEnabled("Add parallel effect", in: menu) == true)
        #expect(isEnabled("Move to series", in: menu) == true)
        #expect(isEnabled("Remove", in: menu) == true)
    }

    @Test func thePresetMenuOfAPluginWithoutFactoryPresetsExplainsWhere() {
        let menu = PluginMenus.presets(saved: [Preset(name: "Lead", plugin: plugin, state: Data())], factory: [], current: "Lead")
        #expect(titles(menu) == [
            "legend: My presets", "Lead", "---",
            "hint: This plugin keeps its factory sounds in its own window. Open it, choose a sound and save it here.",
            "Save as preset",
        ])
    }

    @Test func thePresetMenuListsFactoryPresetsWhenThePluginHasThem() {
        let menu = PluginMenus.presets(saved: [], factory: ["Hall", "Room"], current: "Room")
        #expect(titles(menu) == [
            "legend: My presets", "hint: None saved yet", "---", "legend: Factory presets", "Hall", "Room", "---", "Save as preset",
        ])
    }

    @Test func theCurrentPresetIsMarked() {
        let menu = PluginMenus.presets(saved: [], factory: ["Hall", "Room"], current: "Room")
        let current = menu.compactMap { entry -> String? in
            if case .item(let title, _, true, _) = entry { return title }
            return nil
        }
        #expect(current == ["Room"])
    }

    @Test func picksCarryWhatToApply() {
        let preset = Preset(name: "Lead", plugin: plugin, state: Data([1]))
        let actions = PluginMenus.presets(saved: [preset], factory: ["Hall"], current: nil).compactMap { entry -> PresetMenuAction? in
            if case .item(_, let action, _, _) = entry { return action }
            return nil
        }
        #expect(actions == [.saved(preset), .factory("Hall"), .save])
    }

    @Test func theSidechainMenuHasOffAndTheInputsWithTheCurrentOneMarked() {
        let current = AudioChannels.stereo(left: 2, right: 3)
        let menu = PluginMenus.sidechain(deviceInputs: 4, current: current)
        #expect(titles(menu) == ["legend: Sidechain in", "Off", "In 1", "In 2", "In 3", "In 4", "In 1–2", "In 3–4"])
        #expect(menu.last == .item("In 3–4", action: current, isCurrent: true))
        #expect(menu[1] == .item("Off", action: nil))
    }

    @Test func mappingAMenuKeepsItsShape() {
        let menu = PluginMenus.sidechain(deviceInputs: 1, current: nil).map { entry in entry.map { $0 == nil ? "off" : "on" } }
        #expect(menu == [.legend("Sidechain in"), .item("Off", action: "off", isCurrent: true), .item("In 1", action: "on")])
    }

    // MARK: - Channel displays

    @Test func theChannelMenuHoldsAllAboveAGridOfFour() {
        #expect(titles(PluginMenus.midiChannel(current: .all)) == [
            "legend: MIDI channel", "All", "grid 4: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16",
        ])
    }

    @Test func theChannelMenuMarksTheCurrentChannel() {
        #expect(currentCells(PluginMenus.midiChannel(current: .channel(7))) == ["7"])
        #expect(currentCells(PluginMenus.midiChannel(current: .all)).isEmpty)
        #expect(PluginMenus.midiChannel(current: .all)[1] == .item("All", action: .all, isCurrent: true))
    }

    @Test func theDeviceMenuPutsNoMIDIAboveTheSources() {
        #expect(titles(PluginMenus.midiDevice(sources: ["Hapax", "Berlinan"], current: "Hapax")) == [
            "legend: MIDI device", "No MIDI", "---", "Hapax", "Berlinan",
        ])
    }

    @Test func theDeviceMenuKeepsASourceThatIsGone() {
        let entries = PluginMenus.midiDevice(sources: ["Hapax"], current: "Launchpad")
        #expect(titles(entries).last == "Launchpad (not connected)")
        #expect(entries.last == .item("Launchpad (not connected)", action: "Launchpad", isCurrent: true))
    }

    @Test func theDeviceMenuWithoutSourcesHasNoLine() {
        #expect(titles(PluginMenus.midiDevice(sources: [], current: nil)) == ["legend: MIDI device", "No MIDI"])
    }

    @Test func anInputMenuPutsOffAboveTwoColumnsWithMonoFirst() {
        let entries = PluginMenus.audioIn(legend: "Audio in", deviceInputs: 4, allowsOff: true, current: nil)
        #expect(titles(entries) == ["legend: Audio in", "Off", "grid 2: In 1 In 2 In 3 In 4 In 1–2 In 3–4"])
        #expect(entries[1] == .item("Off", action: nil, isCurrent: true))
    }

    @Test func aStandaloneEffectsInputHasNoOff() {
        let entries = PluginMenus.audioIn(legend: "Audio in", deviceInputs: 2, allowsOff: false, current: .stereo(left: 0, right: 1))
        #expect(titles(entries) == ["legend: Audio in", "grid 2: In 1 In 2 In 1–2"])
        #expect(currentCells(entries) == ["In 1–2"])
    }

    @Test func anInputMenuKeepsARouteTheDeviceLacks() {
        let entries = PluginMenus.audioIn(legend: "Sidechain in", deviceInputs: 2, allowsOff: true, current: .mono(5))
        #expect(titles(entries) == ["legend: Sidechain in", "Off", "grid 2: In 1 In 2 In 1–2 In 6"])
        #expect(currentCells(entries) == ["In 6"])
    }

    @Test func anOutputMenuIsTwoColumnsWithPairsFirst() {
        let entries = PluginMenus.audioOut(deviceOutputs: 4, current: .mono(2))
        #expect(titles(entries) == ["legend: Audio out", "grid 2: Out 1–2 Out 3–4 Out 1 Out 2 Out 3 Out 4"])
        #expect(currentCells(entries) == ["Out 3"])
    }
}

struct ConfigurationMenuTests {
    @Test func marksTheCurrentConfigurationAndKeepsTheRest() {
        let first = Configuration.fixture(name: "First")
        let second = Configuration.fixture(name: "Second")
        let entries = PluginMenus.configurations([first, second], current: second.id)
        #expect(entries == [
            .legend("Load rack"),
            .item("First", action: .load(first.id), isCurrent: false),
            .item("Second", action: .load(second.id), isCurrent: true),
            .separator,
            .item("New rack", action: .new),
            .item("Save as", action: .saveAs),
        ])
    }
}
