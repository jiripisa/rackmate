import AudioToolbox
import Foundation

/// Tells which parameter of a plugin the owner moved, for MIDI learn: the plugin's own window reports a
/// grab or a change, and the router's mapped writes do not, since they go out through the same listener.
/// Stops with `stop` or when it goes.
@MainActor
public final class ParameterWatch {
    private nonisolated(unsafe) let listener: AUEventListenerRef?
    /// Held until the event types are removed, so the unit cannot be disposed before them.
    private nonisolated(unsafe) var plugin: HostedPlugin?
    private let events: [AudioUnitEvent]
    private let token: UUID
    private nonisolated(unsafe) weak var router: MIDIRouter?

    /// Reads the plugin's parameters once, so a parameter that appears later is not heard. `onTouch`
    /// runs on the main actor with the ID of the parameter.
    public init(router: MIDIRouter, plugin: HostedPlugin, onTouch: @escaping @MainActor (AudioUnitParameterID) -> Void) {
        self.router = router
        listener = router.parameterListener
        self.plugin = plugin
        token = router.addParameterHandler(for: plugin.audioUnit) { event in
            MainActor.assumeIsolated { onTouch(event.mArgument.mParameter.mParameterID) }
        }
        var events: [AudioUnitEvent] = []
        for parameter in plugin.parameters() {
            for type in [AudioUnitEventType.beginParameterChangeGesture, .parameterValueChange] {
                var event = AudioUnitEvent()
                event.mEventType = type
                event.mArgument.mParameter = AudioUnitParameter(
                    mAudioUnit: plugin.audioUnit, mParameterID: parameter.id, mScope: kAudioUnitScope_Global, mElement: 0)
                events.append(event)
            }
        }
        if let listener {
            for var event in events { AUEventListenerAddEventType(listener, nil, &event) }
        }
        self.events = events
    }

    /// Harmless a second time.
    public func stop() {
        guard let router else { return }
        self.router = nil
        router.removeParameterHandler(token)
        guard let listener else {
            plugin = nil
            return
        }
        for var event in events { AUEventListenerRemoveEventType(listener, nil, &event) }
        plugin = nil
    }

    /// Can run on any thread; the removal goes to the main one, like a plugin's teardown does.
    deinit {
        // The router's listener lives as long as the router, so a watch outliving its router has
        // nothing left to remove.
        guard let router else { return }
        nonisolated(unsafe) let listener = listener
        let events = events
        let token = token
        let plugin = plugin
        let remove: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                router.removeParameterHandler(token)
                if let listener { for var event in events { AUEventListenerRemoveEventType(listener, nil, &event) } }
                withExtendedLifetime(plugin) {}
            }
        }
        if Thread.isMainThread { remove() } else { DispatchQueue.main.async { remove() } }
    }
}
