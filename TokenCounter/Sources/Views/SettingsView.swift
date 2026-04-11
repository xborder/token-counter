import SwiftUI

/// Settings sheet accessible from the popover footer.
struct SettingsView: View {
    @AppStorage("logBasePath") private var logBasePath = ClaudeLogWatcher.defaultBasePath
    @AppStorage("codexLogBasePath") private var codexLogBasePath = CodexLogWatcher.defaultBasePath
    @AppStorage("refreshInterval") private var refreshInterval: Double = 5.0
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

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
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280, height: 420)
    }
}
