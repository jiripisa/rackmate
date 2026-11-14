import AudioToolbox
import CRenderCore
import Foundation
import RackmateCore
import RackmateTestUnits
import Testing
@testable import RackmateAudio

@MainActor
private final class Touches {
    var ids: [AudioUnitParameterID] = []
}

/// Polls the main actor, whose queue the listener reports on, until `done` or `limit` passes.
@MainActor
private func wait(_ limit: Duration, until done: () -> Bool) async {
    let deadline = ContinuousClock.now + limit
    while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor
private func withWatch(
    _ body: @MainActor (MIDIRouter, HostedPlugin, PluginParameter, Touches, ParameterWatch) async throws -> Void
) async throws {
    registerTestUnits()
    let rig = Rig()
    let plugin = try await loadPlugin(type: "aufx", subtype: "PlCt")
    let mix = try #require(plugin.parameters().first { $0.name == "Mix" })
    let router = MIDIRouter(engine: rig.engine)
    let touches = Touches()
    let watch = ParameterWatch(router: router, plugin: plugin) { touches.ids.append($0) }
    defer { withExtendedLifetime(rig) {} }
    try await body(router, plugin, mix, touches, watch)
}

@Suite("Parameter watch")
@MainActor
struct ParameterWatchTests {
    @Test func aChangeFromThePluginIsReported() async throws {
        try await withWatch { _, plugin, mix, touches, _ in
            var parameter = AudioUnitParameter(
                mAudioUnit: plugin.audioUnit, mParameterID: mix.id, mScope: kAudioUnitScope_Global, mElement: 0)
            AUParameterSet(nil, nil, &parameter, 0.3, 0)
            await wait(.seconds(1)) { !touches.ids.isEmpty }
            #expect(touches.ids.first == mix.id)
        }
    }

    @Test func aMappedWriteIsNotReported() async throws {
        try await withWatch { router, plugin, mix, touches, _ in
            let knob = ControlKnob(source: "A", channel: 1, controller: 74)
            router.setControls([
                ControlTarget(knob: knob, node: UUID(), parameter: mix.id, write: ControlWrite(plugin: plugin, range: mix.range, from: 0, to: 1))
            ])
            // Mix starts at 0.5, so 64 lands on it and takes over at once.
            router.handle(.channelVoice(status: 0xB0, data1: 74, data2: 64), fromSource: "A", at: 0)
            await wait(.milliseconds(500)) { !touches.ids.isEmpty }
            var written: AudioUnitParameterValue = 0
            AudioUnitGetParameter(plugin.audioUnit, mix.id, kAudioUnitScope_Global, 0, &written)
            #expect(abs(written - 64 / 127) < 0.001)
            #expect(touches.ids.isEmpty)
        }
    }

    @Test func aStoppedWatchReportsNothing() async throws {
        try await withWatch { _, plugin, mix, touches, watch in
            watch.stop()
            watch.stop()
            var parameter = AudioUnitParameter(
                mAudioUnit: plugin.audioUnit, mParameterID: mix.id, mScope: kAudioUnitScope_Global, mElement: 0)
            AUParameterSet(nil, nil, &parameter, 0.3, 0)
            await wait(.milliseconds(500)) { !touches.ids.isEmpty }
            #expect(touches.ids.isEmpty)
        }
    }
}
