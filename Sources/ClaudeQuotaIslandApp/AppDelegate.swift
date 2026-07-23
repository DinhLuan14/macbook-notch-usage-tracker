import AppKit

@MainActor
enum ClaudeQuotaIslandApplication {
    private static var delegate: ClaudeQuotaIslandAppDelegate?

    static func run() {
        let application = NSApplication.shared
        let delegate = ClaudeQuotaIslandAppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class ClaudeQuotaIslandAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var notchPanel = NotchPanelController(model: model)
    private lazy var settingsWindow = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Claude Quota Island stays active to display Claude usage."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        let activationPolicy: NSApplication.ActivationPolicy =
            ProcessInfo.processInfo.environment["CQI_REGULAR_APP"] == "1" ? .regular : .accessory
        NSApp.setActivationPolicy(activationPolicy)
        configureMainMenu()

        model.onLayoutChanged = { [weak self] in self?.notchPanel.updateLayout() }
        model.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        model.onExpansionChanged = { [weak self] expanded in
            self?.notchPanel.setExpanded(expanded)
        }
        model.start()
        if ProcessInfo.processInfo.environment["CQI_DISABLE_NOTCH"] != "1" {
            notchPanel.show()
        }

        if ProcessInfo.processInfo.environment["CQI_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindow.show()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notchPanel.updateLayout()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "Claude Quota Island", action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Claude Quota Island…",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Claude Quota Island", action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: """
            Copyright © 2026 DinhLuan14 and contributors.

            Licensed under GNU GPL v3. This program comes with absolutely no warranty.
            Source: https://github.com/DinhLuan14/macbook-notch-usage-tracker

            Inspired by Open Island by Octane0411 and contributors.
            """
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }

    @objc private func quit() {
        model.quit()
    }
}
