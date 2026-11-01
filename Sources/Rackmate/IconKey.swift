import SwiftUI

/// `.icon-key`: a square key with a picture, whose text lives in its tooltip. A key that is on lights
/// green and glows. Below the usual 34 points it is `.icon-key.small`, as the gear in the top bar is.
struct IconKey: View {
    let symbol: KeyGlyph
    let isOn: Bool
    let help: String
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VectorArtView(symbol).frame(width: glyphSize.width, height: glyphSize.height)
        }
        .buttonStyle(IconKeyStyle(isOn: isOn, size: size, restingColor: isSmall ? .muted : .keyResting))
        .panelFocusOutline()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var isSmall: Bool { size < 34 }
    private var glyphSize: CGSize { isSmall ? CGSize(width: 17, height: 17) : CGSize(width: 18, height: 16) }
}

private struct IconKeyStyle: ButtonStyle {
    let isOn: Bool
    let size: CGFloat
    let restingColor: Color

    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, isOn: isOn, size: size, restingColor: restingColor, isPressed: configuration.isPressed)
    }

    private struct Face<Label: View>: View {
        let label: Label
        let isOn: Bool
        let size: CGFloat
        let restingColor: Color
        let isPressed: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            label
                .foregroundStyle(color)
                .shadow(color: isLit ? .on : .clear, radius: 3)
                .frame(width: size, height: size)
                .background { face }
                .contentShape(Rectangle())
                .opacity(isPressed ? 0.8 : 1)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isOn)
        }

        /// A key that cannot be pressed stays dark, also when it is on.
        private var isLit: Bool { isOn && isEnabled }
        private var isHot: Bool { isHovered && isEnabled }

        private var color: Color {
            if !isEnabled { return .keyDisabled }
            if isOn { return .on }
            return isHot ? .legend : restingColor
        }

        @ViewBuilder private var face: some View {
            if isLit {
                KeyFace(top: .keyOnTop, bottom: .keyOnBottom, border: .keyOnBorder, isRaised: false, glows: true)
                    .shadow(color: .keyOnHalo, radius: 3.5)
            } else {
                KeyFace(top: .keyDarkTop, bottom: .keyDarkBottom, border: isHot ? .lineStrong : .black, isRaised: isEnabled)
            }
        }
    }
}

private extension Color {
    static let keyDarkTop = Color(hex: 0x2B2C2F)
    static let keyDarkBottom = Color(hex: 0x1C1D20)
    static let keyResting = Color(hex: 0x7F7E74)
    static let keyDisabled = Color(hex: 0x4D4D47)
    static let keyOnBorder = Color(hex: 0x2F7A36)
    static let keyOnTop = Color(hex: 0x16241A)
    static let keyOnBottom = Color(hex: 0x101A13)
    static let keyOnHalo = Color(hex: 0x62E36C, alpha: 0x33)
}
