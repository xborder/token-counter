# Token Counter

A native macOS menu bar app that tracks token usage and costs across Claude and Codex models. Parses local Claude Code JSONL logs in real-time to provide thorough breakdowns of token consumption.

## Features

- **Menu bar popover** with at-a-glance token usage and cost summaries
- **Token breakdown** by type: input, output, cache creation, cache read
- **Per-model breakdown**: see cost distribution across opus, sonnet, haiku, o3, etc.
- **Per-session/project view**: drill down into individual sessions with per-turn detail
- **Subagent tracking**: identifies and labels subagent (Explore, Plan, etc.) token usage
- **Cache economics**: shows money saved by prompt cache hits vs full-price input
- **Real-time updates**: watches `~/.claude/projects/` for new log data via FSEvents
- **Cost estimation**: bundled pricing table with user-overridable rates

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ to build

## Building

```bash
cd TokenCounter
# Open in Xcode
open Package.swift

# Or build from command line
swift build
```

## Architecture

```
TokenCounterApp (MenuBarExtra)
  -> MenuBarPopover (SwiftUI)
    -> MenuBarViewModel (@Observable)
      -> TokenUsageRepository (aggregation)
        -> ClaudeLogWatcher (FSEvents)
          -> ClaudeLogParser (JSONL parsing, requestId dedup)
        -> CostCalculator (pricing math)
      -> SwiftData (persistence)
```

## Data Sources

### Phase 1 (Current): Claude Code Local Logs
Parses JSONL files from `~/.claude/projects/` including main sessions and subagent logs.

### Phase 2 (Planned): Codex CLI Logs
Parse `~/.codex/` logs for OpenAI Codex CLI usage.

### Phase 3 (Planned): API Integration
Query Anthropic Admin API and OpenAI Usage API for organization-level data.