import SwiftUI

/// Detailed breakdown of token types: input, output, cache creation, cache read.
struct TokenBreakdownView: View {
    let summary: TokenUsageRepository.UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token Breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                TokenRow(
                    label: "Input (non-cached)",
                    tokens: summary.inputTokens,
                    cost: summary.inputCost,
                    color: .blue,
                    total: maxTokens
                )

                TokenRow(
                    label: "Output",
                    tokens: summary.outputTokens,
                    cost: summary.outputCost,
                    color: .green,
                    total: maxTokens
                )

                TokenRow(
                    label: "Cache Creation",
                    tokens: summary.cacheCreationTokens,
                    cost: summary.cacheCreationCost,
                    color: .orange,
                    total: maxTokens
                )

                TokenRow(
                    label: "Cache Read",
                    tokens: summary.cacheReadTokens,
                    cost: summary.cacheReadCost,
                    color: .purple,
                    total: maxTokens
                )

                if summary.reasoningTokens > 0 {
                    TokenRow(
                        label: "Reasoning",
                        tokens: summary.reasoningTokens,
                        cost: summary.reasoningCost,
                        color: .pink,
                        total: maxTokens
                    )
                }

                if summary.cachedPromptTokens > 0 {
                    TokenRow(
                        label: "Cached Prompt",
                        tokens: summary.cachedPromptTokens,
                        cost: 0,
                        color: .cyan,
                        total: maxTokens
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var maxTokens: Int {
        max(
            summary.inputTokens,
            summary.outputTokens,
            summary.cacheCreationTokens,
            summary.cacheReadTokens,
            summary.reasoningTokens,
            summary.cachedPromptTokens,
            1
        )
    }
}

struct TokenRow: View {
    let label: String
    let tokens: Int
    let cost: Double
    let color: Color
    let total: Int

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                let fraction = total > 0 ? CGFloat(tokens) / CGFloat(total) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.7))
                    .frame(width: max(fraction * geo.size.width, tokens > 0 ? 2 : 0))
            }
            .frame(height: 8)

            Text(FormatHelpers.formatTokensCompact(tokens))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)

            Text(cost > 0 ? FormatHelpers.formatCost(cost) : "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(cost > 0 ? .primary : .tertiary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
