import Foundation
import SwiftData

@Model
final class Project {
    /// Directory name from ~/.claude/projects/, e.g. "-home-user-token-counter"
    @Attribute(.unique) var path: String

    /// Human-readable name derived from path, e.g. "token-counter"
    var displayName: String

    @Relationship(deleteRule: .cascade, inverse: \Session.project)
    var sessions: [Session] = []

    init(path: String, displayName: String) {
        self.path = path
        self.displayName = displayName
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
        let pathPrefixes: Set<String> = ["home", "Users", "var", "tmp", "opt", "usr", "root"]
        var lastPrefixIndex = -1
        for (i, component) in components.enumerated() {
            if pathPrefixes.contains(String(component)) {
                lastPrefixIndex = i
            }
        }
        // Skip past known user directory patterns: home/<user>/
        if lastPrefixIndex >= 0 && lastPrefixIndex + 1 < components.count {
            let afterPrefix = components[(lastPrefixIndex + 2)...]
            if !afterPrefix.isEmpty {
                return afterPrefix.joined(separator: "-")
            }
        }
        // Fallback: return last component
        return components.last.map(String.init) ?? directoryName
    }
}
