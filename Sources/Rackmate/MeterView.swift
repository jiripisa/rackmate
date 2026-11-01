import RackmateAudio
import RackmateCore
import SwiftUI

/// What moves on a channel: its two meter bars and its LED. One poll of the render core feeds them 15
/// times a second, and only the views that show them read these, so nothing around them redraws.
@MainActor
@Observable
final class ChannelActivity {
    private static let pollInterval = Duration.seconds(1.0 / 15)
    /// The bar spans this many dB below full scale.
    private static let range: Float = 60
    /// How far a bar falls per poll once the signal has dropped, so a short peak stays readable.
    private static let fall: Float = 0.08

    private(set) var left: Float = 0
    private(set) var right: Float = 0
    private(set) var isLit = false

    @ObservationIgnored private var light = ActivityLight()

    /// An instrument's LED follows the MIDI that reaches it, a standalone effect's its signal. Runs
    /// until the task is cancelled.
    func poll(channel: UUID, kind: PluginKind, audio: AudioSession?) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            let peaks = Self.read(channel: channel, audio: audio)
            let targets = (left: Self.position(peaks.left), right: Self.position(peaks.right))
            let now = ContinuousClock.now
            let lit: Bool
            if kind == .effect {
                lit = light.update(hasSignal: targets.left > 0 || targets.right > 0, at: now)
            } else {
                lit = light.update(eventCount: audio?.router.eventCount(channel: channel) ?? 0, at: now)
            }
            show(left: Self.follow(left, target: targets.left), right: Self.follow(right, target: targets.right), isLit: lit)
        }
    }

    /// Writes only what changed, as every write wakes the views that read it.
    private func show(left: Float, right: Float, isLit: Bool) {
        if left != self.left { self.left = left }
        if right != self.right { self.right = right }
        if isLit != self.isLit { self.isLit = isLit }
    }

    /// A channel that is not in the graph has no meter activity.
    private static func read(channel: UUID, audio: AudioSession?) -> (left: Float, right: Float) {
        guard let audio, let strip = audio.runner?.meterStrip(channel: channel) else { return (0, 0) }
        return audio.engine.readMeters(strip: strip)
    }

    /// Where a peak sits on the bar, from 0 at the bottom of its range to 1.
    private static func position(_ peak: Float) -> Float {
        peak > 0 ? min(max((20 * log10(peak) + range) / range, 0), 1) : 0
    }

    private static func follow(_ shown: Float, target: Float) -> Float {
        target >= shown ? target : max(target, shown - fall)
    }
}

/// `.position .led`.
struct ActivityLED: View {
    let activity: ChannelActivity

    var body: some View {
        LED(tone: activity.isLit ? .on : .off)
    }
}

/// `.meter`: two rows of segments, L over R.
struct MeterView: View {
    let activity: ChannelActivity

    var body: some View {
        VStack(spacing: 3) {
            row("L", level: \.left)
            row("R", level: \.right)
        }
        .accessibilityHidden(true)
    }

    private func row(_ label: String, level: KeyPath<ChannelActivity, Float>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.panelText(10))
                .foregroundStyle(Color.muted)
                .frame(width: 9, alignment: .leading)
            MeterBar(activity: activity, level: level)
        }
        .frame(height: 13)
    }
}

/// `.meter-bar`: green, then yellow from 68 %, red from 88 %, each segment 4 points with a gap of 1.
private struct MeterBar: View {
    private static let height: CGFloat = 7
    private static let segment: CGFloat = 4
    private static let gap: CGFloat = 1
    private static let yellowFrom: CGFloat = 0.68
    private static let redFrom: CGFloat = 0.88

    let activity: ChannelActivity
    let level: KeyPath<ChannelActivity, Float>

    var body: some View {
        // Read here and not in the canvas, whose closure runs outside this body.
        let level = CGFloat(activity[keyPath: level])
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                let width = min(Self.segment, size.width - x)
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(.meterUnlit))
                let lit = min(width, size.width * level - x)
                if lit > 0 {
                    context.fill(Path(CGRect(x: x, y: 0, width: lit, height: size.height)), with: .color(Self.color(at: x / size.width)))
                }
                x += Self.segment + Self.gap
            }
        }
        .frame(height: Self.height)
    }

    private static func color(at position: CGFloat) -> Color {
        if position >= redFrom { return .fault }
        return position >= yellowFrom ? .meterYellow : .meterGreen
    }
}

private extension Color {
    static let meterUnlit = Color(hex: 0x2E2F2C)
    static let meterGreen = Color(hex: 0x52D65C)
    static let meterYellow = Color(hex: 0xE9E04A)
}
