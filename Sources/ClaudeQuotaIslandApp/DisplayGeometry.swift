import AppKit
import ClaudeQuotaIslandCore

struct DisplayOption: Identifiable, Equatable {
    let id: String
    let name: String
    let hasNotch: Bool
}

struct NotchLayoutMetrics: Equatable {
    let collapsedLeftWidth: CGFloat
    let expandedLeftWidth: CGFloat
    let notchWidth: CGFloat
    let collapsedRightWidth: CGFloat
    let expandedRightWidth: CGFloat
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    let hasPhysicalNotch: Bool

    var totalWidth: CGFloat { expandedLeftWidth + notchWidth + expandedRightWidth }

    func visualMetrics(isExpanded: Bool) -> NotchVisualMetrics {
        NotchVisualMetrics(
            leftWidth: isExpanded ? expandedLeftWidth : collapsedLeftWidth,
            notchWidth: notchWidth,
            rightWidth: isExpanded ? expandedRightWidth : collapsedRightWidth,
            height: isExpanded ? expandedHeight : collapsedHeight
        )
    }

    static func forScreen(
        _ screen: NSScreen,
        preferences: DisplayPreferences,
        quotaSnapshot: ClaudeSessionSnapshot?,
        sessionSnapshot: ClaudeSessionSnapshot?
    ) -> NotchLayoutMetrics {
        let collapsed = CompactNotchWidthResolver.widths(
            preferences: preferences,
            quotaSnapshot: quotaSnapshot,
            sessionSnapshot: sessionSnapshot
        )
        let expanded = expandedSideWidths(for: preferences)
        let collapsedHeight = ScreenResolver.barHeight(for: screen)
        return NotchLayoutMetrics(
            collapsedLeftWidth: collapsed.left,
            expandedLeftWidth: expanded.left,
            notchWidth: ScreenResolver.notchWidth(for: screen),
            collapsedRightWidth: collapsed.right,
            expandedRightWidth: expanded.right,
            collapsedHeight: collapsedHeight,
            expandedHeight: min(collapsedHeight + 12, 48),
            hasPhysicalNotch: ScreenResolver.hasNotch(screen)
        )
    }

    static func preview(
        preferences: DisplayPreferences,
        quotaSnapshot: ClaudeSessionSnapshot?,
        sessionSnapshot: ClaudeSessionSnapshot?
    ) -> NotchLayoutMetrics {
        let collapsed = CompactNotchWidthResolver.widths(
            preferences: preferences,
            quotaSnapshot: quotaSnapshot,
            sessionSnapshot: sessionSnapshot
        )
        let expanded = expandedSideWidths(for: preferences)
        return NotchLayoutMetrics(
            collapsedLeftWidth: collapsed.left,
            expandedLeftWidth: min(expanded.left, 260),
            notchWidth: 105,
            collapsedRightWidth: collapsed.right,
            expandedRightWidth: min(expanded.right, 250),
            collapsedHeight: 34,
            expandedHeight: 46,
            hasPhysicalNotch: false
        )
    }

    private static func expandedSideWidths(
        for preferences: DisplayPreferences
    ) -> (left: CGFloat, right: CGFloat) {
        let left: CGFloat
        switch preferences.style {
        case .full: left = 272
        case .iconCompact: left = 232
        case .progressRings: left = 264
        case .minimal: left = 176
        }
        if preferences.rightSideMode == .claudeOnly {
            return (left, 106)
        }
        switch preferences.style {
        case .full: return (left, 280)
        case .iconCompact, .progressRings: return (left, 258)
        case .minimal: return (left, 204)
        }
    }
}

private enum CompactNotchWidthResolver {
    private static let laneHorizontalPadding: CGFloat = 16
    private static let itemSpacing: CGFloat = 3
    private static let laneSpacing: CGFloat = 5
    private static let dividerWidth: CGFloat = 1
    private static let symbolWidth: CGFloat = 13
    private static let leftSafetyMargin: CGFloat = 6
    private static let rightSafetyMargin: CGFloat = 2
    private static let modelSlotMinimum: CGFloat = 42
    private static let modelSlotMaximum: CGFloat = 100

    static func widths(
        preferences: DisplayPreferences,
        quotaSnapshot: ClaudeSessionSnapshot?,
        sessionSnapshot: ClaudeSessionSnapshot?
    ) -> (left: CGFloat, right: CGFloat) {
        let now = Date.now
        let fiveHour = quotaSnapshot?.fiveHour?.current(at: now)
        let sevenDay = quotaSnapshot?.sevenDay?.current(at: now)
        let usesSymbols = preferences.style == .iconCompact || preferences.style == .progressRings
        let fiveHourWidth = quotaItemWidth(
            label: "5h",
            percentage: percentageText(
                fiveHour?.usedPercentage,
                metric: preferences.quotaMetric
            ),
            usesSymbol: usesSymbols,
            reset: preferences.showsResetTime
                ? QuotaFormatter.resetDuration(
                    until: fiveHour?.resetsAt,
                    compact: true
                )
                : nil
        )
        let sevenDayWidth = quotaItemWidth(
            label: "7d",
            percentage: percentageText(
                sevenDay?.usedPercentage,
                metric: preferences.quotaMetric
            ),
            usesSymbol: usesSymbols,
            reset: nil
        )
        let left = laneHorizontalPadding
            + fiveHourWidth
            + laneSpacing
            + dividerWidth
            + laneSpacing
            + sevenDayWidth
            + leftSafetyMargin

        if preferences.rightSideMode == .claudeOnly {
            let right = laneHorizontalPadding
                + textWidth("Claude", weight: .semibold)
                + rightSafetyMargin
            return (
                left: ceil(min(max(left, 68), 176)),
                right: ceil(min(max(right, 54), 86))
            )
        }

        let model = sessionSnapshot?.modelDisplayName ?? "Claude"
        let modelSlot = min(
            max(textWidth(model, weight: .semibold), modelSlotMinimum),
            modelSlotMaximum
        )
        let sourceWidth: CGFloat = sessionSnapshot?.resolvedSource.isRemote == true ? 19 : 0
        let context = contextPercentageText(for: sessionSnapshot)
        let right = 18
            + sourceWidth
            + modelSlot
            + 13
            + textWidth(context, weight: .semibold)
            + rightSafetyMargin

        return (
            left: ceil(min(max(left, 68), 176)),
            right: ceil(min(max(right, 82), 174))
        )
    }

    private static func quotaItemWidth(
        label: String,
        percentage: String,
        usesSymbol: Bool,
        reset: String?
    ) -> CGFloat {
        let base = (usesSymbol ? symbolWidth : textWidth(label))
            + itemSpacing
            + textWidth(percentage)
        guard let reset else { return base }
        return base + itemSpacing + textWidth(reset)
    }

    private static func percentageText(_ used: Double?, metric: QuotaMetric) -> String {
        QuotaFormatter.percentage(used, metric: metric).map { "\($0)%" } ?? "…"
    }

    private static func contextPercentageText(for snapshot: ClaudeSessionSnapshot?) -> String {
        if let percentage = snapshot?.contextUsedPercentage {
            return "\(Int(min(max(percentage, 0), 100).rounded()))%"
        }
        return QuotaFormatter.tokenCount(snapshot?.totalInputTokens) ?? "…"
    }

    private static func textWidth(
        _ text: String,
        weight: NSFont.Weight = .medium
    ) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

struct NotchVisualMetrics: Equatable {
    let leftWidth: CGFloat
    let notchWidth: CGFloat
    let rightWidth: CGFloat
    let height: CGFloat

    var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }
}

enum ScreenResolver {
    static func availableOptions() -> [DisplayOption] {
        NSScreen.screens.map {
            DisplayOption(id: id(for: $0), name: $0.localizedName, hasNotch: hasNotch($0))
        }
    }

    static func resolve(preferredID: String) -> NSScreen? {
        if preferredID != AppModel.automaticSelectionID,
           let selected = NSScreen.screens.first(where: { id(for: $0) == preferredID }) {
            return selected
        }
        return NSScreen.screens.first(where: hasNotch) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func id(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "\(screen.localizedName)-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if hasNotch(screen),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let measured = right.minX - left.maxX
            if measured > 80, measured < screen.frame.width / 2 {
                return measured
            }
        }
        return hasNotch(screen) ? 180 : 110
    }

    static func notchCenterX(for screen: NSScreen) -> CGFloat {
        if hasNotch(screen),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }

    static func barHeight(for screen: NSScreen) -> CGFloat {
        let measured = screen.safeAreaInsets.top
        return min(max(measured, 30), 40)
    }
}
