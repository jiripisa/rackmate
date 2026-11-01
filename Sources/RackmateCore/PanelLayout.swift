import CoreGraphics

/// Where things open on the panel.
public enum PanelLayout {

    /// For a view that reports no size at all.
    public static let fallbackPluginWindowSize = CGSize(width: 400, height: 300)

    /// `openMenu`: under the anchor, kept inside the window, with the top left corner last to give way.
    public static func menuOrigin(anchor: CGRect, menu: CGSize, window: CGSize) -> CGPoint {
        CGPoint(
            x: max(26, min(anchor.minX, window.width - menu.width - 26)),
            y: max(12, min(anchor.maxY + 4, window.height - menu.height - 12))
        )
    }

    /// `.stage` and `.stage.parallel` as flex items of `.chain`, which has `width` for all of them: they
    /// grow by even shares and shrink in proportion to their basis, each between its limits. Stages
    /// that do not fit at their minimum stay there, and the chain scrolls.
    public static func stageWidths(isParallel: [Bool], in width: CGFloat) -> [CGFloat] {
        let stages = isParallel.map { $0 ? parallelStage : seriesStage }
        var widths = [CGFloat?](repeating: nil, count: stages.count)
        while widths.contains(nil) {
            let open = widths.indices.filter { widths[$0] == nil }
            let free = width - widths.compactMap(\.self).reduce(0, +) - open.map { stages[$0].basis }.reduce(0, +)
            let weight: (Int) -> CGFloat = { free > 0 ? 1 : stages[$0].basis }
            let total = open.map(weight).reduce(0, +)
            let wished = open.map { (index: $0, width: stages[$0].basis + free * weight($0) / total) }
            let excess = wished.map { stages[$0.index].clamped($0.width) - $0.width }.reduce(0, +)
            // CSS settles the limits of one direction at a time, and the others share what that leaves.
            for stage in wished {
                let clamped = stages[stage.index].clamped(stage.width)
                if excess == 0 || (excess > 0 ? clamped > stage.width : clamped < stage.width) { widths[stage.index] = clamped }
            }
        }
        return widths.compactMap(\.self)
    }

    /// `flex` of a stage, with `min-width` and `max-width`.
    private struct StageSize {
        var minimum: CGFloat
        var basis: CGFloat
        var maximum: CGFloat

        func clamped(_ width: CGFloat) -> CGFloat { min(max(width, minimum), maximum) }
    }

    private static let seriesStage = StageSize(minimum: 120, basis: 150, maximum: 240)
    private static let parallelStage = StageSize(minimum: 150, basis: 190, maximum: 280)

    /// `AUViewController` views often have a zero frame, so the view owner's preferred size and then
    /// the view's fitting size stand in for it.
    public static func pluginWindowSize(frame: CGSize, preferred: CGSize?, fitting: CGSize) -> CGSize {
        [frame, preferred ?? .zero, fitting].first { $0.width > 0 && $0.height > 0 } ?? fallbackPluginWindowSize
    }

    /// `openWindow`: from the top left of the mixer, each window a step further, six steps around.
    public static func pluginWindowOffset(_ count: Int) -> CGPoint {
        let step = CGFloat(count % 6)
        return CGPoint(x: 240 + step * 34, y: 90 + step * 30)
    }
}
