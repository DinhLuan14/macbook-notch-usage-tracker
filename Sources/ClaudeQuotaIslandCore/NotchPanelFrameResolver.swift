import CoreGraphics

public enum NotchPanelFrameResolver {
    public static func originX(
        centerX: CGFloat,
        leftWidth: CGFloat,
        notchWidth: CGFloat,
        totalWidth: CGFloat,
        hasPhysicalNotch: Bool
    ) -> CGFloat {
        if hasPhysicalNotch {
            return centerX - leftWidth - notchWidth / 2
        }
        return centerX - totalWidth / 2
    }
}
