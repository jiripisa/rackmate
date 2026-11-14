import Foundation

/// Which way a waiting knob has to go to take over, for the hint in its row.
public enum TakeoverHint: Sendable, Equatable {
    case turnUp
    case turnDown
    /// The knob has not moved since the wait began, so the way is not known.
    case moveKnob
}

/// Soft takeover: a knob whose position differs from the parameter's value does not make the value jump.
/// It writes only after the knob has reached the value. Plain value fields only, it runs under the router's lock.
public struct Takeover: Sendable {
    public private(set) var isWaiting = true
    private var hasPrevious = false
    private var previous: UInt8 = 0

    /// Starts waiting.
    public init() {}

    /// The knob's previous position in this waiting period, nil before its first move.
    public var lastKnob: UInt8? { hasPrevious ? previous : nil }

    /// Waits for the knob to reach the value again and forgets the previous knob position.
    public mutating func rearm() {
        isWaiting = true
        hasPrevious = false
    }

    /// Whether to write this knob value to the parameter, which is now at `currentFraction`.
    ///
    /// While waiting, `currentFraction` is clamped into the knob's range `from`...`to` and turned into the knob position `k` that
    /// would produce it. The knob takes over when its previous position of this waiting period and the new one lie on both sides
    /// of `k` or touch it; with no previous position, when it is within 1 of `k`. With `from == to` the first move takes over.
    /// Once taken over, every move writes until `rearm()`.
    public mutating func follow(knob: UInt8, currentFraction: Double, from: Double, to: Double) -> Bool {
        guard isWaiting else { return true }
        var takesOver = from == to
        if !takesOver {
            let k = Self.knobPosition(of: currentFraction, from: from, to: to)
            if hasPrevious {
                takesOver = Double(min(previous, knob)) <= k && k <= Double(max(previous, knob))
            } else {
                takesOver = abs(Double(knob) - k) <= 1
            }
        }
        if takesOver {
            isWaiting = false
        } else {
            previous = knob
            hasPrevious = true
        }
        return takesOver
    }

    /// Which way the knob at `knob` has to turn to reach the parameter at `currentFraction`, compared with `k` as `follow` makes
    /// it. Nil when not waiting, and with `from == to`, since the first move takes over then. Without a knob position, or with
    /// the knob on `k`, any move will do, and `currentFraction` does not count.
    public func hint(knob: UInt8?, currentFraction: Double, from: Double, to: Double) -> TakeoverHint? {
        guard isWaiting, from != to else { return nil }
        guard let knob else { return .moveKnob }
        let k = Self.knobPosition(of: currentFraction, from: from, to: to)
        if k > Double(knob) { return .turnUp }
        if k < Double(knob) { return .turnDown }
        return .moveKnob
    }

    /// The knob position, 0 to 127, that puts the parameter at `currentFraction` clamped into `from`...`to`. Not for `from == to`.
    private static func knobPosition(of currentFraction: Double, from: Double, to: Double) -> Double {
        let clamped = min(max(currentFraction, min(from, to)), max(from, to))
        return (clamped - from) / (to - from) * 127
    }
}
