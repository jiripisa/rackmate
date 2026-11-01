/// A line of a menu that can be chosen: entry `entry`, and `cell` when that entry is a grid.
public struct MenuPosition: Hashable, Sendable {
    public var entry: Int
    public var cell: Int?

    public init(entry: Int, cell: Int? = nil) {
        self.entry = entry
        self.cell = cell
    }
}

public enum MenuMove: Sendable {
    case up, down, left, right
}

/// Where the arrow keys go in a menu. Up and down keep the column in a grid and leave it at its edge,
/// left and right walk through its cells, and a move past the end comes back at the other end.
public struct MenuNavigator<Action> {
    private let entries: [MenuEntry<Action>]
    /// The lines that can be chosen, in reading order.
    private let positions: [MenuPosition]

    public init(entries: [MenuEntry<Action>]) {
        self.entries = entries
        positions = entries.enumerated().flatMap { index, entry -> [MenuPosition] in
            switch entry {
            case .item(_, _, _, true): [MenuPosition(entry: index)]
            case .grid(_, let cells): cells.indices.map { MenuPosition(entry: index, cell: $0) }
            case .item, .legend, .hint, .separator: []
            }
        }
    }

    public var first: MenuPosition? { positions.first }

    /// What choosing the line does. Nil for a line that cannot be chosen.
    public func action(at position: MenuPosition) -> Action? {
        guard entries.indices.contains(position.entry) else { return nil }
        switch (entries[position.entry], position.cell) {
        case (.item(_, let action, _, true), nil): return action
        case (.grid(_, let cells), let cell?) where cells.indices.contains(cell): return cells[cell].action
        default: return nil
        }
    }

    /// With nothing highlighted, down and right start at the top, up and left at the bottom.
    public func target(of move: MenuMove, from current: MenuPosition?) -> MenuPosition? {
        guard let current, let index = positions.firstIndex(of: current) else {
            return move == .down || move == .right ? positions.first : positions.last
        }
        switch move {
        case .left, .right:
            guard current.cell != nil else { return current }
            return positions[wrapped(index + (move == .right ? 1 : -1))]
        case .up:
            return vertical(by: -1, from: current, at: index)
        case .down:
            return vertical(by: 1, from: current, at: index)
        }
    }

    private func wrapped(_ index: Int) -> Int {
        (index % positions.count + positions.count) % positions.count
    }

    private func vertical(by step: Int, from current: MenuPosition, at index: Int) -> MenuPosition {
        guard let cell = current.cell, case .grid(let columns, let cells) = entries[current.entry] else {
            return positions[wrapped(index + step)]
        }
        let lastRow = (cells.count - 1) / columns
        let next = cell + step * columns
        if cells.indices.contains(next) { return MenuPosition(entry: current.entry, cell: next) }
        if step > 0, cell / columns < lastRow { return MenuPosition(entry: current.entry, cell: cells.count - 1) }
        let outside = (1..<positions.count).lazy.map { positions[wrapped(index + step * $0)] }.first { $0.entry != current.entry }
        if let outside { return outside }
        // Nothing but this grid: the other end of the column.
        let bottom = lastRow * columns + cell % columns
        let wrappedCell = step > 0 ? cell % columns : bottom < cells.count ? bottom : bottom - columns
        return MenuPosition(entry: current.entry, cell: wrappedCell)
    }
}
