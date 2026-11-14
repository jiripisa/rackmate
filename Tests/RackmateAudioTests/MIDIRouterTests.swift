import AudioToolbox
import CRenderCore
import CoreMIDI
import Foundation
import RackmateCore
import RackmateTestUnits
import Synchronization
import Testing
@testable import RackmateAudio

private let outs23 = PRChannels(left: 2, right: 3)
private let noteOnChannel1 = MIDIEvent.channelVoice(status: 0x90, data1: 60, data2: 100)
private let noteOnUMP: UInt32 = 0x2090_3C64
private let noteOffUMP: UInt32 = 0x2080_3C00
private let clockUMP: UInt32 = 0x10F8_0000
/// At the default 120 BPM.
private let beatsPerBlock = Float(blockFrames) * 2 / Float(sampleRate)

/// The channel of a slot, so that a target for a slot is always for the same channel.
private func channelID(ofSlot slot: Int32) -> UUID {
    UUID(uuid: (UInt8(truncatingIfNeeded: slot), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
}

private func target(_ source: String, _ channel: MIDIChannelFilter, slot: Int32) -> MIDIRouteTarget {
    MIDIRouteTarget(route: MIDIRoute(sourceName: source, channel: channel), slot: slot, channel: channelID(ofSlot: slot))
}

/// Sends `count` clock ticks and returns the time of the last one.
@MainActor
@discardableResult
private func sendTicks(_ router: MIDIRouter, bpm: Double = 124, count: Int = 48, from source: String = "A", after start: Double = 0) -> Double {
    let interval = 60 / bpm / 24
    var time = start
    for _ in 0..<count {
        time += interval
        router.handle(.clock, fromSource: source, at: time)
    }
    return time
}

/// Runs `body` with a router on a new engine playing `strips`, and lets the router go first.
@MainActor
private func withRouter(_ strips: [StripSpec], _ body: @MainActor (MIDIRouter, Rig) async throws -> Void) async throws {
    let rig = Rig()
    for strip in strips {
        #expect(pr_install_host_callbacks(strip.source.audioUnit, rig.engine) == noErr)
        pr_engine_set_follows_transport(rig.engine, strip.source.audioUnit, true)
    }
    rig.install(strips)
    defer { withExtendedLifetime(rig) {} }
    try await body(MIDIRouter(engine: rig.engine), rig)
}

/// One instrument on outputs 1-2 at slot 0, and one on outputs 3-4 at slot 1.
private func twoInstruments() async throws -> [StripSpec] {
    [
        StripSpec(source: try await instrument(), audioOut: outs01, midiSlot: 0),
        StripSpec(source: try await instrument(), audioOut: outs23, midiSlot: 1),
    ]
}

/// A unit that reports tempo on output 1 and beat, or -1 while stopped, on output 2.
private func tempoReporter() async throws -> [StripSpec] {
    [StripSpec(source: try await loadPlugin(type: "aumu", subtype: "PlTp"))]
}

/// Units reporting the all-off controllers they had: one on outputs 1-2 at slot 0, and one on outputs
/// 3-4 at slot 1. All Sound Off shows on the first output of each, All Notes Off on the second.
private func allOffReporters() async throws -> [StripSpec] {
    [
        StripSpec(source: try await loadPlugin(type: "aumu", subtype: "PlOf"), audioOut: outs01, midiSlot: 0),
        StripSpec(source: try await loadPlugin(type: "aumu", subtype: "PlOf"), audioOut: outs23, midiSlot: 1),
    ]
}

/// What an all-off reporter shows once a controller came on each of the 16 MIDI channels.
private let everyChannel: Float = 0.16

private let knob74 = ControlKnob(source: "A", channel: 1, controller: 74)

/// A control change on MIDI channel `channel`, 1 to 16.
private func controlChange(_ controller: UInt8, _ value: UInt8, channel: UInt8 = 1) -> MIDIEvent {
    .channelVoice(status: 0xB0 | (channel - 1), data1: controller, data2: value)
}

/// Test Controls, outside any graph: a mapped write needs no render.
@MainActor
private func testControls() async throws -> HostedPlugin {
    try await loadPlugin(type: "aufx", subtype: "PlCt")
}

/// By name, since the v2 bridge numbers the parameters by itself.
@MainActor
private func parameter(_ name: String, of plugin: HostedPlugin) throws -> PluginParameter {
    try #require(plugin.parameters().first { $0.name == name })
}

/// `knob` driving `parameter` of `plugin` over `from` to `to`. `readsBack` overrides what the unit's kind
/// decides.
private func control(
    _ knob: ControlKnob, node: UUID, _ parameter: PluginParameter, of plugin: HostedPlugin, from: Double = 0, to: Double = 1,
    readsBack: Bool? = nil
) -> ControlTarget {
    ControlTarget(
        knob: knob, node: node, parameter: parameter.id,
        write: ControlWrite(plugin: plugin, range: parameter.range, from: from, to: to, readsBack: readsBack)
    )
}

private func value(of parameter: PluginParameter, in plugin: HostedPlugin) -> Float {
    var value: AudioUnitParameterValue = 0
    AudioUnitGetParameter(plugin.audioUnit, parameter.id, kAudioUnitScope_Global, 0, &value)
    return value
}

private func set(_ parameter: PluginParameter, of plugin: HostedPlugin, to value: Float) {
    AudioUnitSetParameter(plugin.audioUnit, parameter.id, kAudioUnitScope_Global, 0, value, 0)
}

/// The way a sequencer's program change or the plugin's own modulation would: not through the router.
private func setElsewhere(_ parameter: PluginParameter, of plugin: HostedPlugin, to value: Float) {
    var address = AudioUnitParameter(mAudioUnit: plugin.audioUnit, mParameterID: parameter.id, mScope: kAudioUnitScope_Global, mElement: 0)
    AUParameterSet(nil, nil, &address, value, 0)
}

/// Sends knob 74 through `positions` and reads `parameter` after each. A v3 unit holds a read right after
/// a write for about 30 ms, so this runs off the main actor, as on the CoreMIDI thread, and the clock
/// polls of other tests keep running.
private func turn(_ router: MIDIRouter, through positions: [Int], reading parameter: PluginParameter, of plugin: HostedPlugin) async -> [Float] {
    await withCheckedContinuation { (continuation: CheckedContinuation<[Float], Never>) in
        DispatchQueue.global(qos: .userInteractive).async {
            continuation.resume(returning: positions.map { position in
                router.handle(controlChange(74, UInt8(position)), fromSource: "A", at: 0)
                return value(of: parameter, in: plugin)
            })
        }
    }
}

/// Where a knob at `position` puts a parameter mapped 0 to 1 with a linear range of 0 to 1.
private func mixAt(_ position: Float) -> Float { position / 127 }

/// `messages` go into one packet each, so a message of several words stays whole.
private func withEventList(_ messages: [[UInt32]], _ body: (UnsafePointer<MIDIEventList>) -> Void) {
    let size = 1024
    let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIEventList>.alignment)
    defer { storage.deallocate() }
    let list = storage.bindMemory(to: MIDIEventList.self, capacity: 1)
    var packet = MIDIEventListInit(list, ._1_0)
    for words in messages {
        packet = MIDIEventListAdd(list, size, packet, 0, words.count, words)
    }
    body(UnsafePointer(list))
}

private func events(in messages: [[UInt32]]) -> [MIDIEvent] {
    var result: [MIDIEvent] = []
    withEventList(messages) { list in
        forEachEvent(in: list) { result.append($0) }
    }
    return result
}

/// Calls `block` the way CoreMIDI does: off the main actor, with a source's refCon.
private func deliver(_ words: [UInt32], source: SourceTag, to block: @escaping MIDIReceiveBlock) async {
    nonisolated(unsafe) let block = block
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global(qos: .userInteractive).async {
            withEventList([words]) { block($0, Unmanaged.passUnretained(source).toOpaque()) }
            continuation.resume()
        }
    }
}

@Suite("MIDI router")
@MainActor
struct MIDIRouterTests {

    // MARK: - Routes

    @Test func noteGoesOnlyToMatchingRoute() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .channel(1), slot: 0), target("A", .channel(2), slot: 1)])
            router.handle(.channelVoice(status: 0x91, data1: 60, data2: 100), fromSource: "A", at: 0)
            let output = rig.render()
            expectLevel(output[0], 0)
            expectLevel(output[2], 0.25)
        }
    }

    @Test func otherSourceIsIgnored() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .channel(1), slot: 0)])
            router.handle(noteOnChannel1, fromSource: "B", at: 0)
            expectLevel(rig.render()[0], 0)
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            expectLevel(rig.render()[0], 0.25)
        }
    }

    @Test func allChannelsRouteAcceptsAny() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0)])
            router.handle(.channelVoice(status: 0x9F, data1: 60, data2: 100), fromSource: "A", at: 0)
            expectLevel(rig.render()[0], 0.25)
        }
    }

    @Test func oneEventGoesToEveryMatchingRoute() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .channel(1), slot: 0), target("A", .all, slot: 1)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            let output = rig.render()
            expectLevel(output[0], 0.25)
            expectLevel(output[2], 0.25)
        }
    }

    @Test func eventCountAdvancesOnlyForTheChannelThatReceives() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            let first = channelID(ofSlot: 0)
            let second = channelID(ofSlot: 1)
            router.setRoutes([target("A", .channel(1), slot: 0), target("A", .channel(2), slot: 1)])
            #expect(router.eventCount(channel: first) == 0)

            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            #expect(router.eventCount(channel: first) == 1)
            #expect(router.eventCount(channel: second) == 0)

            router.handle(.channelVoice(status: 0x80, data1: 60, data2: 0), fromSource: "A", at: 0)
            router.handle(noteOnChannel1, fromSource: "B", at: 0)
            router.handle(.clock, fromSource: "A", at: 0)
            #expect(router.eventCount(channel: first) == 2)
            #expect(router.eventCount(channel: second) == 0)
            #expect(router.eventCount(channel: UUID()) == 0)
        }
    }

    @Test func aMessageForTwoChannelsCountsForBoth() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .channel(1), slot: 0), target("A", .all, slot: 1)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 1)
            #expect(router.eventCount(channel: channelID(ofSlot: 1)) == 1)
        }
    }

    @Test func theCountSurvivesAnEditThatKeepsTheChannel() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .channel(1), slot: 0)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            router.setRoutes([target("A", .channel(1), slot: 0), target("A", .channel(2), slot: 1)])
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 1)
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 2)
        }
    }

    @Test func newRoutesApplyAtOnce() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0)])
            router.setRoutes([target("B", .all, slot: 1)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            router.handle(noteOnChannel1, fromSource: "B", at: 0)
            let output = rig.render()
            expectLevel(output[0], 0)
            expectLevel(output[2], 0.25)
        }
    }

    // MARK: - Route changes

    @Test func aHeldNoteStopsWhenItsRouteChanges() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0), target("A", .all, slot: 1)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            var output = rig.render()
            expectLevel(output[0], 0.25)
            expectLevel(output[2], 0.25)

            // The key comes up on the old source, whose note off no longer reaches slot 0.
            router.setRoutes([target("B", .all, slot: 0), target("A", .all, slot: 1)])
            router.handle(.channelVoice(status: 0x80, data1: 60, data2: 0), fromSource: "A", at: 0)
            output = rig.render()
            expectLevel(output[0], 0)
            expectLevel(output[2], 0)
        }
    }

    @Test func aHeldNoteOnAnUnchangedRoutePlaysThroughAnEditOfAnother() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0), target("A", .all, slot: 1)])
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            _ = rig.render()

            router.setRoutes([target("B", .all, slot: 0), target("A", .all, slot: 1)])
            let output = rig.render()
            expectLevel(output[0], 0)
            expectLevel(output[2], 0.25)
        }
    }

    @Test(arguments: [
        [target("B", .channel(1), slot: 0)],
        [target("A", .channel(2), slot: 0)],
        [target("A", .channel(1), slot: 1)],
        [],
    ])
    func aRouteThatLeavesItsSlotSendsAllOffOnEveryChannel(routes: [MIDIRouteTarget]) async throws {
        try await withRouter(try await allOffReporters()) { router, rig in
            router.setRoutes([target("A", .channel(1), slot: 0)])
            expectLevel(rig.render()[0], 0)

            router.setRoutes(routes)
            let output = rig.render()
            expectLevel(output[0], everyChannel)
            expectLevel(output[1], everyChannel)
        }
    }

    @Test func aRouteThatStaysSendsNothing() async throws {
        try await withRouter(try await allOffReporters()) { router, rig in
            let first = target("A", .channel(1), slot: 0)
            let second = target("B", .all, slot: 1)
            router.setRoutes([first, second])
            router.setRoutes([second, first])
            for channel in rig.render() { expectLevel(channel, 0) }
        }
    }

    @Test func aFirstRouteOnASlotSendsNothing() async throws {
        try await withRouter(try await allOffReporters()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0)])
            for channel in rig.render() { expectLevel(channel, 0) }
        }
    }

    // MARK: - Clock

    @Test func clockFromOtherSourceIsIgnored() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router, from: "B")
            router.handle(.start, fromSource: "B", at: last)
            router.refreshClock(at: last)
            #expect(router.tempo == 120)
            #expect(!router.clockRunning)
            let output = rig.render()
            expectLevel(output[0], 0.12)
            expectLevel(output[1], -1)
        }
    }

    @Test func clockSetsTempoSeenByPlugin() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.refreshClock(at: last)
            #expect(abs(router.tempo - 124) < 0.1)
            #expect(router.clockRunning)
            expectLevel(rig.render()[0], 0.124)
        }
    }

    @Test func stopClearsPlayingForPlugin() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            expectLevel(rig.render()[1], 0)
            router.handle(.stop, fromSource: "A", at: last)
            let output = rig.render()
            expectLevel(output[1], -1)
            expectLevel(output[0], 0.124)
        }
    }

    @Test func continueResumesPlayingForPlugin() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            _ = rig.render()
            router.handle(.stop, fromSource: "A", at: 0)
            expectLevel(rig.render()[1], -1)
            router.handle(.resume, fromSource: "A", at: 0)
            #expect(rig.render()[1][0] > 0)
        }
    }

    @Test func startAfterStopPlaysFromTheTop() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            for _ in 0..<100 { _ = rig.render() }
            router.handle(.stop, fromSource: "A", at: 1)
            expectLevel(rig.render()[1], -1)
            router.handle(.start, fromSource: "A", at: 2)
            expectLevel(rig.render()[1], 0)
            expectLevel(rig.render()[1], beatsPerBlock)
        }
    }

    @Test func continueAfterStopKeepsThePosition() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            for _ in 0..<100 { _ = rig.render() }
            router.handle(.stop, fromSource: "A", at: 1)
            expectLevel(rig.render()[1], -1)
            router.handle(.resume, fromSource: "A", at: 2)
            expectLevel(rig.render()[1], 100 * beatsPerBlock)
        }
    }

    @Test func startWhilePlayingPlaysFromTheTop() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            for _ in 0..<100 { _ = rig.render() }
            router.handle(.start, fromSource: "A", at: 1)
            expectLevel(rig.render()[1], 0)
        }
    }

    @Test func aTickAfterAStartDoesNotRewindAgain() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            for _ in 0..<100 { _ = rig.render() }
            router.handle(.clock, fromSource: "A", at: 0.5)
            expectLevel(rig.render()[1], 100 * beatsPerBlock)
        }
    }

    @Test func startFromOtherSourceDoesNotRewind() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 0)
            for _ in 0..<100 { _ = rig.render() }
            router.handle(.start, fromSource: "B", at: 1)
            expectLevel(rig.render()[1], 100 * beatsPerBlock)
        }
    }

    @Test func noClockSourceFollowsNothing() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            let last = sendTicks(router)
            router.refreshClock(at: last)
            #expect(router.tempo == 120)
            #expect(!router.clockRunning)
            expectLevel(rig.render()[0], 0.12)
        }
    }

    @Test func aRunningClockFallsWhenTicksStopAndTheTempoStays() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.refreshClock(at: last + 0.5)
            #expect(router.clockRunning)
            router.refreshClock(at: last + 1.5)
            #expect(!router.clockRunning)
            #expect(abs(router.tempo - 124) < 0.1)
            expectLevel(rig.render()[0], 0.124)
        }
    }

    @Test func aClockThatDiesStopsTheTransportAndTheTempoStays() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            expectLevel(rig.render()[1], 0)

            router.refreshClock(at: last + 0.5)
            #expect(rig.render()[1][0] > 0)

            router.refreshClock(at: last + 1.5)
            #expect(!router.clockRunning)
            let output = rig.render()
            expectLevel(output[0], 0.124)
            expectLevel(output[1], -1)
        }
    }

    @Test func aClockThatComesBackDoesNotRestartTheTransport() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            var last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            router.refreshClock(at: last + 1.5)

            last = sendTicks(router, after: last + 2)
            router.refreshClock(at: last)
            #expect(router.clockRunning)
            expectLevel(rig.render()[1], -1)

            router.handle(.resume, fromSource: "A", at: last)
            #expect(rig.render()[1][0] >= 0)
            #expect(rig.render()[1][0] > 0)
        }
    }

    @Test func aStartAfterADeadClockPlaysFromTheTop() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            for _ in 0..<100 { _ = rig.render() }
            router.refreshClock(at: last + 1.5)
            expectLevel(rig.render()[1], -1)

            router.handle(.start, fromSource: "A", at: last + 2)
            expectLevel(rig.render()[1], 0)
        }
    }

    @Test(arguments: [MIDIEvent.start, .resume])
    func aPollRightAfterAStartLeavesItToItsFirstTick(event: MIDIEvent) async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.refreshClock(at: last + 5)
            router.handle(event, fromSource: "A", at: last + 5)
            router.refreshClock(at: last + 5.01)
            #expect(rig.render()[1][0] >= 0)

            sendTicks(router, after: last + 5.02)
            #expect(rig.render()[1][0] > 0)
        }
    }

    @Test func aStartThatNeverGetsATickStopsToo() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.start, fromSource: "A", at: 10)
            router.refreshClock(at: 11.5)
            expectLevel(rig.render()[1], -1)
        }
    }

    @Test func aDeadClockTellsAFollowingUnitThatTheTransportChanged() async throws {
        let strips = try await tempoReporter()
        try await withRouter(strips) { router, rig in
            router.setClockSource("A")
            let last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            _ = rig.render()
            _ = rig.render()

            router.refreshClock(at: last + 1.5)
            _ = rig.render()
            let unit = strips[0].source.audioUnit
            try #expect(!transport(of: unit, in: rig.engine).playing.boolValue)
            try #expect(changedReadings(of: unit, in: rig.engine).allSatisfy { $0 })
        }
    }

    @Test func aUnitThatDoesNotFollowSeesNothingOfADeadClock() async throws {
        let strips = try await tempoReporter()
        try await withRouter(strips) { router, rig in
            let unit = strips[0].source.audioUnit
            pr_engine_set_follows_transport(rig.engine, unit, false)
            router.setClockSource("A")
            let last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            _ = rig.render()
            var output = rig.render()
            expectLevel(output[0], 0.124)
            expectLevel(output[1], -1)

            router.refreshClock(at: last + 1.5)
            output = rig.render()
            expectLevel(output[0], 0.124)
            expectLevel(output[1], -1)
            try #expect(!transport(of: unit, in: rig.engine).playing.boolValue)
            try #expect(changedReadings(of: unit, in: rig.engine).allSatisfy { !$0 })
        }
    }

    @Test func theFirstTickOfAClockChangesNoTempo() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            router.handle(.clock, fromSource: "A", at: 0)
            router.refreshClock(at: 0)
            #expect(router.clockRunning)
            #expect(router.tempo == 120)
            expectLevel(rig.render()[0], 0.12)
        }
    }

    @Test func changingTheClockSourceStartsOverAndKeepsTheTempoUntilANewOneIsKnown() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            var last = sendTicks(router)
            router.handle(.start, fromSource: "A", at: last)
            expectLevel(rig.render()[1], 0)

            router.setClockSource("B")
            #expect(!router.clockRunning)
            #expect(abs(router.tempo - 124) < 0.1)
            var output = rig.render()
            expectLevel(output[0], 0.124)
            expectLevel(output[1], -1)

            // The old source no longer counts.
            last = sendTicks(router, bpm: 60, count: 10, from: "A", after: last)
            router.handle(.start, fromSource: "A", at: last)
            router.refreshClock(at: last)
            #expect(!router.clockRunning)
            #expect(abs(router.tempo - 124) < 0.1)
            output = rig.render()
            expectLevel(output[0], 0.124)
            expectLevel(output[1], -1)

            // One tick from the new source gives no tempo, so plugins keep what they have.
            last = sendTicks(router, count: 1, from: "B", after: last)
            router.handle(.start, fromSource: "B", at: last)
            router.refreshClock(at: last)
            #expect(router.clockRunning)
            #expect(abs(router.tempo - 124) < 0.1)
            expectLevel(rig.render()[0], 0.124)

            // A few ticks make a tempo free of the old source's history.
            last = sendTicks(router, bpm: 90, count: 10, from: "B", after: last)
            router.refreshClock(at: last)
            #expect(abs(router.tempo - 90) < 0.1)
            expectLevel(rig.render()[0], 0.09)
        }
    }

    @Test func settingTheSameClockSourceChangesNothing() async throws {
        try await withRouter(try await tempoReporter()) { router, rig in
            router.setClockSource("A")
            // `setClockSource` reads the host clock, so the events keep to it too.
            let last = sendTicks(router, after: router.hostSeconds())
            router.handle(.start, fromSource: "A", at: last)
            router.setClockSource("A")
            router.refreshClock(at: last)
            #expect(router.clockRunning)
            #expect(rig.render()[1][0] >= 0)
        }
    }

    @Test func thePollFollowsTheClockWithoutAnyHelp() async throws {
        try await withRouter(try await tempoReporter()) { router, _ in
            router.setClockSource("A")
            router.handle(.clock, fromSource: "A", at: router.hostSeconds())
            let rises = ContinuousClock.now + .seconds(1)
            while !router.clockRunning, ContinuousClock.now < rises { try await Task.sleep(for: .milliseconds(10)) }
            #expect(router.clockRunning)
            let falls = ContinuousClock.now + .seconds(3)
            while router.clockRunning, ContinuousClock.now < falls { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!router.clockRunning)
        }
    }

    // MARK: - Controls

    @Test func aMappedKnobSetsTheParameterAndIsNotRouted() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter(try await twoInstruments()) { router, _ in
            let node = UUID()
            router.setRoutes([target("A", .all, slot: 0)])
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            // Mix starts at 0.5, so 64 lands on it and takes over at once.
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(64)) < tolerance)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 0)
            #expect(router.takeMovedNodes() == [node])
            #expect(router.takeMovedNodes().isEmpty)
        }
    }

    @Test func anUnmappedControlChangeStillGoesToTheInstrument() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .all, slot: 0), target("B", .all, slot: 1)])
            router.setControls([control(knob74, node: UUID(), mix, of: plugin)])
            router.handle(controlChange(75, 64), fromSource: "A", at: 0)
            router.handle(controlChange(74, 64, channel: 2), fromSource: "A", at: 0)
            router.handle(.channelVoice(status: 0x90, data1: 74, data2: 64), fromSource: "A", at: 0)
            router.handle(controlChange(74, 64), fromSource: "B", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 3)
            #expect(router.eventCount(channel: channelID(ofSlot: 1)) == 1)
            #expect(value(of: mix, in: plugin) == 0.5)
            #expect(router.takeMovedNodes().isEmpty)
        }
    }

    @Test func aKnobWithoutAWriteIsSwallowed() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .all, slot: 0)])
            router.setControls([ControlTarget(knob: knob74, node: UUID(), parameter: 1, write: nil)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 0)
            #expect(router.takeMovedNodes().isEmpty)
        }
    }

    @Test func oneKnobWritesEveryMappedParameter() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        let cutoff = try parameter("Cutoff", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([
                control(knob74, node: node, mix, of: plugin),
                control(knob74, node: node, cutoff, of: plugin, from: 1, to: 0),
            ])
            // Mix takes over at 64. Cutoff, at 1000 Hz, sits near 55 on its reversed range and waits.
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(64)) < tolerance)
            #expect(value(of: cutoff, in: plugin) == 1000)

            // Crossing 55 takes Cutoff over as well.
            router.handle(controlChange(74, 50), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(50)) < tolerance)
            #expect(abs(value(of: cutoff, in: plugin) - cutoff.range.value(atFraction: 1 - 50.0 / 127)) < 0.01)
            #expect(router.takeMovedNodes() == [node])
        }
    }

    @Test func theKnobWaitsForTheParameter() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        set(mix, of: plugin, to: 0.9)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 10), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - 0.9) < tolerance)
            #expect(router.takeMovedNodes().isEmpty)

            router.handle(controlChange(74, 127), fromSource: "A", at: 0)
            #expect(value(of: mix, in: plugin) == 1)
            #expect(router.takeMovedNodes() == [node])
        }
    }

    @Test func rearmMakesTheKnobWaitAgain() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        let cutoff = try parameter("Cutoff", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            router.rearmControls(node: node)
            router.handle(controlChange(74, 100), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(64)) < tolerance)

            // Taken over again by moving across 64, it follows through a rearm of another parameter or
            // another node.
            router.handle(controlChange(74, 60), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(60)) < tolerance)
            router.rearmControls(node: node, parameter: cutoff.id)
            router.rearmControls(node: UUID())
            router.handle(controlChange(74, 90), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(90)) < tolerance)

            router.rearmControls(node: node, parameter: mix.id)
            router.handle(controlChange(74, 30), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(90)) < tolerance)
        }
    }

    /// With `readsBack`, as for a v2 unit, the knob also keeps what Mix read back after each write, and a
    /// move from outside is far from both.
    @Test(arguments: [false, true])
    func aParameterMovedElsewhereMakesTheKnobWaitAgain(readsBack: Bool) async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin, readsBack: readsBack)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            router.handle(controlChange(74, 70), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(70)) < tolerance)
            _ = router.takeMovedNodes()

            // 0.9 is near 114 on the knob, so a move near the old position writes nothing.
            setElsewhere(mix, of: plugin, to: 0.9)
            router.handle(controlChange(74, 72), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - 0.9) < tolerance)
            #expect(router.takeMovedNodes().isEmpty)

            router.handle(controlChange(74, 120), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(120)) < tolerance)
            #expect(router.takeMovedNodes() == [node])
        }
    }

    @Test func aPluginThatRoundsWhatItReadsBackKeepsFollowing() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            router.setControls([control(knob74, node: UUID(), mix, of: plugin)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            // Rounded to two places, less than one knob step away from what the knob wrote.
            setElsewhere(mix, of: plugin, to: 0.5)
            router.handle(controlChange(74, 100), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(100)) < tolerance)
        }
    }

    @Test func aQuantizedParameterKeepsFollowingATurningKnob() async throws {
        let plugin = try await testControls()
        let steps = try parameter("Steps", of: plugin)
        try await withRouter([]) { router, _ in
            // Read back after each write, as for a v2 unit; Test Controls is a v3 unit, which is not.
            router.setControls([control(knob74, node: UUID(), steps, of: plugin, readsBack: true)])
            let positions = Array(stride(from: 0, through: 125, by: 5))
            let read = await turn(router, through: positions, reading: steps, of: plugin)
            #expect(read == positions.map { (Float($0) / 127 * 3).rounded() / 3 })
        }
    }

    @Test func aV3UnitGetsNoReadAfterAWrite() async throws {
        let plugin = try await testControls()
        #expect(plugin.isAUv3)
        let steps = try parameter("Steps", of: plugin)
        try await withRouter([]) { router, _ in
            router.setControls([control(knob74, node: UUID(), steps, of: plugin)])
            // Without a read after the write, the snapped read-back of 10 looks like a move made another
            // way, and the knob waits again for a value it never passes: the known cost for v3 units.
            let positions = Array(stride(from: 0, through: 125, by: 5))
            let read = await turn(router, through: positions, reading: steps, of: plugin)
            #expect(read == positions.map { _ in 0 })
        }
    }

    @Test func aNewTableKeepsTheTakeoverOfATargetThatStays() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        let cutoff = try parameter("Cutoff", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)

            router.setControls([control(knob74, node: node, cutoff, of: plugin), control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 100), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(100)) < tolerance)
            #expect(value(of: cutoff, in: plugin) == 1000)

            // Another knob on the same parameter is another target, and it waits.
            let knob75 = ControlKnob(source: "A", channel: 1, controller: 75)
            router.setControls([control(knob75, node: node, mix, of: plugin)])
            router.handle(controlChange(75, 10), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(100)) < tolerance)
        }
    }

    // MARK: - Takeover hints

    @Test func aWaitingKnobSaysWhichWayToTurn() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            let key = ControlKey(node: node, parameter: mix.id, knob: knob74)
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            // Mix starts at 0.5, so the knob position is about 64.
            router.handle(controlChange(74, 10), fromSource: "A", at: 0)
            #expect(router.takeoverHints() == [key: .turnUp])

            // Going straight from 10 to 100 would cross 64 and take over.
            router.rearmControls(node: node)
            router.handle(controlChange(74, 100), fromSource: "A", at: 0)
            #expect(router.takeoverHints() == [key: .turnDown])
        }
    }

    @Test func aKnobThatTookOverHasNoHint() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            router.setControls([control(knob74, node: UUID(), mix, of: plugin)])
            router.handle(controlChange(74, 10), fromSource: "A", at: 0)
            router.handle(controlChange(74, 70), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: plugin) - mixAt(70)) < tolerance)
            #expect(router.takeoverHints().isEmpty)
        }
    }

    @Test func aNewTableStartsWithMoveTheKnob() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            let knob75 = ControlKnob(source: "A", channel: 1, controller: 75)
            router.setControls([
                control(knob74, node: node, mix, of: plugin),
                // A row without a write is dimmed and shows nothing.
                ControlTarget(knob: knob75, node: node, parameter: mix.id, write: nil),
            ])
            #expect(router.takeoverHints() == [ControlKey(node: node, parameter: mix.id, knob: knob74): .moveKnob])
        }
    }

    @Test func equalEndsShowNoHint() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin, from: 0.3, to: 0.3)])
            #expect(router.takeoverHints().isEmpty)
            router.rearmControls(node: node)
            #expect(router.takeoverHints().isEmpty)
        }
    }

    @Test func aRearmShowsMoveTheKnob() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(router.takeoverHints().isEmpty)
            router.rearmControls(node: node, parameter: mix.id)
            #expect(router.takeoverHints() == [ControlKey(node: node, parameter: mix.id, knob: knob74): .moveKnob])
        }
    }

    @Test func aNewTableKeepsTheHintOfATargetThatStaysAsItWas() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        let cutoff = try parameter("Cutoff", of: plugin)
        try await withRouter([]) { router, _ in
            let node = UUID()
            let mixKey = ControlKey(node: node, parameter: mix.id, knob: knob74)
            router.setControls([control(knob74, node: node, mix, of: plugin)])
            router.handle(controlChange(74, 10), fromSource: "A", at: 0)

            router.setControls([control(knob74, node: node, mix, of: plugin), control(knob74, node: node, cutoff, of: plugin)])
            #expect(router.takeoverHints() == [mixKey: .turnUp, ControlKey(node: node, parameter: cutoff.id, knob: knob74): .moveKnob])

            // A new range moves the knob position of the value, so the way is not known until the next move.
            router.setControls([control(knob74, node: node, mix, of: plugin, from: 0, to: 0.5)])
            #expect(router.takeoverHints() == [mixKey: .moveKnob])
        }
    }

    @Test func noWriteReachesAPluginAfterItsTableIsReplaced() async throws {
        var plugin: HostedPlugin? = try await testControls()
        weak let unit = plugin
        let mix = try parameter("Mix", of: try #require(plugin))
        try await withRouter([]) { router, _ in
            let controls = try #require(plugin)
            router.setControls([control(knob74, node: UUID(), mix, of: controls)])
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: controls) - mixAt(64)) < tolerance)

            router.setControls([])
            router.handle(controlChange(74, 100), fromSource: "A", at: 0)
            #expect(abs(value(of: mix, in: controls) - mixAt(64)) < tolerance)
            #expect(router.takeMovedNodes().isEmpty)
        }
        plugin = nil
        #expect(unit == nil)
    }

    @Test func aSourceThatComesBackByNameStillWrites() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            // The table and each connection hold the name in strings of their own.
            let name = ["OXI", "E16"].joined(separator: " ")
            router.setControls([control(ControlKnob(source: name, channel: 1, controller: 74), node: UUID(), mix, of: plugin)])
            await deliver([0x20B0_4A40], source: router.sourceTag(named: "OXI E16"), to: router.makeReceiveBlock())
            #expect(abs(value(of: mix, in: plugin) - mixAt(64)) < tolerance)

            // Back after a refresh, under its name and a new receive block.
            let back = String(decoding: Array("OXI E16".utf8), as: UTF8.self)
            await deliver([0x20B0_4A64], source: router.sourceTag(named: back), to: router.makeReceiveBlock())
            #expect(abs(value(of: mix, in: plugin) - mixAt(100)) < tolerance)
        }
    }

    @Test func learningKeepsTheNewestControlChange() async throws {
        try await withRouter([]) { router, _ in
            router.setControls([ControlTarget(knob: knob74, node: UUID(), parameter: 1, write: nil)])
            router.setLearning(true)
            router.handle(controlChange(71, 10, channel: 3), fromSource: "B", at: 0)
            router.handle(controlChange(74, 20), fromSource: "A", at: 0)
            #expect(router.takeLearnedKnob() == knob74)
            #expect(router.takeLearnedKnob() == nil)

            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            #expect(router.takeLearnedKnob() == nil)
            router.handle(controlChange(71, 10, channel: 3), fromSource: "B", at: 0)
            #expect(router.takeLearnedKnob() == ControlKnob(source: "B", channel: 3, controller: 71))
        }
    }

    @Test func learningOffKeepsNothing() async throws {
        try await withRouter([]) { router, _ in
            router.handle(controlChange(74, 20), fromSource: "A", at: 0)
            #expect(router.takeLearnedKnob() == nil)

            router.setLearning(true)
            router.handle(controlChange(74, 20), fromSource: "A", at: 0)
            router.setLearning(false)
            #expect(router.takeLearnedKnob() == nil)
            router.handle(controlChange(74, 30), fromSource: "A", at: 0)
            #expect(router.takeLearnedKnob() == nil)
        }
    }

    @Test func whileLearningNoControlChangeReachesAnInstrument() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .all, slot: 0)])
            router.setLearning(true)
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 0)
            #expect(router.takeLearnedKnob() == knob74)

            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 1)
        }
    }

    @Test func afterLearningControlChangesGoAgain() async throws {
        try await withRouter(try await twoInstruments()) { router, _ in
            router.setRoutes([target("A", .all, slot: 0)])
            router.setLearning(true)
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            router.setLearning(false)
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(router.eventCount(channel: channelID(ofSlot: 0)) == 1)
        }
    }

    @Test func closingDropsTheControlsAndLearning() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        try await withRouter([]) { router, _ in
            router.setControls([control(knob74, node: UUID(), mix, of: plugin)])
            router.setLearning(true)
            router.close()

            router.setControls([control(knob74, node: UUID(), mix, of: plugin)])
            router.setLearning(true)
            router.handle(controlChange(74, 64), fromSource: "A", at: 0)
            #expect(value(of: mix, in: plugin) == 0.5)
            #expect(router.takeLearnedKnob() == nil)
            #expect(router.takeMovedNodes().isEmpty)
        }
    }

    @Test func theScratchOfAControlChangeStaysOnTheStack() {
        // Swift puts a temporary allocation of up to 1 KiB on the stack, and anything larger on the heap.
        #expect(controlChangeScratchBytes <= 1024)
    }

    // MARK: - Event lists

    @Test func eventListsDecodeEveryMessage() {
        #expect(events(in: [[noteOnUMP], [clockUMP]]) == [noteOnChannel1, .clock])
        #expect(events(in: [[clockUMP, noteOnUMP]]) == [.clock, noteOnChannel1])
    }

    @Test func aWordInsideALongerMessageIsNotAMessage() {
        let sysEx: [UInt32] = [0x3006_4142, noteOnUMP]
        let sysEx8: [UInt32] = [0x5000_0000, clockUMP, noteOnUMP, clockUMP]
        let flexData: [UInt32] = [0xD000_0000, clockUMP, noteOnUMP, clockUMP]
        let reserved3: [UInt32] = [0xB000_0000, clockUMP, noteOnUMP]
        let midi2Note: [UInt32] = [0x4090_3C00, noteOnUMP]
        for message in [sysEx, sysEx8, flexData, reserved3, midi2Note] {
            #expect(events(in: [message + [clockUMP]]) == [.clock])
        }
    }

    @Test func anEventListFromAnotherThreadReachesItsRoute() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .channel(1), slot: 0), target("B", .all, slot: 1)])
            await deliver([noteOnUMP], source: router.sourceTag(named: "A"), to: router.makeReceiveBlock())
            let output = rig.render()
            expectLevel(output[0], 0.25)
            expectLevel(output[2], 0)
        }
    }

    @Test func clockFromAnEventListCarriesTheHostTime() async throws {
        try await withRouter(try await tempoReporter()) { router, _ in
            router.setClockSource("A")
            await deliver([clockUMP], source: router.sourceTag(named: "A"), to: router.makeReceiveBlock())
            router.refreshClock(at: router.hostSeconds())
            #expect(router.clockRunning)
        }
    }

    @Test func sourcesOfOneNameShareOneTag() async throws {
        try await withRouter([]) { router, _ in
            #expect(router.sourceTag(named: "A") === router.sourceTag(named: "A"))
            #expect(router.sourceTag(named: "A") !== router.sourceTag(named: "B"))
            #expect(router.sourceTag(named: "A").name == "A")
        }
    }

    // MARK: - Threads

    @Test func routesAndClockChangeWhileEventsArriveAndAudioRenders() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            let rendering = RenderProgress()
            let renderer = startRendering(rig, progress: rendering)
            let sending = RenderProgress()
            let sender = Task.detached {
                var time = 0.0
                while !sending.stop.load(ordering: .relaxed) {
                    time += 0.02
                    router.handle(noteOnChannel1, fromSource: "A", at: time)
                    router.handle(.channelVoice(status: 0x80, data1: 60, data2: 0), fromSource: "A", at: time)
                    router.handle(.clock, fromSource: "A", at: time)
                    router.handle(.start, fromSource: "A", at: time)
                    sending.renders.add(1, ordering: .relaxed)
                }
            }
            for round in 0..<2000 {
                router.setRoutes([target("A", .all, slot: Int32(round % 2))])
                router.setClockSource(round % 3 == 0 ? nil : "A")
                router.refreshClock(at: Double(round))
                await Task.yield()
            }
            sending.stop.store(true, ordering: .relaxed)
            rendering.stop.store(true, ordering: .relaxed)
            await sender.value
            await renderer.value
            #expect(sending.renders.load(ordering: .relaxed) > 0)
            #expect(rendering.renders.load(ordering: .relaxed) > 0)
        }
    }

    @Test func controlsChangeWhileKnobsTurn() async throws {
        let plugin = try await testControls()
        let mix = try parameter("Mix", of: plugin)
        let cutoff = try parameter("Cutoff", of: plugin)
        try await withRouter(try await twoInstruments()) { router, _ in
            let node = UUID()
            let tables = [
                [control(knob74, node: node, mix, of: plugin), control(knob74, node: node, cutoff, of: plugin, from: 1, to: 0)],
                [control(knob74, node: node, mix, of: plugin)],
                [ControlTarget(knob: knob74, node: node, parameter: mix.id, write: nil)],
                [],
            ]
            router.setRoutes([target("A", .all, slot: 0)])
            let sending = RenderProgress()
            let sender = Task.detached {
                var value: UInt8 = 0
                while !sending.stop.load(ordering: .relaxed) {
                    value = (value &+ 7) % 128
                    router.handle(controlChange(74, value), fromSource: "A", at: 0)
                    router.handle(controlChange(75, value), fromSource: "A", at: 0)
                    sending.renders.add(1, ordering: .relaxed)
                }
            }
            for round in 0..<2000 {
                router.setControls(tables[round % tables.count])
                router.setLearning(round % 3 != 0)
                if round % 5 == 0 { router.rearmControls(node: node) }
                _ = router.takeMovedNodes()
                _ = router.takeLearnedKnob()
                await Task.yield()
            }
            sending.stop.store(true, ordering: .relaxed)
            await sender.value
            #expect(sending.renders.load(ordering: .relaxed) > 0)
        }
    }

    @Test func noEventReachesTheEngineOnceTheRouterHasGone() async throws {
        let strips = try await twoInstruments()
        let rig = Rig()
        rig.install(strips)
        var router: MIDIRouter? = MIDIRouter(engine: rig.engine)
        router?.setRoutes([target("A", .all, slot: 0)])
        let tag = try #require(router).sourceTag(named: "A")
        let block = try #require(router).makeReceiveBlock()
        await deliver([noteOnUMP], source: tag, to: block)
        expectLevel(rig.render()[0], 0.25)

        router = nil
        await deliver([noteOffUMP], source: tag, to: block)
        expectLevel(rig.render()[0], 0.25)
    }

    @Test func closingCutsTheRouterOffFromTheEngine() async throws {
        try await withRouter(try await twoInstruments()) { router, rig in
            router.setRoutes([target("A", .all, slot: 0)])
            router.setClockSource("A")
            router.close()
            #expect(router.isClosed)

            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            expectLevel(rig.render()[0], 0)

            router.setRoutes([target("A", .all, slot: 0)])
            router.setClockSource("A")
            router.handle(noteOnChannel1, fromSource: "A", at: 0)
            sendTicks(router)
            router.refreshClock(at: 2)
            expectLevel(rig.render()[0], 0)
            #expect(!router.clockRunning)
            #expect(router.sources.isEmpty)
        }
    }

    // MARK: - Sources

    @Test func connectionsFollowTheSystemsSources() {
        let connected: [MIDIEndpointRef: String] = [1: "Stays", 2: "Leaves", 3: "Old name"]
        let present: [MIDIEndpointRef: String] = [1: "Stays", 3: "New name", 4: "Arrives"]
        let changes = connectionChanges(connected: connected, present: present)
        #expect(Set(changes.disconnect) == [2, 3])
        #expect(Set(changes.connect) == [3, 4])
    }

    @Test func nothingChangesWhenTheSourcesAreTheSame() {
        let sources: [MIDIEndpointRef: String] = [1: "A", 2: "A"]
        let changes = connectionChanges(connected: sources, present: sources)
        #expect(changes.disconnect.isEmpty)
        #expect(changes.connect.isEmpty)
    }

    @Test func sourcesOfOneNameListOnce() {
        #expect(uniqueSourceNames(["B", "A", "B", "C", "A"]) == ["B", "A", "C"])
    }
}
