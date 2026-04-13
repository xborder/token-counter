import Foundation

/// Parses Pi CLI session JSONL files.
/// Pi logs are stored at `~/.pi/agent/sessions/<project-slug>/<ISO-timestamp>_<uuid>.jsonl`.
/// Each file contains messages; we extract `message` events where `message.role == "assistant"` with token usage.
struct PiLogParser {

    // MARK: - JSONL event models

    struct LogEvent: Decodable {
        let type: String
        let id: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let role: String
            let model: String?
            let provider: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input: Int?
            let output: Int?
            let cacheRead: Int?
            let cacheWrite: Int?
            let cost: Cost?

            struct Cost: Decodable {
                let total: Double?
            }
        }
    }

    /// A parsed turn extracted from one assistant message.
    struct ParsedTurn {
        let id: String
        let timestamp: Date
        let model: String
        let provider: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let estimatedCost: Double
        let projectPath: String  // Encoded project slug
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

    /// Parse a Pi session JSONL file and return per-turn token usage.
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

        // Extract project slug from path: ~/.pi/agent/sessions/<project-slug>/<timestamp>_<uuid>.jsonl
        let projectPath = extractProjectSlug(from: url.pathComponents)

        var turns: [ParsedTurn] = []

        for lineData in lines {
            guard let event = try? decoder.decode(LogEvent.self, from: Data(lineData)) else {
                continue
            }

            guard event.type == "message",
                  let message = event.message,
                  message.role == "assistant",
                  let usage = message.usage,
                  let id = event.id,
                  let timestampStr = event.timestamp,
                  let timestamp = parseDate(timestampStr),
                  let model = message.model,
                  let provider = message.provider else {
                continue
            }

            let rawInput = usage.input ?? 0
            let cacheRead = usage.cacheRead ?? 0
            // Pi's `input` field includes cached tokens; subtract cacheRead
            // to get non-cached input (same as Codex does)
            let nonCachedInput = max(0, rawInput - cacheRead)
            let totalTokens = rawInput + (usage.output ?? 0)
            if totalTokens > 0 {
                turns.append(ParsedTurn(
                    id: id,
                    timestamp: timestamp,
                    model: model,
                    provider: provider,
                    inputTokens: nonCachedInput,
                    outputTokens: usage.output ?? 0,
                    cacheReadTokens: cacheRead,
                    cacheCreationTokens: usage.cacheWrite ?? 0,
                    estimatedCost: usage.cost?.total ?? 0.0,
                    projectPath: projectPath
                ))
            }
        }

        return (turns, fileSize)
    }

    private static func extractProjectSlug(from components: [String]) -> String {
        // Path: ~/.pi/agent/sessions/<project-slug>/<timestamp>_<uuid>.jsonl
        // Extract the <project-slug> component
        guard let sessionsIdx = components.lastIndex(of: "sessions"),
              sessionsIdx + 1 < components.count else {
            return "pi"
        }
        let slug = components[sessionsIdx + 1]
        // Decode slug: --Users-helder-repos-dremio-fork-- -> -Users-helder-repos-dremio-fork
        let trimmed = slug.hasPrefix("--") && slug.hasSuffix("--")
            ? String(slug.dropFirst(2).dropLast(2))
            : slug
        return "-" + trimmed
    }
}
