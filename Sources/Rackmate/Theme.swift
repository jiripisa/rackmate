import SwiftUI

// The rack of `ui-prototype/styles.css`, whose sizes and colors these are.

extension Color {
    static let chassis = Color(hex: 0x131416)
    static let panel = Color(hex: 0x26272A)
    static let panelDeep = Color(hex: 0x161719)
    static let panelRaised = Color(hex: 0x33353A)
    static let legend = Color(hex: 0xECE8DC)
    static let muted = Color(hex: 0xA3A194)
    static let line = Color(hex: 0x4A4B47)
    static let lineStrong = Color(hex: 0x8F8C80)
    /// Amber is for displays only.
    static let led = Color(hex: 0xFF9A3C)
    static let ledSoft = Color(hex: 0xFFB066)
    /// Green is for lit status.
    static let on = Color(hex: 0x62E36C)
    /// Red is for faults.
    static let fault = Color(hex: 0xFF6A52)
    static let ledOff = Color(hex: 0x45453F)
    static let displayBackground = Color(hex: 0x1B0E05)
    /// `.glyph`, the picture of a plugin.
    static let glyph = Color(hex: 0xD9D5C9)
    /// A menu or dialog above the panel.
    static let panelMenu = Color(hex: 0x1C1D20)
    static let walnut = Color(hex: 0x6D4529)
    static let walnutDark = Color(hex: 0x553420)

    /// A CSS color: `hex` is `rrggbb` and `alpha` the optional last two digits.
    init(hex: UInt32, alpha: UInt32 = 0xFF) {
        self.init(
            .sRGB,
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

extension Font {
    /// DIN Condensed, for names. macOS ships it in bold only.
    static func panelDisplay(_ size: CGFloat) -> Font { .custom("DINCondensed-Bold", fixedSize: size) }
    /// DIN Alternate, for everything else. macOS ships it in bold only.
    static func panelText(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", fixedSize: size) }
}

extension View {
    /// CSS letter spacing, given in em for a font of `size`.
    func panelSpacing(_ em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }
}

/// `:focus-visible`: amber instead of the system's blue ring, which the window turns off.
///
/// It reads the focus of the control it is attached to, so it goes on the `Button` itself. The
/// `isFocused` environment value reaches a label only under the plain button style.
private struct FocusOutline: ViewModifier {
    let outset: CGFloat

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .overlay {
                if isFocused {
                    Rectangle().strokeBorder(Color.led, lineWidth: 2).padding(-outset).allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// For a control that can take keyboard focus; attach it to the `Button`, after its style.
    /// `outset` is the prototype's 2 pt gap and its 2 pt outline; a row in a scrolling list has no
    /// room for them.
    func panelFocusOutline(outset: CGFloat = 4) -> some View {
        modifier(FocusOutline(outset: outset))
    }
}

/// The body of `.key` and `.icon-key`: a raised face with a light top edge.
struct KeyFace: View {
    static let cornerRadius: CGFloat = 3

    let top: Color
    let bottom: Color
    let border: Color
    /// A key that is lit or cannot be pressed lies flat.
    var isRaised = true
    /// Lit from inside, as a key that is on.
    var glows = false

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                if glows {
                    RackArt.keyGlow.resizable(capInsets: EdgeInsets(RackArt.keyGlowCap), resizingMode: .stretch)
                }
            }
            .overlay(alignment: .top) {
                if isRaised {
                    Rectangle().fill(Color.edgeLight).frame(height: 1).padding(.top, 1).padding(.horizontal, 1)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(border, lineWidth: 1) }
            .shadow(color: isRaised ? .keyShadow : .clear, radius: 1, y: 1)
    }
}

/// `.key`. Use `.key` or `KeyButtonStyle.primary`.
struct KeyButtonStyle: ButtonStyle {
    static let primary = KeyButtonStyle(isPrimary: true)

    private static let fontSize: CGFloat = 12.5

    var isPrimary = false
    /// `.key.replace`: takes the width it is offered, and the height of the preset it stands in for.
    var stretches = false

    func makeBody(configuration: Configuration) -> some View {
        KeyLabel(label: configuration.label, isPrimary: isPrimary, stretches: stretches, isPressed: configuration.isPressed)
    }

    private struct KeyLabel<Label: View>: View {
        let label: Label
        let isPrimary: Bool
        let stretches: Bool
        let isPressed: Bool

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            label
                .font(.panelText(KeyButtonStyle.fontSize))
                .panelSpacing(0.06, size: KeyButtonStyle.fontSize)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize(horizontal: !stretches, vertical: true)
                .frame(maxWidth: stretches ? .infinity : nil)
                .frame(height: stretches ? 18 : 16.25)
                .foregroundStyle(isPrimary ? Color.panelDeep : Color.legend)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background { face }
                .contentShape(Rectangle())
                .opacity(isPrimary && !isEnabled ? 0.4 : isPressed ? 0.8 : 1)
                .onHover { isHovered = $0 }
        }

        @ViewBuilder private var face: some View {
            if isPrimary {
                KeyFace(top: .legend, bottom: .legend, border: .legend, isRaised: false)
            } else {
                KeyFace(top: .keyTop, bottom: .keyBottom, border: isHovered && isEnabled ? .legend : .keyBorder)
            }
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    static var key: KeyButtonStyle { KeyButtonStyle() }
    static var wideKey: KeyButtonStyle { KeyButtonStyle(stretches: true) }
}

/// `.legend`, the silk-screen label above a control.
struct Legend: View {
    private static let fontSize: CGFloat = 11.5

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.panelText(Self.fontSize))
            .panelSpacing(0.08, size: Self.fontSize)
            .textCase(.uppercase)
            .foregroundStyle(Color.muted)
            .padding(.bottom, 3)
    }
}

/// `.led`, `.led.off` and `.led.fault`.
struct LED: View {
    enum Tone {
        case on, off, fault
    }

    var tone = Tone.on

    var body: some View {
        Group {
            if tone == .off {
                Circle().fill(Color.ledOff.shadow(.inner(color: .ledRecess, radius: 0.5, y: 1)))
            } else {
                Circle().fill(color).shadow(color: color, radius: 3.5)
            }
        }
        .frame(width: 9, height: 9)
    }

    private var color: Color {
        tone == .fault ? .fault : .on
    }
}

/// The rack between its two walnut cheeks. The rack stays below the title bar, while the chassis and
/// the cheeks run up to the top of the window.
struct WalnutFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            WalnutCheek()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            WalnutCheek()
        }
        .background(Color.chassis.ignoresSafeArea())
    }
}

/// `body::before`: 9 pt of grain, repeating along a line 2 degrees off the horizontal, so the stripes
/// lean a little. Distance along that line starts from the top left corner.
private struct WalnutCheek: View {
    private static let width: CGFloat = 18
    private static let period: CGFloat = 9
    private static let darkFrom: CGFloat = 3
    private static let darkTo: CGFloat = 4
    private static let across = sin(92 * CGFloat.pi / 180)
    private static let down = -cos(92 * CGFloat.pi / 180)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.walnut))
            var distance = -Self.period
            let end = size.width * Self.across + size.height * Self.down
            while distance < end {
                context.fill(stripe(from: distance + Self.darkFrom, to: distance + Self.darkTo, height: size.height), with: .color(.walnutDark))
                distance += Self.period
            }
        }
        .frame(width: Self.width)
        .ignoresSafeArea()
    }

    private func stripe(from start: CGFloat, to end: CGFloat, height: CGFloat) -> Path {
        func x(_ distance: CGFloat, atY y: CGFloat) -> CGFloat { (distance - y * Self.down) / Self.across }
        var path = Path()
        path.move(to: CGPoint(x: x(start, atY: 0), y: 0))
        path.addLine(to: CGPoint(x: x(end, atY: 0), y: 0))
        path.addLine(to: CGPoint(x: x(end, atY: height), y: height))
        path.addLine(to: CGPoint(x: x(start, atY: height), y: height))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    static let keyTop = Color(hex: 0x303134)
    static let keyBottom = Color(hex: 0x212225)
    static let keyBorder = Color(hex: 0x6F6E67)
    static let keyShadow = Color(hex: 0x000000, alpha: 0x99)
    static let edgeLight = Color(hex: 0xFFFFFF, alpha: 0x14)
    static let ledRecess = Color(hex: 0x000000, alpha: 0x88)
}
