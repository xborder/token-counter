# Token Counter

A native macOS menu bar app that tracks token usage and costs across Claude Code and Codex CLI. Monitors local JSONL logs in real-time and provides detailed breakdowns of token consumption, costs, and cache economics.

## Features

- **Menu bar popover** with real-time token usage and cost summaries
- **Token breakdown** by type: input, output, cache creation, cache read, reasoning
- **Per-model breakdown**: see cost and usage distribution across all models (gpt-4o, opus, sonnet, haiku, gpt-5.4, gpt-5.3-codex, etc.)
- **Time range filtering**: view today, 7-day, 30-day, or all-time statistics
- **Per-session/project view**: drill down into individual sessions with per-turn token details
- **Subagent tracking**: identifies and labels subagent (Explore, Plan, etc.) token usage
- **Cache economics**: displays money saved by prompt cache hits vs full-price input
- **Per-type cost display**: see cost breakdown by token type (input, output, cache read, cache write)
- **Dual-provider support**: tracks Claude (Anthropic) and Codex (OpenAI) usage separately
- **Real-time updates**: watches logs via periodic scanning (5-second interval)
- **Cost estimation**: bundled pricing tables with user-overridable rates
- **Comprehensive test suite**: 47 tests covering parser logic, filtering, aggregation, and bug regression

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0+ (included with Xcode 16.1+)

## Building & Running

```bash
cd TokenCounter
swift build

# Run the app
./.build/debug/TokenCounter
```

## Architecture

```
TokenCounterApp (MenuBarExtra)
  ├─ MenuBarPopover (SwiftUI views)
  │  └─ MenuBarViewModel (@Observable, real-time refresh)
  │
  ├─ TokenStore (in-memory + JSON persistence)
  │  └─ ~/.local/share/TokenCounter/store.json
  │
  ├─ TokenUsageRepository (query/aggregation layer)
  │  ├─ Time-range filtering (today, 7d, 30d, all-time)
  │  ├─ Provider filtering (Claude vs Codex)
  │  └─ Cost calculation
  │
  ├─ ClaudeLogWatcher + ClaudeLogParser
  │  └─ ~/.claude/projects/**/*.jsonl (JSONL, requestId dedup)
  │
  ├─ CodexLogWatcher + CodexLogParser
  │  └─ ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (JSONL, turn_context events)
  │
  └─ CostCalculator (pricing lookup + cost math)
```

## Data Sources

### Claude Code CLI
Monitors JSONL logs at `~/.claude/projects/` for all sessions and subagent interactions. Deduplicates by `requestId` and tracks all token types including cache usage.

### Codex CLI (OpenAI)
Monitors date-sharded JSONL logs at `~/.codex/sessions/YYYY/MM/DD/` for Codex CLI interactions. Extracts model names from `turn_context` events and handles token delta computation from streaming events.

## Testing

Run the test suite:
```bash
cd TokenCounter
swift test
```

The test suite includes:
- **Parser tests**: JSONL parsing, model extraction, token field extraction
- **Time-range filtering tests**: projects, sessions, turns filtered by date range
- **Integration tests**: session breakdown totals matching header summaries
- **Regression tests**: bugs fixed in recent sessions (Codex model extraction, filtering, deduplication)