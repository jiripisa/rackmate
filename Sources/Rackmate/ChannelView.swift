import RackmateAudio
import RackmateCore
import SwiftUI

/// `.unit`: one instrument or standalone effect, in the columns position, inputs, identity, keys,
/// effects and output. Its fields come from the plugin's capabilities, and its edits go through
/// `AppModel.edit`.
struct ChannelUnit: View {
    private static let minimumHeight: CGFloat = 132
    /// The two rows of identity, which the first input and the keys line up with. The space above them
    /// is for the legend of the first input.
    private static let rowsTop: CGFloat = 18
    private static let topRowHeight: CGFloat = 36
    private static let bottomRowHeight: CGFloat = 32
    private static let rowGap: CGFloat = 7

    let channel: Channel
    let index: Int
    let activity: ChannelActivity

    @Environment(AppModel.self) private var model

    var body: some View {
        RackUnit(tint: channel.kind == .effect ? .standalone : .plain) {
            HStack(alignment: .top, spacing: 12) {
                position
                inputs
                identity
                keys
                effects
                output
            }
            .padding(.horizontal, 14)
            // 10 and the 1 point of the plate's edge, which `RackUnit` draws over the content.
            .padding(.vertical, 11)
            .frame(minHeight: Self.minimumHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - State

    private var audio: AudioSession? { model.audio }
    private var status: ChannelStatus? { audio?.runner?.status[channel.id] }

    private var fields: ChannelFields {
        ChannelFields(channel: channel, capabilities: audio?.runner?.capabilities(channel: channel.id))
    }

    /// Only a plugin that runs has a window and a sound to pick.
    private var isHosted: Bool { audio?.runner?.plugin(channel: channel.id, effect: nil) != nil }

    private var isWindowOpen: Bool { model.pluginWindows.isOpen(channel: channel.id, effect: nil) }

    /// A fault of an effect shows on the effect, and the channel's own plugin plays on.
    private var isFaultOfAnEffect: Bool {
        guard isHosted, case .loadFailed(let message) = status else { return false }
        return channel.effects.joined().contains { audio?.runner?.failure(effect: $0.id) == message }
    }

    /// Why the plugin of the channel does not play.
    private var pluginFault: String? {
        switch status {
        case .pluginMissing: "Plugin not installed on this Mac"
        case .loadFailed(let message): isFaultOfAnEffect ? nil : "Plugin failed to load: \(message)"
        default: nil
        }
    }

    /// The route the device does not have, such as "Out 15–16".
    private var missingRoute: String? {
        if case .routingUnavailable(let label) = status { label } else { nil }
    }

    private var followsTransportHelp: String { "Follow Start/Stop: \(channel.followsTransport ? "On" : "Off")" }

    private func edit(_ change: @escaping (inout Channel) -> Void) {
        let id = channel.id
        model.edit { configuration in
            guard let position = configuration.channels.firstIndex(where: { $0.id == id }) else { return }
            change(&configuration.channels[position])
        }
    }

    // MARK: - Position

    private var position: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "%02d", index + 1))
                .font(.panelDisplay(21))
                .panelSpacing(0.05, size: 21)
                .foregroundStyle(Color.legend)
                .frame(height: 21)
            Button { model.askToRemove(channel) } label: {
                Text("×")
                    .font(.panelText(15))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RemoveButtonStyle())
            .panelFocusOutline(outset: 2)
            .padding(.leading, -5)
            .help("Remove")
            .accessibilityLabel("Remove \(channel.slot.displayName)")
            Spacer(minLength: 0)
            ActivityLED(activity: activity)
                .padding(.leading, 2)
                .help(channel.kind == .effect ? "Lights when audio comes in" : "Lights when MIDI comes in")
        }
        .frame(width: 34, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Inputs

    private var inputs: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            if fields.midiIn { midiIn }
            if fields.audioIn {
                input("Audio in", channel.audioIn, isFirst: !fields.midiIn) { anchor in
                    model.showAudioInMenu(channel: channel.id, anchor: anchor)
                }
            }
            if fields.sidechainIn {
                input("Sidechain in", channel.sidechainIn, isFirst: !fields.midiIn && !fields.audioIn) { anchor in
                    model.showSidechainInMenu(channel: channel.id, anchor: anchor)
                }
            }
        }
        .frame(width: 92, alignment: .leading)
        .padding(.top, Self.rowsTop)
    }

    /// The channel display on the picture's row and the device on the preset's. The legend sits in the
    /// space above the rows.
    private var midiIn: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            ChannelDisplay(
                text: SevenSegment.channelText(channel.midiIn), tone: channel.midiIn == nil ? .dim : .lit, spokenValue: spokenMIDIChannel
            ) { anchor in
                model.showMIDIChannelMenu(channel: channel.id, anchor: anchor)
            }
            .disabled(channel.midiIn == nil)
            .frame(height: Self.topRowHeight, alignment: .bottom)
            deviceValue
                .frame(height: Self.bottomRowHeight)
        }
        .overlay(alignment: .topLeading) {
            Legend("MIDI in")
                .fixedSize()
                .offset(y: -12)
        }
    }

    private var spokenMIDIChannel: String {
        switch channel.midiIn?.channel {
        case nil: "Off"
        case .all: "All"
        case .channel(let number): "Channel \(number)"
        }
    }

    private var deviceValue: some View {
        let isMissing = channel.midiIn.map { !(audio?.router.sources ?? []).contains($0.sourceName) } ?? false
        let name = channel.midiIn?.sourceName
        return DeviceValue(
            text: isMissing ? "\(name ?? "") is not connected" : name ?? "No MIDI",
            tone: isMissing ? .fault : name == nil ? .dim : .lit
        ) { anchor in
            model.showMIDIDeviceMenu(channel: channel.id, anchor: anchor)
        }
    }

    /// `isFirst`: the display shares its bottom edge with the picture, and its legend reaches up into
    /// the space above the rows.
    @ViewBuilder
    private func input(_ legend: String, _ route: AudioChannels?, isFirst: Bool, action: @escaping (CGRect) -> Void) -> some View {
        let display = RouteDisplay(legend: legend, text: SevenSegment.routeText(route), tone: inputTone(route), action: action)
        if isFirst {
            display.frame(height: Self.topRowHeight, alignment: .bottom)
        } else {
            display
        }
    }

    private func inputTone(_ route: AudioChannels?) -> SegmentTone {
        guard let route else { return .dim }
        return route.label(prefix: "In") == missingRoute ? .fault : .lit
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            HStack(spacing: 10) {
                PluginGlyph(kind: .init(channel.kind, isSampler: model.isSampler(channel.slot.plugin)))
                pluginName
            }
            .frame(height: Self.topRowHeight)
            soundPlace
        }
        .frame(width: 210, alignment: .leading)
        .padding(.top, Self.rowsTop)
    }

    private var pluginName: some View {
        let name = channel.slot.displayName
        // Not `textCase`, which would shout the fault at VoiceOver as well.
        return Text(name.uppercased())
            .font(.panelDisplay(31))
            .panelSpacing(0.04, size: 31)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.tail)
            .foregroundStyle(pluginFault == nil ? Color.legend : Color.fault)
            .offset(y: 1)
            .help(pluginFault ?? name)
            .accessibilityLabel(pluginFault.map { "\(name). \($0)" } ?? name)
    }

    /// The preset, or what stands in for it while there is none to pick.
    @ViewBuilder private var soundPlace: some View {
        let sound = model.presetLabel(for: channel.slot)
        switch status {
        case .pluginMissing:
            Button("Replace plugin") { model.beginReplacePlugin(channel: channel.id) }
                .buttonStyle(.wideKey)
                .panelFocusOutline()
        case .loading where !isHosted:
            PresetDisplay(text: "Loading")
        default:
            if isHosted, pluginFault == nil {
                PresetDisplay(text: sound) { anchor in
                    model.showPresetMenu(channel: channel.id, effect: nil, anchor: anchor)
                }
            } else {
                PresetDisplay(text: sound)
            }
        }
    }

    // MARK: - Keys

    private var keys: some View {
        VStack(spacing: Self.rowGap) {
            IconKey(symbol: .openPlugin, isOn: isWindowOpen, help: isWindowOpen ? "Close plugin" : "Open plugin") {
                model.pluginWindows.toggle(channel: channel.id, effect: nil)
            }
            .disabled(!isHosted)
            IconKey(symbol: .follow, isOn: channel.followsTransport, help: followsTransportHelp) {
                edit { $0.slot.followsTransport = !$0.followsTransport }
            }
        }
        .frame(width: 34)
        .padding(.top, Self.rowsTop + 1)
    }

    // MARK: - Effects

    private var effects: some View {
        VStack(alignment: .leading, spacing: 0) {
            Legend("Effects")
            EffectChainView(channel: channel)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) { Rectangle().fill(Color.line).frame(width: 1) }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.line).frame(width: 1) }
        .reportsFrame(of: .area(channel: channel.id))
    }

    // MARK: - Output

    /// A missing input lights its own display, and the words stay here for an input that has none.
    private var output: some View {
        VStack(alignment: .trailing, spacing: Self.rowGap) {
            RouteDisplay(
                legend: "Audio out", text: SevenSegment.routeText(channel.audioOut),
                tone: channel.audioOut.label(prefix: "Out") == missingRoute ? .fault : .lit, alignment: .trailing
            ) { anchor in
                model.showAudioOutMenu(channel: channel.id, anchor: anchor)
            }
            if let missingRoute { warning("\(missingRoute) is not available on this device") }
            MeterView(activity: activity)
        }
        .frame(width: 136)
        .frame(maxHeight: .infinity)
    }

    private func warning(_ text: String) -> some View {
        HStack(spacing: 6) {
            LED(tone: .fault)
            Text(text)
                .font(.panelText(12.5))
                .foregroundStyle(Color.fault)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 5)
    }
}

/// `.remove`: muted until hovered.
private struct RemoveButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Hovering { isHovered in
            configuration.label.foregroundStyle(isHovered ? Color.legend : Color.muted)
        }
    }

    private struct Hovering<Content: View>: View {
        @ViewBuilder let content: (Bool) -> Content
        @State private var isHovered = false

        var body: some View {
            content(isHovered).onHover { isHovered = $0 }
        }
    }
}
