# Phase 1.7: Agent Autonomy - Implementation Details

## Overview

Phase 1.7 implements agent autonomy for the Flame Graph Context Management plugin. This phase adds intelligent heuristics that help the agent decide when to push or pop frames, with configurable levels of autonomy.

## Core Concept

From SPEC.md Section 7 (Control Authority):
- **Human**: Explicit commands (/push, /pop, /plan, /status)
- **Agent**: Autonomous decisions based on heuristics
- Possibly mediated by a "Controller/Meta Agent" separate from the worker agent

Phase 1.7 enables the "Agent" part of this control hierarchy.

## Architecture

### Autonomy Levels

Three levels of autonomy are supported:

| Level | Behavior |
|-------|----------|
| `manual` | Agent never auto-pushes/pops, only evaluates when asked |
| `suggest` | Agent suggests push/pop actions but waits for confirmation |
| `auto` | Agent can autonomously trigger push/pop based on heuristics |

### Configuration Interface

```typescript
interface AutonomyConfig {
  level: 'manual' | 'suggest' | 'auto'
  pushThreshold: number      // Confidence threshold for auto-push (0-100)
  popThreshold: number       // Confidence threshold for auto-pop (0-100)
  suggestInContext: boolean  // Include suggestions in LLM context
  enabledHeuristics: string[] // Which heuristics to use
}
```

### Default Configuration

```typescript
const DEFAULT_AUTONOMY_CONFIG: AutonomyConfig = {
  level: "suggest",
  pushThreshold: 70,
  popThreshold: 80,
  suggestInContext: true,
  enabledHeuristics: [
    "failure_boundary",
    "context_switch",
    "complexity",
    "duration",
    "goal_completion",
    "stagnation",
    "context_overflow",
  ],
}
```

## Push Heuristics

Evaluates whether a new child frame should be created based on:

### 1. Failure Boundary (from SPEC.md)
- Detects if current work is a discrete unit that could be retried
- Scores higher when errors are present
- Scores higher when there's a distinct potential new goal

### 2. Context Switch (from SPEC.md)
- Detects switches to different files/concepts
- Compares keyword overlap between current and potential new goal
- Considers number of recent file changes

### 3. Complexity
- Evaluates if task is complex enough to warrant isolation
- Based on message count and file change count
- More messages/files = higher complexity score

### 4. Duration
- Based on token count as proxy for time spent
- Higher token counts suggest more context and potential for isolation

### Scoring

Each heuristic produces a score from 0-100. The confidence is the average of all enabled heuristic scores. If confidence >= pushThreshold, a push is recommended.

## Pop Heuristics

Evaluates whether the current frame should be completed:

### 1. Goal Completion
- Detects success signals
- Checks artifact production
- Measures keyword coverage between goal and accomplishments

### 2. Stagnation
- Tracks turns without progress
- Detects repeated failures
- Suggests `blocked` or `failed` status when appropriate

### 3. Context Overflow
- Monitors token usage relative to context limit
- Higher ratio = higher urgency to pop and summarize

### Status Suggestions

The pop evaluation also suggests an appropriate status:
- `completed` - Goal appears achieved
- `blocked` - No progress but recoverable
- `failed` - Repeated failures, not recoverable

## Suggestion System

### Suggestion Format

When autonomy level is `suggest` or `auto`, suggestions are formatted and injected into context:

```
[FLAME SUGGESTION: Consider pushing a new frame for "X" - Reason: Y (Z% confidence)]
```

### Suggestion Lifecycle

1. **Creation**: When heuristics recommend action, suggestion is created
2. **Pending**: Suggestion waits in queue for up to 5 minutes
3. **Injection**: Pending suggestions are appended to frame context
4. **Action**: When user/agent acts, suggestion is marked as acted upon
5. **Expiry**: Unacted suggestions expire after 5 minutes

### Statistics Tracking

The system tracks:
- Total suggestions made
- Push vs pop suggestions
- Acted upon vs ignored
- Auto-triggered actions (in auto mode)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FLAME_AUTONOMY_LEVEL` | `suggest` | manual/suggest/auto |
| `FLAME_PUSH_THRESHOLD` | `70` | Confidence for push (0-100) |
| `FLAME_POP_THRESHOLD` | `80` | Confidence for pop (0-100) |
| `FLAME_SUGGEST_IN_CONTEXT` | `true` | Include suggestions in context |
| `FLAME_ENABLED_HEURISTICS` | (all) | Comma-separated list of heuristics |

## Tools Added

### flame_autonomy_config
View and modify autonomy settings at runtime.

```
flame_autonomy_config { level: "auto", pushThreshold: 60 }
```

### flame_should_push
Evaluate push heuristics for current context.

```
flame_should_push {
  potentialGoal: "Implement authentication",
  recentMessages: 15,
  errorCount: 3
}
```

### flame_should_pop
Evaluate pop heuristics for current frame.

```
flame_should_pop {
  successSignals: ["tests passing", "build succeeded"],
  tokenCount: 50000,
  contextLimit: 100000
}
```

### flame_auto_suggest
Toggle and manage auto-suggestions.

```
flame_auto_suggest { enable: true, showHistory: true }
```

### flame_autonomy_stats
View detailed autonomy statistics.

```
flame_autonomy_stats {}
```

## Integration Points

### Message Transform Hook

The `experimental.chat.messages.transform` hook was updated to:
1. Generate frame context as before
2. Append autonomy suggestions when enabled
3. Inject combined context into messages

### Runtime State

The `RuntimeState` interface was extended with:

```typescript
interface RuntimeState {
  // ... existing fields ...
  autonomyTracking: AutonomyTracking
}
```

## Files Modified

- `/Users/sl/code/flame/.opencode/plugin/flame.ts`
  - Added AutonomyConfig and related types
  - Added autonomy tracking to RuntimeState
  - Added heuristic evaluation functions
  - Added suggestion management functions
  - Added 5 new tools
  - Updated message transform hook

## Testing

Run the test script to verify implementation:

```bash
/Users/sl/code/flame/phase1/1.7-agent-autonomy/tests/test-autonomy.sh
```

Tests verify:
1. Type definitions exist
2. Environment variable loading works
3. Push heuristics are implemented
4. Pop heuristics are implemented
5. All tools are registered
6. Suggestion system works
7. Context injection includes suggestions
8. Default configuration is correct
9. Runtime initialization works
10. Manual mode blocks suggestions

## Usage Examples

### Example 1: Check if push is needed

```
flame_should_push {
  potentialGoal: "Fix authentication bug",
  recentMessages: 20,
  recentFileChanges: ["src/auth/login.ts", "src/auth/token.ts"],
  errorCount: 2
}
```

Output:
```
# Push Heuristic Evaluation

**Session:** abc12345
**Autonomy Level:** suggest

## Recommendation
- **Should Push:** YES
- **Confidence:** 75% (threshold: 70%)
- **Primary Reason:** context switch
- **Suggested Goal:** "Fix authentication bug"

## Heuristic Scores
- failure_boundary: 30
- context_switch: 60
- complexity: 35
- duration: 0
```

### Example 2: Configure autonomy level

```
flame_autonomy_config { level: "auto", pushThreshold: 80 }
```

### Example 3: View suggestions

```
flame_auto_suggest { showHistory: true }
```

## Design Decisions

### Why Average of Heuristic Scores?

We average scores rather than max/sum because:
- Avoids single heuristic dominating decision
- Encourages multiple signals for confidence
- Makes threshold configuration more intuitive

### Why 5-Minute Suggestion Expiry?

- Long enough to be seen across multiple turns
- Short enough to avoid stale suggestions
- Balances helpfulness with noise reduction

### Why Default to "suggest" Mode?

- Safe default - doesn't take autonomous action
- Provides value immediately (suggestions appear)
- Users can upgrade to "auto" when comfortable

## Known Limitations

1. **Heuristic Accuracy**: Heuristics are approximate and may not capture all nuances
2. **Token Count**: Must be provided externally; plugin can't directly measure
3. **File Changes**: Must be provided by caller; plugin doesn't track files
4. **Context Injection**: Suggestions add to context size

## Future Improvements

1. **Learning**: Track suggestion outcomes to improve heuristics
2. **Custom Heuristics**: Allow users to define custom heuristic functions
3. **Agent-Specific Tuning**: Different thresholds per agent type
4. **Feedback Loop**: Let agents report on suggestion usefulness
