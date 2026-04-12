import Foundation

/// Parses OpenAI Codex CLI session JSONL files (rollout-*.jsonl).
///
/// Codex logs are stored at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
/// Each file contains events; we extract `token_count` events which carry
/// both cumulative (`total_token_usage`) and per-turn (`last_token_usage`)
/// token breakdowns.
struct CodexLogParser {

    // MARK: - JSONL event models

    struct LogEvent: Decodable {
        let timestamp: String?
        let type: String
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let info: TokenInfo?
            // Direct model field present on `type: "turn_context"` events
            let model: String?
            // Session metadata from `type: "session_meta"` events
            let id: String?
            let cwd: String?
        }

        struct TokenInfo: Decodable {
            let totalTokenUsage: TokenUsage?
            let lastTokenUsage: TokenUsage?

            enum CodingKeys: String, CodingKey {
                case totalTokenUsage = "total_token_usage"
                case lastTokenUsage = "last_token_usage"
            }
        }

        struct TokenUsage: Decodable {
            let inputTokens: Int?
            let cachedInputTokens: Int?
            let outputTokens: Int?
            let reasoningOutputTokens: Int?
            let totalTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
                case reasoningOutputTokens = "reasoning_output_tokens"
                case totalTokens = "total_tokens"
            }
        }

    }

    /// A parsed turn extracted from one token_count event.
    struct ParsedTurn {
        let timestamp: Date
        let sessionId: String
        let model: String
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
        let sessionDate: String
        let cwd: String  // Working directory from session_meta
        let projectPath: String  // Encoded project path for storing in TokenStore
    }

    // MARK: - Date parsing

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601Fallback.date(from: string)
    }

    // MARK: - Parsing

    /// Parse a Codex rollout JSONL file and return per-turn token usage.
    ///
    /// For each `token_count` event:
    /// - If `last_token_usage` is present, use it directly (per-turn delta)
    /// - Otherwise, compute delta from consecutive `total_token_usage` snapshots
    static func parseFile(at url: URL, fromOffset offset: UInt64 = 0) throws -> (turns: [ParsedTurn], newOffset: UInt64) {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > offset else {
            return ([], fileSize)
        }

        fileHandle.seek(toFileOffset: offset)
        guard let data = try? fileHandle.readToEnd(), !data.isEmpty else {
            return ([], fileSize)
        }

        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        let decoder = JSONDecoder()

        let filename = url.deletingPathExtension().lastPathComponent
        let sessionId = filename.hasPrefix("rollout-") ? String(filename.dropFirst(8)) : filename
        let sessionDate = extractSessionDate(from: url.pathComponents)

        var turns: [ParsedTurn] = []
        var previousTotal: LogEvent.TokenUsage?
        var currentModel = "codex"
        var currentCwd = ""
        var projectPath = "codex"  // Default fallback

        for lineData in lines {
            guard let event = try? decoder.decode(LogEvent.self, from: Data(lineData)) else {
                continue
            }

            // Extract working directory from session_meta event
            if event.type == "session_meta", let cwd = event.payload?.cwd {
                currentCwd = cwd
                projectPath = encodeProjectPath(cwd)
            }

            if event.type == "turn_context", let model = event.payload?.model {
                currentModel = model
            }

            guard event.type == "event_msg",
                  event.payload?.type == "token_count",
                  let info = event.payload?.info,
                  let timestampStr = event.timestamp,
                  let timestamp = parseDate(timestampStr) else {
                continue
            }

            let turnUsage: (input: Int, cached: Int, output: Int, reasoning: Int)

            if let last = info.lastTokenUsage {
                turnUsage = (
                    input: (last.inputTokens ?? 0) - (last.cachedInputTokens ?? 0),
                    cached: last.cachedInputTokens ?? 0,
                    output: last.outputTokens ?? 0,
                    reasoning: last.reasoningOutputTokens ?? 0
                )
            } else if let total = info.totalTokenUsage, let prev = previousTotal {
                let deltaInput = (total.inputTokens ?? 0) - (prev.inputTokens ?? 0)
                let deltaCached = (total.cachedInputTokens ?? 0) - (prev.cachedInputTokens ?? 0)
                let deltaOutput = (total.outputTokens ?? 0) - (prev.outputTokens ?? 0)
                let deltaReasoning = (total.reasoningOutputTokens ?? 0) - (prev.reasoningOutputTokens ?? 0)
                turnUsage = (
                    input: deltaInput - deltaCached,
                    cached: deltaCached,
                    output: deltaOutput,
                    reasoning: deltaReasoning
                )
            } else if let total = info.totalTokenUsage {
                turnUsage = (
                    input: (total.inputTokens ?? 0) - (total.cachedInputTokens ?? 0),
                    cached: total.cachedInputTokens ?? 0,
                    output: total.outputTokens ?? 0,
                    reasoning: total.reasoningOutputTokens ?? 0
                )
            } else {
                previousTotal = info.totalTokenUsage
                continue
            }

            let totalForTurn = turnUsage.input + turnUsage.cached + turnUsage.output
            if totalForTurn > 0 {
                turns.append(ParsedTurn(
                    timestamp: timestamp,
                    sessionId: sessionId,
                    model: currentModel,
                    inputTokens: max(0, turnUsage.input),
                    cachedInputTokens: max(0, turnUsage.cached),
                    outputTokens: max(0, turnUsage.output),
                    reasoningTokens: max(0, turnUsage.reasoning),
                    sessionDate: sessionDate,
                    cwd: currentCwd,
                    projectPath: projectPath
                ))
            }

            previousTotal = info.totalTokenUsage
        }

        return (turns, fileSize)
    }

    private static func extractSessionDate(from components: [String]) -> String {
        guard let idx = components.lastIndex(of: "sessions"),
              idx + 3 < components.count else {
            return "unknown"
        }
        return "\(components[idx + 1])/\(components[idx + 2])/\(components[idx + 3])"
    }

    private static func encodeProjectPath(_ cwd: String) -> String {
        // Encode working directory as project path: /Users/helder/repos/foo -> -Users-helder-repos-foo
        // Remove leading slash and replace remaining slashes with dashes
        let trimmed = cwd.hasPrefix("/") ? String(cwd.dropFirst()) : cwd
        return "-" + trimmed.replacingOccurrences(of: "/", with: "-")
    }
}
