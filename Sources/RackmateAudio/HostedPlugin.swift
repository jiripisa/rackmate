import AudioToolbox
import Foundation
import RackmateCore

public enum HostedPluginError: Error {
    case notFound(PluginID)
    case osStatus(OSStatus, String)
    case invalidState
    case unknownPreset(String)
}

extension HostedPluginError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            "The plugin \(id.type)/\(id.subtype)/\(id.manufacturer) is not installed on this Mac."
        case .osStatus(let status, let operation):
            "\(operation) failed with error \(status)."
        case .invalidState:
            "The saved plugin state cannot be read."
        case .unknownPreset(let name):
            "The plugin has no preset named \(name)."
        }
    }
}

/// A parameter of a plugin as MIDI learn needs it: the id to read and write it by, a name to show, and its range.
public struct PluginParameter: Equatable, Sendable {
    public var id: AudioUnitParameterID
    public var name: String
    public var range: ParameterRange

    public init(id: AudioUnitParameterID, name: String, range: ParameterRange) {
        self.id = id
        self.name = name
        self.range = range
    }
}

/// How long the interface gets to draw before a plugin holds up the main thread: a little over a frame.
private let drawPause = Duration.milliseconds(20)

/// An instantiated Audio Unit. Holds the raw `AudioUnit` because the C render core
/// calls `AudioUnitRender` on it directly.
///
/// Audio Units expect to be created, set up and destroyed on the main thread. JUCE plugins run timers
/// there, and one that fires during a destructor on another thread lands in a half destroyed object.
/// So everything of that kind is `@MainActor`, and `deinit` passes the unit to the main thread when the
/// last reference drops somewhere else.
public final class HostedPlugin: @unchecked Sendable {

    public let id: PluginID
    public let audioUnit: AudioUnit
    /// A version 3 unit, which runs in process through the system's v2 bridge.
    public let isAUv3: Bool
    /// Channels per bus: 2, or 1 when `configure` found the unit refuses stereo.
    public private(set) var channelCount: UInt32 = 2
    private var isInitialized = false
    /// Keeps the owner of the plugin's view (view controller or Cocoa factory) alive, since a view does
    /// not own it. `releaseView` lets go of it.
    var viewOwner: AnyObject?

    private init(id: PluginID, audioUnit: AudioUnit, isAUv3: Bool) {
        self.id = id
        self.audioUnit = audioUnit
        self.isAUv3 = isAUv3
    }

    /// The last reference can drop on any thread. No render reaches the unit by then, because the
    /// runner only lets go of a unit that has left every graph. This never waits for the main thread,
    /// which may itself be waiting for the thread this runs on.
    deinit {
        let teardown = Teardown(audioUnit: audioUnit, isInitialized: isInitialized, viewOwner: viewOwner)
        viewOwner = nil
        if Thread.isMainThread {
            teardown.run()
        } else {
            DispatchQueue.main.async { teardown.run() }
        }
    }

    /// Instantiates in process (version 3 units included), since the render thread calls into the unit.
    /// This holds up the main thread for as long as the unit takes to create, so call `letInterfaceDraw` first.
    @MainActor
    public static func load(_ id: PluginID) async throws -> HostedPlugin {
        var description = id.componentDescription
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw HostedPluginError.notFound(id)
        }
        let unit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UnitBox, Error>) in
            // `@Sendable` keeps the block nonisolated: the system may call it on any thread.
            let completion: @Sendable (AudioComponentInstance?, OSStatus) -> Void = { instance, status in
                if status == noErr, let instance {
                    continuation.resume(returning: UnitBox(unit: instance))
                } else {
                    continuation.resume(throwing: HostedPluginError.osStatus(status, "AudioComponentInstantiate"))
                }
            }
            AudioComponentInstantiate(component, .loadInProcess, completion)
        }
        var found = AudioComponentDescription()
        AudioComponentGetDescription(component, &found)
        let isAUv3 = found.componentFlags & AudioComponentFlags.isV3AudioUnit.rawValue != 0
        return HostedPlugin(id: id, audioUnit: unit.unit, isAUv3: isAUv3)
    }

    /// Frees the main thread long enough to draw, so a "Loading" state shows before a plugin holds it up.
    @MainActor
    static func letInterfaceDraw() async {
        try? await Task.sleep(for: drawPause)
    }

    /// Names of the input buses; "Input" or "Bus n" when the unit does not name one.
    @MainActor
    public var inputBusNames: [String] {
        var count: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &count, &size) == noErr
        else { return [] }
        return (0..<count).map { element in
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ElementName, kAudioUnitScope_Input, element, &name, &nameSize)
            if status == noErr, let name { return name.takeRetainedValue() as String }
            return element == 0 ? "Input" : "Bus \(element)"
        }
    }

    /// Sets maximum frames and a deinterleaved Float32 format on every bus (stereo, mono when
    /// the unit refuses), then initializes the unit.
    @MainActor
    public func configure(sampleRate: Double, maxFrames: UInt32) throws {
        if isInitialized {
            AudioUnitUninitialize(audioUnit)
            isInitialized = false
        }
        var frames = maxFrames
        try check(
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, UInt32(MemoryLayout<UInt32>.size)),
            "MaximumFramesPerSlice"
        )
        if (try? applyFormat(channels: 2, sampleRate: sampleRate)) != nil {
            channelCount = 2
        } else {
            try applyFormat(channels: 1, sampleRate: sampleRate)
            channelCount = 1
        }
        try check(AudioUnitInitialize(audioUnit), "AudioUnitInitialize")
        isInitialized = true
    }

    /// The unit's class info, serialized as a binary property list.
    @MainActor
    public func fullState() throws -> Data {
        var info: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        try check(AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &info, &size), "ClassInfo")
        guard let info else { throw HostedPluginError.invalidState }
        return try PropertyListSerialization.data(fromPropertyList: info.takeRetainedValue(), format: .binary, options: 0)
    }

    @MainActor
    public func restore(_ state: Data) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: state, options: [], format: nil) as? NSDictionary
        else { throw HostedPluginError.invalidState }
        let dictionary = plist as CFDictionary
        var info = Unmanaged.passUnretained(dictionary)
        try withExtendedLifetime(dictionary) {
            try check(
                AudioUnitSetProperty(audioUnit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &info, UInt32(MemoryLayout<Unmanaged<CFDictionary>>.size)),
                "ClassInfo"
            )
        }
    }

    @MainActor
    public func factoryPresets() -> [String] {
        presets().map(\.name)
    }

    @MainActor
    public func selectFactoryPreset(_ name: String) throws {
        guard let preset = presets().first(where: { $0.name == name }) else {
            throw HostedPluginError.unknownPreset(name)
        }
        let cfName = name as CFString
        var value = AUPreset(presetNumber: preset.number, presetName: Unmanaged.passUnretained(cfName))
        try withExtendedLifetime(cfName) {
            try check(
                AudioUnitSetProperty(audioUnit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout<AUPreset>.size)),
                "PresentPreset"
            )
        }
    }

    /// The plugin's parameters (global scope, element 0), in the order it lists them. Reads properties only.
    @MainActor
    public func parameters() -> [PluginParameter] {
        var size: UInt32 = 0
        guard AudioUnitGetPropertyInfo(audioUnit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &size, nil) == noErr,
            size > 0
        else { return [] }
        var ids = [AudioUnitParameterID](repeating: 0, count: Int(size) / MemoryLayout<AudioUnitParameterID>.size)
        guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &ids, &size) == noErr
        else { return [] }
        return ids.prefix(Int(size) / MemoryLayout<AudioUnitParameterID>.size).compactMap { parameter($0) }
    }

    /// One parameter by id, or nil when the plugin has none by that id.
    @MainActor
    public func parameter(_ id: AudioUnitParameterID) -> PluginParameter? {
        var info = AudioUnitParameterInfo()
        var size = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
        guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global, id, &info, &size) == noErr
        else { return nil }
        let flags = info.flags
        var name: String
        if flags.contains(.flag_HasCFNameString), let cfName = info.cfNameString {
            // The plugin hands over its own string; only when it says so is it ours to release.
            name = (flags.contains(.flag_CFNameRelease) ? cfName.takeRetainedValue() : cfName.takeUnretainedValue()) as String
        } else {
            name = withUnsafeBytes(of: info.name) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        let unit = info.unit
        let range = ParameterRange(
            minimum: info.minValue, maximum: info.maxValue, scale: Self.scale(of: flags),
            isStepped: unit == .indexed || unit == .boolean
        )
        return PluginParameter(id: id, name: name, range: range)
    }

    // MARK: - Private

    /// The display flags are one masked field, not independent bits.
    private static func scale(of flags: AudioUnitParameterOptions) -> ParameterScale {
        switch flags.intersection(.flag_DisplayMask) {
        case .flag_DisplayLogarithmic: .logarithmic
        case .flag_DisplayExponential: .exponential
        case .flag_DisplaySquareRoot: .squareRoot
        case .flag_DisplaySquared: .squared
        case .flag_DisplayCubeRoot: .cubeRoot
        case .flag_DisplayCubed: .cubed
        default: .linear
        }
    }

    private struct UnitBox: @unchecked Sendable {
        let unit: AudioUnit
    }

    /// What `deinit` hands to the main thread. The owner of the plugin's view comes along, since a view
    /// controller has to go there too, and goes first, because what it shows uses the unit. `run` lets
    /// go of it rather than leaving that to this object, whose last reference can drop on either thread.
    private final class Teardown: @unchecked Sendable {
        private let audioUnit: AudioUnit
        private let isInitialized: Bool
        private var viewOwner: AnyObject?

        init(audioUnit: AudioUnit, isInitialized: Bool, viewOwner: AnyObject?) {
            self.audioUnit = audioUnit
            self.isInitialized = isInitialized
            self.viewOwner = viewOwner
        }

        func run() {
            viewOwner = nil
            if isInitialized { AudioUnitUninitialize(audioUnit) }
            AudioComponentInstanceDispose(audioUnit)
        }
    }

    private func presets() -> [(number: Int32, name: String)] {
        var array: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_FactoryPresets, kAudioUnitScope_Global, 0, &array, &size) == noErr,
            let array
        else { return [] }
        let cfArray = array.takeRetainedValue()
        return (0..<CFArrayGetCount(cfArray)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(cfArray, index) else { return nil }
            let preset = pointer.assumingMemoryBound(to: AUPreset.self).pointee
            return (preset.presetNumber, (preset.presetName?.takeUnretainedValue() as String?) ?? "")
        }
    }

    private func applyFormat(channels: UInt32, sampleRate: Double) throws {
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
        for scope in [kAudioUnitScope_Input, kAudioUnitScope_Output] {
            var count: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_ElementCount, scope, 0, &count, &size) == noErr else { continue }
            for element in 0..<count {
                try check(
                    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, scope, element, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                    "StreamFormat"
                )
            }
        }
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw HostedPluginError.osStatus(status, what) }
    }
}
