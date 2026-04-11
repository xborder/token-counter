import SwiftUI

/// Per-model usage breakdown with expandable detail rows.
struct ModelBreakdownView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By Model")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            if viewModel.modelBreakdown.isEmpty {
                Text("No data for this period")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.modelBreakdown) { usage in
                    ModelRow(usage: usage, isExpanded: viewModel.expandedModels.contains(usage.model)) {
                        viewModel.toggleModel(usage.model)
                    }
                }
            }
        }
    }
}

struct ModelRow: View {
    let usage: TokenUsageRepository.ModelUsage
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    ProviderBadge(provider: usage.provider)

                    Text(displayModelName(usage.model))
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text(FormatHelpers.formatCost(usage.estimatedCost))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ModelDetailRow(label: "Input", value: FormatHelpers.formatTokens(usage.inputTokens))
                    ModelDetailRow(label: "Output", value: FormatHelpers.formatTokens(usage.outputTokens))
                    ModelDetailRow(label: "Cache Create", value: FormatHelpers.formatTokens(usage.cacheCreationTokens))
                    ModelDetailRow(label: "Cache Read", value: FormatHelpers.formatTokens(usage.cacheReadTokens))
                    ModelDetailRow(label: "Turns", value: "\(usage.turnCount)")
                }
                .padding(.leading, 22)
                .padding(.bottom, 4)
            }
        }
    }

    private func displayModelName(_ model: String) -> String {
        // Shorten common prefixes
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
            .replacingOccurrences(of: "-20260410", with: "")
    }
}

struct ModelDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct ProviderBadge: View {
    let provider: String

    var body: some View {
        Text(provider == "claude" ? "C" : "O")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(provider == "claude" ? Color.orange : Color.teal)
            .clipShape(Circle())
    }
}
