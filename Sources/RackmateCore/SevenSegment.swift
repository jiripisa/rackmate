import Foundation

/// The seven bars of a digit, named the usual way: a on top, g in the middle, d at the bottom.
public enum Segment: CaseIterable, Sendable {
    case a, b, c, d, e, f, g
}

/// Which bars light for a character, and the text the displays show. The table is the one
/// of the UI prototype (`SEGMENT_MAP`).
public enum SevenSegment {
    static let table: [Character: Set<Segment>] = [
        "0": [.a, .b, .c, .d, .e, .f], "1": [.b, .c], "2": [.a, .b, .d, .e, .g], "3": [.a, .b, .c, .d, .g],
        "4": [.b, .c, .f, .g], "5": [.a, .c, .d, .f, .g], "6": [.a, .c, .d, .e, .f, .g], "7": [.a, .b, .c],
        "8": Set(Segment.allCases), "9": [.a, .b, .c, .d, .f, .g],
        "A": [.a, .b, .c, .e, .f, .g], "F": [.a, .e, .f, .g], "L": [.d, .e, .f], "O": [.a, .b, .c, .d, .e, .f],
        "-": [.g], " ": [],
    ]

    /// The lit bars of the character; a character without a shape stays dark.
    public static func segments(for character: Character) -> Set<Segment> {
        table[character] ?? []
    }

    /// The three digits of the MIDI channel display: right aligned `1` to `16`, `ALL`, or `---` with no MIDI.
    public static func channelText(_ route: MIDIRoute?) -> String {
        guard let route else { return "---" }
        switch route.channel {
        case .all: return "ALL"
        case .channel(let number): return padded(String(number), to: 3)
        }
    }

    /// The five digits of an audio route display: `3-4`, `11-12`, a mono `3` (all one-based), or `OFF`.
    public static func routeText(_ channels: AudioChannels?) -> String {
        guard let channels else { return "  OFF" }
        switch channels {
        case .mono(let channel): return padded(String(channel + 1), to: 5)
        case .stereo(let left, let right): return padded("\(left + 1)-\(right + 1)", to: 5)
        }
    }

    private static func padded(_ text: String, to width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }
}
