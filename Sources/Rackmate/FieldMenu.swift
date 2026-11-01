import RackmateCore
import SwiftUI

/// `.field`: a selector on a dark inset, which opens a menu with the current entry ticked.
struct FieldMenu<Value: Hashable & Sendable>: View {
    private static var fontSize: CGFloat { 14 }

    let title: String
    let options: [RouteOption<Value>]
    let selection: Value
    let select: (Value) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: { select($0) })) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(options.first { $0.value == selection }?.label ?? "")
                    .font(.panelText(Self.fontSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.muted)
            }
            .foregroundStyle(Color.legend)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panelDeep, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isHovered && isEnabled ? Color.lineStrong : Color.line, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }
}

/// The dark well of `.channel-display` and `.preset` under a value that opens a menu. Its border turns
/// amber on hover and red on a fault, and a value that cannot open goes quiet.
private struct DisplayButtonStyle: ButtonStyle {
    var glow = DisplayWell.Glow.digits
    var isFault = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Face(label: configuration.label, glow: glow, isFault: isFault)
    }

    private struct Face<Label: View>: View {
        let label: Label
        let glow: DisplayWell.Glow
        let isFault: Bool

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            label
                .background { DisplayWell(glow: isEnabled ? glow : .quiet, border: border) }
                .contentShape(Rectangle())
                .panelFocusOutline()
                .onHover { isHovered = $0 }
        }

        private var border: Color {
            if isHovered && isEnabled { return .led }
            return isFault ? .fault : .black
        }
    }
}

/// How wide the digits' display is, and how far they stay from its ends.
private enum DisplaySize {
    static let width: CGFloat = 78
    static let inset: CGFloat = 8
}

/// `.channel-display.audio` under its legend: Audio in, Audio out or Sidechain in. `action` gets the
/// display's frame, for the menu to open under.
struct RouteDisplay: View {
    private static let height: CGFloat = 26
    private static let digitHeight: CGFloat = 15

    let legend: String
    let text: String
    let tone: SegmentTone
    /// `.output` lines the legend up with the display at the right.
    var alignment = HorizontalAlignment.leading
    let action: (CGRect) -> Void

    @State private var anchor = CGRect.zero

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Legend(legend)
            Button { action(anchor) } label: {
                SevenSegmentView(text: text, height: Self.digitHeight, tone: tone)
                    .padding(.horizontal, DisplaySize.inset)
                    .frame(width: DisplaySize.width, height: Self.height, alignment: .trailing)
            }
            .buttonStyle(DisplayButtonStyle(isFault: tone == .fault))
            .panelMenuAnchor($anchor)
            .help(legend)
            .accessibilityLabel("\(legend): \(text.trimmingCharacters(in: .whitespaces))")
        }
    }
}

/// `.channel-display` of MIDI in: three digits and a small `CH`. It does not open with no MIDI.
struct ChannelDisplay: View {
    private static let height: CGFloat = 30
    private static let digitHeight: CGFloat = 18
    private static let labelSize: CGFloat = 10

    let text: String
    let tone: SegmentTone
    /// What VoiceOver reads for the digits.
    let spokenValue: String
    let action: (CGRect) -> Void

    @State private var anchor = CGRect.zero

    var body: some View {
        Button { action(anchor) } label: {
            HStack(spacing: 0) {
                Text("CH")
                    .font(.panelText(Self.labelSize))
                    .panelSpacing(0.08, size: Self.labelSize)
                    .foregroundStyle(Color.unitLabel)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 7)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                SevenSegmentView(text: text, height: Self.digitHeight, tone: tone)
            }
            .padding(.horizontal, DisplaySize.inset)
            .frame(width: DisplaySize.width, height: Self.height)
        }
        .buttonStyle(DisplayButtonStyle())
        .panelMenuAnchor($anchor)
        .help("MIDI channel")
        .accessibilityLabel("MIDI channel: \(spokenValue)")
    }
}

/// `.device-value`: the MIDI device in small text, or in red when it is gone.
struct DeviceValue: View {
    private static let fontSize: CGFloat = 12.5

    let text: String
    let tone: SegmentTone
    let action: (CGRect) -> Void

    @State private var anchor = CGRect.zero
    @State private var isHovered = false

    var body: some View {
        Button { action(anchor) } label: {
            Text(text)
                .font(.panelText(Self.fontSize))
                .lineLimit(tone == .fault ? 2 : 1)
                .truncationMode(.tail)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .panelMenuAnchor($anchor)
        .help("MIDI device")
        .accessibilityLabel("MIDI device: \(text)")
    }

    private var color: Color {
        switch tone {
        case .lit: isHovered ? .legend : .muted
        case .dim: .deviceNone
        case .fault: .fault
        }
    }
}

/// `.preset`: the sound of a plugin, which opens the preset menu. Without `action` it is `.preset.quiet`,
/// for a sound nobody can change now.
struct PresetDisplay: View {
    private static let height: CGFloat = 32
    private static let fontSize: CGFloat = 18

    let text: String
    var action: ((CGRect) -> Void)?

    @State private var anchor = CGRect.zero

    var body: some View {
        if let action {
            Button { action(anchor) } label: {
                row {
                    Text("▼").font(.panelText(9)).padding(.trailing, 2).accessibilityHidden(true)
                }
                .foregroundStyle(Color.led)
            }
            .buttonStyle(DisplayButtonStyle(glow: .preset))
            .panelMenuAnchor($anchor)
        } else {
            row { EmptyView() }
                .foregroundStyle(Color.presetQuiet)
                .background { DisplayWell(glow: .quiet) }
        }
    }

    private func row(@ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.panelDisplay(Self.fontSize))
                .panelSpacing(0.04, size: Self.fontSize)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
    }
}

private extension Color {
    static let unitLabel = Color(hex: 0xA8703D)
    static let deviceNone = Color(hex: 0x75746B)
    static let presetQuiet = Color(hex: 0x8B7A66)
}
