import RackmateAudio
import RackmateCore
import SwiftUI

/// The main screen: the top bar over the rack, whose units scroll when they do not fit. The vent takes
/// the height left under the last unit.
struct MixerScreen: View {
    let model: AppModel

    @State private var effectDrag = EffectDrag()
    @State private var meters = MeterTicker()

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            GeometryReader { viewport in
                RackScrollView {
                    VStack(spacing: 5) {
                        ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                            ChannelUnit(channel: channel, index: index, activity: meters.activity(of: channel.id))
                        }
                        AddRow { model.beginAddChannel() }
                        VentUnit()
                    }
                    .padding(.vertical, 5)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
                .reportsFrame(of: .rack)
            }
        }
        .coordinateSpace(.named(EffectDrag.mixerSpace))
        .overlay(alignment: .topLeading) { EffectDragLayer() }
        .onPreferenceChange(EffectFramesKey.self) { [effectDrag, model] frames in
            MainActor.assumeIsolated { effectDrag.place(frames, in: model.session?.configuration) }
        }
        .task { [meters, model] in await meters.run(model: model) }
        .environment(model)
        .environment(effectDrag)
    }

    private var channels: [Channel] { model.session?.configuration.channels ?? [] }
}

/// The units' scroll view, which moves by itself while an effect is dragged near its top or bottom
/// edge. The position lives here, so those steps do not redraw the mixer.
private struct RackScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(EffectDrag.self) private var drag
    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { [drag] _, geometry in
                drag.rackGeometry = geometry
            }
            .task(id: drag.source != nil) {
                while drag.source != nil, !Task.isCancelled {
                    scrollStep()
                    try? await Task.sleep(for: EffectDragScroll.interval)
                }
            }
    }

    private func scrollStep() {
        guard let rack = drag.frames[.rack], let geometry = drag.rackGeometry else { return }
        let step = EffectDragScroll.step(pointerY: drag.pointer.y, top: rack.minY, bottom: rack.maxY)
        let start = -geometry.contentInsets.top
        let end = max(start, geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
        let offset = min(max(geometry.contentOffset.y + step, start), end)
        if offset != geometry.contentOffset.y { position.scrollTo(y: offset) }
    }
}

/// `.add-row`, on a unit of its own.
private struct AddRow: View {
    private static let fontSize: CGFloat = 13

    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        RackUnit {
            Button(action: action) {
                HStack(spacing: 14) {
                    PlusGlyph()
                        .frame(width: 28, height: 28)
                        .overlay { Circle().strokeBorder(color, lineWidth: 1) }
                        .accessibilityHidden(true)
                    Text("Add instrument or effect")
                        .font(.panelText(Self.fontSize))
                        .panelSpacing(0.14, size: Self.fontSize)
                        .textCase(.uppercase)
                }
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isHovered ? Color.lineStrong : Color.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelFocusOutline()
            .onHover { isHovered = $0 }
            .padding(.vertical, 12)
            .padding(.horizontal, 34)
        }
    }

    private var color: Color { isHovered ? .legend : .muted }
}

/// `.topbar`.
private struct TopBar: View {
    let model: AppModel

    @State private var anchor = CGRect.zero

    var body: some View {
        RackTopBar {
            configurationMenu
            saveState.fixedSize()
            Spacer(minLength: 0)
            if let audio = model.audio {
                AudioFaults(audio: audio)
                ClockReadout(router: audio.router, source: model.settings.clockSource)
                CPUReadout(engine: audio.engine)
            }
            RackDivider()
            IconKey(symbol: .settings, isOn: false, help: "Settings", size: 30) { model.showSettings() }
        }
    }

    private var name: String {
        guard let name = model.session?.configuration.name, !name.isEmpty else { return "New rack" }
        return name
    }

    private var configurationMenu: some View {
        Button {
            model.showConfigurationMenu(anchor: anchor)
        } label: {
            HStack(spacing: 7) {
                RackTitle(text: name)
                    .truncationMode(.tail)
                Text("▾")
                    .font(.panelText(14))
                    .foregroundStyle(Color.muted)
                    .offset(y: -2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelFocusOutline(outset: 2)
        .help(name)
        .panelMenuAnchor($anchor)
        // Takes the free space beside it first, and gives way only to what has to stay whole.
        .layoutPriority(1)
    }

    @ViewBuilder private var saveState: some View {
        if let session = model.session {
            if session.isDirty {
                Text("Unsaved changes").font(.panelText(13)).foregroundStyle(Color.muted)
                Button("Save") { model.saveCurrent() }.buttonStyle(.key).panelFocusOutline()
            } else if session.isSaved {
                Text("Saved").font(.panelText(13)).foregroundStyle(Color.muted)
                // An open plugin window may hold a change the configuration has not heard of yet.
                if model.hasOpenPluginWindows {
                    Button("Save") { model.saveIfChanged() }.buttonStyle(.key).panelFocusOutline()
                }
            }
        }
    }
}

/// `.readout`.
private struct Readout<Lead: View>: View {
    let text: String
    @ViewBuilder let lead: Lead
    var color = Color.muted

    var body: some View {
        HStack(spacing: 6) {
            lead
            Text(text)
        }
        .font(.panelText(13))
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Why nothing is playing, or nothing comes in, when something is wrong with the audio device. Waiting
/// for the owner's answer is not a fault, so it stays in the muted color.
struct AudioFaults: View {
    let audio: AudioSession

    var body: some View {
        if case .waitingForMicrophone = audio.engine.state {
            Readout(text: "Waiting for microphone access") { LED(tone: .off) }
        }
        if case .deviceMissing = audio.engine.state {
            Readout(text: "Audio device missing", lead: { LED(tone: .fault) }, color: .fault)
        }
        if audio.startFailure != nil {
            Readout(text: "Audio could not start", lead: { LED(tone: .fault) }, color: .fault)
                .help(audio.startFailure ?? "")
        }
        if audio.engine.inputPermissionDenied {
            Readout(text: "Microphone access denied, inputs are silent", lead: { LED(tone: .fault) }, color: .fault)
        }
    }
}

private struct ClockReadout: View {
    let router: MIDIRouter
    let source: String?

    var body: some View {
        if router.clockRunning, let source {
            Readout(text: "\(source) clock, \(String(format: "%.1f", router.tempo)) BPM") {
                BeatLED(tempo: router.tempo)
            }
        } else {
            Readout(text: "No MIDI clock") { LED(tone: .off) }
        }
    }
}

/// `.led.beat`: lit for half of each beat.
private struct BeatLED: View {
    let tempo: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let half = 30 / max(tempo, 1)
        TimelineView(.periodic(from: .now, by: half)) { timeline in
            let lit = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate / half) % 2 == 0
            LED().opacity(lit ? 1 : 0.15)
        }
    }
}

/// Polls the engine's load itself, so the screen around it does not redraw.
private struct CPUReadout: View {
    let engine: AudioEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Readout(text: "CPU \(Int((engine.dspLoad * 100).rounded())) %") { EmptyView() }
        }
    }
}
