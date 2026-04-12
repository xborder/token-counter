import SwiftUI

/// Main popover view displayed when clicking the menu bar icon.
struct MenuBarPopover: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                switch viewModel.selectedUIVariant {
                case .classic:
                    ClassicVariant(viewModel: viewModel)
                case .compact:
                    CompactVariant(viewModel: viewModel)
                case .minimal:
                    MinimalVariant(viewModel: viewModel)
                case .tabbed:
                    TabbedVariant(viewModel: viewModel)
                case .cardGrid:
                    CardGridVariant(viewModel: viewModel)
                case .treeOnly:
                    TreeOnlyVariant(viewModel: viewModel)
                case .costFocused:
                    CostFocusedVariant(viewModel: viewModel)
                case .timelineView:
                    TimelineVariant(viewModel: viewModel)
                case .comparison:
                    ComparisonVariant(viewModel: viewModel)
                case .sparklines:
                    SparklinesVariant(viewModel: viewModel)
                }
            }

            Divider()

            // Footer with variant selector
            FooterView(viewModel: viewModel)
        }
        .frame(width: 340, height: 520)
    }
}

// MARK: - Variant: Classic (Current Layout)
struct ClassicVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)
            Divider()
            TokenBreakdownView(summary: viewModel.summary)
            Divider()
            ModelBreakdownView(viewModel: viewModel)
            Divider()
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Compact
struct CompactVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryHeaderView(viewModel: viewModel)
            TokenBreakdownView(summary: viewModel.summary)
            ModelBreakdownView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(8)
    }
}

// MARK: - Variant: Minimal
struct MinimalVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(FormatHelpers.formatTokensCompact(viewModel.summary.totalTokens))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(FormatHelpers.formatCost(viewModel.summary.estimatedCost))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .padding(12)
            .background(.fill.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()

            SummaryHeaderView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Tabbed
struct TabbedVariant: View {
    @Bindable var viewModel: MenuBarViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Summary").tag(0)
                Text("Breakdown").tag(1)
                Text("Models").tag(2)
                Text("Sessions").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case 0:
                    SummaryHeaderView(viewModel: viewModel)
                case 1:
                    TokenBreakdownView(summary: viewModel.summary)
                case 2:
                    ModelBreakdownView(viewModel: viewModel)
                case 3:
                    SessionListView(viewModel: viewModel)
                default:
                    Text("Unknown tab")
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Variant: Card Grid
struct CardGridVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MetricCard(label: "Input", value: FormatHelpers.formatTokensCompact(viewModel.summary.inputTokens), color: .blue)
                    MetricCard(label: "Output", value: FormatHelpers.formatTokensCompact(viewModel.summary.outputTokens), color: .green)
                }
                HStack(spacing: 8) {
                    MetricCard(label: "Cache Create", value: FormatHelpers.formatTokensCompact(viewModel.summary.cacheCreationTokens), color: .orange)
                    MetricCard(label: "Cache Read", value: FormatHelpers.formatTokensCompact(viewModel.summary.cacheReadTokens), color: .purple)
                }
            }

            ModelBreakdownView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Variant: Tree Only
struct TreeOnlyVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)
            Divider()
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Cost Focused
struct CostFocusedVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)

            VStack(alignment: .leading, spacing: 8) {
                Text("Cost Breakdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FormatHelpers.formatCost(viewModel.summary.inputCost))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FormatHelpers.formatCost(viewModel.summary.outputCost))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FormatHelpers.formatCost(viewModel.summary.cacheCreationCost + viewModel.summary.cacheReadCost))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(10)
            .background(.fill.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            ModelBreakdownView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Timeline
struct TimelineVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)
            Divider()
            Text("Recent Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Comparison
struct ComparisonVariant: View {
    @Bindable var viewModel: MenuBarViewModel
    private var claudeSummary: TokenUsageRepository.UsageSummary {
        let repo = TokenUsageRepository(store: .init())
        return repo.summary(for: viewModel.selectedTimeRange, provider: .claude)
    }
    private var openaiSummary: TokenUsageRepository.UsageSummary {
        let repo = TokenUsageRepository(store: .init())
        return repo.summary(for: viewModel.selectedTimeRange, provider: .openai)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                ForEach(TokenUsageRepository.TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(FormatHelpers.formatTokensCompact(claudeSummary.totalTokens))
                        .font(.title3)
                    Text(FormatHelpers.formatCost(claudeSummary.estimatedCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(FormatHelpers.formatTokensCompact(openaiSummary.totalTokens))
                        .font(.title3)
                    Text(FormatHelpers.formatCost(openaiSummary.estimatedCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.teal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            ModelBreakdownView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

// MARK: - Variant: Sparklines
struct SparklinesVariant: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeaderView(viewModel: viewModel)

            VStack(alignment: .leading, spacing: 8) {
                Text("Trends (Last 7 days)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FormatHelpers.formatTokensCompact(viewModel.summary.totalTokens))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 30)
                            .cornerRadius(4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cost")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FormatHelpers.formatCost(viewModel.summary.estimatedCost))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Rectangle()
                            .fill(Color.green.opacity(0.3))
                            .frame(height: 30)
                            .cornerRadius(4)
                    }
                }
            }

            ModelBreakdownView(viewModel: viewModel)
            SessionListView(viewModel: viewModel)
        }
        .padding(12)
    }
}

struct FooterView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showVariantSelector {
                Divider()
                VariantSelectorView(viewModel: viewModel)
            }

            Divider()

            HStack {
                Text("Updated \(FormatHelpers.formatRelativeTime(viewModel.lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    viewModel.showVariantSelector.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Toggle UI variants")

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $viewModel.showSettings) {
                    SettingsView()
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Quit TokenCounter")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

struct VariantSelectorView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(UIVariant.allCases) { variant in
                    VariantButton(
                        variant: variant,
                        isSelected: viewModel.selectedUIVariant == variant,
                        action: { viewModel.selectedUIVariant = variant }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct VariantButton: View {
    let variant: UIVariant
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(variant.name)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(variant.description)
    }
}
