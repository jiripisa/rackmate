import CoreGraphics

/// How the rack scrolls under a dragged effect, so a drag can reach a channel out of view.
public enum EffectDragScroll {
    /// How far from the rack's top or bottom edge the pointer scrolls it, on either side of the edge.
    static let band: CGFloat = 40
    /// 300 points a second, a channel in about half a second.
    static let pace: CGFloat = 5

    /// How often `step` is asked.
    public static let interval = Duration.seconds(1.0 / 60)

    /// How far to scroll now with the pointer at `pointerY`: up is negative, down is positive, and
    /// away from both edges it is zero. All three are in one coordinate space.
    public static func step(pointerY: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        if abs(pointerY - top) <= band { return -pace }
        if abs(pointerY - bottom) <= band { return pace }
        return 0
    }
}
