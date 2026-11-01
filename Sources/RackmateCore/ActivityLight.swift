/// Whether a channel's LED is lit. Each look at the channel says what has come in since the last one,
/// and the light stays on for `hold` after that, so a single note can be seen.
public struct ActivityLight: Sendable {
    public static let hold = Duration.milliseconds(100)

    private var lastCount: UInt64?
    private var litUntil: ContinuousClock.Instant?

    public init() {}

    /// For MIDI. Any change counts, because the count starts over when a channel loses its route. The
    /// first count is what came in before anyone looked.
    public mutating func update(eventCount: UInt64, at now: ContinuousClock.Instant) -> Bool {
        defer { lastCount = eventCount }
        return update(hasSignal: lastCount.map { $0 != eventCount } ?? false, at: now)
    }

    public mutating func update(hasSignal: Bool, at now: ContinuousClock.Instant) -> Bool {
        if hasSignal { litUntil = now + Self.hold }
        return litUntil.map { now < $0 } ?? false
    }
}
