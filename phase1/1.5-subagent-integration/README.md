# Phase 1.5: Subagent Integration

This phase integrates Flame's frame management with OpenCode's native TaskTool/subagent system, enabling automatic detection and tracking of subagent sessions.

## Goals

From SYNTHESIS.md Phase 5:
- TaskTool session detection
- Heuristic-based frame creation
- Frame completion on subagent finish

## Status: Complete

All features implemented and tested.

## Features

### Automatic Subagent Detection

When OpenCode's TaskTool creates a child session, Flame detects it via the `session.created` event with a `parentID`. Sessions are classified as subagents based on:

1. **Pattern Matching**: Title matches patterns like `(@agent subagent)`
2. **Parent Frame**: Parent session is already a tracked Flame frame

### Heuristic-Based Frame Creation

Not all subagent sessions become frames. The system uses heuristics to avoid creating frames for short-lived operations:

| Heuristic | Default | Purpose |
|-----------|---------|---------|
| Min Duration | 60 seconds | Avoid noise from quick lookups |
| Min Messages | 3 | Ensure meaningful work occurred |

Pattern-matched sessions (detected by title) get frames immediately to ensure context injection works from the start.

### Automatic Frame Completion

When a subagent session goes idle:
1. Check if heuristics pass (create frame if not yet created)
2. Schedule auto-completion after configured delay (5 seconds default)
3. Generate summary and propagate to parent context

### New Tools

| Tool | Description |
|------|-------------|
| `flame_subagent_config` | View/modify subagent settings |
| `flame_subagent_stats` | Show detection statistics |
| `flame_subagent_complete` | Manually complete a subagent |
| `flame_subagent_list` | List all tracked subagent sessions |

## Configuration

### Runtime Configuration

Use `flame_subagent_config` to view and modify settings:

```
flame_subagent_config
flame_subagent_config enabled=false
flame_subagent_config minDuration=30000
flame_subagent_config addPattern="\\[MyTask\\]"
```

### Environment Variables

Set at startup:

```bash
# Disable subagent integration
FLAME_SUBAGENT_ENABLED=false opencode

# Lower thresholds for faster frame creation
FLAME_SUBAGENT_MIN_DURATION=30000 FLAME_SUBAGENT_MIN_MESSAGES=2 opencode

# Custom patterns
FLAME_SUBAGENT_PATTERNS="@.*subagent,my-custom-pattern" opencode
```

## How It Works

### Detection Flow

```
session.created (with parentID)
       │
       ▼
  Is parent a frame?
       │
       ├── No ─────────────────► Skip (not a Flame context)
       │
       ▼
  Register subagent session
       │
       ▼
  Title matches patterns?
       │
       ├── Yes ────────────────► Create frame immediately
       │
       ▼
  Track session activity
       │
       ▼
  session.idle fires
       │
       ▼
  Meets heuristics?
       │
       ├── No ─────────────────► Skip (too short/few messages)
       │
       ▼
  Create frame if needed
       │
       ▼
  Schedule auto-completion
       │
       ▼
  Complete frame, propagate summary
```

### Context Flow

1. **Parent → Subagent**: Parent frame's context is automatically injected into subagent sessions via the existing message transform hook
2. **Subagent → Parent**: When subagent completes, its summary becomes available as a completed sibling in the parent's context

## Testing

Run the test suite:

```bash
./phase1/1.5-subagent-integration/tests/test-subagent.sh
```

Expected output:
```
========================================
  Phase 1.5 Subagent Integration Tests
========================================

[PASS] Plugin loads with Phase 1.5 code
[PASS] Subagent types are defined
[PASS] Default config values are correct
[PASS] Subagent patterns are defined
[PASS] Detection functions exist
[PASS] Subagent tools are defined
[PASS] Event handlers are updated
[PASS] Environment config loading works
[PASS] Heuristic logic is implemented
[PASS] Auto-complete timer is implemented
[PASS] Cache invalidation is correct
[PASS] Cleanup function exists
[PASS] Duration formatting exists

All tests passed!
```

## Files

| File | Description |
|------|-------------|
| `README.md` | This file |
| `IMPLEMENTATION.md` | Technical implementation details |
| `tests/test-subagent.sh` | Automated test suite |

## Integration Points

- **Phase 1.2 (Context Assembly)**: Subagent frames use token budgets and context caching
- **Phase 1.3 (Compaction)**: Subagent frames use custom compaction prompts
- **Phase 1.4 (Skipped)**: OpenCode's native logging handles persistence

## Usage Example

```typescript
// Normal flow - TaskTool creates subagent
// 1. User invokes TaskTool in main session
// 2. OpenCode creates child session with parentID
// 3. Flame detects via session.created event
// 4. If pattern matches: frame created immediately
// 5. If not: tracked, frame created when heuristics pass
// 6. Subagent works, receiving parent context
// 7. Session goes idle
// 8. After delay, frame auto-completed
// 9. Summary propagated to parent context

// Manual flow - use tools directly
flame_subagent_list filter=active        // See active subagents
flame_subagent_stats                      // View statistics
flame_subagent_complete summary="..."     // Manual completion
```

## Notes

### Why Skip Phase 1.4?

Phase 1.4 (Log Persistence) was skipped because OpenCode already provides comprehensive logging of all conversation history. See `/Users/sl/code/flame/phase1/research/opencode-logging.md` for details.

### Backwards Compatibility

If subagent integration is disabled (`FLAME_SUBAGENT_ENABLED=false`), the system falls back to Phase 1.3 behavior where all child sessions automatically get frames.
