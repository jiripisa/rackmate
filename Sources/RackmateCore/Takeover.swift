import Foundation

/// Soft takeover: a knob whose position differs from the parameter's value does not make the value jump.
/// It writes only after the knob has reached the value. Plain value fields only, it runs under the router's lock.
public struct Takeover: Sendable {
    private var isWaiting = true
    private var hasPrevious = false
    private var previous: UInt8 = 0

    /// Starts waiting.
    public init() {}

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
            let clamped = min(max(currentFraction, min(from, to)), max(from, to))
            let k = (clamped - from) / (to - from) * 127
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
}
