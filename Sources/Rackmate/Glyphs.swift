import RackmateCore
import SwiftUI

/// A picture of the prototype, in the units of its `viewBox`. An SVG stroke grows with the picture,
/// so lines are kept apart from filled shapes.
struct VectorArt: Sendable {
    var viewBox: CGSize
    var fill = Path()
    var lines = Path()
    var lineWidth: CGFloat = 1
    var isEvenOdd = false
}

/// Scales the art to fit, centered, and paints it in the foreground style.
struct VectorArtView: View {
    let art: VectorArt

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / art.viewBox.width, size.height / art.viewBox.height)
            context.translateBy(
                x: (size.width - art.viewBox.width * scale) / 2,
                y: (size.height - art.viewBox.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            context.fill(art.fill, with: .foreground, style: FillStyle(eoFill: art.isEvenOdd))
            context.stroke(art.lines, with: .foreground, lineWidth: art.lineWidth)
        }
    }
}

/// The picture on a key: `OPEN_ICON`, `FOLLOW_ICON` and `GEAR_ICON`.
enum KeyGlyph {
    case openPlugin, follow, settings

    fileprivate var art: VectorArt {
        switch self {
        case .openPlugin: Self.openPluginArt
        case .follow: Self.followArt
        case .settings: Self.settingsArt
        }
    }

    private static let openPluginArt = VectorArt(
        viewBox: CGSize(width: 20, height: 20),
        lines: Path { path in
            path.addLines(points((8, 3), (2.5, 3), (2.5, 17.5), (17, 17.5), (17, 12)))
            path.addLines(points((11, 2.5), (17.5, 2.5), (17.5, 9)))
            path.addLines(points((17.5, 2.5), (9, 11)))
        },
        lineWidth: 1.6
    )

    private static let followArt = VectorArt(
        viewBox: CGSize(width: 24, height: 20),
        fill: Path { path in
            path.addLines(points((2, 3.5), (2, 16.5), (12, 10)))
            path.closeSubpath()
            path.addRect(CGRect(x: 14.5, y: 4, width: 7.5, height: 12))
        }
    )

    private static let settingsArt = VectorArt(
        viewBox: CGSize(width: 24, height: 24),
        fill: Path { path in
            path.addLines(points(
                (9.5, 4.8), (10, 2), (14, 2), (14.5, 4.8), (15.3, 5.1), (17.6, 3.5), (20.5, 6.4), (18.9, 8.7),
                (19.2, 9.5), (22, 10), (22, 14), (19.2, 14.5), (18.9, 15.3), (20.5, 17.6), (17.6, 20.5), (15.3, 18.9),
                (14.5, 19.2), (14, 22), (10, 22), (9.5, 19.2), (8.7, 18.9), (6.4, 20.5), (3.5, 17.6), (5.1, 15.3),
                (4.8, 14.5), (2, 14), (2, 10), (4.8, 9.5), (5.1, 8.7), (3.5, 6.4), (6.4, 3.5), (8.7, 5.1)
            ))
            path.closeSubpath()
            path.addEllipse(in: circle(x: 12, y: 12, radius: 3.4))
        },
        isEvenOdd: true
    )
}

extension VectorArtView {
    init(_ glyph: KeyGlyph) {
        self.init(art: glyph.art)
    }
}

/// `MORE_ICON`: the vertical three dots that open an effect's menu.
struct MoreGlyph: View {
    private static let art = VectorArt(
        viewBox: CGSize(width: 4, height: 16),
        fill: Path { path in
            for y in [2.5, 8, 13.5] { path.addEllipse(in: circle(x: 2, y: y, radius: 1.5)) }
        }
    )

    var body: some View {
        VectorArtView(art: Self.art).frame(width: 4, height: 16)
    }
}

/// A generic picture by plugin type, `GLYPHS`, as Audio Units do not supply reliable ones. The channel
/// picture is 54 by 36 and the small picture on an effect slot 17 by 17, in the color around it.
struct PluginGlyph: View {
    enum Kind {
        case keys, pads, effect, slot

        /// `glyphOf`.
        init(_ plugin: PluginKind, isSampler: Bool = false) {
            switch plugin {
            case .effect: self = .effect
            case .instrument: self = isSampler ? .pads : .keys
            }
        }

        fileprivate var art: VectorArt {
            switch self {
            case .keys: PluginArt.keys
            case .pads: PluginArt.pads
            case .effect: PluginArt.effect
            case .slot: PluginArt.slot
            }
        }
    }

    let kind: Kind
    /// The side of the small picture on an effect slot.
    var slotSide: CGFloat = 17

    var body: some View {
        if kind == .slot {
            VectorArtView(art: kind.art).frame(width: slotSide, height: slotSide)
        } else {
            VectorArtView(art: kind.art).frame(width: 54, height: 36).foregroundStyle(Color.glyph)
        }
    }
}

/// `GLYPHS`.
private enum PluginArt {
    private static let frame = CGRect(x: 0.5, y: 0.5, width: 53, height: 35)
    private static let frameCorner = CGSize(width: 1, height: 1)

    static let keys = VectorArt(
        viewBox: CGSize(width: 54, height: 36),
        fill: Path { path in
            for x in [6, 13.5, 28.5, 36, 43.5] { path.addRect(CGRect(x: x, y: 13, width: 5, height: 13)) }
        },
        lines: Path { path in
            path.addRoundedRect(in: frame, cornerSize: frameCorner)
            path.addLines(points((1, 13), (53, 13)))
            for x in [8.5, 16, 23.5, 31, 38.5, 46] { path.addLines(points((x, 13), (x, 36))) }
            for x in [8.0, 16, 24] { path.addEllipse(in: circle(x: x, y: 7, radius: 2)) }
            path.addLines(points((33, 7), (49, 7)))
        }
    )

    static let pads = VectorArt(
        viewBox: CGSize(width: 54, height: 36),
        lines: Path { path in
            path.addRoundedRect(in: frame, cornerSize: frameCorner)
            for y in [6.0, 20] {
                for (x, width) in [(6, 9), (17.5, 9), (29, 9), (40.5, 8)] as [(CGFloat, CGFloat)] {
                    path.addRect(CGRect(x: x, y: y, width: width, height: 10))
                }
            }
        }
    )

    static let effect = VectorArt(
        viewBox: CGSize(width: 54, height: 36),
        lines: Path { path in
            path.addRoundedRect(in: frame, cornerSize: frameCorner)
            path.move(to: CGPoint(x: 5, y: 18))
            path.addCurve(to: CGPoint(x: 14, y: 18), control1: CGPoint(x: 8, y: 7), control2: CGPoint(x: 11, y: 7))
            path.addCurve(to: CGPoint(x: 23, y: 18), control1: CGPoint(x: 17, y: 29), control2: CGPoint(x: 20, y: 29))
            path.addCurve(to: CGPoint(x: 32, y: 18), control1: CGPoint(x: 26, y: 7), control2: CGPoint(x: 29, y: 7))
            path.addCurve(to: CGPoint(x: 41, y: 18), control1: CGPoint(x: 35, y: 29), control2: CGPoint(x: 38, y: 29))
            path.addCurve(to: CGPoint(x: 49, y: 14), control1: CGPoint(x: 44, y: 7), control2: CGPoint(x: 46, y: 10))
        }
    )

    static let slot = VectorArt(
        viewBox: CGSize(width: 17, height: 17),
        fill: Path { path in
            for (x, y, height) in [(1, 2, 13), (5, 5, 10), (9, 1, 14), (13, 7, 8)] as [(CGFloat, CGFloat, CGFloat)] {
                path.addRect(CGRect(x: x, y: y, width: 2, height: height))
            }
        }
    )
}

private func points(_ pairs: (CGFloat, CGFloat)...) -> [CGPoint] {
    pairs.map { CGPoint(x: $0.0, y: $0.1) }
}

private func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> CGRect {
    CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
}
