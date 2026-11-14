# MIDI Learn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map knobs of hardware MIDI controllers to parameters of any plugin in a rack, learned by touch in the plugin window, with range, direction and soft takeover, saved with the rack.

**Architecture:** The mapping model, the value formula, takeover and learn bookkeeping are pure logic in `RackmateCore`. `MIDIRouter` gets a second table beside its routes, of control targets: on the CoreMIDI thread a matching control change is swallowed and written to the mapped parameters, with no hop to the main actor. A parameter listener tells the plugin window which parameter the owner moved. `AudioSession` builds the control table from the configuration and the loaded plugins; `AppModel` polls the router for learned knobs and mapped moves; the plugin window gets a SwiftUI strip.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AudioToolbox (Audio Unit v2 C API: `kAudioUnitProperty_ParameterList`, `kAudioUnitProperty_ParameterInfo`, `AUEventListenerCreate`, `AUParameterSet`), CoreMIDI, SwiftUI in `NSHostingView`.

**Spec:** `docs/superpowers/specs/2026-11-14-midi-learn-design.md`

## Global Constraints

- Logic without UI goes into `RackmateCore`, test first (Swift Testing). `Sources/Rackmate` stays a thin layer.
- The render thread never allocates, locks, logs or calls Swift.
- MIDI goes from the CoreMIDI thread to the plugin without waiting for the main actor. The router's lock is held without allocation and without anything that blocks.
- Every Audio Unit lifecycle call (instantiate, initialize, restore, uninitialize, dispose, factory preset select) runs on the main thread.
- The router goes before the engine, and units before the engine. A control table must let go of a plugin before the plugin can be disposed.
- A missing device or plugin never stops a rack from loading.
- Checks with audio running use silent units only; no test unit that makes a test signal may reach the app. Running the app with real plugins needs the owner's OK.
- Never compare plugin state with stored state.
- Interface text is English. Rack files from 1.1.x open unchanged.
- Every user-visible change: a line under `## Unreleased` in `CHANGELOG.md`, and `docs/manual.html` plus `docs/cs/manual.html` describe it.
- Commits without AI attribution trailers; `git status` before every commit.
- Run the full suite as `swift test > "$TMPDIR/test.log" 2>&1; tail -5 "$TMPDIR/test.log"` and read the summary line.

## Review Focus

1. A control change for a mapping whose plugin is still loading, failed to load, or lacks the parameter: swallowed, nothing written, no crash. Test in Task 5.
2. A plugin removed from the rack while its knob is being turned: no write reaches it after the table that held it is replaced. Test in Task 5 (`setControls([])` then the plugin's last reference goes; a later CC writes nothing).
3. A rack file saved by 1.1.2 (no `controls` key) opens with no mappings. Test in Task 1.
4. A controller unplugged and plugged back in under the same name: its mappings work again without relearning. Test in Task 5 (the table names the source; a CC from that name after a `sources` refresh still writes).
5. Inverted (`from > to`) and equal (`from == to`) ranges under takeover. Tests in Task 2.

---

### Task 1: Mapping model in the rack file

**Files:**
- Create: `Sources/RackmateCore/ControlMapping.swift`
- Modify: `Sources/RackmateCore/Models.swift` (`PluginSlot`), `Sources/RackmateCore/EditingSession.swift`
- Test: `Tests/RackmateCoreTests/ControlMappingTests.swift`, `Tests/RackmateCoreTests/ModelsTests.swift`, `Tests/RackmateCoreTests/EditingSessionTests.swift`

**Interfaces:**
- Produces:
  - `public struct ControlKnob: Codable, Hashable, Sendable { public var source: String; public var channel: Int /* 1...16 */; public var controller: Int /* 0...127 */ }`, with `public var label: String` → `"OXI E16 · CH 1 · CC 74"`.
  - `public struct ControlMapping: Codable, Equatable, Sendable { public var knob: ControlKnob; public var parameter: UInt32; public var parameterName: String; public var from: Double; public var to: Double }`; `init(knob:parameter:parameterName:from: = 0, to: = 1)`.
  - `ControlMapping.fromPercent: Int` and `toPercent: Int` (get and set; whole numbers, set clamps to 0...100, get rounds).
  - `PluginSlot.controls: [ControlMapping]` (default `[]`, decoded with `decodeIfPresent ?? []`).
  - `PluginSlot.learn(_ mapping: ControlMapping)`: appends, unless a mapping with the same `knob` and `parameter` exists, which then stays as it is (range kept).
  - `EditingSession.markChanged()`: sets `isDirty` with no edit (a mapped move changed plugin state the configuration does not hold).

- [ ] **Step 1: Write the failing tests**

```swift
// ControlMappingTests.swift
@Test func aKnobReadsAsDeviceChannelAndController() {
    #expect(ControlKnob(source: "OXI E16", channel: 1, controller: 74).label == "OXI E16 · CH 1 · CC 74")
}
@Test func percentagesAreWholeAndClamped() {
    var mapping = ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff")
    #expect(mapping.fromPercent == 0 && mapping.toPercent == 100)
    mapping.fromPercent = 30; mapping.toPercent = 140
    #expect(mapping.from == 0.3 && mapping.to == 1)
    mapping.to = 0.704
    #expect(mapping.toPercent == 70)
}
@Test func learningTheSameKnobAndParameterKeepsTheRange() {
    var slot = PluginSlot.fixture()
    var first = ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff")
    first.fromPercent = 30
    slot.learn(first)
    slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
    #expect(slot.controls == [first])
}
@Test func oneKnobCanDriveSeveralParameters() {
    var slot = PluginSlot.fixture()
    slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff"))
    slot.learn(ControlMapping(knob: .fixture(), parameter: 4, parameterName: "Mix"))
    #expect(slot.controls.map(\.parameter) == [3, 4])
}
// ModelsTests.swift
@Test func aSlotFromBeforeMIDILearnHasNoControls() throws {
    let json = #"{"plugin":{"type":"aufx","subtype":"test","manufacturer":"Test"},"displayName":"Old","state":"AQ=="}"#
    #expect(try JSONDecoder().decode(PluginSlot.self, from: Data(json.utf8)).controls.isEmpty)
}
@Test func controlsSurviveTheFile() throws {
    var slot = PluginSlot.fixture()
    slot.learn(ControlMapping(knob: .fixture(), parameter: 3, parameterName: "Cutoff", from: 0.6, to: 0.1))
    #expect(try JSONDecoder().decode(PluginSlot.self, from: JSONEncoder().encode(slot)) == slot)
}
@Test func movingAnEffectKeepsItsControls()   // EffectMove between rows and channels: slot.controls unchanged
@Test func replacingAPluginDropsItsControls() // AddPicker.replacing(channel, with:...) → new channel's slot.controls.isEmpty
@Test func pickingAPresetKeepsItsControls()   // slot.takePreset(name, state:) leaves slot.controls unchanged
// EditingSessionTests.swift
@Test func markChangedMakesASavedSessionDirty() {
    var session = EditingSession(saved: .fixture())
    session.markChanged()
    #expect(session.isDirty && session.leaveAction == .askToSave)
}
```

Add `ControlKnob.fixture()` (`source: "Faderfox", channel: 1, controller: 74`) to `Tests/RackmateCoreTests/Fixtures.swift`.

- [ ] **Step 2: Run them, expect compile failures** — `swift test --filter "ControlMappingTests|ModelsTests|EditingSessionTests"`
- [ ] **Step 3: Implement the interfaces above.** `controls` joins `PluginSlot.CodingKeys`; the existing decoder comment names it among keys an older file lacks.
- [ ] **Step 4: Run the filtered tests, then the full suite; all pass.**
- [ ] **Step 5: Commit** `feat: MIDI control mappings in the rack file`

---

### Task 2: Parameter scale, knob value and takeover

**Files:**
- Create: `Sources/RackmateCore/ParameterRange.swift`, `Sources/RackmateCore/Takeover.swift`
- Test: `Tests/RackmateCoreTests/ParameterRangeTests.swift`, `Tests/RackmateCoreTests/TakeoverTests.swift`

**Interfaces:**
- Consumes: `ControlMapping` (Task 1).
- Produces:
  - `public enum ParameterScale: Sendable { case linear, logarithmic, exponential, squareRoot, squared, cubeRoot, cubed }` — the shapes Audio Unit `kAudioUnitParameterFlag_Display…` flags declare.
  - `public struct ParameterRange: Equatable, Sendable { public var minimum: Float; public var maximum: Float; public var scale: ParameterScale; public var isStepped: Bool }` with `func value(atFraction: Double) -> Float` and `func fraction(of value: Float) -> Double` (inverse, clamped to 0...1). A stepped range rounds the value to the nearest whole number. `logarithmic` with `minimum <= 0` behaves as `linear`.
  - `ControlMapping.fraction(forKnob value: UInt8) -> Double` = `from + (to − from) × value / 127`.
  - `public struct Takeover: Sendable` — `init()` starts waiting; `mutating func rearm()`; `mutating func follow(knob: UInt8, currentFraction: Double, from: Double, to: Double) -> Bool` returns whether to write this knob value. It never allocates (it runs under the router's lock).

The takeover rule (the spec's, made exact): while waiting, clamp `currentFraction` to `min(from, to)...max(from, to)` and convert it to a knob position `k = (clamped − from) / (to − from) × 127`. Take over when the previous knob value of this waiting period and the new one lie on both sides of `k` or touch it, or, with no previous value, when `abs(knob − k) <= 1`. With `from == to`, take over at the first move. Once taken over, every move writes until `rearm()`.

- [ ] **Step 1: Write the failing tests**

```swift
// ParameterRangeTests.swift
@Test func linearRangeMapsBothWays() {
    let range = ParameterRange(minimum: 0, maximum: 10, scale: .linear, isStepped: false)
    #expect(range.value(atFraction: 0.25) == 2.5 && range.fraction(of: 2.5) == 0.25)
}
@Test func logarithmicCutoffIsHalfWayAtTheGeometricMean() {
    let range = ParameterRange(minimum: 20, maximum: 20_000, scale: .logarithmic, isStepped: false)
    #expect(abs(range.value(atFraction: 0.5) - 632.46) < 0.1)
    #expect(abs(range.fraction(of: 632.46) - 0.5) < 0.0001)
}
@Test func aSteppedParameterTakesTheNearestStep() {
    let range = ParameterRange(minimum: 0, maximum: 2, scale: .linear, isStepped: true)
    #expect(range.value(atFraction: 0.3) == 1 && range.value(atFraction: 0.2) == 0)
}
@Test func knobValueFollowsTheRangeAndItsDirection() {
    var mapping = ControlMapping(knob: .fixture(), parameter: 0, parameterName: "Mix", from: 0.6, to: 0.1)
    #expect(mapping.fraction(forKnob: 0) == 0.6 && mapping.fraction(forKnob: 127) == 0.1)
    mapping.from = 0.3; mapping.to = 0.7
    #expect(abs(mapping.fraction(forKnob: 64) - 0.5016) < 0.001)
}
// TakeoverTests.swift
@Test func waitsUntilTheKnobCrossesTheValue() {
    var takeover = Takeover()
    #expect(!takeover.follow(knob: 10, currentFraction: 0.5, from: 0, to: 1))
    #expect(!takeover.follow(knob: 40, currentFraction: 0.5, from: 0, to: 1))
    #expect(takeover.follow(knob: 70, currentFraction: 0.5, from: 0, to: 1))   // crossed 63.5
    #expect(takeover.follow(knob: 20, currentFraction: 0.9, from: 0, to: 1))   // follows from now on
}
@Test func landingOnTheValueTakesOver() {
    var takeover = Takeover()
    #expect(takeover.follow(knob: 64, currentFraction: 0.5, from: 0, to: 1))
}
@Test func rearmWaitsAgain() {
    var takeover = Takeover()
    _ = takeover.follow(knob: 64, currentFraction: 0.5, from: 0, to: 1)
    takeover.rearm()
    #expect(!takeover.follow(knob: 0, currentFraction: 0.5, from: 0, to: 1))
}
@Test func aValueOutsideTheRangeTakesOverAtTheNearerEnd() {
    var takeover = Takeover()   // range 0–50 %, parameter at 90 %: the end at knob 127
    #expect(!takeover.follow(knob: 100, currentFraction: 0.9, from: 0, to: 0.5))
    #expect(takeover.follow(knob: 127, currentFraction: 0.9, from: 0, to: 0.5))
}
@Test func anInvertedRangeTakesOverWhereItsValueIs() {
    var takeover = Takeover()   // 60 % → 10 %, parameter at 35 %: knob 63.5
    #expect(!takeover.follow(knob: 0, currentFraction: 0.35, from: 0.6, to: 0.1))
    #expect(takeover.follow(knob: 80, currentFraction: 0.35, from: 0.6, to: 0.1))
}
@Test func equalEndsTakeOverAtTheFirstMove() {
    var takeover = Takeover()
    #expect(takeover.follow(knob: 5, currentFraction: 0.9, from: 0.4, to: 0.4))
}
```

- [ ] **Step 2: Run, expect failures** — `swift test --filter "ParameterRangeTests|TakeoverTests"`
- [ ] **Step 3: Implement.** Scales: `logarithmic` interpolates `log(min)…log(max)`; `exponential` its inverse shape; the power scales use the power on the fraction (`squareRoot`: value fraction = f², and so on, matching how AU generic views draw them).
- [ ] **Step 4: Run filtered tests and the full suite; all pass.**
- [ ] **Step 5: Commit** `feat: parameter scales and soft takeover for MIDI control`

---

### Task 3: Learn bookkeeping

**Files:**
- Create: `Sources/RackmateCore/ControlLearning.swift`
- Test: `Tests/RackmateCoreTests/ControlLearningTests.swift`

**Interfaces:**
- Consumes: `ControlKnob`, `ControlMapping`, `PluginLocation`.
- Produces: `public struct ControlLearning: Sendable` with
  - `mutating func start(at: PluginLocation)`, `mutating func stop(at: PluginLocation)`, `func isOn(at: PluginLocation) -> Bool`, `var isAnyOn: Bool`;
  - `mutating func touch(at: PluginLocation, parameter: UInt32, name: String)` — ignored where Learn is off; replaces that location's pending parameter and makes it the newest;
  - `func pending(at: PluginLocation) -> (parameter: UInt32, name: String)?`;
  - `mutating func receive(_ knob: ControlKnob) -> (location: PluginLocation, mapping: ControlMapping)?` — the newest pending parameter of all locations takes the knob (range 0 → 100 %) and stops pending; Learn stays on there.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aKnobBeforeAnyTouchLearnsNothing()          // start(at: a); receive(knob) == nil
@Test func touchThenKnobMakesAMapping()                // start, touch(param 3 "Cutoff"), receive → (a, mapping 3 knob 0→1); pending(at: a) == nil; isOn(at: a)
@Test func aTouchWithLearnOffIsIgnored()               // touch without start; pending == nil
@Test func aLaterTouchReplacesThePendingParameter()    // touch 3, touch 4, receive → parameter 4
@Test func theNewestPendingWindowTakesTheKnob()        // start a, b; touch a; touch b; receive → location b; receive again → location a
@Test func stoppingDropsThePendingParameter()          // start, touch, stop; receive == nil; isAnyOn == false
```

- [ ] **Step 2: Run, expect failures** — `swift test --filter ControlLearningTests`
- [ ] **Step 3: Implement.** Keep a monotonically increasing touch counter per pending entry.
- [ ] **Step 4: Run filtered tests and the full suite; all pass.**
- [ ] **Step 5: Commit** `feat: MIDI learn bookkeeping`

---

### Task 4: Plugin parameters and a test unit that has some

**Files:**
- Modify: `Sources/RackmateAudio/HostedPlugin.swift`, `Sources/RackmateTestUnits/TestUnits.swift`
- Test: `Tests/RackmateAudioTests/HostingTests.swift`, `Tests/RackmateAudioTests/TestUnitsTests.swift`

**Interfaces:**
- Consumes: `ParameterRange`, `ParameterScale` (Task 2).
- Produces:
  - `public struct PluginParameter: Equatable, Sendable { public var id: AudioUnitParameterID; public var name: String; public var range: ParameterRange }`.
  - `HostedPlugin.parameters() -> [PluginParameter]` (global scope, element 0; `kAudioUnitProperty_ParameterList` then `kAudioUnitProperty_ParameterInfo`; name from `cfNameString` when `kAudioUnitParameterFlag_HasCFNameString`, else the C name; `isStepped` for units `Indexed` and `Boolean`; scale from the `Display…` flags). `HostedPlugin.parameter(_ id: AudioUnitParameterID) -> PluginParameter?`.
  - Test unit **Test Controls**: type `aufx`, subtype `PlCt`, manufacturer `Plug`, silent output (writes zeros), registered by `registerTestUnits()` only (not a safe unit). Parameter tree: address 0 `Cutoff`, 20…20 000 Hz, logarithmic display flag, starts at 1 000; address 1 `Mix`, 0…1, linear, starts at 0.5; address 2 `Mode`, 0…2, indexed, starts at 0. Values readable and writable through the AU v2 API.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("Parameters come with names, ranges and scales")
func parametersOfTestControls() async throws {
    registerTestUnits()
    let plugin = try await HostedPlugin.load(PluginID(type: "aufx", subtype: "PlCt", manufacturer: "Plug"))
    let parameters = plugin.parameters()
    #expect(parameters.map(\.name) == ["Cutoff", "Mix", "Mode"])
    #expect(parameters[0].range == ParameterRange(minimum: 20, maximum: 20_000, scale: .logarithmic, isStepped: false))
    #expect(parameters[2].range.isStepped)
    #expect(plugin.parameter(1)?.name == "Mix" && plugin.parameter(99) == nil)
}
@Test("Apple's delay lists its parameters") // dely: non-empty, every range has minimum < maximum
```

In `TestUnitsTests.swift`, assert Test Controls renders silence (follow the file's existing pattern for silent units).

- [ ] **Step 2: Run, expect failures** — `swift test --filter "HostingTests|TestUnitsTests"`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run filtered tests and the full suite; all pass.**
- [ ] **Step 5: Commit** `feat: read a plugin's parameters`

---

### Task 5: Control table in the MIDI router

**Files:**
- Modify: `Sources/RackmateAudio/MIDIRouter.swift`
- Test: `Tests/RackmateAudioTests/MIDIRouterTests.swift`

**Interfaces:**
- Consumes: `ControlKnob`, `ControlMapping.fraction(forKnob:)`, `ParameterRange`, `Takeover` (Tasks 1–2); `HostedPlugin`, `PluginParameter` (Task 4).
- Produces:
  - `public struct ControlTarget: Sendable { public var knob: ControlKnob; public var node: UUID; public var parameter: AudioUnitParameterID; public var write: ControlWrite? }` and `public struct ControlWrite: Sendable { public var plugin: HostedPlugin; public var range: ParameterRange; public var from: Double; public var to: Double }`. `write == nil` means the plugin is loading, failed, or lacks the parameter: the knob is still swallowed.
  - `MIDIRouter.setControls(_ targets: [ControlTarget])` — replaces the table; a target with the same `node`, `parameter` and `knob` as one in the old table keeps its takeover state, any other starts waiting. The old table is released on the main actor after the lock.
  - `MIDIRouter.rearmControls(node: UUID, parameter: AudioUnitParameterID? = nil)` — makes the node's targets (or the one parameter's) wait again.
  - `MIDIRouter.takeMovedNodes() -> Set<UUID>` — nodes a mapped knob wrote to since the last call.
  - `MIDIRouter.setLearning(_ on: Bool)` and `MIDIRouter.takeLearnedKnob() -> ControlKnob?` — while on, the newest control change from any source (mapped or not) is kept for the next take; off clears it.
  - `MIDIRouter.parameterListener` — the app's one `AUEventListenerRef`, created by the router on the main queue (`AUEventListenerCreateWithDispatchQueue`), used as the sending listener of every mapped write so Task 6's watch never hears the app's own writes.

Behaviour in `MIDIRouting.handle`, for a `.channelVoice` whose status is `0xB0…0xBF`, under the lock:
1. Note the knob for learning when learning is on.
2. If any target's knob matches (source by `isSameName`, MIDI channel `status & 0x0F + 1`, controller `data1`): do **not** run the routes for this message. For each matching target with a `write`, read the parameter's current value (`AudioUnitGetParameter`), convert with `range.fraction(of:)`, ask its `Takeover`, and if it says yes, compute the value `range.value(atFraction: fraction(forKnob:))` and set its node's moved flag.
3. Otherwise route as today.
4. After the lock: `AUParameterSet(parameterListener, nil, &parameter, value, 0)` for each write, the plugin retained across the unlock (a fixed-size stack buffer of at most 32 writes per message; extra writes are dropped). A plugin whose last reference goes here hands its disposal to the main thread, as `HostedPlugin.deinit` already does.

Takeover state, moved flags and the learn slot live in the table built on the main actor, so the CoreMIDI thread changes values in place and allocates nothing. `close()` also empties the control table.

- [ ] **Step 1: Write the failing tests** (Test Controls from Task 4; follow `withRouter` / `target` helpers already in the file)

```swift
@Test func aMappedKnobSetsTheParameterAndIsNotRouted()
// route "A" all → instrument slot 0; control: knob ("A", ch 1, CC 74) → Test Controls param 1 Mix, 0→1.
// Feed CC 74 = 64 (lands on its start value 0.5): Mix ≈ 0.504; the instrument received no CC 74; takeMovedNodes() == [node].
@Test func anUnmappedControlChangeStillGoesToTheInstrument()
@Test func aKnobWithoutAWriteIsSwallowed()            // write nil: instrument gets nothing, nothing moved
@Test func oneKnobWritesEveryMappedParameter()         // Mix 0→1 and Cutoff 1→0 on the same knob
@Test func theKnobWaitsForTheParameter()               // Mix at 0.9; CC 10 writes nothing; CC 127 then writes
@Test func rearmMakesTheKnobWaitAgain()
@Test func aNewTableKeepsTheTakeoverOfATargetThatStays()
@Test func noWriteReachesAPluginAfterItsTableIsReplaced()   // setControls([]); CC writes nothing; plugin can go
@Test func aSourceThatComesBackByNameStillWrites()
@Test func learningKeepsTheNewestControlChange()       // setLearning(true); CC 71 then CC 74 → take == knob 74; take again == nil
@Test func learningOffKeepsNothing()
```

- [ ] **Step 2: Run, expect failures** — `swift test --filter MIDIRouterTests`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run filtered tests and the full suite; all pass.**
- [ ] **Step 5: Commit** `feat: MIDI router writes mapped knobs to plugin parameters`

---

### Task 6: Watching which parameter the owner moved

**Files:**
- Create: `Sources/RackmateAudio/ParameterWatch.swift`
- Test: `Tests/RackmateAudioTests/ParameterWatchTests.swift`

**Interfaces:**
- Consumes: `MIDIRouter.parameterListener`, `HostedPlugin.parameters()`.
- Produces: `@MainActor public final class ParameterWatch` — `init(router: MIDIRouter, plugin: HostedPlugin, onTouch: @escaping @MainActor (AudioUnitParameterID) -> Void)`; registers `kAudioUnitEvent_BeginParameterChangeGesture` and `kAudioUnitEvent_ParameterValueChange` for every parameter of the plugin on the router's listener; `stop()` (and `deinit`) removes them. Calls `onTouch` on the main actor.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aChangeFromThePluginIsReported()      // AUParameterSet(nil, nil, Mix, 0.3) → onTouch(1) within 1 s
@Test func aMappedWriteIsNotReported()           // a router write of Mix (Task 5 path) → no onTouch within 0.5 s
@Test func aStoppedWatchReportsNothing()
```

- [ ] **Step 2–4: Run, implement, run filtered and full suite.**
- [ ] **Step 5: Commit** `feat: watch a plugin's parameters for MIDI learn`

---

### Task 7: The session keeps the control table up to date

**Files:**
- Modify: `Sources/RackmateAudio/AudioSession.swift`, `Sources/RackmateAudio/ConfigurationRunner.swift`
- Modify: `Sources/RackmateCore/ControlMapping.swift` — `extension Configuration { public var controlNodes: [(node: UUID, mapping: ControlMapping)] }`, channel slots under the channel ID and effect slots under the effect ID, in channel then row order
- Test: `Tests/RackmateAudioTests/AudioSessionTests.swift`, `Tests/RackmateCoreTests/ControlMappingTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces:
  - `ConfigurationRunner.onPluginsChanged: (() -> Void)?`, called after `apply` changes `hosted` and after each load that sets `hosted[node]`.
  - `AudioSession` builds `[ControlTarget]` from `wanted` (channel slots by channel ID, effect slots by effect ID) and the runner's plugins, and calls `router.setControls` from `refreshRoutes` and from `onPluginsChanged`. A target's `write` is nil when the node has no running plugin or `plugin.parameter(mapping.parameter)` is nil. `releaseRunner` and `close` call `router.setControls([])` before the runner lets go of plugins.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func controlsFollowTheConfiguration()       // open with Test Controls effect mapping Mix; CC writes Mix; update without the mapping; CC writes nothing
@Test func aControlWaitsForItsPluginToLoad()       // before the load settles the knob is swallowed; after, it writes
@Test func closingTheSessionEmptiesTheControls()
// ControlMappingTests: controlNodes lists channel and effect mappings with their node IDs
```

- [ ] **Step 2–4: Run `swift test --filter "AudioSessionTests|ControlMappingTests"`, implement, run filtered and full suite.**
- [ ] **Step 5: Commit** `feat: the audio session feeds mapped knobs to the router`

---

### Task 8: App wiring

**Files:**
- Modify: `Sources/Rackmate/AppModel.swift`

**Interfaces:**
- Consumes: Tasks 1, 3, 5, 6, 7.
- Produces (used by Task 9):
  - `AppModel.learning: ControlLearning` (observable).
  - `func startLearning(at: PluginLocation)`, `func stopLearning(at: PluginLocation)` (also called when the window closes) — `router.setLearning(learning.isAnyOn)`.
  - `func noteParameterTouched(at: PluginLocation, parameter: UInt32)` — looks up the name with `hostedPlugin(at:)?.parameter(_:)`, calls `learning.touch`, and `audio?.router.rearmControls(node:parameter:)`.
  - `func pickParameter(at: PluginLocation, parameter: UInt32)` — the fallback menu, same as a touch.
  - `func removeControl(at: PluginLocation, index: Int)`, `func setControlRange(at: PluginLocation, index: Int, fromPercent: Int, toPercent: Int)` — through `edit`.
  - A poll every 250 ms while a rack is open: `takeLearnedKnob()` → `learning.receive` → `edit { updateSlot(at:) { $0.learn(mapping) } }`; `takeMovedNodes()` → for each node's location `edit { updateSlot { $0.isCustomSound = true } }` then `session.markChanged()`.
  - After a preset is picked (both preset paths in `AppModel`), `audio?.router.rearmControls(node:)` for that plugin.

- [ ] **Step 1: Implement.** No new logic here beyond calls; anything with a rule belongs in Tasks 1–3.
- [ ] **Step 2: `./build.sh` with zero warnings (`grep -c "warning:"` on the log is 0); full suite passes.**
- [ ] **Step 3: Commit** `feat: wire MIDI learn into the app`

---

### Task 9: The MIDI CONTROL strip in the plugin window

**Files:**
- Create: `Sources/Rackmate/MIDIControlStrip.swift`
- Modify: `Sources/Rackmate/PluginWindows.swift`, `Sources/RackmateCore/PanelLayout.swift` (window size with the strip), `Tests/RackmateCoreTests/PanelLayoutTests.swift`

**Interfaces:**
- Consumes: Task 8's `AppModel` API; `ControlMapping.fromPercent/toPercent`, `ControlKnob.label`; `HostedPlugin.parameters()`; `router.sources` (device present?).
- Produces: `PanelLayout.pluginWindowSize(plugin: CGSize, strip: CGSize) -> CGSize` (width the larger of the two, heights added), tested.

Layout and copy, from the mockup `learn-strip-v2.html`:
- Under the plugin view, full window width: a `LEARN` switch (amber when on) and the title `MIDI CONTROL`.
- Learn on: the hint `Move a control in the plugin, then a knob on your controller.` and a `Pick a parameter` menu of the plugin's parameters (the fallback).
- Rows: parameter name; knob label in amber; two whole-number percent fields `from % → to %`; `×`. A pending row: parameter name and `waiting for a knob…`. A row is dimmed when its device is not in `router.sources` or the plugin lacks its parameter.
- The window owns a `ParameterWatch` while open; closing the window stops it and stops learning there. The window's height grows with the rows; the plugin view keeps its own size, and the existing resize-from-the-bottom behaviour includes the strip.
- Fonts and colours from `Theme.swift`; no new colours.

- [ ] **Step 1: Write the failing `PanelLayoutTests` case** `stripSitsUnderThePlugin` (plugin 500×300, strip 420×120 → 500×420; plugin 300×200, strip 420×120 → 420×320). Run, expect failure.
- [ ] **Step 2: Implement the layout function and the strip.**
- [ ] **Step 3: `./build.sh` with zero warnings; full suite passes.**
- [ ] **Step 4: Check by hand, with the owner's OK to run the app with Apple's AUDelay:** Learn on; move Dry/Wet Mix with the mouse; the pending row shows; a knob on a connected controller, turned by the owner, completes it; a range edit and `×` mark the rack unsaved; closing and reopening the rack keeps the row.
- [ ] **Step 5: Commit** `feat: MIDI CONTROL strip in plugin windows`

---

### Task 10: Manual, changelog

**Files:**
- Modify: `docs/manual.html`, `docs/cs/manual.html`, `CHANGELOG.md`
- Create: `docs/assets/manual/midi-control.png`

- [ ] **Step 1:** `CHANGELOG.md` under `## Unreleased`: one line, e.g. "MIDI learn: map knobs of a MIDI controller to plugin parameters, with range, direction and soft takeover, in a new MIDI CONTROL strip under each plugin window."
- [ ] **Step 2:** Manual, English and Czech: a section on the strip (Learn, pick a parameter, range and direction, `×`, takeover, one knob to several parameters, mapped CCs no longer reach the instrument, mappings saved with the rack, dimmed rows), with the screenshot framed like the other figures (`.view`, `.mark` from `docs/assets/manual.css`).
- [ ] **Step 3:** Screenshot of a plugin window with the strip, captured by window id only (`screencapture -x -o -l <id>`), with the owner's OK to run the app.
- [ ] **Step 4:** Commit `docs: MIDI learn in the manual and changelog`
