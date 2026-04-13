import SwiftUI

/// Settings sheet accessible from the popover footer.
struct SettingsView: View {
    let controller: AppController

    @State private var logBasePath: String
    @State private var codexLogBasePath: String
    @State private var refreshInterval: Double
    @State private var launchAtLogin: Bool
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    init(controller: AppController) {
        self.controller = controller
        _logBasePath = State(initialValue: AppSettings.claudeLogBasePath())
        _codexLogBasePath = State(initialValue: AppSettings.codexLogBasePath())
        _refreshInterval = State(initialValue: AppSettings.refreshInterval())
        _launchAtLogin = State(initialValue: LaunchAtLoginManager.isEnabled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Log directory
            GroupBox("Claude Code Logs") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Log directory path:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Path", text: $logBasePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Text("Default: ~/.claude/projects")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(4)
            }

            // Codex CLI log directory
            GroupBox("Codex CLI Logs") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Log directory path:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Path", text: $codexLogBasePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Text("Default: ~/.codex/sessions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(4)
            }

            // Refresh interval
            GroupBox("Refresh") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scan interval:")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(refreshInterval))s")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    Slider(value: $refreshInterval, in: 1...30, step: 1)
                }
                .padding(4)
            }

            // Launch at login
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.caption)

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280, height: 420)
    }

    private func saveSettings() {
        let normalizedClaudeLogBasePath = (logBasePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let normalizedCodexLogBasePath = (codexLogBasePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let effectiveClaudeLogBasePath = normalizedClaudeLogBasePath.isEmpty ? ClaudeLogWatcher.defaultBasePath : normalizedClaudeLogBasePath
        let effectiveCodexLogBasePath = normalizedCodexLogBasePath.isEmpty ? CodexLogWatcher.defaultBasePath : normalizedCodexLogBasePath
        let effectiveRefreshInterval = AppSettings.clampRefreshInterval(refreshInterval)

        do {
            try controller.applySettings(
                claudeLogBasePath: effectiveClaudeLogBasePath,
                codexLogBasePath: effectiveCodexLogBasePath,
                refreshInterval: effectiveRefreshInterval,
                launchAtLogin: launchAtLogin
            )
            AppSettings.save(
                claudeLogBasePath: effectiveClaudeLogBasePath,
                codexLogBasePath: effectiveCodexLogBasePath,
                refreshInterval: effectiveRefreshInterval
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
