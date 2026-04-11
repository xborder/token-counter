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
