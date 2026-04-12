import Foundation

final class Project: Codable, Identifiable {
    var id: String { path }

    /// Directory name from ~/.claude/projects/, e.g. "-home-user-token-counter"
    var path: String

    /// Human-readable name derived from path, e.g. "token-counter"
    var displayName: String

    var sessions: [Session] = []

    init(path: String, displayName: String) {
        self.path = path
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case path, displayName, sessions
    }

    /// Derives a display name from the Claude Code project directory name.
    /// The directory name is the absolute path with `/` replaced by `-`.
    /// e.g. "-home-user-token-counter" -> "token-counter"
    static func deriveDisplayName(from directoryName: String) -> String {
        // Strip leading dash, split on dashes, take last non-empty component
        let cleaned = directoryName.hasPrefix("-") ? String(directoryName.dropFirst()) : directoryName
        let components = cleaned.split(separator: "-")
        // The last component of the original path is the project name.
        // But path components themselves may contain dashes, so we heuristically
        // take the last "segment" that looks like a project name.
        // For "-home-user-my-project", the original path was /home/user/my-project
        // We can't perfectly reverse this, so we take everything after the last
        // path-like segment (common prefixes: home, Users, var, tmp, etc.)
        // Prefixes that contain a username after them: /home/<user>/... or /Users/<user>/...
        let prefixesWithUsername: Set<String> = ["home", "Users"]
        // Prefixes that ARE the home dir: /root/...
        let directHomePrefixes: Set<String> = ["root", "var", "tmp", "opt", "usr"]

        for (i, component) in components.enumerated() {
            let c = String(component)
            if prefixesWithUsername.contains(c) {
                // Skip prefix + username, return everything after
                let start = i + 2
                if start < components.count {
                    return components[start...].joined(separator: "-")
                }
            } else if directHomePrefixes.contains(c) {
                // Skip just the prefix itself, return everything after
                let start = i + 1
                if start < components.count {
                    return components[start...].joined(separator: "-")
                }
            }
        }
        // Fallback: return last component
        return components.last.map(String.init) ?? directoryName
    }
}
