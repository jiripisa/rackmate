import RackmateAudio
import RackmateCore
import SwiftUI

/// The MIDI CONTROL strip under a plugin's own view: Learn, and the knobs that drive this plugin.
/// It tells its window its height, which grows with the rows up to `visibleRows` and scrolls beyond.
struct MIDIControlStrip: View {
    /// The window is at least this wide, so a row has room for its columns.
    static let minimumWidth: CGFloat = 520

    private static let visibleRows = 6
    private static let rowHeight: CGFloat = 30
    private static let knobWidth: CGFloat = 190
    private static let rangeWidth: CGFloat = 130
    private static let removeWidth: CGFloat = 18
    private static let columnGap: CGFloat = 10
    private static let fontSize: CGFloat = 14

    let model: AppModel
    let location: PluginLocation
    /// Read once when the window opened, in the plugin's order, for the fallback menu.
    let parameters: [PluginParameter]
    let onHeight: @MainActor (CGFloat) -> Void

    private let parameterIDs: Set<UInt32>

    init(model: AppModel, location: PluginLocation, parameters: [PluginParameter], onHeight: @escaping @MainActor (CGFloat) -> Void) {
        self.model = model
        self.location = location
        self.parameters = parameters
        self.onHeight = onHeight
        parameterIDs = Set(parameters.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isLearning {
                Text("Move a control in the plugin, then a knob on your controller.")
                    .font(.panelText(13))
                    .foregroundStyle(Color.led)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            if !controls.isEmpty || pending != nil {
                columnTitles.padding(.top, 10)
                rows
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
        // Its own height whatever the window offers, so the window can follow it.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.panel)
        // `panelFocusOutline` and the fields' amber border stand in for the system's ring, as in the mixer.
        .focusEffectDisabled()
    }

    private var isLearning: Bool { model.learning.isOn(at: location) }
    private var pending: (parameter: UInt32, name: String)? { model.learning.pending(at: location) }
    private var controls: [ControlMapping] { model.session?.configuration.slot(at: location)?.controls ?? [] }
    private var sources: [String] { model.audio?.router.sources ?? [] }

    private var header: some View {
        HStack(spacing: 10) {
            Button("LEARN") {
                if isLearning { model.stopLearning(at: location) } else { model.startLearning(at: location) }
            }
            .buttonStyle(isLearning ? KeyButtonStyle(isPrimary: true, primaryFace: .led) : KeyButtonStyle())
            .panelFocusOutline()
            .accessibilityAddTraits(isLearning ? .isSelected : [])
            Legend("MIDI CONTROL")
            Spacer(minLength: 0)
            if isLearning && !parameters.isEmpty { ParameterMenu(parameters: parameters) { model.pickParameter(at: location, parameter: $0) } }
        }
    }

    private var columnTitles: some View {
        HStack(spacing: Self.columnGap) {
            Legend("Parameter").frame(maxWidth: .infinity, alignment: .leading)
            Legend("Knob").frame(width: Self.knobWidth, alignment: .leading)
            Legend("Knob min → max").frame(width: Self.rangeWidth, alignment: .leading)
            Color.clear.frame(width: Self.removeWidth, height: 1)
        }
        .padding(.horizontal, 6)
    }

    private var rows: some View {
        let count = controls.count + (pending == nil ? 0 : 1)
        return ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(controls.enumerated()), id: \.element.rowID) { index, mapping in
                        row(mapping, index: index)
                    }
                    if let pending {
                        pendingRow(name: pending.name).id(Self.pendingRowID)
                    }
                }
            }
            .frame(height: CGFloat(min(count, Self.visibleRows)) * Self.rowHeight)
            .onChange(of: pending?.parameter) { _, parameter in
                if parameter != nil { scroller.scrollTo(Self.pendingRowID, anchor: .bottom) }
            }
        }
    }

    private static let pendingRowID = "pending"

    private func row(_ mapping: ControlMapping, index: Int) -> some View {
        HStack(spacing: Self.columnGap) {
            // The name comes first and is cut only when it alone does not fit; the hint gets what is left.
            HStack(spacing: 0) {
                Text(mapping.parameterName)
                    .foregroundStyle(Color.legend)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let hint = takeoverHint(for: mapping) { HintText(hint: hint) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(mapping.knob.label)
                .foregroundStyle(Color.led)
                .truncationMode(.middle)
                .frame(width: Self.knobWidth, alignment: .leading)
            HStack(spacing: 6) {
                PercentField(value: mapping.fromPercent, label: "Knob minimum") {
                    model.setControlRange(at: location, index: index, fromPercent: $0, toPercent: mapping.toPercent)
                }
                Text("→").foregroundStyle(Color.muted)
                PercentField(value: mapping.toPercent, label: "Knob maximum") {
                    model.setControlRange(at: location, index: index, fromPercent: mapping.fromPercent, toPercent: $0)
                }
            }
            .frame(width: Self.rangeWidth, alignment: .leading)
            RemoveButton { model.removeControl(at: location, index: index) }
                .frame(width: Self.removeWidth)
        }
        .modifier(RowLook(height: Self.rowHeight, fontSize: Self.fontSize))
        // The row stays, and starts working again when its device comes back.
        .opacity(isWorking(mapping) ? 1 : 0.4)
    }

    private func pendingRow(name: String) -> some View {
        HStack(spacing: Self.columnGap) {
            Text(name)
                .foregroundStyle(Color.legend)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("waiting for a knob…")
                .foregroundStyle(Color.led)
                .frame(width: Self.knobWidth + Self.columnGap + Self.rangeWidth + Self.columnGap + Self.removeWidth, alignment: .leading)
        }
        .modifier(RowLook(height: Self.rowHeight, fontSize: Self.fontSize))
        .background(Color.displayBackground)
    }

    /// Which way the row's knob has to turn to take over, as of the model's last poll. A dimmed row has
    /// none: its knob may still have a write while its device is gone.
    private func takeoverHint(for mapping: ControlMapping) -> TakeoverHint? {
        guard isWorking(mapping) else { return nil }
        let key = ControlKey(node: location.effect ?? location.channel, parameter: mapping.parameter, knob: mapping.knob)
        return model.takeoverHints[key]
    }

    /// A row does nothing while its device is gone or its plugin has no such parameter.
    private func isWorking(_ mapping: ControlMapping) -> Bool {
        // By bytes, as the router tells sources apart.
        sources.contains { $0.utf8.elementsEqual(mapping.knob.source.utf8) } && parameterIDs.contains(mapping.parameter)
    }
}

/// A takeover hint in what is left of the Parameter column after the name: the text, cut short if need
/// be, then only its arrow below `minimumTextWidth`, then nothing.
private struct HintText: View {
    let hint: TakeoverHint

    private static let gap: CGFloat = 8
    private static let minimumTextWidth: CGFloat = 40

    var body: some View {
        // The last view goes when nothing else fits, so the gap goes with the hint.
        ViewThatFits(in: .horizontal) {
            Text(text)
                .lineLimit(1)
                .frame(minWidth: Self.minimumTextWidth, idealWidth: Self.minimumTextWidth, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.gap)
            if let arrow { Text(arrow).padding(.leading, Self.gap) }
            Color.clear.frame(width: 0, height: 0)
        }
        .foregroundStyle(Color.muted)
        .accessibilityLabel(text)
    }

    private var text: String {
        switch hint {
        case .turnUp: "↑ turn up to take over"
        case .turnDown: "↓ turn down to take over"
        case .moveKnob: "move the knob to take over"
        }
    }

    private var arrow: String? {
        switch hint {
        case .turnUp: "↑"
        case .turnDown: "↓"
        case .moveKnob: nil
        }
    }
}

private extension ControlMapping {
    /// A plugin has one row for each knob and parameter.
    struct RowID: Hashable {
        var knob: ControlKnob
        var parameter: UInt32
    }

    var rowID: RowID { RowID(knob: knob, parameter: parameter) }
}

/// A line of the table, with the rule above it.
private struct RowLook: ViewModifier {
    let height: CGFloat
    let fontSize: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.panelText(fontSize))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: height)
            .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}

/// `Pick a parameter`: for a plugin that does not say which control the mouse moved.
private struct ParameterMenu: View {
    let parameters: [PluginParameter]
    let pick: (UInt32) -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(parameters, id: \.id) { parameter in
                Button(parameter.name) { pick(parameter.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Pick a parameter").font(.panelText(13))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.muted)
            }
            .foregroundStyle(Color.legend)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(Color.panelDeep, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isHovered ? Color.lineStrong : Color.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .accessibilityLabel("Pick a parameter")
    }
}

/// A whole percentage, 0 to 100, kept on Return or when the field loses the keyboard. Anything else
/// puts the value back.
private struct PercentField: View {
    let value: Int
    let label: String
    let commit: (Int) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: Int, label: String, commit: @escaping (Int) -> Void) {
        self.value = value
        self.label = label
        self.commit = commit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(apply)
                .frame(width: 26)
                .accessibilityLabel(label)
            Text("%")
        }
        .foregroundStyle(Color.led)
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .background(Color.panelDeep, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isFocused ? Color.led : Color.line, lineWidth: isFocused ? 2 : 1))
        .onChange(of: isFocused) { _, focused in
            if !focused { apply() }
        }
        .onChange(of: value) { _, value in text = String(value) }
    }

    private func apply() {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)), (0...100).contains(number) else {
            text = String(value)
            return
        }
        text = String(number)
        // The same number again is no edit, and leaves the rack saved.
        if number != value { commit(number) }
    }
}

/// `×`, which deletes its row.
private struct RemoveButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("×")
                .foregroundStyle(isHovered ? Color.legend : Color.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Delete")
    }
}
