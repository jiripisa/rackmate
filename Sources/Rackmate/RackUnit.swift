import SwiftUI

/// The metal of a unit: `.plate`, the plate of `.unit.standalone`, and `.vent .plate`.
enum RackTint {
    case plain, standalone, vent
}

/// `.unit`: `content` on a plate between two ears. The unit is as high as its content, and the content
/// is laid out edge to edge, so it brings its own padding.
struct RackUnit<Content: View>: View {
    var tint = RackTint.plain
    /// `.ear` padding: 18 on the tall unit of the Start screen.
    var earInset: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RackEar.width)
            .background {
                HStack(spacing: 0) {
                    RackEar(inset: earInset)
                    RackPlate(tint: tint)
                    RackEar(inset: earInset)
                }
                .accessibilityHidden(true)
            }
    }
}

/// `.ear`: two screws and a slot.
struct RackEar: View {
    static let width: CGFloat = 34

    let inset: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            screw
            Spacer(minLength: 0)
            RackArt.slot
            Spacer(minLength: 0)
            screw
        }
        .padding(.vertical, inset + 1)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background { RackArt.earFace.resizable() }
        .overlay { Rectangle().strokeBorder(Color.black, lineWidth: 1) }
    }

    private var screw: some View {
        RackArt.screw(scale: displayScale).frame(width: RackArt.screwDiameter, height: RackArt.screwDiameter)
    }
}

/// `.plate`, in layers that are painted once. The brush lines repeat, and the metal and the shading
/// stretch to the unit, so a unit of any height costs three images.
private struct RackPlate: View {
    let tint: RackTint

    var body: some View {
        ZStack {
            RackArt.metal(tint).resizable()
            if tint != .vent {
                RackArt.brushLines.resizable(resizingMode: .tile)
            }
            RackArt.shading.resizable(capInsets: EdgeInsets(RackArt.shadingCap), resizingMode: .stretch)
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.plateEdge).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 1) }
    }
}

/// `.unit.vent`: fills the free height under the last unit, and is gone when less than 74 points are
/// free. It asks for no height of its own, so a rack with none to spare does not scroll for it.
struct VentUnit: View {
    private static let minimumHeight: CGFloat = 74

    @State private var height: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
            .overlay {
                if height >= Self.minimumHeight {
                    RackUnit(tint: .vent) {
                        RackArt.ventSlots
                            .resizable(resizingMode: .tile)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 38)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The dark amber well behind presets and digits, with `.channel-display` and `.preset` glowing from
/// their edges. It takes the size of what it is put behind, at least 26 points high.
struct DisplayWell: View {
    enum Glow {
        /// `.channel-display`.
        case digits
        /// `.preset`.
        case preset
        /// Nothing to show: `.channel-display:disabled` and `.preset.quiet`.
        case quiet
    }

    var glow = Glow.digits
    /// Amber on hover, red on a fault.
    var border = Color.black

    var body: some View {
        RackArt.well(glow)
            .resizable(capInsets: EdgeInsets(RackArt.wellCap), resizingMode: .stretch)
            .overlay { RoundedRectangle(cornerRadius: RackArt.wellCorner).strokeBorder(border, lineWidth: 1) }
            .background {
                RoundedRectangle(cornerRadius: RackArt.wellCorner).fill(Color.plateLight).offset(y: 1)
            }
    }
}

/// `.topbar`: the brand and a divider, then what the screen puts there. It reaches up under the title
/// bar.
struct RackTopBar<Content: View>: View {
    private static var brandSize: CGFloat { 19 }

    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            Text("Rackmate")
                .font(.panelDisplay(Self.brandSize))
                .panelSpacing(0.32, size: Self.brandSize)
                .textCase(.uppercase)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .fixedSize()
            RackDivider()
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.topBarTop, .topBarBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 1) }
    }
}

/// `.divider`.
struct RackDivider: View {
    var body: some View {
        Rectangle().fill(Color.line).frame(width: 1, height: 22).accessibilityHidden(true)
    }
}

/// `.config-name`: the big name in the top bar.
struct RackTitle: View {
    private static let fontSize: CGFloat = 23

    let text: String

    var body: some View {
        Text(text)
            .font(.panelDisplay(Self.fontSize))
            .panelSpacing(0.05, size: Self.fontSize)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(Color.legend)
    }
}

private extension Color {
    static let plateEdge = Color(hex: 0xFFFFFF, alpha: 0x12)
    static let plateLight = Color(hex: 0xFFFFFF, alpha: 0x14)
    static let topBarTop = Color(hex: 0x1C1D20)
    static let topBarBottom = Color(hex: 0x141517)
}

extension EdgeInsets {
    /// The same on every side, as the caps of a stretched image are.
    init(_ all: CGFloat) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }
}

/// The gradients and shadows of a unit, painted once. Drawn live on every unit, they would be redone
/// on the main thread whenever a meter changes the window.
enum RackArt {
    fileprivate static let scale: CGFloat = 2
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    // MARK: - Ears

    static let earFace = paint(width: 4, height: 64) { context, size in
        context.fillGradient([(0x17181A, 0), (0x101113, 1)], height: size.height)
    }

    static let screwDiameter: CGFloat = 18

    /// What a screw is drawn with, set by hand for each scale, as the cross has a few pixels to work with.
    private struct ScrewTuning {
        /// How far the cross sits above the middle of the head.
        var crossRise: CGFloat
        var crossWidth: CGFloat
        /// From the middle of the cross to the end of an arm. The cross spans about 47 % of the head.
        var armAcross: CGFloat
        var armDown: CGFloat
        var highlightRise: CGFloat
        var highlightBlur: CGFloat
        var highlightAlpha: UInt32
        var glintDrop: CGFloat
        var glintRadius: CGFloat
    }

    private static let screwAt1x = screwImage(
        scale: 1,
        ScrewTuning(
            crossRise: 0, crossWidth: 2, armAcross: 4.2, armDown: 4,
            highlightRise: 0.8, highlightBlur: 1, highlightAlpha: 0xB0, glintDrop: 6, glintRadius: 1.5))
    private static let screwAt2x = screwImage(
        scale: 2,
        ScrewTuning(
            crossRise: 0.5, crossWidth: 2.5, armAcross: 4.3, armDown: 4.1,
            highlightRise: 0.6, highlightBlur: 1, highlightAlpha: 0xC0, glintDrop: 5.5, glintRadius: 1.3))

    /// The screw for a screen of `scale`.
    static func screw(scale: CGFloat) -> Image {
        scale < 2 ? screwAt1x : screwAt2x
    }

    /// `.screw`: a dark metal dome lit softly from above in a fine darker ring, with a small upright
    /// black Phillips recess, metal all around it, a pale highlight on its upper edges and a small
    /// glint under it. There is room around it for its shadow, which the layout does not count.
    private static func screwImage(scale: CGFloat, _ tuning: ScrewTuning) -> Image {
        let margin: CGFloat = 2
        return paint(width: screwDiameter + 2 * margin, height: screwDiameter + 2 * margin, scale: scale) { context, _ in
            let ring = CGRect(x: margin, y: margin, width: screwDiameter, height: screwDiameter)
            let center = CGPoint(x: ring.midX, y: ring.midY)
            let cross = CGPoint(x: center.x, y: center.y - tuning.crossRise)
            let across = tuning.armAcross - tuning.crossWidth / 2
            let down = tuning.armDown - tuning.crossWidth / 2
            let recess = [
                CGPoint(x: cross.x - across, y: cross.y), CGPoint(x: cross.x + across, y: cross.y),
                CGPoint(x: cross.x, y: cross.y - down), CGPoint(x: cross.x, y: cross.y + down),
            ]

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -scale), blur: scale, color: cgColor(0x000000))
            context.setFillColor(cgColor(0x040405))
            context.fillEllipse(in: ring)
            context.restoreGState()

            context.saveGState()
            context.addEllipse(in: ring.insetBy(dx: 0.6, dy: 0.6))
            context.clip()
            if let dome = gradient([(0x4A4846, 0), (0x2D2C2B, 0.4), (0x151514, 0.72), (0x070707, 1)]) {
                let lit = CGPoint(x: center.x, y: center.y - 3.2)
                context.drawRadialGradient(dome, startCenter: lit, startRadius: 0, endCenter: lit, endRadius: 10.3, options: .drawsAfterEndLocation)
            }
            context.fillGlow(0x8E8C88, [(0, 0.84), (0x38, 0.93), (0, 1)], at: CGPoint(x: center.x, y: center.y + 2), radius: 10.1)
            context.fillGlow(0xB9B6AE, [(0x50, 0), (0x24, 0.6), (0, 1)], at: cross, radius: 5.3)
            context.fillGlow(0xE8E5DE, [(0xC8, 0), (0x88, 0.5), (0, 1)], at: CGPoint(x: cross.x, y: cross.y - 3), radius: 3.2)

            context.setStrokeColor(cgColor(0x010101))
            context.setLineWidth(tuning.crossWidth)
            context.setLineCap(.round)
            // The recess casts the highlight, which stops at its upper edges.
            context.saveGState()
            context.clip(to: CGRect(x: ring.minX, y: ring.minY, width: ring.width, height: cross.y + 0.5 - ring.minY))
            context.setShadow(
                offset: CGSize(width: 0, height: tuning.highlightRise * scale), blur: tuning.highlightBlur * scale,
                color: cgColor(0xF2EFE8, alpha: tuning.highlightAlpha))
            context.strokeLineSegments(between: recess)
            context.restoreGState()
            context.strokeLineSegments(between: recess)

            context.translateBy(x: center.x, y: center.y + tuning.glintDrop)
            context.scaleBy(x: 1, y: 0.6)
            context.fillGlow(0xCFCCC4, [(0xA8, 0), (0x70, 0.5), (0, 1)], at: .zero, radius: tuning.glintRadius)
            context.restoreGState()
        }
    }

    /// `.ear .hole`, with its light lower edge.
    static let slot = paint(width: 15, height: 10) { context, _ in
        let hole = CGRect(x: 0, y: 0, width: 15, height: 9)
        context.setFillColor(cgColor(0xFFFFFF, alpha: 0x14))
        context.addPath(CGPath(roundedRect: hole.offsetBy(dx: 0, dy: 1), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
        context.fillPath()
        context.setFillColor(cgColor(0x000000))
        context.addPath(CGPath(roundedRect: hole, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
        context.fillPath()
    }

    // MARK: - Plate

    private static let plainMetal = metalImage([(0x2C2D31, 0), (0x232427, 0.55), (0x1F2023, 1)])
    private static let standaloneMetal = metalImage([(0x302D36, 0), (0x26242C, 0.55), (0x211F26, 1)])
    private static let ventMetal = metalImage([(0x1B1C1E, 0), (0x151618, 1)])

    static func metal(_ tint: RackTint) -> Image {
        switch tint {
        case .plain: plainMetal
        case .standalone: standaloneMetal
        case .vent: ventMetal
        }
    }

    private static func metalImage(_ stops: [(UInt32, CGFloat)]) -> Image {
        paint(width: 4, height: 256) { context, size in
            context.fillGradient(stops, height: size.height)
        }
    }

    /// `--brushed`: one period of the fine lines over the metal.
    static let brushLines = paint(width: 4, height: 5) { context, size in
        context.setFillColor(cgColor(0x000000, alpha: 0x14))
        context.fill(CGRect(x: 0, y: 1, width: size.width, height: 1))
        context.setFillColor(cgColor(0xFFFFFF, alpha: 0x04))
        context.fill(CGRect(x: 0, y: 3, width: size.width, height: 1))
    }

    /// `inset 0 -8px 16px #0003`. The caps hold the whole shadow, and the middle is clear.
    static let shadingCap: CGFloat = 32
    static let shading = paint(width: 2 * shadingCap + 1, height: 2 * shadingCap + 1) { context, size in
        context.fillInnerShadow(
            CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), offsetY: -8, blur: 16, color: cgColor(0x000000, alpha: 0x33))
    }

    /// One period of `.vent-slots`.
    static let ventSlots = paint(width: 70, height: 14) { context, _ in
        context.setFillColor(cgColor(0x050505))
        context.fill(CGRect(x: 0, y: 0, width: 56, height: 6))
    }

    // MARK: - Displays

    static let wellCorner: CGFloat = 3
    /// Half of the lowest display, `.channel-display.audio`.
    static let wellCap: CGFloat = 13

    private static let digitsWell = wellImage(glow: cgColor(0xFF8A1F, alpha: 0x1C))
    private static let presetWell = wellImage(glow: cgColor(0xFF8A1F, alpha: 0x22))
    private static let quietWell = wellImage(glow: cgColor(0x000000, alpha: 0x66))

    static func well(_ glow: DisplayWell.Glow) -> Image {
        switch glow {
        case .digits: digitsWell
        case .preset: presetWell
        case .quiet: quietWell
        }
    }

    private static func wellImage(glow: CGColor) -> Image {
        paint(width: 2 * wellCap + 1, height: 2 * wellCap + 1) { context, size in
            let shape = CGPath(
                roundedRect: CGRect(origin: .zero, size: size), cornerWidth: wellCorner, cornerHeight: wellCorner, transform: nil)
            context.addPath(shape)
            context.clip()
            context.fillGradient([(0x120903, 0), (0x1B0E05, 1)], height: size.height)
            context.fillInnerShadow(shape, offsetY: 0, blur: 14, color: glow)
        }
    }

    // MARK: - Keys

    /// Half of the smallest key.
    static let keyGlowCap: CGFloat = 15

    /// `inset 0 0 12px #62e36c47`, in a key that is on.
    static let keyGlow = paint(width: 2 * keyGlowCap + 1, height: 2 * keyGlowCap + 1) { context, size in
        let shape = CGPath(
            roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 3, cornerHeight: 3, transform: nil)
        context.fillInnerShadow(shape, offsetY: 0, blur: 12, color: cgColor(0x62E36C, alpha: 0x47))
    }

    // MARK: - Painting

    fileprivate static func cgColor(_ hex: UInt32, alpha: UInt32 = 0xFF) -> CGColor {
        CGColor(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    fileprivate static func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient? {
        CGGradient(colorsSpace: colorSpace, colors: stops.map { cgColor($0.0) } as CFArray, locations: stops.map(\.1))
    }

    /// One color, at the alpha of each stop.
    fileprivate static func gradient(_ color: UInt32, alphas: [(UInt32, CGFloat)]) -> CGGradient? {
        CGGradient(colorsSpace: colorSpace, colors: alphas.map { cgColor(color, alpha: $0.0) } as CFArray, locations: alphas.map(\.1))
    }

    /// An image of the size in points, drawn with the origin at the top left, by default for a 2x screen.
    private static func paint(width: CGFloat, height: CGFloat, scale: CGFloat = RackArt.scale, draw: (CGContext, CGSize) -> Void) -> Image {
        let context = CGContext(
            data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { return Image(nsImage: NSImage()) }
        context.translateBy(x: 0, y: height * scale)
        context.scaleBy(x: scale, y: -scale)
        draw(context, CGSize(width: width, height: height))
        guard let image = context.makeImage() else { return Image(nsImage: NSImage()) }
        return Image(decorative: image, scale: scale)
    }
}

private extension CGContext {
    func fillGradient(_ stops: [(UInt32, CGFloat)], height: CGFloat) {
        guard let gradient = RackArt.gradient(stops) else { return }
        drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }

    /// A soft light of one color around `center`, clear wherever the stops say nothing.
    func fillGlow(_ color: UInt32, _ alphas: [(UInt32, CGFloat)], at center: CGPoint, radius: CGFloat) {
        guard let gradient = RackArt.gradient(color, alphas: alphas) else { return }
        drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// CSS `inset 0 <offsetY> <blur> <color>`, in points. A ring around the shape casts the shadow
    /// into it, and the ring itself stays outside the clip. Shadows ignore the drawing transform.
    func fillInnerShadow(_ shape: CGPath, offsetY: CGFloat, blur: CGFloat, color: CGColor) {
        let scale = RackArt.scale
        saveGState()
        addPath(shape)
        clip()
        setShadow(offset: CGSize(width: 0, height: -offsetY * scale), blur: blur * scale, color: color)
        setFillColor(CGColor(gray: 0, alpha: 1))
        addRect(shape.boundingBox.insetBy(dx: -4 * blur, dy: -4 * blur))
        addPath(shape)
        fillPath(using: .evenOdd)
        restoreGState()
    }
}
