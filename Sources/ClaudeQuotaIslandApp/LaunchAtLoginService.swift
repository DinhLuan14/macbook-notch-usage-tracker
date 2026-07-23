import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginService {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else {
            throw LaunchAtLoginError.requiresAppBundle
        }
        let status = SMAppService.mainApp.status
        if enabled {
            if status != .enabled && status != .requiresApproval {
                try SMAppService.mainApp.register()
            }
        } else if status != .notRegistered && status != .notFound {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case requiresAppBundle

    var errorDescription: String? {
        "Launch at Login is available after installing the app bundle."
    }
}
