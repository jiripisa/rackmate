import Foundation

/// One line of a menu on the panel, `.menu` of `ui-prototype/styles.css`.
public enum MenuEntry<Action> {
    case legend(String)
    case hint(String)
    case separator
    case item(String, action: Action, isCurrent: Bool = false, isEnabled: Bool = true)
    /// `.channel-grid` and `.route-grid`: lines side by side, read row by row.
    case grid(columns: Int, cells: [MenuCell<Action>])

    public func map<Other>(_ transform: (Action) -> Other) -> MenuEntry<Other> {
        switch self {
        case .legend(let text): .legend(text)
        case .hint(let text): .hint(text)
        case .separator: .separator
        case .item(let title, let action, let isCurrent, let isEnabled):
            .item(title, action: transform(action), isCurrent: isCurrent, isEnabled: isEnabled)
        case .grid(let columns, let cells):
            .grid(columns: columns, cells: cells.map { MenuCell($0.title, action: transform($0.action), isCurrent: $0.isCurrent) })
        }
    }
}

extension MenuEntry: Equatable where Action: Equatable {}
extension MenuEntry: Sendable where Action: Sendable {}

/// One line of a grid.
public struct MenuCell<Action> {
    public var title: String
    public var action: Action
    public var isCurrent: Bool

    public init(_ title: String, action: Action, isCurrent: Bool = false) {
        self.title = title
        self.action = action
        self.isCurrent = isCurrent
    }
}

extension MenuCell: Equatable where Action: Equatable {}
extension MenuCell: Sendable where Action: Sendable {}

public enum ConfigurationMenuAction: Equatable, Sendable {
    case load(UUID)
    case new
    case saveAs
}

public enum EffectMenuAction: Equatable, Sendable {
    case togglePlugin
    case toggleEffect
    case presets
    case sidechain
    case toggleFollowsTransport
    case addParallel(row: Int)
    case moveToSeries
    case remove
}

public enum PresetMenuAction: Equatable, Sendable {
    case saved(Preset)
    case factory(String)
    case save
}

/// What the menus of a plugin and a channel hold, `fxMenuHtml`, `presetMenuHtml`, `sidechainMenuHtml`,
/// `midiChannelMenuHtml`, `midiDeviceMenuHtml` and `routeMenuHtml` of `ui-prototype/app.js`.
public enum PluginMenus {

    /// `sidechain` is what the plugin's sidechain input reads, nil when it has none. A plugin that
    /// does not run has no window and no sound to pick, but its place in the chain can still change.
    /// One that failed can only go.
    public static func effect(
        rowSize: Int, rowIndex: Int, isOpen: Bool, isHosted: Bool, isOn: Bool, isFailed: Bool, presetLabel: String, sidechain: String?,
        followsTransport: Bool
    ) -> [MenuEntry<EffectMenuAction>] {
        if isFailed { return [.item("Remove", action: .remove)] }
        var entries: [MenuEntry<EffectMenuAction>] = [
            .item(isOpen ? "Close plugin" : "Open plugin", action: .togglePlugin, isEnabled: isHosted),
            .item(isOn ? "Turn effect off" : "Turn effect on", action: .toggleEffect),
            .item("Presets: \(presetLabel)", action: .presets, isEnabled: isHosted),
        ]
        if let sidechain { entries.append(.item("Sidechain in: \(sidechain)", action: .sidechain)) }
        entries.append(.item("Follow Start/Stop: \(followsTransport ? "On" : "Off")", action: .toggleFollowsTransport))
        entries.append(.separator)
        if rowSize < Channel.maxParallel { entries.append(.item("Add parallel effect", action: .addParallel(row: rowIndex))) }
        if rowSize > 1 { entries.append(.item("Move to series", action: .moveToSeries)) }
        entries.append(.item("Remove", action: .remove))
        return entries
    }

    /// The Default sound is only offered when adding. `current` is the name of the slot's preset.
    public static func presets(saved: [Preset], factory: [String], current: String?) -> [MenuEntry<PresetMenuAction>] {
        var entries: [MenuEntry<PresetMenuAction>] = [.legend("My presets")]
        if saved.isEmpty {
            entries.append(.hint("None saved yet"))
        } else {
            entries += saved.map { .item($0.name, action: .saved($0), isCurrent: $0.name == current) }
        }
        entries.append(.separator)
        if factory.isEmpty {
            entries.append(.hint("This plugin keeps its factory sounds in its own window. Open it, choose a sound and save it here."))
        } else {
            entries.append(.legend("Factory presets"))
            entries += factory.map { .item($0, action: .factory($0), isCurrent: $0 == current) }
            entries.append(.separator)
        }
        entries.append(.item("Save as preset", action: .save))
        return entries
    }

    /// The configurations to load, the current one marked, then New rack and Save as.
    public static func configurations(_ configurations: [Configuration], current: UUID?) -> [MenuEntry<ConfigurationMenuAction>] {
        [.legend("Load rack")]
            + configurations.map { .item($0.name, action: .load($0.id), isCurrent: $0.id == current) }
            + [.separator, .item("New rack", action: .new), .item("Save as", action: .saveAs)]
    }

    /// Off, then the device's inputs. A sidechain the configuration holds stays listed.
    public static func sidechain(deviceInputs: Int, current: AudioChannels?) -> [MenuEntry<AudioChannels?>] {
        let options = ChannelOptions.inputs(deviceInputs: deviceInputs, allowsOff: true, current: current)
        return [.legend("Sidechain in")] + options.map { .item($0.label, action: $0.value, isCurrent: $0.value == current) }
    }

    /// All, then the sixteen channels in a grid of four.
    public static func midiChannel(current: MIDIChannelFilter) -> [MenuEntry<MIDIChannelFilter>] {
        let options = ChannelOptions.midiChannels
        return [.legend("MIDI channel")]
            + options.prefix(1).map { .item($0.label, action: $0.value, isCurrent: $0.value == current) }
            + [grid(columns: 4, options.dropFirst(), current: current)]
    }

    /// No MIDI, then the system's sources. A source the channel holds stays listed.
    public static func midiDevice(sources: [String], current: String?) -> [MenuEntry<String?>] {
        let options = ChannelOptions.midiSources(sources, current: current)
        let items = options.map { MenuEntry<String?>.item($0.label, action: $0.value, isCurrent: $0.value == current) }
        return [.legend("MIDI device")] + items.prefix(1) + (items.count > 1 ? [.separator] : []) + items.dropFirst()
    }

    /// Audio in and sidechain in: Off as a line of its own, then the routes in two columns.
    public static func audioIn(legend: String, deviceInputs: Int, allowsOff: Bool, current: AudioChannels?) -> [MenuEntry<AudioChannels?>] {
        let options = ChannelOptions.inputs(deviceInputs: deviceInputs, allowsOff: allowsOff, current: current)
        return [.legend(legend)]
            + options.filter { $0.value == nil }.map { .item($0.label, action: nil, isCurrent: current == nil) }
            + [grid(columns: 2, options.filter { $0.value != nil }, current: current)]
    }

    public static func audioOut(deviceOutputs: Int, current: AudioChannels) -> [MenuEntry<AudioChannels>] {
        [.legend("Audio out"), grid(columns: 2, ChannelOptions.outputs(deviceOutputs: deviceOutputs, current: current), current: current)]
    }

    private static func grid<Value>(columns: Int, _ options: some Sequence<RouteOption<Value>>, current: Value) -> MenuEntry<Value> {
        .grid(columns: columns, cells: options.map { MenuCell($0.label, action: $0.value, isCurrent: $0.value == current) })
    }
}
