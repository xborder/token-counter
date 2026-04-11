import SwiftUI

/// Main popover view displayed when clicking the menu bar icon.
struct MenuBarPopover: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. Summary header with time range selector
                    SummaryHeaderView(viewModel: viewModel)

                    Divider()

                    // 2. Token type breakdown
                    TokenBreakdownView(summary: viewModel.summary)

                    Divider()

                    // 3. Per-model breakdown
                    ModelBreakdownView(viewModel: viewModel)

                    Divider()

                    // 4. Session/project list
                    SessionListView(viewModel: viewModel)
                }
                .padding(12)
            }

            Divider()

            // 5. Footer
            FooterView(viewModel: viewModel)
        }
        .frame(width: 340, height: 520)
    }
}

struct FooterView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        HStack {
            Text("Updated \(FormatHelpers.formatRelativeTime(viewModel.lastUpdated))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
