# Phase 1.7: Agent Autonomy

This phase implements agent autonomy for the Flame Graph Context Management plugin, enabling the agent to intelligently suggest or automatically perform push/pop frame operations based on heuristics.

## Status: Complete

Phase 1.7 is the final phase of Phase 1, completing the core plugin implementation.

## Goals

From SPEC.md Section 7 (Control Authority):
> - Human: Explicit commands (/push, /pop, /plan, /status)
> - Agent: Autonomous decisions based on heuristics
> - Possibly mediated by a "Controller/Meta Agent" separate from the worker agent

From SYNTHESIS.md Phase 7:
> - flame_push/flame_pop tools for agent use (already implemented)
> - Configuration for autonomy level
> - Heuristics for auto-push suggestions

## Features Implemented

### 1. Autonomy Configuration

Three levels of autonomy:
- **manual**: Agent never auto-pushes, only evaluates when explicitly asked
- **suggest**: Agent suggests push/pop but waits for human confirmation
- **auto**: Agent can autonomously trigger push/pop based on heuristics

### 2. Push Heuristics

Determines if a new child frame should be created:
- **Failure Boundary**: Is this a discrete unit that could be retried?
- **Context Switch**: Are we switching to different files/concepts?
- **Complexity**: Is the task complex enough to warrant isolation?
- **Duration**: Has significant time/tokens been spent on a subtask?

### 3. Pop Heuristics

Determines if current frame should be completed:
- **Goal Completion**: Has the goal been achieved?
- **Stagnation**: No progress, repeated failures?
- **Context Overflow**: Approaching context limit?

### 4. Auto-Suggestion System

- Suggestions are generated when heuristics trigger
- Suggestions are injected into LLM context
- Format: `[FLAME SUGGESTION: Consider pushing a new frame for "X" - Reason: Y]`

## New Tools

| Tool | Purpose |
|------|---------|
| `flame_autonomy_config` | View/modify autonomy settings |
| `flame_should_push` | Evaluate push heuristics |
| `flame_should_pop` | Evaluate pop heuristics |
| `flame_auto_suggest` | Toggle auto-suggestions |
| `flame_autonomy_stats` | View autonomy statistics |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FLAME_AUTONOMY_LEVEL` | `suggest` | manual/suggest/auto |
| `FLAME_PUSH_THRESHOLD` | `70` | Confidence for auto-push (0-100) |
| `FLAME_POP_THRESHOLD` | `80` | Confidence for auto-pop (0-100) |
| `FLAME_SUGGEST_IN_CONTEXT` | `true` | Include suggestions in context |
| `FLAME_ENABLED_HEURISTICS` | (all) | Comma-separated list |

## Usage Examples

### Configure Autonomy Level

```typescript
// Set to auto mode with lower push threshold
flame_autonomy_config({ level: "auto", pushThreshold: 60 })
```

### Evaluate Push Decision

```typescript
flame_should_push({
  potentialGoal: "Implement authentication",
  recentMessages: 15,
  errorCount: 2
})
```

### Evaluate Pop Decision

```typescript
flame_should_pop({
  successSignals: ["tests passing"],
  tokenCount: 50000,
  contextLimit: 100000
})
```

### View Suggestions

```typescript
flame_auto_suggest({ showHistory: true })
```

## Testing

Run the test script:

```bash
./tests/test-autonomy.sh
```

## Directory Structure

```
1.7-agent-autonomy/
├── README.md              # This file
├── IMPLEMENTATION.md      # Detailed implementation docs
└── tests/
    └── test-autonomy.sh   # Automated tests
```

## Integration Notes

### Context Injection

Suggestions are appended to frame context in the `experimental.chat.messages.transform` hook:

```typescript
const autonomySuggestions = formatSuggestionsForContext()
if (autonomySuggestions) {
  frameContext = frameContext + autonomySuggestions
}
```

### Suggestion Format

```xml
<!-- Flame Autonomy Suggestions -->
[FLAME SUGGESTION: Consider pushing a new frame for "Fix auth bug" - Reason: context switch (75% confidence)]
```

## Related Documentation

- [SPEC.md](/Users/sl/code/flame/SPEC.md) - Control Authority section
- [SYNTHESIS.md](/Users/sl/code/flame/phase1/design/SYNTHESIS.md) - Phase 7
- [Plugin Source](/Users/sl/code/flame/.opencode/plugin/flame.ts)

## Phase 1 Summary

With Phase 1.7 complete, the Flame Graph Context Management plugin now includes:

| Phase | Feature | Status |
|-------|---------|--------|
| 1.0 | Validation | Complete |
| 1.1 | State Manager | Complete |
| 1.2 | Context Assembly | Complete |
| 1.3 | Compaction Integration | Complete |
| 1.4 | Log Persistence | Skipped (native) |
| 1.5 | Subagent Integration | Complete |
| 1.6 | Planning & Invalidation | Complete |
| 1.7 | Agent Autonomy | Complete |

Phase 1 is now complete. The plugin provides a full tree-structured context management system with intelligent frame lifecycle control.
