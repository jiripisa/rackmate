import AudioToolbox
import CRenderCore
import CoreMIDI
import Foundation
import Observation
import RackmateCore
import Synchronization
import os

private let logger = Logger(subsystem: "io.jp4.rackmate", category: "midi")

private let clockPollInterval = Duration.milliseconds(250)

private let controlChange: UInt8 = 0xB0
private let allSoundOff: UInt8 = 120
private let allNotesOff: UInt8 = 123
private let midiChannels: ClosedRange<UInt8> = 0...15

/// At most this many parameters follow one control change; a knob mapped to more drops the rest.
private let maxWritesPerControlChange = 32

/// One step of a knob's travel, as a fraction of a parameter's range: a read-back closer than this to
/// what the knob left is the knob's own.
private let knobStep = 1.0 / 127

/// Where the events of one route go, and whose they are.
public struct MIDIRouteTarget: Equatable, Sendable {
    public var route: MIDIRoute
    public var slot: Int32
    /// The channel the route belongs to, for `eventCount`.
    public var channel: UUID

    public init(route: MIDIRoute, slot: Int32, channel: UUID) {
        self.route = route
        self.slot = slot
        self.channel = channel
    }
}

/// A knob mapped to a parameter of a plugin in the rack.
public struct ControlTarget: Sendable {
    public var knob: ControlKnob
    /// The rack node that holds the plugin, for `takeMovedNodes` and `rearmControls`.
    public var node: UUID
    public var parameter: AudioUnitParameterID
    /// Nil while the plugin loads, when it failed or when it lacks the parameter. The knob is still
    /// swallowed then.
    public var write: ControlWrite?

    public init(knob: ControlKnob, node: UUID, parameter: AudioUnitParameterID, write: ControlWrite?) {
        self.knob = knob
        self.node = node
        self.parameter = parameter
        self.write = write
    }
}

/// What a knob needs to write its parameter: the plugin, the parameter's range, and the part `from`
/// to `to` of that range the knob's travel covers.
public struct ControlWrite: Sendable {
    public var plugin: HostedPlugin
    public var range: ParameterRange
    public var from: Double
    public var to: Double

    public init(plugin: HostedPlugin, range: ParameterRange, from: Double, to: Double) {
        self.plugin = plugin
        self.range = range
        self.from = from
        self.to = to
    }
}

/// Takes MIDI from every system source to the strips that want it, and follows the clock of one
/// source. Notes go from the CoreMIDI thread straight into the render core and never wait for the
/// main actor. The app only listens: it has no output port and sends MIDI to nothing.
///
/// `clockRunning` and `tempo` follow at 4 Hz, from a poll on the main actor, so the CoreMIDI thread
/// never hops here and a clock that goes silent still shows. `tempo` is what plugins are told, which
/// is the last tempo known, or 120 BPM if there has been none. That poll also stops the transport of
/// a source that went silent without a Stop, and then only a Start or Continue starts it again.
///
/// A control change that matches a knob of `setControls` goes to no instrument. It sets the knob's
/// parameters instead, from the CoreMIDI thread as well, once each has taken over (`Takeover`). A
/// parameter that moved another way since the knob last wrote it, such as by a program change or the
/// plugin's own modulation, makes the knob wait again; the knob sees that at its next move.
///
/// The router does not own the engine, and must go before the engine does.
@MainActor
@Observable
public final class MIDIRouter {

    /// The names of the system's sources in its order. Sources with one name are one name here,
    /// and a route to it hears them all.
    public private(set) var sources: [String] = []

    public private(set) var clockRunning = false
    public private(set) var tempo = ClockTracker.defaultTempo

    private let routing: MIDIRouting
    @ObservationIgnored private let parameterEvents = ParameterEvents()
    @ObservationIgnored private var input: MIDIInput?
    @ObservationIgnored private var clockPoll: Task<Void, Never>?

    /// The app's one Audio Unit event listener, which sends every mapped write, so that a listener
    /// watching for the owner's moves can tell them from the knobs'. Its events go to the handlers
    /// of `addParameterHandler`. Nil only if the system could not make one; writes then go without it. It
    /// lasts as long as the router.
    public var parameterListener: AUEventListenerRef? { routing.parameterListener }

    /// Hears each event of `parameterListener` that is about `audioUnit`, on the main actor, until
    /// `removeParameterHandler` or `close`. Several windows can watch at once, each its own plugin.
    public func addParameterHandler(for audioUnit: AudioUnit, _ handler: @escaping (AudioUnitEvent) -> Void) -> UUID {
        let token = UUID()
        if !isClosed { parameterEvents.handlers[token] = (audioUnit, handler) }
        return token
    }

    public func removeParameterHandler(_ token: UUID) {
        parameterEvents.handlers[token] = nil
    }

    /// Without a CoreMIDI client, which is not an error, `sources` stays empty and only `handle`
    /// gets events through.
    public init(engine: OpaquePointer) {
        routing = MIDIRouting(engine: engine, parameterEvents: parameterEvents)
        input = MIDIInput(routing: routing) { [weak self] in
            Task { @MainActor in self?.refreshSources() }
        }
        refreshSources()
        clockPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: clockPollInterval)
                guard let self else { return }
                refreshClock(at: routing.hostSeconds())
            }
        }
    }

    deinit {
        clockPoll?.cancel()
        routing.close()
    }

    /// Past this, nothing reaches the engine, so the engine can go.
    public private(set) var isClosed = false

    /// Lets go of every source and stops the clock poll. The router does nothing after this.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        clockPoll?.cancel()
        input = nil
        routing.close()
        parameterEvents.handlers = [:]
        sources = []
    }

    /// Applies at once: the next event goes by these routes. The note off of a note held on a route
    /// that left would go nowhere, so its slot gets all sound off and all notes off. A slot whose
    /// route stays gets nothing, so an edit elsewhere cuts no note.
    public func setRoutes(_ routes: [MIDIRouteTarget]) {
        guard !isClosed else { return }
        routing.setRoutes(routes)
    }

    /// Applies at once, like `setRoutes`. A target with the node, parameter and knob of one in the
    /// table keeps its takeover and a move `takeMovedNodes` has not reported yet, and while its plugin
    /// stays, what it wrote last; any other waits for its parameter.
    public func setControls(_ targets: [ControlTarget]) {
        guard !isClosed else { return }
        routing.setControls(targets)
    }

    /// The knobs of `node`, or only those of its `parameter`, wait for the parameter again: after a
    /// preset is picked, or when the owner moved the parameter in the plugin's window.
    public func rearmControls(node: UUID, parameter: AudioUnitParameterID? = nil) {
        routing.rearmControls(node: node, parameter: parameter)
    }

    /// The nodes a knob wrote to since the last call.
    public func takeMovedNodes() -> Set<UUID> {
        routing.takeMovedNodes()
    }

    /// While on, the newest control change from any source, mapped or not, waits for
    /// `takeLearnedKnob`, and no control change goes to an instrument. Off forgets it.
    public func setLearning(_ on: Bool) {
        guard !isClosed else { return }
        routing.setLearning(on)
    }

    /// The knob of the newest control change since learning went on or since the last take.
    public func takeLearnedKnob() -> ControlKnob? {
        routing.takeLearnedKnob()
    }

    /// How many channel-voice messages the routes have delivered to `channel` since it got its first
    /// route. Only ever grows while the channel keeps a route; zero for a channel without one. A
    /// message that reaches two channels counts for both, and the count says nothing of the message.
    public func eventCount(channel: UUID) -> UInt64 {
        routing.eventCount(channel: channel)
    }

    /// Follows the clock of the source called `name`, and of nothing when it is nil. A new source
    /// starts over: its transport is stopped until it says otherwise, and plugins keep the last
    /// known tempo until it gives one.
    public func setClockSource(_ name: String?) {
        guard !isClosed else { return }
        routing.setClockSource(name)
        refreshClock(at: routing.hostSeconds())
    }

    /// The one path of every event, from CoreMIDI and from tests. Time in `seconds` only has to
    /// keep to one clock.
    public nonisolated func handle(_ event: MIDIEvent, fromSource source: String, at seconds: Double) {
        routing.handle(event, fromSource: source, at: seconds)
    }

    /// What the poll does each time. `seconds` is on the clock of `handle`.
    func refreshClock(at seconds: Double) {
        let clock = routing.clock(at: seconds)
        if clock.running != clockRunning { clockRunning = clock.running }
        if clock.tempo != tempo { tempo = clock.tempo }
    }

    nonisolated func hostSeconds() -> Double {
        routing.hostSeconds()
    }

    nonisolated func makeReceiveBlock() -> MIDIReceiveBlock {
        routing.makeReceiveBlock()
    }

    nonisolated func sourceTag(named name: String) -> SourceTag {
        routing.tag(named: name)
    }

    private func refreshSources() {
        sources = input?.refresh() ?? []
    }
}

/// Takes the events of the parameter listener to the main actor. The listener comes with the
/// routing, before the router exists.
@MainActor
private final class ParameterEvents {
    var handlers: [UUID: (audioUnit: AudioUnit, handler: (AudioUnitEvent) -> Void)] = [:]

    func deliver(_ event: AudioUnitEvent) {
        let audioUnit = event.mArgument.mParameter.mAudioUnit
        for entry in handlers.values where entry.audioUnit == audioUnit { entry.handler(event) }
    }
}

/// Names one source in the refCon of its connection, so the CoreMIDI thread gets a name without
/// looking anything up.
final class SourceTag: Sendable {
    let name: String

    init(name: String) {
        self.name = name
    }
}

/// What the CoreMIDI thread and the main actor share. Everything here runs on either. The receive
/// block is made here because a closure formed on the main actor belongs to it, and CoreMIDI calls
/// this one on its own thread.
///
/// One `Mutex`, an `os_unfair_lock` on this platform, guards it, and neither side holds it for long.
/// The main actor builds a new route table or tracker outside the lock, swaps it in, and frees the
/// old one after letting go. The CoreMIDI thread holds it for one event, which is a scan of the
/// routes and some pushes onto rings, with no allocation and nothing that blocks. The route table
/// is never changed in place, only replaced.
///
/// Routing inside the lock, rather than retaining the table and routing after, means a replaced
/// table is never used again and never freed on the CoreMIDI thread, a clock that was just replaced
/// cannot overwrite the transport, and nothing reaches the engine after `close`. The all-off messages
/// of a route change go in with the swap, so they come after every note of the old table.
///
/// `pr_engine_push_midi` takes one producer per slot. That producer is the one thread CoreMIDI calls
/// the port's receive block on, whichever source a message came from, the main actor for a route
/// change, or the test's thread for a `handle` in a test. Every push is under the lock, so none of
/// these can overlap.
///
/// The control table is the one thing the CoreMIDI thread changes in place: takeover, moved flags,
/// last writes and the learned knob are values in it, made on the main actor, so nothing is made
/// under the lock. Nothing but `State` holds the table, or the first change would copy it. A control
/// change calls into Audio Units, which take locks of their own, so it never does under this one: it
/// notes its parameters and retains their plugins under the lock, reads their values outside it,
/// decides under the lock again, writes and reads back outside it, and notes what it read under the
/// lock a third time. A table replaced meanwhile writes nothing, but a write that passed its second
/// check can still land after `setControls` or `close`, on a plugin kept alive by its own retain.
private final class MIDIRouting: Sendable {

    private struct Control {
        var target: ControlTarget
        var takeover = Takeover()
        /// Set when the knob wrote, cleared by `takeMovedNodes`.
        var moved = false
        /// What the knob wrote last, while it follows, and what the plugin read back right after.
        /// A plugin may snap, clamp or round what it is given, so the next read-back is compared
        /// with both (`movedElsewhere`).
        var lastWritten: Float?
        var lastRead: Float?

        mutating func rearm() {
            takeover.rearm()
            lastWritten = nil
            lastRead = nil
        }

        /// The parameter, now at `value`, changed another way since the knob last wrote it: it is more
        /// than one knob step from what was written and from what was read back after. A plugin whose
        /// read-back lags a write shows the value written by the next control change.
        func movedElsewhere(to value: Float, in range: ParameterRange) -> Bool {
            guard let lastWritten else { return false }
            let fraction = range.fraction(of: value)
            if abs(fraction - range.fraction(of: lastWritten)) <= knobStep { return false }
            if let lastRead, abs(fraction - range.fraction(of: lastRead)) <= knobStep { return false }
            return true
        }

        func isSame(as other: ControlTarget) -> Bool {
            target.node == other.node && target.parameter == other.parameter && target.knob.isSame(as: other.knob)
        }
    }

    private struct State {
        var routes: [MIDIRouteTarget] = []
        /// One entry per channel with a route, made when the routes are set, so counting on the
        /// CoreMIDI thread changes a value in place and allocates nothing.
        var eventCounts: [UUID: UInt64] = [:]
        var clockSource: String?
        /// Only `handle` gives it ticks. The main actor replaces it whole with a new one, reads
        /// `reading` and stops a stranded transport, so the CoreMIDI thread owns its tick storage and
        /// never copies it.
        var tracker = ClockTracker()
        var reading = ClockTracker().reading
        /// What plugins are told, which outlives any one tracker.
        var tempo = ClockTracker.defaultTempo
        var controls: [Control] = []
        /// Moves on with every new table, so a control change that let go of the lock between its
        /// passes knows its indices still point at the same targets.
        var controlsGeneration: UInt64 = 0
        var isLearning = false
        var learnedKnob: ControlKnob?
    }

    private nonisolated(unsafe) let engine: OpaquePointer
    /// Disposed only with this object, since a write on its way after `close` still sends with it,
    /// and every `handle` holds this object until it returns.
    nonisolated(unsafe) let parameterListener: AUEventListenerRef?
    private let secondsPerHostTick: Double
    private let state = Mutex(State())
    /// One per name and never removed, so that a callback carrying a tag finds it alive even after
    /// its source left. The receive block holds this object, so the tags outlive every callback.
    private let tags = Mutex<[String: SourceTag]>([:])

    /// On the main actor, whose queue the listener reports on.
    init(engine: OpaquePointer, parameterEvents: ParameterEvents) {
        self.engine = engine
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        secondsPerHostTick = Double(timebase.numer) / Double(timebase.denom) / 1e9
        var listener: AUEventListenerRef?
        let status = AUEventListenerCreateWithDispatchQueue(&listener, 0, 0, .main) { _, event, _, _ in
            let event = event.pointee
            MainActor.assumeIsolated { parameterEvents.deliver(event) }
        }
        if status != noErr { logger.error("Cannot create a parameter listener: \(status)") }
        parameterListener = status == noErr ? listener : nil
    }

    /// Can run on the CoreMIDI thread, when the receive block lets go last.
    deinit {
        guard let parameterListener else { return }
        nonisolated(unsafe) let listener = parameterListener
        if Thread.isMainThread {
            AUListenerDispose(listener)
        } else {
            DispatchQueue.main.async { AUListenerDispose(listener) }
        }
    }

    func handle(_ event: MIDIEvent, fromSource source: String, at seconds: Double) {
        if case .channelVoice(let status, let data1, let data2) = event, status & 0xF0 == controlChange {
            handleControlChange(status: status, controller: data1, value: data2, fromSource: source)
            return
        }
        state.withLock { state in
            if case .channelVoice(let status, let data1, let data2) = event {
                route(status: status, data1: data1, data2: data2, fromSource: source, in: &state)
            } else if let clockSource = state.clockSource, isSameName(clockSource, source) {
                state.tracker.receive(event, at: seconds)
                state.reading = state.tracker.reading
                state.tempo = state.reading.tempo ?? state.tempo
                if state.reading.justStarted { pr_engine_rewind_transport(engine) }
                pr_engine_set_transport(engine, state.tempo, state.reading.isPlaying)
            }
        }
    }

    /// Only under the lock.
    private func route(status: UInt8, data1: UInt8, data2: UInt8, fromSource source: String, in state: inout State) {
        for target in state.routes where isSameName(target.route.sourceName, source) && target.route.channel.matches(status: status) {
            pr_engine_push_midi(engine, target.slot, status, data1, data2)
            state.eventCounts[target.channel, default: 0] &+= 1
        }
    }

    /// The passes of the type comment. Their scratch is on the stack, and whatever is let go of, the
    /// knob a learn replaced or a plugin's retain, goes after the lock.
    private func handleControlChange(status: UInt8, controller: UInt8, value: UInt8, fromSource source: String) {
        // A copy of the source's name, which is a retain: the name lives in its tag.
        var heard: ControlKnob? = ControlKnob(source: source, channel: Int(status & 0x0F) + 1, controller: Int(controller))
        withUnsafeTemporaryAllocation(of: PendingWrite.self, capacity: maxWritesPerControlChange) { pending in
            var count = 0
            var generation: UInt64 = 0
            state.withLock { state in
                if state.isLearning { swap(&state.learnedKnob, &heard) }
                var isMapped = false
                for index in state.controls.indices where state.controls[index].target.knob.matches(heard: source, status: status, controller: controller) {
                    isMapped = true
                    guard count < pending.count, let write = state.controls[index].target.write else { continue }
                    let entry = PendingWrite(
                        plugin: .passRetained(write.plugin), unit: write.plugin.audioUnit, index: Int32(index),
                        parameter: state.controls[index].target.parameter, value: 0
                    )
                    (pending.baseAddress! + count).initialize(to: entry)
                    count += 1
                }
                // While learning, an instrument that answers the knob itself would report a touch of its
                // own parameter, and that would take the knob instead of the one the owner moved.
                if !isMapped && !state.isLearning { route(status: status, data1: controller, data2: value, fromSource: source, in: &state) }
                generation = state.controlsGeneration
            }
            guard count > 0 else { return }

            for index in 0..<count {
                AudioUnitGetParameter(pending[index].unit, pending[index].parameter, kAudioUnitScope_Global, 0, &pending[index].value)
            }

            state.withLock { state in
                let isSameTable = state.controlsGeneration == generation
                for index in 0..<count {
                    let control = Int(pending[index].index)
                    pending[index].index = -1
                    guard isSameTable, let write = state.controls[control].target.write else { continue }
                    let current = write.range.fraction(of: pending[index].value)
                    if state.controls[control].movedElsewhere(to: pending[index].value, in: write.range) {
                        state.controls[control].rearm()
                    }
                    guard state.controls[control].takeover.follow(knob: value, currentFraction: current, from: write.from, to: write.to)
                    else { continue }
                    pending[index].value = write.range.value(atFraction: ControlMapping.fraction(forKnob: value, from: write.from, to: write.to))
                    pending[index].index = Int32(control)
                    state.controls[control].moved = true
                    state.controls[control].lastWritten = pending[index].value
                    state.controls[control].lastRead = nil
                }
            }

            var wrote = false
            for index in 0..<count where pending[index].index >= 0 {
                var parameter = AudioUnitParameter(
                    mAudioUnit: pending[index].unit, mParameterID: pending[index].parameter, mScope: kAudioUnitScope_Global, mElement: 0
                )
                AUParameterSet(parameterListener, nil, &parameter, pending[index].value, 0)
                AudioUnitGetParameter(pending[index].unit, pending[index].parameter, kAudioUnitScope_Global, 0, &pending[index].value)
                wrote = true
            }

            // A rearm in between leaves no `lastWritten`, so a read noted after it compares with nothing.
            if wrote {
                state.withLock { state in
                    guard state.controlsGeneration == generation else { return }
                    for index in 0..<count where pending[index].index >= 0 {
                        state.controls[Int(pending[index].index)].lastRead = pending[index].value
                    }
                }
            }

            for index in 0..<count {
                // The last reference can go here; the plugin then hands its disposal to the main thread.
                pending[index].plugin.release()
            }
        }
    }

    func setControls(_ targets: [ControlTarget]) {
        var replaced = targets.map { Control(target: $0) }
        state.withLock { state in
            // A target that stays keeps its takeover and its move, and its last write while its plugin
            // stays. Only values move here, nothing is made.
            for index in replaced.indices {
                guard let old = state.controls.firstIndex(where: { $0.isSame(as: replaced[index].target) }) else { continue }
                replaced[index].takeover = state.controls[old].takeover
                replaced[index].moved = state.controls[old].moved
                if replaced[index].target.write?.plugin === state.controls[old].target.write?.plugin {
                    replaced[index].lastWritten = state.controls[old].lastWritten
                    replaced[index].lastRead = state.controls[old].lastRead
                }
            }
            swap(&state.controls, &replaced)
            state.controlsGeneration &+= 1
        }
    }

    func rearmControls(node: UUID, parameter: AudioUnitParameterID?) {
        state.withLock { state in
            for index in state.controls.indices where state.controls[index].target.node == node {
                if let parameter, state.controls[index].target.parameter != parameter { continue }
                state.controls[index].rearm()
            }
        }
    }

    func takeMovedNodes() -> Set<UUID> {
        // Room for every target, so the lock below never grows it. Only the main actor changes the
        // table, so it cannot grow in between; if it did, the rest would wait for the next call.
        var nodes: [UUID] = []
        nodes.reserveCapacity(state.withLock { $0.controls.count })
        state.withLock { state in
            for index in state.controls.indices where state.controls[index].moved {
                guard nodes.count < nodes.capacity else { break }
                nodes.append(state.controls[index].target.node)
                state.controls[index].moved = false
            }
        }
        return Set(nodes)
    }

    func setLearning(_ on: Bool) {
        var forgotten: ControlKnob?
        state.withLock { state in
            state.isLearning = on
            if !on { swap(&state.learnedKnob, &forgotten) }
        }
    }

    func takeLearnedKnob() -> ControlKnob? {
        var taken: ControlKnob?
        state.withLock { swap(&$0.learnedKnob, &taken) }
        return taken
    }

    func setRoutes(_ routes: [MIDIRouteTarget]) {
        var replaced = routes
        var counts = Dictionary(routes.map { ($0.channel, UInt64(0)) }, uniquingKeysWith: { first, _ in first })
        state.withLock { state in
            // A channel that keeps a route keeps its count. Only values move here, nothing is made.
            for target in routes { counts[target.channel] = state.eventCounts[target.channel] ?? 0 }
            swap(&state.eventCounts, &counts)
            swap(&state.routes, &replaced)
            for target in replaced where !state.routes.contains(target) {
                pushAllOff(slot: target.slot)
            }
        }
    }

    func eventCount(channel: UUID) -> UInt64 {
        state.withLock { $0.eventCounts[channel] ?? 0 }
    }

    /// 32 messages, far less than a ring holds. Only under the lock.
    private func pushAllOff(slot: Int32) {
        for channel in midiChannels {
            pr_engine_push_midi(engine, slot, controlChange | channel, allSoundOff, 0)
            pr_engine_push_midi(engine, slot, controlChange | channel, allNotesOff, 0)
        }
    }

    func setClockSource(_ name: String?) {
        var replaced = ClockTracker()
        state.withLock { state in
            guard name != state.clockSource else { return }
            state.clockSource = name
            swap(&state.tracker, &replaced)
            state.reading = state.tracker.reading
            pr_engine_set_transport(engine, state.tempo, false)
        }
    }

    func clock(at seconds: Double) -> (running: Bool, tempo: Double) {
        state.withLock { state in
            if state.reading.isStranded(at: seconds) {
                // In the tracker as well, or the next tick of a clock that returns would restart it.
                state.tracker.receive(.stop, at: seconds)
                state.reading = state.tracker.reading
                pr_engine_set_transport(engine, state.tempo, false)
            }
            return (state.reading.isClockRunning(at: seconds), state.tempo)
        }
    }

    /// Past this, no event reaches the engine, not even one already on its way, and no knob reaches
    /// a plugin, but for a write already past its last check.
    func close() {
        var replaced: [MIDIRouteTarget] = []
        var counts: [UUID: UInt64] = [:]
        var controls: [Control] = []
        var forgotten: ControlKnob?
        state.withLock { state in
            swap(&state.routes, &replaced)
            swap(&state.eventCounts, &counts)
            state.clockSource = nil
            swap(&state.controls, &controls)
            state.controlsGeneration &+= 1
            state.isLearning = false
            swap(&state.learnedKnob, &forgotten)
        }
    }

    func hostSeconds() -> Double {
        Double(mach_absolute_time()) * secondsPerHostTick
    }

    func tag(named name: String) -> SourceTag {
        tags.withLock { tags in
            if let tag = tags[name] { return tag }
            let tag = SourceTag(name: name)
            tags[name] = tag
            return tag
        }
    }

    func makeReceiveBlock() -> MIDIReceiveBlock {
        { [self] list, refCon in
            guard let refCon else { return }
            let source = Unmanaged<SourceTag>.fromOpaque(refCon).takeUnretainedValue()
            let seconds = hostSeconds()
            forEachEvent(in: list) { handle($0, fromSource: source.name, at: seconds) }
        }
    }
}

/// One parameter a control change reaches, on the stack between the passes of `handle`. Plain
/// values only, so the scratch needs no cleanup.
private struct PendingWrite {
    /// Retained in the first pass, so a table replaced meanwhile cannot free the plugin.
    var plugin: Unmanaged<HostedPlugin>
    var unit: AudioUnit
    /// The target in the table, and -1 once the second pass decided not to write.
    var index: Int32
    var parameter: AudioUnitParameterID
    /// The parameter's value read in between, then the value to write, then what was read back after it.
    var value: AudioUnitParameterValue
}

/// What one control change puts on the stack. Swift keeps a temporary allocation of up to 1 KiB there
/// and takes anything larger from the heap, so this must stay within that.
let controlChangeScratchBytes = MemoryLayout<PendingWrite>.stride * maxWritesPerControlChange

extension ControlKnob {
    /// By value, without making the knob of the message. The channel and controller come from the
    /// status byte, so a knob decoded with numbers out of range never matches.
    fileprivate func matches(heard source: String, status: UInt8, controller: UInt8) -> Bool {
        self.controller == Int(controller) && channel == Int(status & 0x0F) + 1 && isSameName(self.source, source)
    }

    /// By bytes, like `matches`, since this runs under the lock.
    fileprivate func isSame(as other: ControlKnob) -> Bool {
        controller == other.controller && channel == other.channel && isSameName(source, other.source)
    }
}

/// The CoreMIDI client and its input port. `refresh` runs on the main actor.
private final class MIDIInput {
    private let routing: MIDIRouting
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: [MIDIEndpointRef: String] = [:]

    /// `setupChanged` is called on a thread of CoreMIDI's choosing.
    init?(routing: MIDIRouting, setupChanged: @escaping @Sendable () -> Void) {
        self.routing = routing
        var status = MIDIClientCreateWithBlock("Rackmate" as CFString, &client) { notification in
            if notification.pointee.messageID == .msgSetupChanged { setupChanged() }
        }
        guard status == noErr else {
            logger.error("Cannot create a MIDI client: \(status)")
            return nil
        }
        status = MIDIInputPortCreateWithProtocol(client, "Rackmate In" as CFString, ._1_0, &port, routing.makeReceiveBlock())
        guard status == noErr else {
            logger.error("Cannot create a MIDI input port: \(status)")
            return nil
        }
    }

    /// Runs for a failed `init` too, and takes the port with the client.
    deinit {
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Connects what is new, lets go of what is gone, and returns the names of the sources.
    func refresh() -> [String] {
        let endpoints = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { $0 != 0 }
        let names = endpoints.map(Self.name)
        let present = Dictionary(zip(endpoints, names), uniquingKeysWith: { first, _ in first })
        let changes = connectionChanges(connected: connected, present: present)
        for endpoint in changes.disconnect {
            MIDIPortDisconnectSource(port, endpoint)
            connected[endpoint] = nil
        }
        for endpoint in changes.connect {
            guard let name = present[endpoint] else { continue }
            let tag = Unmanaged.passUnretained(routing.tag(named: name)).toOpaque()
            let status = MIDIPortConnectSource(port, endpoint, tag)
            if status == noErr {
                connected[endpoint] = name
            } else {
                logger.error("Cannot connect \(name, privacy: .public): \(status)")
            }
        }
        return uniqueSourceNames(names)
    }

    private static func name(of endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr, let value else {
            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            return "Source \(uniqueID)"
        }
        var name = value.takeRetainedValue() as String
        // A native string, so that comparing it per message never calls back into a bridged one.
        name.makeContiguousUTF8()
        return name
    }
}

/// By bytes, because `==` allocates to compare strings with stacked combining marks, and this runs
/// per message. Every name comes from CoreMIDI, so one source always has the same bytes.
private func isSameName(_ first: String, _ second: String) -> Bool {
    first.utf8.elementsEqual(second.utf8)
}

/// What to do when the sources `present` replace the ones `connected`. A source that was renamed
/// is in both lists, because its name lives in its connection.
func connectionChanges(
    connected: [MIDIEndpointRef: String], present: [MIDIEndpointRef: String]
) -> (disconnect: [MIDIEndpointRef], connect: [MIDIEndpointRef]) {
    (
        disconnect: connected.filter { present[$0.key] != $0.value }.map(\.key),
        connect: present.filter { connected[$0.key] != $0.value }.map(\.key)
    )
}

func uniqueSourceNames(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    return names.filter { seen.insert($0).inserted }
}

/// Calls `body` with each message in `list` that is a `MIDIEvent`.
func forEachEvent(in list: UnsafePointer<MIDIEventList>, _ body: (MIDIEvent) -> Void) {
    for packet in list.unsafeSequence() {
        let words = packet.words()
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            if let event = MIDIEvent(ump: word) { body(event) }
            index += wordCount(ofMessageStartingWith: word)
        }
    }
}

/// A packet can hold several messages, and a later word of a long one, such as system exclusive
/// data, can look like a note or a clock tick. The message type in the top four bits gives the size.
private func wordCount(ofMessageStartingWith word: UInt32) -> Int {
    switch word >> 28 {
    case 0x0, 0x1, 0x2, 0x6, 0x7: 1
    case 0x3, 0x4, 0x8, 0x9, 0xA: 2
    case 0xB, 0xC: 3
    default: 4
    }
}
