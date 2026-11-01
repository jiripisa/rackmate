import Foundation
import Testing
@testable import RackmateCore

private let vasc = PluginID(type: "aumu", subtype: "VasC", manufacturer: "RoCl")

@Test func corruptConfigurationIsSkipped() throws {
    let dir = try tempDir()
    let store = ConfigurationStore(directory: dir)
    try store.save(.fixture(name: "Good"))
    try Data("{ not json".utf8).write(to: dir.appending(path: "broken.json"))
    #expect(store.loadAll().map(\.name) == ["Good"])
}

@Test func configurationsAreSortedByNameAndOverwrittenById() throws {
    let store = ConfigurationStore(directory: try tempDir())
    var b = Configuration.fixture(name: "b")
    try store.save(b)
    try store.save(.fixture(name: "A"))
    b.name = "c"
    try store.save(b)
    #expect(store.loadAll().map(\.name) == ["A", "c"])
}

@Test func deleteRemovesConfigurationAndUnknownIdIsNoOp() throws {
    let store = ConfigurationStore(directory: try tempDir())
    let config = Configuration.fixture(name: "X")
    try store.save(config)
    try store.delete(id: UUID())
    #expect(store.loadAll().count == 1)
    try store.delete(id: config.id)
    #expect(store.loadAll().isEmpty)
}

@Test func savingPresetWithSameNameReplaces() throws {
    let store = PresetStore(directory: try tempDir())
    try store.save(.init(name: "Bass", plugin: vasc, state: Data([1])))
    try store.save(.init(name: "Bass", plugin: vasc, state: Data([2])))
    #expect(store.presets(for: vasc).map(\.state) == [Data([2])])
}

@Test func presetsAreSortedCaseInsensitivelyAndAnyNameIsLegal() throws {
    let store = PresetStore(directory: try tempDir())
    let odd = PluginID(type: "aufx", subtype: "a/b ", manufacturer: "é\u{FF}.")
    for name in ["bravo", "Alpha", "../x/y", "Charlie"] {
        try store.save(.init(name: name, plugin: odd, state: Data()))
    }
    #expect(store.presets(for: odd).map(\.name) == ["../x/y", "Alpha", "bravo", "Charlie"])
    #expect(store.presets(for: vasc).isEmpty)
}

@Test func settingsFileMissingGivesDefaults() throws {
    let store = SettingsStore(file: try tempDir().appending(path: "settings.json"))
    #expect(store.load() == AppSettings.defaults)
}

@Test func settingsRoundTripAndCorruptFileGivesDefaults() throws {
    let file = try tempDir().appending(path: "settings.json")
    let store = SettingsStore(file: file)
    var settings = AppSettings.defaults
    settings.bufferFrames = 256
    settings.recentPlugins = [vasc]
    try store.save(settings)
    #expect(store.load() == settings)
    try Data("garbage".utf8).write(to: file)
    #expect(store.load() == AppSettings.defaults)
}

@Test func settingsFileWithoutRecentPluginsKeepsEverythingElse() throws {
    let file = try tempDir().appending(path: "settings.json")
    let store = SettingsStore(file: file)
    var settings = AppSettings.defaults
    settings.audioDeviceUID = "fuse"
    settings.sampleRate = 96000
    settings.bufferFrames = 256
    settings.clockSource = "Keys"
    settings.instrumentPositions = [.init(midiIn: .init(sourceName: "Keys", channel: .channel(3)), audioOut: .stereo(left: 4, right: 5))]
    settings.effectPositions = []
    settings.recentPlugins = [vasc]
    try store.save(settings)

    var fields = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(fields.removeValue(forKey: "recentPlugins") != nil)
    try JSONSerialization.data(withJSONObject: fields).write(to: file)

    settings.recentPlugins = []
    #expect(store.load() == settings)
}

@Test func settingsFileWithoutTheOptionalFieldsReads() throws {
    let file = try tempDir().appending(path: "settings.json")
    let store = SettingsStore(file: file)
    try store.save(.defaults)
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("audioDeviceUID"))
    #expect(!text.contains("clockSource"))
    #expect(store.load() == AppSettings.defaults)
}

@Test func capabilityCachePersistsAndSurvivesCorruption() throws {
    let file = try tempDir().appending(path: "caps.json")
    let caps = PluginCapabilities(acceptsMIDI: true, hasAudioIn: false, hasSidechain: false)
    let cache = CapabilityCache(file: file)
    #expect(cache[vasc] == nil)
    cache[vasc] = caps
    #expect(CapabilityCache(file: file)[vasc] == caps)
    cache[vasc] = nil
    #expect(CapabilityCache(file: file)[vasc] == nil)
    try Data("garbage".utf8).write(to: file)
    #expect(CapabilityCache(file: file)[vasc] == nil)
}

@Test func appPathsBaseIsRackmateApplicationSupport() {
    #expect(AppPaths.base().path.hasSuffix("Library/Application Support/Rackmate"))
}

@Suite("CapabilityCache presets")
struct CapabilityCachePresetTests {
    let plugin = PluginID(type: "aumu", subtype: "Mari", manufacturer: "Test")
    let caps = PluginCapabilities(acceptsMIDI: true, hasAudioIn: false, hasSidechain: false)

    @Test("Factory presets are remembered with the capabilities")
    func remembered() throws {
        let file = try tempDir().appending(path: "capabilities.json")
        let cache = CapabilityCache(file: file)
        #expect(cache.factoryPresets(for: plugin) == nil)
        cache.store(caps, factoryPresets: ["Bell", "Pad"], for: plugin)
        let again = CapabilityCache(file: file)
        #expect(again[plugin] == caps)
        #expect(again.factoryPresets(for: plugin) == ["Bell", "Pad"])
    }

    @Test("A cache file from before factory presets still reads")
    func oldFile() throws {
        let file = try tempDir().appending(path: "capabilities.json")
        let key = [plugin.type, plugin.subtype, plugin.manufacturer].joined(separator: "\u{0}")
        let old = try JSONEncoder().encode([key: caps])
        try old.write(to: file)
        let cache = CapabilityCache(file: file)
        #expect(cache[plugin] == caps)
        #expect(cache.factoryPresets(for: plugin) == nil)
    }

    @Test("Setting capabilities alone keeps the presets known")
    func subscriptKeepsPresets() throws {
        let cache = CapabilityCache(file: try tempDir().appending(path: "capabilities.json"))
        cache.store(caps, factoryPresets: ["Bell"], for: plugin)
        cache[plugin] = caps
        #expect(cache.factoryPresets(for: plugin) == ["Bell"])
    }
}

private func fileBytes(in folder: URL) throws -> [String: Data] {
    let paths = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
    var result: [String: Data] = [:]
    for path in paths {
        let url = folder.appending(path: path)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        result[path] = isDirectory.boolValue ? Data() : try Data(contentsOf: url)
    }
    return result
}

@Test func migrationCopiesTheOldFolder() throws {
    let root = try tempDir()
    let legacy = root.appending(path: "Pluginarium", directoryHint: .isDirectory)
    let base = root.appending(path: "Rackmate", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: legacy.appending(path: "presets"), withIntermediateDirectories: true)
    try Data("settings".utf8).write(to: legacy.appending(path: "settings.json"))
    try Data([1, 2, 3]).write(to: legacy.appending(path: "presets/a.json"))
    let before = try fileBytes(in: legacy)

    #expect(try AppPaths.migrate(from: legacy, to: base) == true)
    #expect(try fileBytes(in: base) == before)
    #expect(try fileBytes(in: legacy) == before)
}

@Test func migrationLeavesAnExistingFolderAlone() throws {
    let root = try tempDir()
    let legacy = root.appending(path: "Pluginarium", directoryHint: .isDirectory)
    let base = root.appending(path: "Rackmate", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: legacy.appending(path: "settings.json"))
    try Data("new".utf8).write(to: base.appending(path: "mine.json"))
    let legacyBefore = try fileBytes(in: legacy)
    let baseBefore = try fileBytes(in: base)

    #expect(try AppPaths.migrate(from: legacy, to: base) == false)
    #expect(try fileBytes(in: legacy) == legacyBefore)
    #expect(try fileBytes(in: base) == baseBefore)
}

@Test func migrationWithNoOldFolderDoesNothing() throws {
    let root = try tempDir()
    let legacy = root.appending(path: "Pluginarium", directoryHint: .isDirectory)
    let base = root.appending(path: "Rackmate", directoryHint: .isDirectory)

    #expect(try AppPaths.migrate(from: legacy, to: base) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func aFailedMigrationLeavesNoPartialFolder() throws {
    let root = try tempDir()
    let legacy = root.appending(path: "Pluginarium", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("settings".utf8).write(to: legacy.appending(path: "settings.json"))
    let notAFolder = root.appending(path: "file")
    try Data().write(to: notAFolder)
    let base = notAFolder.appending(path: "Rackmate", directoryHint: .isDirectory)

    #expect(throws: (any Error).self) { try AppPaths.migrate(from: legacy, to: base) }
    #expect(!FileManager.default.fileExists(atPath: base.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["Pluginarium", "file"])
}
