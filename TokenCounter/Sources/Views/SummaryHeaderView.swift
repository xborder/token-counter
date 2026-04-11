import SwiftUI

/// Top section of the popover: time range selector, total tokens, total cost.
struct SummaryHeaderView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 10) {
            // Time range picker
            Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                ForEach(TokenUsageRepository.TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTimeRange) { _, newValue in
                viewModel.selectTimeRange(newValue)
            }

            // Provider filter pills
            HStack(spacing: 6) {
                ForEach(TokenUsageRepository.ProviderFilter.allCases) { filter in
                    ProviderPill(
                        label: filter.rawValue,
                        isSelected: viewModel.selectedProvider == filter
                    ) {
                        viewModel.selectProvider(filter)
                    }
                }
                Spacer()
            }

            // Summary cards
            HStack(spacing: 12) {
                SummaryCard(
                    title: "Total Tokens",
                    value: FormatHelpers.formatTokensCompact(viewModel.summary.totalTokens),
                    subtitle: "\(FormatHelpers.formatTokens(viewModel.summary.turnCount)) turns"
                )

                SummaryCard(
                    title: "Est. Cost",
                    value: FormatHelpers.formatCost(viewModel.summary.estimatedCost),
                    subtitle: "saved \(FormatHelpers.formatCost(viewModel.summary.cacheSavings))"
                )
            }
        }
    }
}

struct ProviderPill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
