import Foundation

/// Token provider (Claude/Anthropic, OpenAI/Codex, Pi CLI, or OpenCode).
enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case openai
    case pi
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openai: "OpenAI"
        case .pi: "Pi CLI"
        case .opencode: "OpenCode"
        }
    }
}
