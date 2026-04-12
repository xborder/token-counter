import SwiftUI

/// Per-project/session view with expandable session details showing per-turn breakdown.
struct SessionListView: View {
    @Bindable var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            if viewModel.projects.isEmpty {
                Text("No sessions found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.projects) { project in
                    ProjectRow(
                        project: project,
                        viewModel: viewModel,
                        isExpanded: viewModel.expandedProjects.contains(project.path)
                    )
                }
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    @Bindable var viewModel: MenuBarViewModel
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.toggleProject(project.path)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    Text(project.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text("\(viewModel.sessions(for: project).count) sessions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            if isExpanded {
                let sessions = viewModel.sessions(for: project)
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        viewModel: viewModel,
                        isExpanded: viewModel.expandedSessions.contains(session.sessionId)
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: Session
    @Bindable var viewModel: MenuBarViewModel
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.toggleSession(session.sessionId)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(session.slug ?? session.sessionId.prefix(8).description)
                                .font(.caption)
                                .lineLimit(1)

                            if let branch = session.gitBranch {
                                Text(branch.split(separator: "/").last.map(String.init) ?? branch)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.fill.tertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .lineLimit(1)
                            }
                        }

                        Text(FormatHelpers.formatSessionDate(session.lastActivityAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(FormatHelpers.formatCost(session.totalEstimatedCost))
                            .font(.caption)
                            .monospacedDigit()
                        Text(FormatHelpers.formatTokensCompact(session.totalTokens) + " tokens")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            if isExpanded {
                TurnListView(turns: viewModel.turns(for: session))
                    .padding(.leading, 16)
            }
        }
    }
}

struct TurnListView: View {
    let turns: [Turn]

    private struct ModelRow: Identifiable {
        let id: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheTokens: Int
        let cost: Double
    }

    private var modelRows: [ModelRow] {
        var grouped: [String: (input: Int, output: Int, cache: Int, cost: Double)] = [:]
        for turn in turns {
            let key = turn.model
            grouped[key, default: (0, 0, 0, 0.0)].input += turn.totalInputTokens
            grouped[key, default: (0, 0, 0, 0.0)].output += turn.outputTokens
            grouped[key, default: (0, 0, 0, 0.0)].cache += turn.cacheReadTokens
            grouped[key, default: (0, 0, 0, 0.0)].cost += turn.estimatedCostUSD
        }
        return grouped.map { key, val in
            ModelRow(id: key, model: key, inputTokens: val.input,
                     outputTokens: val.output, cacheTokens: val.cache, cost: val.cost)
        }.sorted { $0.cost > $1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Model")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("In")
                    .frame(width: 40, alignment: .trailing)
                Text("Out")
                    .frame(width: 40, alignment: .trailing)
                Text("Cache")
                    .frame(width: 40, alignment: .trailing)
                Text("Cost")
                    .frame(width: 45, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.tertiary)

            ForEach(modelRows) { row in
                HStack(spacing: 4) {
                    Text(shortName(row.model))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(FormatHelpers.formatTokensCompact(row.inputTokens))
                        .frame(width: 40, alignment: .trailing)
                    Text(FormatHelpers.formatTokensCompact(row.outputTokens))
                        .frame(width: 40, alignment: .trailing)
                    Text(FormatHelpers.formatTokensCompact(row.cacheTokens))
                        .frame(width: 40, alignment: .trailing)
                    Text(FormatHelpers.formatCost(row.cost))
                        .frame(width: 45, alignment: .trailing)
                }
                .font(.system(size: 9))
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func shortName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }
}
