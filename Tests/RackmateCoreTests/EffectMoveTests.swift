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

struct EffectLandingTests {
    private let a = InsertEffect.fixture(), b = InsertEffect.fixture(), c = InsertEffect.fixture()
    private let moving = InsertEffect.fixture()
    private let first = UUID(), second = UUID()

    /// `first` holds [a, b] [c] and `moving`; `second` is empty. Slots are 100 wide and 40 high.
    private var configuration: Configuration {
        var one = Channel.fixture(effectRows: [[a, b], [c], [moving]])
        one.id = first
        var two = Channel.fixture()
        two.id = second
        return .fixture(channels: [one, two])
    }

    private var frames: [EffectPart: CGRect] {
        [
            .rack: CGRect(x: 0, y: 50, width: 1000, height: 500),
            .area(channel: first): CGRect(x: 100, y: 50, width: 500, height: 130),
            .chain(channel: first): CGRect(x: 110, y: 70, width: 480, height: 100),
            .add(channel: first): CGRect(x: 520, y: 100, width: 34, height: 34),
            .area(channel: second): CGRect(x: 100, y: 200, width: 500, height: 130),
            .chain(channel: second): CGRect(x: 110, y: 220, width: 480, height: 100),
            .add(channel: second): CGRect(x: 112, y: 250, width: 34, height: 34),
            .stage(first: a.id): CGRect(x: 110, y: 70, width: 124, height: 86),
            .slot(a.id): CGRect(x: 122, y: 70, width: 100, height: 40),
            .slot(b.id): CGRect(x: 122, y: 116, width: 100, height: 40),
            .stage(first: c.id): CGRect(x: 260, y: 93, width: 100, height: 40),
            .slot(c.id): CGRect(x: 260, y: 93, width: 100, height: 40),
            .stage(first: moving.id): CGRect(x: 390, y: 93, width: 100, height: 40),
            .slot(moving.id): CGRect(x: 390, y: 93, width: 100, height: 40),
        ]
    }

    private func landing(_ x: CGFloat, _ y: CGFloat, in configuration: Configuration? = nil, frames: [EffectPart: CGRect]? = nil) -> EffectLanding? {
        (configuration ?? self.configuration).landing(of: moving.id, at: CGPoint(x: x, y: y), frames: frames ?? self.frames)
    }

    @Test func theOuterPartOfASlotMeansASeriesStageBesideItsStage() {
        #expect(landing(265, 110) == EffectLanding(drop: .before(c.id), mark: CGRect(x: 256, y: 93, width: 2, height: 40)))
        #expect(landing(355, 110) == EffectLanding(drop: .after(c.id), mark: CGRect(x: 362, y: 93, width: 2, height: 40)))
    }

    @Test func theLineOfASeriesStageRunsAlongTheWholeStage() {
        #expect(landing(125, 80) == EffectLanding(drop: .before(a.id), mark: CGRect(x: 106, y: 70, width: 2, height: 86)))
    }

    @Test func theMiddleOfASlotMeansParallelByItsHalf() {
        #expect(landing(310, 100) == EffectLanding(drop: .above(c.id), mark: CGRect(x: 260, y: 89, width: 100, height: 2)))
        #expect(landing(310, 120) == EffectLanding(drop: .below(c.id), mark: CGRect(x: 260, y: 135, width: 100, height: 2)))
    }

    @Test func aFullStageOffersOnlyTheSides() {
        let extra = InsertEffect.fixture()
        var full = configuration
        full.channels[0].effects[0].append(extra)
        #expect(landing(160, 80, in: full)?.drop == .before(a.id))
        #expect(landing(180, 80, in: full)?.drop == .after(a.id))
    }

    @Test func aFullStageHoldingTheMovingEffectStillTakesItBack() {
        var full = configuration
        full.channels[0].effects = [[a, b, moving], [c]]
        #expect(landing(170, 80, in: full)?.drop == .above(a.id))
    }

    @Test func droppingOnItselfLandsNowhere() {
        #expect(landing(440, 110) == nil)
    }

    @Test func aDropCanLandOnASlotOfAnotherChannel() {
        var frames = frames
        frames[.slot(c.id)] = CGRect(x: 260, y: 240, width: 100, height: 40)
        var configuration = configuration
        configuration.channels[1].effects = [[c]]
        configuration.channels[0].effects = [[a, b], [moving]]
        frames[.stage(first: c.id)] = CGRect(x: 260, y: 240, width: 100, height: 40)
        #expect(landing(265, 250, in: configuration, frames: frames)?.drop == .before(c.id))
    }

    @Test func elsewhereInAnEffectsAreaMeansTheEndOfThatChain() {
        #expect(landing(150, 60) == EffectLanding(drop: .end(channel: first), mark: CGRect(x: 517, y: 100, width: 2, height: 34)))
        #expect(landing(245, 110)?.drop == .end(channel: first))
    }

    @Test func theGapInAStageIsNotASlot() {
        #expect(landing(170, 113)?.drop == .end(channel: first))
    }

    @Test func anEmptyChainTakesTheEffectAtItsEnd() {
        #expect(landing(300, 300) == EffectLanding(drop: .end(channel: second), mark: CGRect(x: 109, y: 250, width: 2, height: 34)))
    }

    @Test func outsideAnyEffectsAreaThereIsNoLanding() {
        #expect(landing(50, 110) == nil)
        #expect(landing(300, 190) == nil)
    }

    @Test func aChannelScrolledOutOfTheRackIsNotThere() {
        var frames = frames
        frames[.rack] = CGRect(x: 0, y: 100, width: 1000, height: 450)
        #expect(landing(310, 80, frames: frames) == nil)
    }

    @Test func aSlotScrolledOutOfItsChainIsNotThere() {
        var frames = frames
        frames[.chain(channel: first)] = CGRect(x: 110, y: 70, width: 200, height: 100)
        #expect(landing(355, 110, frames: frames)?.drop == .end(channel: first))
    }

    @Test func theLineStaysInAChainWhosePlusIsScrolledOut() {
        var frames = frames
        frames[.chain(channel: first)] = CGRect(x: 110, y: 70, width: 300, height: 100)
        #expect(landing(150, 60, frames: frames)?.mark == CGRect(x: 408, y: 100, width: 2, height: 34))
    }
}
