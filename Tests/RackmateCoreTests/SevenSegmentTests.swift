import Testing
@testable import RackmateCore

struct SevenSegmentTests {
    private func lit(_ text: String) -> Set<Segment> {
        Set(text.map { char in
            switch char {
            case "a": Segment.a
            case "b": .b
            case "c": .c
            case "d": .d
            case "e": .e
            case "f": .f
            default: .g
            }
        })
    }

    @Test func eightLightsAllSeven() {
        #expect(SevenSegment.segments(for: "8") == Set(Segment.allCases))
    }

    @Test func oneIsBAndC() {
        #expect(SevenSegment.segments(for: "1") == [.b, .c])
    }

    @Test(arguments: [
        ("0", "abcdef"), ("2", "abdeg"), ("3", "abcdg"), ("4", "bcfg"), ("5", "acdfg"), ("6", "acdefg"),
        ("7", "abc"), ("9", "abcdfg"), ("A", "abcefg"), ("F", "aefg"), ("L", "def"), ("O", "abcdef"),
        ("-", "g"), (" ", ""),
    ] as [(Character, String)])
    func charactersMatchThePrototype(char: Character, expected: String) {
        #expect(SevenSegment.segments(for: char) == lit(expected))
    }

    @Test func channelText() {
        #expect(SevenSegment.channelText(MIDIRoute(sourceName: "Keys", channel: .channel(1))) == "  1")
        #expect(SevenSegment.channelText(MIDIRoute(sourceName: "Keys", channel: .channel(16))) == " 16")
        #expect(SevenSegment.channelText(MIDIRoute(sourceName: "Keys", channel: .all)) == "ALL")
        #expect(SevenSegment.channelText(nil) == "---")
    }

    @Test func routeText() {
        #expect(SevenSegment.routeText(.stereo(left: 2, right: 3)) == "  3-4")
        #expect(SevenSegment.routeText(.stereo(left: 10, right: 11)) == "11-12")
        #expect(SevenSegment.routeText(.mono(2)) == "    3")
        #expect(SevenSegment.routeText(nil) == "  OFF")
    }

    @Test func everyProducedCharacterHasAnEntry() {
        var texts = [SevenSegment.channelText(nil), SevenSegment.channelText(MIDIRoute(sourceName: "", channel: .all)),
                     SevenSegment.routeText(nil)]
        for n in 1...16 { texts.append(SevenSegment.channelText(MIDIRoute(sourceName: "", channel: .channel(n)))) }
        for n in 0..<16 {
            texts.append(SevenSegment.routeText(.mono(n)))
            texts.append(SevenSegment.routeText(.stereo(left: n, right: n + 1)))
        }
        for char in Set(texts.joined()) {
            #expect(SevenSegment.table[char] != nil, "no entry for '\(char)'")
        }
    }
}
