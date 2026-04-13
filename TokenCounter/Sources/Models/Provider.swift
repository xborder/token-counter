import Foundation

/// Token provider (Claude/Anthropic or OpenAI/Codex).
enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openai: "OpenAI"
        }
    }
}
