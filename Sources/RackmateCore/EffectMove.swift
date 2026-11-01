import CoreGraphics
import Foundation

/// Where a dragged effect lands.
public enum EffectDrop: Equatable, Sendable {
    /// A new series stage before the target's stage.
    case before(UUID)
    /// A new series stage after the target's stage.
    case after(UUID)
    /// Into the target's parallel stage, ahead of the target.
    case above(UUID)
    /// Into the target's parallel stage, behind the target.
    case below(UUID)
    /// A new series stage at the end of the channel's chain.
    case end(channel: UUID)
}

/// Turns the pointer position over a slot into a drop.
public enum EffectDropZone {
    /// The outer part of a slot's width that means a series stage.
    static let sideShare = 0.3

    /// - Parameters:
    ///   - across: where the pointer is across the slot, 0 at the left edge and 1 at the right.
    ///   - inUpperHalf: whether the pointer is in the upper half of the slot.
    ///   - stageHasRoom: whether the target's stage takes one more effect.
    public static func drop(target: UUID, across: Double, inUpperHalf: Bool, stageHasRoom: Bool) -> EffectDrop {
        if across < sideShare { return .before(target) }
        if across > 1 - sideShare { return .after(target) }
        if stageHasRoom { return inUpperHalf ? .above(target) : .below(target) }
        return across < 0.5 ? .before(target) : .after(target)
    }
}

/// A part of the effects columns whose place on screen a drag has to know.
public enum EffectPart: Hashable, Sendable {
    /// What shows of the units, which scroll under the top bar.
    case rack
    /// `.effects`: everything a drag can end in for this channel.
    case area(channel: UUID)
    /// `.chain`: what shows of the effects, which scroll sideways.
    case chain(channel: UUID)
    /// `.add-fx`.
    case add(channel: UUID)
    /// `.stage`, by the first effect in it.
    case stage(first: UUID)
    /// `.fx`.
    case slot(UUID)
}

/// Where a dragged effect would land, and the amber line that shows it.
public struct EffectLanding: Equatable, Sendable {
    public var drop: EffectDrop
    public var mark: CGRect

    public init(drop: EffectDrop, mark: CGRect) {
        self.drop = drop
        self.mark = mark
    }
}

extension Configuration {
    /// `dropAt`: what ending a drag of `moving` at `point` would do, nil when it would do nothing.
    /// `point` and `frames` are in one coordinate space.
    public func landing(of moving: UUID, at point: CGPoint, frames: [EffectPart: CGRect]) -> EffectLanding? {
        guard let rack = frames[.rack], rack.contains(point),
            let channel = channels.first(where: { frames[.area(channel: $0.id)]?.contains(point) == true }),
            var landing = landing(of: moving, in: channel, at: point, frames: frames)
        else { return nil }
        // The top of a unit can be scrolled under the top bar, and the bottom off the rack.
        landing.mark.origin.y = max(rack.minY, min(landing.mark.minY, rack.maxY - landing.mark.height))
        return landing
    }

    private func landing(of moving: UUID, in channel: Channel, at point: CGPoint, frames: [EffectPart: CGRect]) -> EffectLanding? {
        if frames[.chain(channel: channel.id)]?.contains(point) == true {
            for row in channel.effects {
                guard let target = row.first(where: { frames[.slot($0.id)]?.contains(point) == true }) else { continue }
                if target.id == moving { return nil }
                return landing(of: moving, on: target.id, in: row, at: point, frames: frames)
            }
        }
        guard let add = frames[.add(channel: channel.id)], let chain = frames[.chain(channel: channel.id)] else { return nil }
        let mark = CGRect(x: min(add.minX - 3, chain.maxX - 2), y: add.minY, width: 2, height: add.height)
        return EffectLanding(drop: .end(channel: channel.id), mark: mark)
    }

    private func landing(of moving: UUID, on target: UUID, in row: [InsertEffect], at point: CGPoint, frames: [EffectPart: CGRect]) -> EffectLanding? {
        guard let slot = frames[.slot(target)], let first = row.first, let stage = frames[.stage(first: first.id)] else { return nil }
        let drop = EffectDropZone.drop(
            target: target, across: (point.x - slot.minX) / slot.width, inUpperHalf: point.y < slot.midY,
            stageHasRoom: stageHasRoom(for: target, moving: moving))
        let mark = switch drop {
        case .before: CGRect(x: stage.minX - 4, y: stage.minY, width: 2, height: stage.height)
        case .after: CGRect(x: stage.maxX + 2, y: stage.minY, width: 2, height: stage.height)
        case .above: CGRect(x: slot.minX, y: slot.minY - 4, width: slot.width, height: 2)
        case .below, .end: CGRect(x: slot.minX, y: slot.maxY + 2, width: slot.width, height: 2)
        }
        return EffectLanding(drop: drop, mark: mark)
    }

    /// Whether the stage of `target` takes `moving`: it is not full, or `moving` already stands in it.
    public func stageHasRoom(for target: UUID, moving: UUID) -> Bool {
        for channel in channels {
            for row in channel.effects where row.contains(where: { $0.id == target }) {
                return row.count < Channel.maxParallel || row.contains(where: { $0.id == moving })
            }
        }
        return false
    }

    /// Moves the effect, with its id and state, to the drop. Returns true when something changed.
    /// A refused or pointless move leaves the configuration as it was.
    @discardableResult
    public mutating func moveEffect(_ id: UUID, to drop: EffectDrop) -> Bool {
        var copy = self
        guard copy.perform(id, drop), copy != self else { return false }
        self = copy
        return true
    }

    private mutating func perform(_ id: UUID, _ drop: EffectDrop) -> Bool {
        guard let source = channels.firstIndex(where: { $0.effects.joined().contains { $0.id == id } }) else { return false }
        let target: UUID? = switch drop {
        case .before(let t), .after(let t), .above(let t), .below(let t): t
        case .end: nil
        }
        if target == id { return false }
        if let target, !channels.contains(where: { $0.effects.joined().contains { $0.id == target } }) { return false }
        if case .end(let channel) = drop, !channels.contains(where: { $0.id == channel }) { return false }

        guard let effect = channels[source].effects.joined().first(where: { $0.id == id }) else { return false }
        channels[source].removeEffect(effectID: id)

        switch drop {
        case .end(let channel):
            guard let index = channels.firstIndex(where: { $0.id == channel }) else { return false }
            channels[index].addEffect(effect)
        case .before(let t), .after(let t), .above(let t), .below(let t):
            guard let (channelIndex, rowIndex) = locate(t) else { return false }
            switch drop {
            case .before: channels[channelIndex].effects.insert([effect], at: rowIndex)
            case .after: channels[channelIndex].effects.insert([effect], at: rowIndex + 1)
            default:
                guard channels[channelIndex].effects[rowIndex].count < Channel.maxParallel,
                    let slot = channels[channelIndex].effects[rowIndex].firstIndex(where: { $0.id == t })
                else { return false }
                if case .above = drop {
                    channels[channelIndex].effects[rowIndex].insert(effect, at: slot)
                } else {
                    channels[channelIndex].effects[rowIndex].insert(effect, at: slot + 1)
                }
            }
        }
        return true
    }

    private func locate(_ effectID: UUID) -> (channel: Int, row: Int)? {
        for (channelIndex, channel) in channels.enumerated() {
            if let row = channel.effects.firstIndex(where: { $0.contains { $0.id == effectID } }) {
                return (channelIndex, row)
            }
        }
        return nil
    }
}
