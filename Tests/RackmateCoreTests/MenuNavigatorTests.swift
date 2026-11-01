import Testing
@testable import RackmateCore

struct MenuNavigatorTests {
    private func cells(_ count: Int) -> [MenuCell<Int>] {
        (0..<count).map { MenuCell(String($0), action: $0) }
    }

    private func item(_ title: String, _ action: Int, isEnabled: Bool = true) -> MenuEntry<Int> {
        .item(title, action: action, isEnabled: isEnabled)
    }

    private func position(_ entry: Int, cell: Int? = nil) -> MenuPosition {
        MenuPosition(entry: entry, cell: cell)
    }

    /// `All` at 1 over the sixteen channels at 2, as the channel menu is.
    private var channelMenu: MenuNavigator<Int> {
        MenuNavigator(entries: [.legend("MIDI channel"), item("All", 99), .grid(columns: 4, cells: cells(16))])
    }

    /// Nothing but a grid, as the output menu is.
    private var gridOnly: MenuNavigator<Int> {
        MenuNavigator(entries: [.legend("Audio out"), .grid(columns: 2, cells: cells(5))])
    }

    // MARK: - Plain menus

    @Test func theFirstLineThatCanBeChosenComesFirst() {
        let menu = MenuNavigator(entries: [.legend("L"), item("Off", 1, isEnabled: false), .separator, item("On", 2)])
        #expect(menu.first == position(3))
    }

    @Test func aMenuOfNothingHasNoFirst() {
        #expect(MenuNavigator<Int>(entries: [.legend("L"), .hint("None"), .grid(columns: 2, cells: [])]).first == nil)
    }

    @Test func upAndDownSkipWhatCannotBeChosenAndWrap() {
        let menu = MenuNavigator(entries: [item("A", 1), .separator, item("B", 2, isEnabled: false), item("C", 3)])
        #expect(menu.target(of: .down, from: position(0)) == position(3))
        #expect(menu.target(of: .down, from: position(3)) == position(0))
        #expect(menu.target(of: .up, from: position(0)) == position(3))
    }

    @Test func withNothingHighlightedDownStartsAtTheTopAndUpAtTheBottom() {
        let menu = MenuNavigator(entries: [item("A", 1), item("B", 2)])
        #expect(menu.target(of: .down, from: nil) == position(0))
        #expect(menu.target(of: .up, from: nil) == position(1))
    }

    @Test func sidewaysDoesNothingOnAPlainLine() {
        #expect(channelMenu.target(of: .right, from: position(1)) == position(1))
        #expect(channelMenu.target(of: .left, from: position(1)) == position(1))
    }

    @Test func aMenuOfNothingGoesNowhere() {
        #expect(MenuNavigator<Int>(entries: [.hint("None")]).target(of: .down, from: nil) == nil)
    }

    // MARK: - Grids

    @Test func downFromALineEntersTheGridAtItsFirstCell() {
        #expect(channelMenu.target(of: .down, from: position(1)) == position(2, cell: 0))
    }

    @Test func downAndUpKeepTheColumn() {
        #expect(channelMenu.target(of: .down, from: position(2, cell: 1)) == position(2, cell: 5))
        #expect(channelMenu.target(of: .up, from: position(2, cell: 5)) == position(2, cell: 1))
    }

    @Test func leftAndRightRunThroughTheCellsAndAcrossRows() {
        #expect(channelMenu.target(of: .right, from: position(2, cell: 3)) == position(2, cell: 4))
        #expect(channelMenu.target(of: .left, from: position(2, cell: 4)) == position(2, cell: 3))
    }

    @Test func upFromTheTopRowLeavesTheGrid() {
        #expect(channelMenu.target(of: .up, from: position(2, cell: 2)) == position(1))
    }

    @Test func downFromTheBottomRowWrapsToTheTopOfTheMenu() {
        #expect(channelMenu.target(of: .down, from: position(2, cell: 14)) == position(1))
    }

    @Test func upFromTheTopOfTheMenuWrapsToTheLastCell() {
        #expect(channelMenu.target(of: .up, from: position(1)) == position(2, cell: 15))
    }

    @Test func downOverAShortLastRowLandsOnItsLastCell() {
        #expect(gridOnly.target(of: .down, from: position(1, cell: 3)) == position(1, cell: 4))
    }

    @Test func aMenuThatIsOneGridWrapsWithinItsColumn() {
        #expect(gridOnly.target(of: .down, from: position(1, cell: 4)) == position(1, cell: 0))
        #expect(gridOnly.target(of: .up, from: position(1, cell: 1)) == position(1, cell: 3))
        #expect(gridOnly.target(of: .up, from: position(1, cell: 0)) == position(1, cell: 4))
    }

    @Test func sidewaysWrapsOverTheWholeMenu() {
        #expect(gridOnly.target(of: .right, from: position(1, cell: 4)) == position(1, cell: 0))
        #expect(gridOnly.target(of: .left, from: position(1, cell: 0)) == position(1, cell: 4))
    }

    // MARK: - Actions

    @Test func aPositionNamesItsAction() {
        #expect(channelMenu.action(at: position(1)) == 99)
        #expect(channelMenu.action(at: position(2, cell: 7)) == 7)
    }

    @Test func aLineThatCannotBeChosenHasNoAction() {
        let menu = MenuNavigator(entries: [item("Off", 1, isEnabled: false), .legend("L")])
        #expect(menu.action(at: position(0)) == nil)
        #expect(menu.action(at: position(1)) == nil)
    }
}
