import UIKit

extension DeviceMetrics {
    func sgAppBadgeOffset(statusBarHeight: CGFloat? = nil) -> CGFloat {
        let offset: CGFloat
        switch self {
        case .iPhoneX, .iPhone12Mini, .iPhone13Mini:
            offset = 2.0
        case .iPhoneXr, .iPhone12ProMax, .iPhone13ProMax:
            offset = 6.0
        case .iPhoneXSMax, .iPhone12, .iPhone13, .iPhone13Pro:
            offset = 4.0
        case .iPhone14Pro, .iPhone14ProZoomed:
            offset = 18.0
        case .iPhone14ProMax, .iPhone14ProMaxZoomed:
            offset = 19.0
        case .iPhone16Pro:
            offset = 21.0
        case .iPhone16ProMax, .iPhoneAir:
            offset = 22.0
        case let .unknown(_, measuredHeight, _, _):
            // Future phones use measured layout, not a device-name whitelist.
            offset = max(0.0, ((statusBarHeight ?? measuredHeight) - 22.0) * 0.5)
        default:
            offset = 0.0
        }
        return floorToScreenPixels(offset * self.sgScaleFactor)
    }

    var sgIsDisplayZoomed: Bool {
        UIScreen.main.scale < UIScreen.main.nativeScale
    }

    var sgScaleFactor: CGFloat {
        UIScreen.main.scale / UIScreen.main.nativeScale
    }

    var sgShowAppBadge: Bool {
        // Support future notched and Dynamic Island phones. Tablets and
        // home-button phones retain the previous hidden-badge behavior.
        self.type == .phone && self.onScreenNavigationHeight(inLandscape: false, systemOnScreenNavigationHeight: nil) != nil
    }
}
