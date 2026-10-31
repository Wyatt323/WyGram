import UIKit

/// Height reserved by a docked keyboard, including the gap below a glass keyboard.
public func dockedKeyboardHeight(frame: CGRect, in bounds: CGRect, safeBottom: CGFloat) -> CGFloat {
    guard !frame.isNull, !frame.isInfinite, !frame.isEmpty, !bounds.isEmpty,
          frame.minY.isFinite, frame.maxY.isFinite else {
        return 0.0
    }
    let overlap = frame.intersection(bounds)
    guard !overlap.isNull, overlap.width >= bounds.width * 0.8,
          frame.maxY >= bounds.maxY - max(44.0, safeBottom), frame.minY < bounds.maxY else {
        // Floating iPad keyboards should not lift the entire interface.
        return 0.0
    }
    return min(bounds.height, max(0.0, bounds.maxY - frame.minY))
}
