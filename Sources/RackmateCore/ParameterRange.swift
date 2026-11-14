import Foundation

/// How a parameter's value is spread over a knob's travel, as the Audio Unit parameter flags declare it.
///
/// `t` is the position along the travel (0...1) and `g` the share of the value range reached there:
/// - `linear`: g = t
/// - `logarithmic`: value = minimum × (maximum / minimum)^t, equal steps in ratio (needs a positive minimum)
/// - `exponential`: g = log10(1 + 9t), the mirror of the logarithmic shape
/// - `squareRoot`: g = t², `squared`: g = √t, `cubeRoot`: g = t³, `cubed`: g = ∛t, the way generic Audio Unit views draw them
public enum ParameterScale: Sendable {
    case linear, logarithmic, exponential, squareRoot, squared, cubeRoot, cubed
}

/// The range of a plugin parameter, to turn a position 0...1 into a value and back.
public struct ParameterRange: Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float
    public var scale: ParameterScale
    /// A stepped parameter only takes whole numbers.
    public var isStepped: Bool

    public init(minimum: Float, maximum: Float, scale: ParameterScale, isStepped: Bool) {
        self.minimum = minimum
        self.maximum = maximum
        self.scale = scale
        self.isStepped = isStepped
    }

    /// The value at `fraction` (clamped to 0...1) of the travel, rounded to a whole number when stepped.
    public func value(atFraction fraction: Double) -> Float {
        let t = min(max(fraction, 0), 1)
        let low = Double(minimum), high = Double(maximum)
        let raw: Double
        if usesLogarithm {
            raw = t >= 1 ? high : low * pow(high / low, t)
        } else {
            raw = low + (high - low) * share(atFraction: t)
        }
        let value = Float(raw)
        return isStepped ? value.rounded() : value
    }

    /// The position (0...1) of `value`, the inverse of `value(atFraction:)`. A value outside the range, or a range without width, clamps.
    public func fraction(of value: Float) -> Double {
        let low = Double(minimum), high = Double(maximum)
        guard high != low else { return 0 }
        let clamped = min(max(Double(value), min(low, high)), max(low, high))
        let t: Double
        if usesLogarithm {
            t = log(clamped / low) / log(high / low)
        } else {
            t = position(forShare: (clamped - low) / (high - low))
        }
        return min(max(t, 0), 1)
    }

    private var usesLogarithm: Bool { scale == .logarithmic && minimum > 0 && maximum > 0 }

    /// The share g of the value range reached at position `t`; every scale except the true logarithm.
    private func share(atFraction t: Double) -> Double {
        switch scale {
        case .linear, .logarithmic: t
        case .exponential: log10(1 + 9 * t)
        case .squareRoot: t * t
        case .squared: t.squareRoot()
        case .cubeRoot: t * t * t
        case .cubed: cbrt(t)
        }
    }

    private func position(forShare g: Double) -> Double {
        switch scale {
        case .linear, .logarithmic: g
        case .exponential: (pow(10, g) - 1) / 9
        case .squareRoot: g.squareRoot()
        case .squared: g * g
        case .cubeRoot: cbrt(g)
        case .cubed: g * g * g
        }
    }
}
