import Foundation

/// Parses Claude Code JSONL log files and extracts token usage per API request.
///
/// Each JSONL file contains streaming chunks — multiple lines share the same
/// `requestId` but have different `uuid`s. The last line per `requestId` holds
/// the final accumulated usage. We deduplicate on `requestId` and keep only
/// the last occurrence.
struct ClaudeLogParser {

    // MARK: - JSONL line models (Codable)

    struct LogLine: Decodable {
        let type: String
        let uuid: String?
        let requestId: String?
        let parentUuid: String?
        let isSidechain: Bool?
        let agentId: String?
        let message: Message?
        let timestamp: String?
        let sessionId: String?
        let gitBranch: String?
        let slug: String?
        let cwd: String?

        struct Message: Decodable {
            let model: String?
            let role: String?
            let usage: Usage?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case model, role, usage
                case stopReason = "stop_reason"
            }
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreation: CacheCreation?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreation = "cache_creation"
            }

            struct CacheCreation: Decodable {
                let ephemeral5mInputTokens: Int?
                let ephemeral1hInputTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
                    case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
                }
            }
        }
    }

    /// A parsed turn extracted from one API request (deduplicated by requestId).
    struct ParsedTurn {
        let uuid: String
        let requestId: String
        let timestamp: Date
        let sessionId: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let cacheCreation5mTokens: Int
        let cacheCreation1hTokens: Int
        let gitBranch: String?
        let slug: String?
        let cwd: String?
        let isSubagent: Bool
        let agentId: String?
    }

    // MARK: - Subagent metadata

    struct SubagentMeta: Decodable {
        let agentType: String?
        let description: String?
    }

    // MARK: - Parsing

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601FallbackFormatter.date(from: string)
    }

    /// Parse a JSONL file and return deduplicated turns.
    /// Only processes lines from `offset` onwards (byte offset into the file).
    /// Returns the parsed turns and the new file offset after parsing.
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

        // Collect all assistant lines, keyed by requestId.
        // For each requestId, keep only the last line (final accumulated usage).
        var lastByRequestId: [String: LogLine] = [:]
        var orderByRequestId: [String: Int] = [:]
        var lineIndex = 0

        for lineData in lines {
            lineIndex += 1
            guard let logLine = try? decoder.decode(LogLine.self, from: Data(lineData)) else {
                continue
            }

            // Only assistant lines with usage data are relevant
            guard logLine.type == "assistant",
                  logLine.message?.role == "assistant",
                  logLine.message?.usage != nil else {
                continue
            }

            // Use requestId for deduplication (streaming chunks share the same requestId)
            // Fall back to uuid if requestId is missing
            let dedupKey = logLine.requestId ?? logLine.uuid ?? UUID().uuidString
            lastByRequestId[dedupKey] = logLine
            orderByRequestId[dedupKey] = lineIndex
        }

        // Convert to ParsedTurns, sorted by first line order (stable key ordering)
        let sortedKeys = lastByRequestId.keys.sorted { (orderByRequestId[$0] ?? 0) < (orderByRequestId[$1] ?? 0) }

        let turns: [ParsedTurn] = sortedKeys.compactMap { key in
            guard let line = lastByRequestId[key],
                  let usage = line.message?.usage,
                  let model = line.message?.model,
                  let timestampStr = line.timestamp,
                  let timestamp = parseDate(timestampStr),
                  let sessionId = line.sessionId else {
                return nil
            }

            let uuid = line.uuid ?? key

            return ParsedTurn(
                uuid: uuid,
                requestId: key,
                timestamp: timestamp,
                sessionId: sessionId,
                model: model,
                inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                cacheCreation5mTokens: usage.cacheCreation?.ephemeral5mInputTokens ?? 0,
                cacheCreation1hTokens: usage.cacheCreation?.ephemeral1hInputTokens ?? 0,
                gitBranch: line.gitBranch,
                slug: line.slug,
                cwd: line.cwd,
                isSubagent: line.isSidechain ?? false,
                agentId: line.agentId
            )
        }

        // Sort by timestamp for consistent chronological ordering
        return (turns.sorted { $0.timestamp < $1.timestamp }, fileSize)
    }

    /// Parse a subagent meta.json file.
    static func parseSubagentMeta(at url: URL) -> SubagentMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SubagentMeta.self, from: data)
    }
}
