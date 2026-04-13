import Foundation

/// Parses OpenCode SQLite database for token usage.
/// Database location: `~/.local/share/opencode/opencode.db`
struct OpenCodeLogParser {

    /// Result of querying the OpenCode database.
    struct ParsedTurn {
        let id: String
        let sessionId: String
        let timestamp: Date
        let model: String
        let provider: String
        let inputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let sessionDirectory: String
        let sessionTitle: String?
        let projectPath: String
    }

    private struct QueryRow: Decodable {
        let id: String
        let session_id: String
        let time_created: Int
        let model: String?
        let provider: String?
        let input_tokens: Int?
        let output_tokens: Int?
        let reasoning_tokens: Int?
        let cache_read_tokens: Int?
        let cache_write_tokens: Int?
        let directory: String
        let title: String?
    }

    // MARK: - Database querying

    /// Query the OpenCode SQLite database and return all assistant turns with token usage.
    static func queryDatabase(at dbPath: String) throws -> [ParsedTurn] {
        let sql = """
        SELECT m.id, m.session_id, m.time_created,
               json_extract(m.data, '$.modelID') as model,
               json_extract(m.data, '$.providerID') as provider,
               json_extract(m.data, '$.tokens.input') as input_tokens,
               json_extract(m.data, '$.tokens.output') as output_tokens,
               json_extract(m.data, '$.tokens.reasoning') as reasoning_tokens,
               json_extract(m.data, '$.tokens.cache.read') as cache_read_tokens,
               json_extract(m.data, '$.tokens.cache.write') as cache_write_tokens,
               s.directory, s.title
        FROM message m
        JOIN session s ON m.session_id = s.id
        WHERE json_extract(m.data, '$.role') = 'assistant'
          AND json_extract(m.data, '$.tokens') IS NOT NULL
        ORDER BY m.id ASC
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "-json", sql]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        guard let rows = try? decoder.decode([QueryRow].self, from: Data(jsonString.utf8)) else {
            return []
        }

        var turns: [ParsedTurn] = []
        for row in rows {
            guard let model = row.model, let provider = row.provider else { continue }
            guard let inputTokens = row.input_tokens, let outputTokens = row.output_tokens else { continue }

            let timestamp = Date(timeIntervalSince1970: TimeInterval(row.time_created) / 1000.0)
            let projectPath = encodeProjectPath(row.directory)

            let turn = ParsedTurn(
                id: row.id,
                sessionId: row.session_id,
                timestamp: timestamp,
                model: model,
                provider: provider,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                reasoningTokens: row.reasoning_tokens ?? 0,
                cacheReadTokens: row.cache_read_tokens ?? 0,
                cacheCreationTokens: row.cache_write_tokens ?? 0,
                sessionDirectory: row.directory,
                sessionTitle: row.title,
                projectPath: projectPath
            )
            turns.append(turn)
        }

        return turns
    }

    private static func encodeProjectPath(_ directory: String) -> String {
        // Encode working directory as project path: /Users/helder/repos/foo -> -Users-helder-repos-foo
        let trimmed = directory.hasPrefix("/") ? String(directory.dropFirst()) : directory
        return "-" + trimmed.replacingOccurrences(of: "/", with: "-")
    }
}
