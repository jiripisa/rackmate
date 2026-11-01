import RackmateCore
import SwiftUI

/// How the lit bars of a display read. The unlit bars stay the same in every tone.
enum SegmentTone {
    case lit, dim, fault

    fileprivate var color: Color {
        switch self {
        case .lit: .led
        case .dim: .segmentDim
        case .fault: .fault
        }
    }

    /// `drop-shadow(0 0 2px …)` of `.segments .lit`; a dim display does not glow.
    fileprivate var glow: Color {
        switch self {
        case .lit: .segmentGlow
        case .dim: .clear
        case .fault: .segmentFaultGlow
        }
    }
}

/// `sevenSegment` of `ui-prototype/app.js`: digits drawn as vector shapes, one per character of `text`,
/// with the unlit bars faintly visible. The display around it tells VoiceOver what it reads.
struct SevenSegmentView: View {
    let text: String
    let height: CGFloat
    let tone: SegmentTone

    var body: some View {
        ZStack {
            SegmentBars(text: text, isLit: false).fill(Color.segmentUnlit)
            SegmentBars(text: text, isLit: true).fill(tone.color).shadow(color: tone.glow, radius: 2)
        }
        .frame(width: SegmentBars.viewBoxWidth(characters: text.count) * height / SegmentBars.viewBoxHeight, height: height)
        .accessibilityHidden(true)
    }
}

/// The lit or the unlit bars of every digit, in the prototype's 26 units of height.
private struct SegmentBars: Shape {
    static let viewBoxHeight: CGFloat = 26
    private static let digitWidth: CGFloat = 15
    private static let leadIn: CGFloat = 2
    private static let skew = tan(-5 * CGFloat.pi / 180)

    /// `SEGMENTS`.
    private static let bars: [Segment: [CGPoint]] = [
        .a: points((2.2, 1), (11.8, 1), (9.8, 3.4), (4.2, 3.4)),
        .b: points((12.6, 1.8), (12.6, 12.2), (11.4, 13), (10.2, 11.8), (10.2, 4.2)),
        .c: points((12.6, 13.8), (12.6, 24.2), (10.2, 21.8), (10.2, 14.2), (11.4, 13)),
        .d: points((2.2, 25), (11.8, 25), (9.8, 22.6), (4.2, 22.6)),
        .e: points((1.4, 13.8), (1.4, 24.2), (3.8, 21.8), (3.8, 14.2), (2.6, 13)),
        .f: points((1.4, 1.8), (1.4, 12.2), (2.6, 13), (3.8, 11.8), (3.8, 4.2)),
        .g: points((3, 13), (4.2, 11.8), (9.8, 11.8), (11, 13), (9.8, 14.2), (4.2, 14.2)),
    ]

    let text: String
    let isLit: Bool

    static func viewBoxWidth(characters: Int) -> CGFloat {
        CGFloat(characters) * digitWidth + leadIn
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, character) in text.enumerated() {
            let lit = SevenSegment.segments(for: character)
            let digit = CGAffineTransform(a: 1, b: 0, c: Self.skew, d: 1, tx: CGFloat(index) * Self.digitWidth + Self.leadIn, ty: 0)
            for segment in Segment.allCases where lit.contains(segment) == isLit {
                path.addLines(Self.bars[segment, default: []].map { $0.applying(digit) })
                path.closeSubpath()
            }
        }
        let scale = rect.height / Self.viewBoxHeight
        return path.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: rect.minX / scale, y: rect.minY / scale))
    }

    private static func points(_ pairs: (CGFloat, CGFloat)...) -> [CGPoint] {
        pairs.map { CGPoint(x: $0.0, y: $0.1) }
    }
}

private extension Color {
    static let segmentUnlit = Color(hex: 0xFF9A3C, alpha: 0x12)
    static let segmentDim = Color(hex: 0x8A5A2E)
    static let segmentGlow = Color(hex: 0xFF8A1F, alpha: 0xA6)
    static let segmentFaultGlow = Color(hex: 0xFF6A52, alpha: 0xA6)
}
