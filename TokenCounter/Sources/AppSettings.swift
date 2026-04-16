import Foundation
import ServiceManagement

enum AppSettings {
    static let claudeLogBasePathKey = "logBasePath"
    static let codexLogBasePathKey = "codexLogBasePath"
    static let refreshIntervalKey = "refreshInterval"
    static let defaultRefreshInterval = 5.0

    static func claudeLogBasePath(defaults: UserDefaults = .standard) -> String {
        normalizedPath(
            defaults.string(forKey: claudeLogBasePathKey),
            fallback: ClaudeLogWatcher.defaultBasePath
        )
    }

    static func codexLogBasePath(defaults: UserDefaults = .standard) -> String {
        normalizedPath(
            defaults.string(forKey: codexLogBasePathKey),
            fallback: CodexLogWatcher.defaultBasePath
        )
    }

    static func refreshInterval(defaults: UserDefaults = .standard) -> TimeInterval {
        guard let value = defaults.object(forKey: refreshIntervalKey) as? Double else {
            return defaultRefreshInterval
        }
        return clampRefreshInterval(value)
    }

    static func save(
        claudeLogBasePath: String,
        codexLogBasePath: String,
        refreshInterval: Double,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            normalizedPath(claudeLogBasePath, fallback: ClaudeLogWatcher.defaultBasePath),
            forKey: claudeLogBasePathKey
        )
        defaults.set(
            normalizedPath(codexLogBasePath, fallback: CodexLogWatcher.defaultBasePath),
            forKey: codexLogBasePathKey
        )
        defaults.set(clampRefreshInterval(refreshInterval), forKey: refreshIntervalKey)
    }

    static func clampRefreshInterval(_ value: Double) -> Double {
        min(max(value, 1.0), 30.0)
    }

    private static func normalizedPath(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPath = trimmed.isEmpty ? fallback : trimmed
        return (rawPath as NSString).expandingTildeInPath
    }
}

enum LaunchAtLoginManager {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        switch (enabled, service.status) {
        case (true, .enabled), (false, .notRegistered):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }
}
