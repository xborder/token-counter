import Foundation

/// Formatting utilities for token counts and costs.
enum FormatHelpers {

    /// Format a token count with thousands separators.
    /// e.g. 1234567 -> "1,234,567"
    static func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// Format a token count compactly.
    /// e.g. 1500 -> "1.5K", 2300000 -> "2.3M"
    static func formatTokensCompact(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            return String(format: "%.1fK", thousands)
        }
        return "\(count)"
    }

    /// Format a USD cost.
    /// e.g. 0.0523 -> "$0.05", 1.234 -> "$1.23", 15.5 -> "$15.50"
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 && cost > 0 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    /// Format a relative time string.
    /// e.g. "2 seconds ago", "5 minutes ago"
    static func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Format a date for session display.
    static func formatSessionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
