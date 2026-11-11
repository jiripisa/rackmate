import AppKit
import RackmateCore
import SwiftUI

/// Below this the picture on a slot leaves the room to the name.
private let slotWidthForPicture: CGFloat = 150

/// `.chain`: the stages of a channel left to right, joined by arrows, with the plus at the end. The
/// chain scrolls sideways when its stages do not fit at their smallest.
struct EffectChainView: View {
    private static let addButton = "add"

    let channel: Channel

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ChainLayout(width: width - 2) {
                    ForEach(channel.effects, id: \.first?.id) { row in
                        EffectStage(channel: channel.id, row: row)
                            .layoutValue(key: StageIsParallel.self, value: row.count > 1)
                        ChainArrow()
                    }
                    AddEffectButton {
                        model.beginAddEffect(channel: channel.id)
                    } didUnfold: {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(Self.addButton, anchor: .trailing) }
                    }
                    .id(Self.addButton)
                    .reportsFrame(of: .add(channel: channel.id))
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .reportsFrame(of: .chain(channel: channel.id))
        }
    }
}

/// Lays the chain out as `.chain` does as a flex row, centered in its height. A stage says so with
/// `StageIsParallel`, and everything else keeps its own width.
private struct ChainLayout: Layout {
    private static let gap: CGFloat = 4

    /// What the chain has, as the scroll view around it offers no width.
    let width: CGFloat

    private func widths(of subviews: Subviews) -> [CGFloat] {
        let others = subviews.filter { $0[StageIsParallel.self] == nil }.map { $0.sizeThatFits(.unspecified).width }
        let free = width - others.reduce(0, +) - Self.gap * CGFloat(max(subviews.count - 1, 0))
        var stages = PanelLayout.stageWidths(isParallel: subviews.compactMap { $0[StageIsParallel.self] }, in: free).makeIterator()
        var rest = others.makeIterator()
        return subviews.map { $0[StageIsParallel.self] == nil ? rest.next() ?? 0 : stages.next() ?? 0 }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let widths = widths(of: subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + Self.gap * CGFloat(max(subviews.count - 1, 0)), height: max(height, proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(of: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
            x += width + Self.gap
        }
    }
}

private struct StageIsParallel: LayoutValueKey {
    static let defaultValue: Bool? = nil
}

/// `.stage`: one effect, or up to three in parallel between two brackets.
private struct EffectStage: View {
    let channel: UUID
    let row: [InsertEffect]

    private var isParallel: Bool { row.count > 1 }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(row) { effect in
                EffectSlot(channel: channel, effect: effect)
            }
        }
        .padding(.horizontal, isParallel ? 12 : 0)
        .background {
            if isParallel { StageBrackets().stroke(Color.lineStrong, lineWidth: 1) }
        }
        .reportsFrame(of: row.first.map { .stage(first: $0.id) })
    }
}

/// `.stage.parallel::before` and `::after`, whose legs reach in towards the effects.
private struct StageBrackets: Shape {
    private static let outset: CGFloat = 1.5
    private static let leg: CGFloat = 8.5
    private static let height: CGFloat = 19.5

    func path(in rect: CGRect) -> Path {
        // On pixel centers, so the 1 pt stroke stays sharp.
        let top = rect.minY + Self.height
        let bottom = rect.maxY - Self.height
        let left = rect.minX + Self.outset
        let right = rect.maxX - Self.outset
        var path = Path()
        path.addLines([CGPoint(x: left + Self.leg, y: top), CGPoint(x: left, y: top), CGPoint(x: left, y: bottom), CGPoint(x: left + Self.leg, y: bottom)])
        path.addLines([CGPoint(x: right - Self.leg, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), CGPoint(x: right - Self.leg, y: bottom)])
        return path
    }
}

/// `.arrow`.
private struct ChainArrow: View {
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addLines([CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)])
            path.addLines([CGPoint(x: rect.maxX - 4, y: rect.midY - 4), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX - 4, y: rect.midY + 4)])
            return path
        }
    }

    var body: some View {
        Line()
            .stroke(Color.lineStrong, lineWidth: 1)
            .frame(width: 15, height: 9)
            .accessibilityHidden(true)
    }
}

/// What an effect looks like, in its slot and on the ghost a drag carries.
struct EffectLook {
    let effect: InsertEffect
    let isFailed: Bool
    let isOpen: Bool
    let showsPicture: Bool

    fileprivate var name: String { effect.slot.displayName }

    fileprivate var nameColor: Color {
        if isFailed { return .fault }
        if !effect.isOn { return .effectOff }
        return isOpen ? .legend : .led
    }

    fileprivate var led: LED.Tone {
        if isFailed { return .fault }
        return effect.isOn ? .on : .off
    }
}

/// `.fx`: the box, with the sidechain under the controls.
private struct SlotCard<Controls: View>: View {
    private static var corner: CGFloat { 3 }

    let look: EffectLook
    var border = Color.black
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) { controls }
                .frame(height: 38)
                .padding(.leading, 8)
                .padding(.trailing, 3)
            if let source = look.effect.sidechainIn {
                Text("Sidechain from \(source.label(prefix: "In"))")
                    .font(.panelText(11.5))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(1)
        .background {
            RoundedRectangle(cornerRadius: Self.corner).fill(LinearGradient(colors: [.slotTop, .slotBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay { RoundedRectangle(cornerRadius: Self.corner).strokeBorder(border, lineWidth: 1) }
        .background {
            RoundedRectangle(cornerRadius: Self.corner).fill(Color.slotEdge).offset(y: 1)
        }
    }
}

/// `.fx-open`: the small picture, hidden in a narrow slot, and the name.
private struct SlotName: View {
    private static let fontSize: CGFloat = 17
    /// The bars span 14 of the art's 17 units and end 2 above its bottom, so at this side they stand
    /// exactly as tall as the capitals, on the same baseline.
    private static let pictureSide: CGFloat = 15.5
    /// Where the bars end, from the picture's top, on a whole pixel so both edges meet the capitals.
    /// Nonisolated: the alignment guide reads it from a Sendable closure.
    nonisolated private static let pictureBaseline: CGFloat = 13.5

    let look: EffectLook

    var body: some View {
        // On one baseline and as tall as the capitals: DIN Condensed sits high in its line box.
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if look.showsPicture {
                PluginGlyph(kind: .slot, slotSide: Self.pictureSide)
                    .alignmentGuide(.firstTextBaseline) { _ in Self.pictureBaseline }
            }
            Text(look.name)
                .font(.panelDisplay(Self.fontSize))
                .panelSpacing(0.03, size: Self.fontSize)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(look.nameColor)
        .offset(y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// One effect of a stage. A click on the name opens or closes its plugin, and a drag from the name
/// moves it. An effect that failed does neither, and says why in its tooltip.
private struct EffectSlot: View {
    let channel: UUID
    let effect: InsertEffect

    @Environment(AppModel.self) private var model
    @Environment(EffectDrag.self) private var drag
    @State private var isHovered = false
    @State private var showsPicture = true
    @GestureState private var isDragged = false

    private var failure: String? { model.audio?.runner?.failure(effect: effect.id) }
    private var isFailed: Bool { failure != nil }
    private var isOpen: Bool { model.pluginWindows.isOpen(channel: channel, effect: effect.id) }
    private var name: String { effect.slot.displayName }

    private var look: EffectLook {
        EffectLook(effect: effect, isFailed: isFailed, isOpen: isOpen, showsPicture: showsPicture)
    }

    private var border: Color {
        if isFailed { return .fault }
        return isHovered ? .lineStrong : .black
    }

    var body: some View {
        SlotCard(look: look, border: border) {
            nameButton
            EffectSwitch(name: name, tone: look.led, isOn: effect.isOn, isFailed: isFailed) {
                model.setEffect(channel: channel, effect: effect.id, isOn: !effect.isOn)
            }
            EffectMenuButton(name: name) { anchor in
                model.showEffectMenu(channel: channel, effect: effect.id, anchor: anchor)
            }
        }
        // Keeps its contents in place while the plus makes the stages move.
        .geometryGroup()
        .opacity(drag.source?.effect.id == effect.id ? 0.35 : 1)
        .onHover { isHovered = $0 }
        .onGeometryChange(for: Bool.self, of: { $0.size.width >= slotWidthForPicture }) { showsPicture = $0 }
        .reportsFrame(of: .slot(effect.id))
        .onChange(of: isDragged) { _, dragged in
            if !dragged { drag.end() }
        }
        .onDisappear {
            if drag.source?.effect.id == effect.id { drag.end() }
        }
    }

    private var nameButton: some View {
        Button { model.pluginWindows.toggle(channel: channel, effect: effect.id) } label: {
            SlotName(look: look)
                .contentShape(Rectangle())
        }
        .buttonStyle(SlotControlStyle())
        .panelFocusOutline(outset: 0)
        .disabled(isFailed)
        .highPriorityGesture(dragging, including: isFailed ? .none : .all)
        .pointerStyle(isFailed ? .default : .grabIdle)
        .help(failure ?? "\(name): \(isOpen ? "close" : "open") plugin")
        .accessibilityLabel(failure.map { "\(name). \($0)" } ?? name)
    }

    private var dragging: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(EffectDrag.mixerSpace))
            .updating($isDragged) { _, isDragged, _ in isDragged = true }
            .onChanged { value in
                guard let configuration = model.session?.configuration else { return }
                drag.move(look, to: value.location, in: configuration)
            }
            .onEnded { value in
                let landing = model.session?.configuration.landing(of: effect.id, at: value.location, frames: drag.frames)
                drag.end()
                if let landing { model.moveEffect(effect.id, to: landing.drop) }
            }
    }
}

/// The controls of a slot have no press state, and the name stays red when it is disabled.
private struct SlotControlStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
    }
}

/// `.fx-switch`: the LED is the switch.
private struct EffectSwitch: View {
    let name: String
    let tone: LED.Tone
    let isOn: Bool
    let isFailed: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            LED(tone: tone)
                .frame(width: 22, height: 22)
                .background { Circle().fill(isHovered && !isFailed ? Color.slotSwitchHover : .clear) }
                .contentShape(Circle())
        }
        .buttonStyle(SlotControlStyle())
        .panelFocusOutline(outset: 0)
        .disabled(isFailed)
        .onHover { isHovered = $0 }
        .help(isFailed ? "Failed to load" : isOn ? "Turn effect off" : "Turn effect on")
        .accessibilityLabel("\(name) effect")
        .accessibilityValue(isFailed ? "Failed to load" : isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// `.fx-more`: the three dots.
private struct EffectMenuButton: View {
    let name: String
    let action: (CGRect) -> Void

    @State private var isHovered = false
    @State private var anchor = CGRect.zero

    var body: some View {
        Button { action(anchor) } label: {
            MoreGlyph()
                .foregroundStyle(isHovered ? Color.legend : Color.muted)
                .frame(width: 18, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(SlotControlStyle())
        .panelFocusOutline(outset: 0)
        .onHover { isHovered = $0 }
        .help("Menu")
        .accessibilityLabel("\(name) menu")
        .panelMenuAnchor($anchor)
    }
}

/// `.add-fx`: a round plus that unfolds into a labelled button on hover or keyboard focus.
struct AddEffectButton: View {
    let action: () -> Void
    /// So a chain that scrolls can keep the wider button in view.
    let didUnfold: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button("Add effect", action: action)
            .buttonStyle(AddEffectStyle(isFocused: isFocused, didUnfold: didUnfold))
            .focused($isFocused)
            // Its title reaches VoiceOver only while it can be seen.
            .accessibilityLabel("Add effect")
    }
}

private struct AddEffectStyle: ButtonStyle {
    let isFocused: Bool
    let didUnfold: () -> Void

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Face(label: configuration.label, isFocused: isFocused, didUnfold: didUnfold)
    }

    private struct Face<Label: View>: View {
        private static var foldedSize: CGFloat { 34 }
        private static var unfoldedWidth: CGFloat { 126 }
        private static var fontSize: CGFloat { 12.5 }

        let label: Label
        let isFocused: Bool
        let didUnfold: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false
        @State private var isUnfolded = false

        private var corner: CGFloat { isUnfolded ? 3 : Self.foldedSize / 2 }

        var body: some View {
            HStack(spacing: 0) {
                PlusGlyph()
                    .frame(width: Self.foldedSize - 2, height: Self.foldedSize - 2)
                    .accessibilityHidden(true)
                label
                    .font(.panelText(Self.fontSize))
                    .panelSpacing(0.06, size: Self.fontSize)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(isUnfolded ? 1 : 0)
            }
            .foregroundStyle(isUnfolded ? Color.legend : Color.muted)
            .padding(.leading, 1)
            .frame(width: isUnfolded ? Self.unfoldedWidth : Self.foldedSize, height: Self.foldedSize, alignment: .leading)
            .background { face.clipped() }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay { RoundedRectangle(cornerRadius: corner).strokeBorder(isUnfolded ? Color.addBorder : Color.line, lineWidth: 1) }
            .contentShape(Rectangle())
            .overlay {
                if isFocused { Rectangle().strokeBorder(Color.led, lineWidth: 2).padding(-2) }
            }
            .onHover { isHovered = $0 }
            // Moves as one, while the stages beside it make room.
            .geometryGroup()
            .onChange(of: isHovered || isFocused) { _, unfolded in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isUnfolded = unfolded
                } completion: {
                    if unfolded { didUnfold() }
                }
            }
        }

        private var face: some View {
            LinearGradient(colors: [.addTop, .addBottom], startPoint: .top, endPoint: .bottom).opacity(isUnfolded ? 1 : 0)
        }
    }
}

/// A drag of an effect across the mixer: what is dragged, where the pointer is and where the effect
/// would land. Only the slots of a drag and `EffectDragLayer` look at this, so a drag redraws them
/// alone. The landing itself is worked out by `Configuration.landing`.
@MainActor
@Observable
final class EffectDrag {
    /// The coordinate space of everything a drag works with, which reaches over all the units.
    static let mixerSpace = "mixer"

    struct Source {
        var look: EffectLook
        var width: CGFloat

        var effect: InsertEffect { look.effect }
    }

    private(set) var source: Source?
    private(set) var pointer = CGPoint.zero
    private(set) var landing: EffectLanding?

    /// Where everything is, kept up to date while the mixer moves. Nothing is drawn from this, so
    /// a scroll does not redraw the mixer.
    @ObservationIgnored private(set) var frames: [EffectPart: CGRect] = [:]
    /// Where the rack has scrolled to, also not drawn from.
    @ObservationIgnored var rackGeometry: ScrollGeometry?

    func move(_ look: EffectLook, to point: CGPoint, in configuration: Configuration) {
        if source == nil {
            source = Source(look: look, width: frames[.slot(look.effect.id)]?.width ?? 0)
            NSCursor.closedHand.push()
        }
        pointer = point
        landing = configuration.landing(of: look.effect.id, at: point, frames: frames)
    }

    /// Takes the new `frames`. The rack can scroll under a pointer that stands still, so what the
    /// pointer is over is looked up again.
    func place(_ frames: [EffectPart: CGRect], in configuration: Configuration?) {
        self.frames = frames
        guard let source, let configuration else { return }
        landing = configuration.landing(of: source.effect.id, at: pointer, frames: frames)
    }

    func end() {
        guard source != nil else { return }
        source = nil
        landing = nil
        NSCursor.pop()
    }
}

/// `.fx-ghost` and `#drop-mark`, over everything in the mixer.
struct EffectDragLayer: View {
    private static let ghostOffset: CGFloat = 8

    @Environment(EffectDrag.self) private var drag

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let landing = drag.landing {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.led)
                    .shadow(color: .led, radius: 3)
                    .frame(width: landing.mark.width, height: landing.mark.height)
                    .offset(x: landing.mark.minX, y: landing.mark.minY)
            }
            if let source = drag.source {
                SlotCard(look: source.look) {
                    SlotName(look: source.look)
                    LED(tone: source.look.led).frame(width: 22, height: 22)
                    MoreGlyph().foregroundStyle(Color.muted).frame(width: 18, height: 26)
                }
                .frame(width: source.width)
                .shadow(color: .ghostShadow, radius: 12, y: 10)
                .offset(x: drag.pointer.x + Self.ghostOffset, y: drag.pointer.y + Self.ghostOffset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The frames of the parts of the effects columns, in the mixer's coordinate space.
struct EffectFramesKey: PreferenceKey {
    static let defaultValue: [EffectPart: CGRect] = [:]

    static func reduce(value: inout [EffectPart: CGRect], nextValue: () -> [EffectPart: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Tells a drag of an effect where this view is. With no part it tells nothing.
    func reportsFrame(of part: EffectPart?) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: EffectFramesKey.self, value: part.map { [$0: proxy.frame(in: .named(EffectDrag.mixerSpace))] } ?? [:])
            }
        }
    }
}

private extension Color {
    static let slotTop = Color(hex: 0x1B1C1E)
    static let slotBottom = Color(hex: 0x141517)
    static let slotEdge = Color(hex: 0xFFFFFF, alpha: 0x14)
    static let slotSwitchHover = Color(hex: 0xFFFFFF, alpha: 0x14)
    /// `.fx.off .fx-open`.
    static let effectOff = Color(hex: 0x75746B)
    static let addTop = Color(hex: 0x303134)
    static let addBottom = Color(hex: 0x212225)
    static let addBorder = Color(hex: 0x6F6E67)
    static let ghostShadow = Color(hex: 0x000000, alpha: 0xBB)
}
