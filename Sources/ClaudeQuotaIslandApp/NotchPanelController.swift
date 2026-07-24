import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    private static let collapseFrameDelay: TimeInterval = 0.38

    private let model: AppModel
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchBarView>?
    private var collapseFrameWorkItem: DispatchWorkItem?
    private var pointerPollingTimer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateLayout()
        panel.orderFrontRegardless()
        startPointerPolling()
    }

    func updateLayout() {
        guard let screen = ScreenResolver.resolve(preferredID: model.preferredDisplayID) else { return }
        let metrics = layoutMetrics(for: screen)
        let panel = panel ?? makePanel()
        self.panel = panel

        let frame = panelFrame(on: screen, metrics: metrics, isExpanded: model.isIslandExpanded)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        hostingView?.rootView = NotchBarView(model: model, metrics: metrics)
        panel.orderFrontRegardless()
    }

    func setExpanded(_ expanded: Bool) {
        collapseFrameWorkItem?.cancel()
        collapseFrameWorkItem = nil

        guard let panel,
              let screen = ScreenResolver.resolve(preferredID: model.preferredDisplayID) else { return }
        let metrics = layoutMetrics(for: screen)

        if expanded {
            // Grow the transparent AppKit canvas first; the visible SwiftUI
            // surface then animates inside it without frame-animation jank.
            panel.setFrame(panelFrame(on: screen, metrics: metrics, isExpanded: true), display: true)
            panel.orderFrontRegardless()
            return
        }

        // Keep the large canvas while SwiftUI finishes the closing spring,
        // then shrink the transparent hit area back to the compact surface.
        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel,
                  !self.model.isIslandExpanded,
                  let screen = ScreenResolver.resolve(preferredID: self.model.preferredDisplayID) else { return }
            let currentMetrics = self.layoutMetrics(for: screen)
            panel.setFrame(
                self.panelFrame(on: screen, metrics: currentMetrics, isExpanded: false),
                display: true
            )
        }
        collapseFrameWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseFrameDelay, execute: workItem)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.sharingType = .readOnly

        let metrics = ScreenResolver.resolve(preferredID: model.preferredDisplayID)
            .map(layoutMetrics)
            ?? .preview(
                preferences: model.displayPreferences,
                quotaSnapshot: model.quotaSnapshot,
                sessionSnapshot: model.selectedSnapshot
            )
        let hostingView = HoverTrackingHostingView(rootView: NotchBarView(model: model, metrics: metrics))
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.onHoverChanged = { [weak model] hovering in
            model?.handleIslandHover(hovering)
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.hostingView = hostingView
        return panel
    }

    private func layoutMetrics(for screen: NSScreen) -> NotchLayoutMetrics {
        NotchLayoutMetrics.forScreen(
            screen,
            preferences: model.displayPreferences,
            quotaSnapshot: model.quotaSnapshot,
            sessionSnapshot: model.selectedSnapshot
        )
    }

    private func panelFrame(
        on screen: NSScreen,
        metrics: NotchLayoutMetrics,
        isExpanded: Bool
    ) -> NSRect {
        let visual = metrics.visualMetrics(isExpanded: isExpanded)
        return NSRect(
            x: screen.frame.midX - visual.totalWidth / 2,
            y: screen.frame.maxY - visual.height,
            width: visual.totalWidth,
            height: visual.height
        )
    }

    private func startPointerPolling() {
        guard ProcessInfo.processInfo.environment["CQI_HOLD_EXPANDED"] != "1" else { return }
        guard pointerPollingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.model.handleIslandHover(panel.frame.contains(NSEvent.mouseLocation))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerPollingTimer = timer
    }
}

private final class NonActivatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onHoverChanged?(true)
        super.mouseDown(with: event)
    }
}
