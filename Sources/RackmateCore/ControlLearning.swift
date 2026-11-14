import Foundation

/// Which plugin windows have Learn on, and the parameter each one has been waiting on since the
/// user last touched it. The next knob that moves goes to the newest of those parameters.
public struct ControlLearning: Sendable {
    private struct Pending: Sendable {
        var parameter: UInt32
        var name: String
        /// Orders the touches across windows; the highest takes the knob.
        var order: Int
    }

    private var on: Set<PluginLocation> = []
    private var pendings: [PluginLocation: Pending] = [:]
    private var touches = 0

    public init() {}

    public mutating func start(at location: PluginLocation) {
        on.insert(location)
    }

    /// Turns Learn off there and forgets its pending parameter.
    public mutating func stop(at location: PluginLocation) {
        on.remove(location)
        pendings[location] = nil
    }

    public func isOn(at location: PluginLocation) -> Bool { on.contains(location) }

    public var isAnyOn: Bool { !on.isEmpty }

    /// A touched parameter replaces the one pending in that window. Ignored where Learn is off.
    public mutating func touch(at location: PluginLocation, parameter: UInt32, name: String) {
        guard on.contains(location) else { return }
        touches += 1
        pendings[location] = Pending(parameter: parameter, name: name, order: touches)
    }

    public func pending(at location: PluginLocation) -> (parameter: UInt32, name: String)? {
        pendings[location].map { ($0.parameter, $0.name) }
    }

    /// The newest pending parameter of all windows takes the knob and stops pending; Learn stays on.
    public mutating func receive(_ knob: ControlKnob) -> (location: PluginLocation, mapping: ControlMapping)? {
        guard let (location, pending) = pendings.max(by: { $0.value.order < $1.value.order }) else { return nil }
        pendings[location] = nil
        return (location, ControlMapping(knob: knob, parameter: pending.parameter, parameterName: pending.name))
    }
}
