# Phase 1.5: Subagent Integration - Implementation Details

## Overview

Phase 1.5 implements integration between Flame's frame management and OpenCode's native TaskTool/subagent system. This allows Flame to automatically detect and track subagent sessions, creating frames with appropriate heuristics to avoid noise from short-lived sessions.

## Architecture

### Core Components

1. **Subagent Detection**: Identifies sessions created via TaskTool by checking for `parentID` in session creation events
2. **Pattern Matching**: Uses regex patterns to detect subagent sessions by title (e.g., `(@agent subagent)`)
3. **Heuristic Engine**: Decides when to create frames based on session duration and message count
4. **Auto-Completion**: Automatically completes subagent frames when sessions go idle
5. **Context Propagation**: Ensures parent context flows to subagents and summaries propagate back

### Type Definitions

```typescript
interface SubagentConfig {
  enabled: boolean              // Master switch for subagent integration
  minDuration: number           // Minimum duration (ms) for frame creation
  minMessageCount: number       // Minimum messages for frame creation
  subagentPatterns: string[]    // Regex patterns for title matching
  autoCompleteOnIdle: boolean   // Auto-complete on session.idle
  idleCompletionDelay: number   // Delay before auto-completion (ms)
  injectParentContext: boolean  // Inject parent context into subagent
  propagateSummaries: boolean   // Propagate summaries to parent
}

interface SubagentSession {
  sessionID: string
  parentSessionID: string
  title: string
  createdAt: number
  lastActivityAt: number
  isSubagent: boolean           // Matched subagent pattern
  hasFrame: boolean             // Frame was created
  messageCount: number
  idleTimerID?: ReturnType<typeof setTimeout>
  isIdle: boolean
  isCompleted: boolean
}

interface SubagentStats {
  totalDetected: number
  framesCreated: number
  skippedByHeuristics: number
  autoCompleted: number
  manuallyCompleted: number
  lastReset: number
}
```

## Implementation Flow

### Session Creation

When a `session.created` event fires:

1. Check if session has a `parentID` (indicates child session)
2. Verify parent is a tracked frame
3. If subagent integration is enabled:
   - Register session in `subagentTracking.sessions`
   - Check title against subagent patterns
   - If pattern matches: create frame immediately
   - If no pattern match: wait for heuristics to trigger

```typescript
if (parentFrame && runtime.subagentTracking.config.enabled) {
  const subagentSession = registerSubagentSession(
    info.id,
    info.parentID,
    info.title || 'Subagent task'
  )

  if (subagentSession.isSubagent) {
    // Pattern match - create frame immediately
    await manager.createFrame(info.id, goal, info.parentID)
    subagentSession.hasFrame = true
  }
  // Non-pattern sessions wait for heuristics
}
```

### Activity Tracking

On each `chat.message` event:

1. Update `lastActivityAt` timestamp
2. Increment `messageCount`
3. Clear idle state and any pending idle timer

This data feeds the heuristics that determine frame eligibility.

### Heuristic-Based Frame Creation

The `meetsFrameHeuristics()` function checks:

1. **Duration**: `Date.now() - session.createdAt >= config.minDuration`
2. **Message Count**: `session.messageCount >= config.minMessageCount`

Both conditions must be met for frame creation on non-pattern-matched sessions.

Default thresholds:
- `minDuration`: 60000 (1 minute)
- `minMessageCount`: 3

### Session Idle Handling

When `session.idle` fires:

1. Check if session is a tracked subagent
2. Try to create frame if heuristics now pass
3. If auto-complete enabled and session has frame:
   - Schedule completion after `idleCompletionDelay`
   - Timer is cleared if session becomes active again

```typescript
if (config.autoCompleteOnIdle && session.hasFrame) {
  session.idleTimerID = setTimeout(async () => {
    // Verify still idle
    if (!currentSession.isIdle || currentSession.isCompleted) return

    await manager.completeFrame(sessionID, 'completed', '(Auto-completed)')
    currentSession.isCompleted = true
    runtime.subagentTracking.stats.autoCompleted++
  }, config.idleCompletionDelay)
}
```

### Pattern Detection

Default patterns for subagent detection:

```typescript
subagentPatterns: [
  "@.*subagent",      // OpenCode TaskTool: (@agent subagent)
  "subagent",         // Generic
  "\\[Task\\]",       // Task markers
]
```

The `isSubagentTitle()` function tests each pattern (case-insensitive) against the session title.

## New Tools

### flame_subagent_config

View or modify subagent integration settings at runtime.

**Arguments:**
- `enabled`: Enable/disable integration
- `minDuration`: Minimum session duration (ms)
- `minMessageCount`: Minimum message count
- `autoCompleteOnIdle`: Enable/disable auto-completion
- `idleCompletionDelay`: Delay before auto-completion (ms)
- `addPattern`: Add a detection pattern
- `removePattern`: Remove a detection pattern
- `injectParentContext`: Enable/disable parent context injection
- `propagateSummaries`: Enable/disable summary propagation

### flame_subagent_stats

View statistics about subagent session detection and handling.

**Arguments:**
- `reset`: Reset all statistics
- `showActive`: Show details of active sessions (default: true)

**Output includes:**
- Total sessions detected
- Frames created
- Sessions skipped by heuristics
- Auto-completed count
- Manually completed count
- Active session details

### flame_subagent_complete

Manually complete a subagent session.

**Arguments:**
- `sessionID`: Session to complete (optional, defaults to current)
- `status`: Completion status (completed/failed/blocked)
- `summary`: Optional summary text

### flame_subagent_list

List all tracked subagent sessions.

**Arguments:**
- `filter`: all | active | completed | with-frame | without-frame

## Environment Variables

Configuration can be set via environment variables at startup:

| Variable | Description | Default |
|----------|-------------|---------|
| `FLAME_SUBAGENT_ENABLED` | Enable/disable integration | true |
| `FLAME_SUBAGENT_MIN_DURATION` | Minimum duration (ms) | 60000 |
| `FLAME_SUBAGENT_MIN_MESSAGES` | Minimum message count | 3 |
| `FLAME_SUBAGENT_AUTO_COMPLETE` | Auto-complete on idle | true |
| `FLAME_SUBAGENT_IDLE_DELAY` | Idle completion delay (ms) | 5000 |
| `FLAME_SUBAGENT_PATTERNS` | Comma-separated patterns | (defaults) |

Example:
```bash
FLAME_SUBAGENT_MIN_DURATION=30000 opencode
```

## Cache Invalidation

The implementation properly invalidates context caches when:

1. A subagent frame is created (parent cache invalidated)
2. A subagent session is completed (both session and parent caches invalidated)

This ensures parent frames see updated sibling summaries.

## Session Cleanup

The `cleanupOldSubagentSessions()` function runs periodically (on session.idle events) to remove completed sessions older than 1 hour from memory. This prevents memory growth from long-running OpenCode sessions.

## Testing

Run the test suite:

```bash
./phase1/1.5-subagent-integration/tests/test-subagent.sh
```

Tests verify:
- Type definitions exist
- Default configuration values
- Detection functions implemented
- Tools defined and accessible
- Event handlers updated
- Environment variable loading
- Heuristic logic
- Timer implementation
- Cache invalidation
- Cleanup function

## Integration with Existing Features

### Phase 1.2: Context Assembly

Subagent frames automatically benefit from:
- Token budget management
- Ancestor/sibling context injection
- Context caching

### Phase 1.3: Compaction Integration

Subagent frames use:
- Custom compaction prompts when completing
- Summary extraction from compaction events
- Automatic summary storage

## Future Enhancements

Potential improvements for future phases:

1. **Persistence**: Save subagent tracking state to disk for recovery across restarts
2. **Pattern Learning**: Automatically learn patterns from successful subagent detections
3. **Hierarchical Summaries**: Generate parent-aware summaries when completing subagents
4. **UI Integration**: Visual indicators in TUI for subagent frames
5. **Metrics Export**: Export statistics to monitoring systems
