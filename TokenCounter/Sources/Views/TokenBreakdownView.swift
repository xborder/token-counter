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
                    color: .blue,
                    total: maxTokens
                )

                TokenRow(
                    label: "Output",
                    tokens: summary.outputTokens,
                    color: .green,
                    total: maxTokens
                )

                TokenRow(
                    label: "Cache Creation",
                    tokens: summary.cacheCreationTokens,
                    color: .orange,
                    total: maxTokens
                )

                TokenRow(
                    label: "Cache Read",
                    tokens: summary.cacheReadTokens,
                    color: .purple,
                    total: maxTokens
                )

                if summary.reasoningTokens > 0 {
                    TokenRow(
                        label: "Reasoning",
                        tokens: summary.reasoningTokens,
                        color: .pink,
                        total: maxTokens
                    )
                }

                if summary.cachedPromptTokens > 0 {
                    TokenRow(
                        label: "Cached Prompt",
                        tokens: summary.cachedPromptTokens,
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
    let color: Color
    let total: Int

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

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
                .frame(width: 50, alignment: .trailing)
        }
    }
}
