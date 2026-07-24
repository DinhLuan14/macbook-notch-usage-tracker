import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Claude Quota Island Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 640, height: 560))
        window.minSize = NSSize(width: 600, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
