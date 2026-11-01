import Foundation
import Testing
@testable import RackmateCore

struct EffectMoveTests {
    private func move(_ config: inout Configuration, _ id: UUID, to drop: EffectDrop) -> Bool {
        config.moveEffect(id, to: drop)
    }

    private func ids(_ channel: Channel) -> [[UUID]] { channel.effects.map { $0.map(\.id) } }

    @Test func beforeMakesASeriesStage() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a, b], [c]])])
        #expect(move(&config, c.id, to: .before(a.id)))
        #expect(ids(config.channels[0]) == [[c.id], [a.id, b.id]])
    }

    @Test func afterAStageGoesBehindAllOfIt() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[c], [a, b]])])
        #expect(move(&config, c.id, to: .after(a.id)))
        #expect(ids(config.channels[0]) == [[a.id, b.id], [c.id]])
    }

    @Test func belowJoinsTheParallelStage() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a, b], [c]])])
        #expect(move(&config, c.id, to: .below(a.id)))
        #expect(ids(config.channels[0]) == [[a.id, c.id, b.id]])
    }

    @Test func aboveJoinsBeforeTheTarget() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a, b], [c]])])
        #expect(move(&config, c.id, to: .above(b.id)))
        #expect(ids(config.channels[0]) == [[a.id, c.id, b.id]])
    }

    @Test func theLastEffectOfAStageLeavesNoEmptyRow() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a], [b], [c]])])
        #expect(move(&config, a.id, to: .below(c.id)))
        #expect(ids(config.channels[0]) == [[b.id], [c.id, a.id]])
    }

    @Test func droppingOnItselfChangesNothing() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a, b]])])
        let before = config
        #expect(!move(&config, a.id, to: .above(a.id)))
        #expect(!move(&config, a.id, to: .before(a.id)))
        #expect(config == before)
    }

    @Test func aFullStageRefusesAParallelDrop() {
        let full = (0..<3).map { _ in InsertEffect.fixture() }
        let c = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [full, [c]])])
        let before = config
        #expect(!move(&config, c.id, to: .above(full[0].id)))
        #expect(!move(&config, c.id, to: .below(full[2].id)))
        #expect(config == before)
    }

    @Test func reorderingInsideAFullStageIsAllowed() {
        let full = (0..<3).map { _ in InsertEffect.fixture() }
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [full])])
        #expect(config.stageHasRoom(for: full[0].id, moving: full[2].id))
        #expect(move(&config, full[2].id, to: .above(full[0].id)))
        #expect(ids(config.channels[0]) == [[full[2].id, full[0].id, full[1].id]])
    }

    @Test func movingToAnotherChannelKeepsIDAndState() {
        var moved = InsertEffect.fixture()
        moved.isOn = false
        moved.slot.state = Data([1, 2, 3])
        moved.sidechainIn = .mono(1)
        let source = Channel.fixture(effectRows: [[moved]])
        let target = Channel.fixture(kind: .effect)
        var config = Configuration.fixture(channels: [source, target])
        #expect(move(&config, moved.id, to: .end(channel: target.id)))
        #expect(config.channels[0].effects.isEmpty)
        #expect(config.channels[1].effects == [[moved]])
    }

    @Test func endOnAnEmptyChainStartsIt() {
        let a = InsertEffect.fixture()
        let target = Channel.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a]]), target])
        #expect(move(&config, a.id, to: .end(channel: target.id)))
        #expect(ids(config.channels[1]) == [[a.id]])
    }

    @Test func endOfTheOwnChainWhenAlreadyLastChangesNothing() {
        let a = InsertEffect.fixture(), b = InsertEffect.fixture()
        let channel = Channel.fixture(effectRows: [[a], [b]])
        var config = Configuration.fixture(channels: [channel])
        let before = config
        #expect(!move(&config, b.id, to: .end(channel: channel.id)))
        #expect(config == before)
    }

    @Test func anUnknownTargetChangesNothing() {
        let a = InsertEffect.fixture()
        var config = Configuration.fixture(channels: [Channel.fixture(effectRows: [[a]])])
        let before = config
        #expect(!move(&config, a.id, to: .before(UUID())))
        #expect(!move(&config, a.id, to: .end(channel: UUID())))
        #expect(!move(&config, UUID(), to: .before(a.id)))
        #expect(config == before)
    }

    @Test func zoneSidesAreSeriesStages() {
        let t = UUID()
        #expect(EffectDropZone.drop(target: t, across: 0.29, inUpperHalf: true, stageHasRoom: true) == .before(t))
        #expect(EffectDropZone.drop(target: t, across: 0.71, inUpperHalf: false, stageHasRoom: true) == .after(t))
    }

    @Test func zoneMiddleIsParallelByHalf() {
        let t = UUID()
        #expect(EffectDropZone.drop(target: t, across: 0.5, inUpperHalf: true, stageHasRoom: true) == .above(t))
        #expect(EffectDropZone.drop(target: t, across: 0.5, inUpperHalf: false, stageHasRoom: true) == .below(t))
    }

    @Test func zoneMiddleOfAFullStageTakesTheNearerSide() {
        let t = UUID()
        #expect(EffectDropZone.drop(target: t, across: 0.45, inUpperHalf: false, stageHasRoom: false) == .before(t))
        #expect(EffectDropZone.drop(target: t, across: 0.55, inUpperHalf: true, stageHasRoom: false) == .after(t))
        #expect(EffectDropZone.drop(target: t, across: 0.5, inUpperHalf: true, stageHasRoom: false) == .after(t))
    }
}
