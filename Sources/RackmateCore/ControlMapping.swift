import Foundation

/// A physical knob of a MIDI controller, told apart by device, MIDI channel and controller number.
public struct ControlKnob: Codable, Hashable, Sendable {
    public var source: String
    /// 1 to 16.
    public var channel: Int
    /// 0 to 127.
    public var controller: Int

    public init(source: String, channel: Int, controller: Int) {
        self.source = source
        self.channel = channel
        self.controller = controller
    }

    /// How the knob is named on screen: "OXI E16 · CH 1 · CC 74".
    public var label: String { "\(source) · CH \(channel) · CC \(controller)" }
}

/// A knob driving one parameter of a plugin, over the part `from` to `to` of the parameter's range.
public struct ControlMapping: Codable, Equatable, Sendable {
    public var knob: ControlKnob
    /// The parameter's address in the plugin.
    public var parameter: UInt32
    /// The parameter's name when it was learned, shown when the plugin is not loaded.
    public var parameterName: String
    /// Where the knob's lowest position lands, 0 to 1 of the parameter's range. `from` above `to` inverts.
    public var from: Double
    /// Where the knob's highest position lands, 0 to 1 of the parameter's range.
    public var to: Double

    public init(knob: ControlKnob, parameter: UInt32, parameterName: String, from: Double = 0, to: Double = 1) {
        self.knob = knob
        self.parameter = parameter
        self.parameterName = parameterName
        self.from = from
        self.to = to
    }

    /// `from` as a whole percentage; setting clamps to 0...100.
    public var fromPercent: Int {
        get { Self.percent(from) }
        set { from = Self.fraction(newValue) }
    }

    /// `to` as a whole percentage; setting clamps to 0...100.
    public var toPercent: Int {
        get { Self.percent(to) }
        set { to = Self.fraction(newValue) }
    }

    /// The fraction of the parameter's range a knob value 0...127 lands on.
    public func fraction(forKnob value: UInt8) -> Double {
        // Written as a blend so that 0 and 127 give `from` and `to` exactly.
        let position = Double(value) / 127
        return from * (1 - position) + to * position
    }

    private static func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
    private static func fraction(_ percent: Int) -> Double { Double(min(max(percent, 0), 100)) / 100 }
}

extension PluginSlot {
    /// Adds `mapping`, unless the knob already drives that parameter: the mapping stays as it is, with its range.
    public mutating func learn(_ mapping: ControlMapping) {
        guard !controls.contains(where: { $0.knob == mapping.knob && $0.parameter == mapping.parameter }) else { return }
        controls.append(mapping)
    }
}
