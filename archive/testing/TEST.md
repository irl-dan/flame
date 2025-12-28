# Testing the Flame Plugin

This document describes how to manually test the Flame Graph Context Management plugin.

## Prerequisites

- OpenCode CLI installed (`opencode` command available)
- Plugin located at `.opencode/plugin/flame.ts`
- Dependencies installed in `.opencode/` (`@opencode-ai/plugin`)

## How to Run Tests

### Basic Test Pattern

Use `opencode run` to execute single-message tests:

```bash
opencode run "Your test prompt here" --model anthropic/claude-sonnet-4-5-20250929
```

For observing logs during execution:

```bash
opencode run "Your test prompt" --print-logs 2>&1
```

### Session Resumption

OpenCode supports resuming existing sessions, which is crucial for multi-step frame workflows:

```bash
# Continue the last session
opencode run --continue "Continue working on this task"

# Resume a specific session by ID
opencode run --session ses_abc123xyz "Continue from where we left off"
```

**This is the recommended approach for multi-step frame workflows:**

```bash
# Step 1: Create a child frame and capture the session ID
opencode run "flame_push with goal 'Implement feature X'" --format json | jq -r '.sessionID'
# Output: ses_abc123xyz

# Step 2: Resume THAT session to do work
opencode run --session ses_abc123xyz "Work on the feature"

# Step 3: Pop from the SAME session (runtime.currentSessionID is correct)
opencode run --session ses_abc123xyz "flame_pop status=completed summary='Feature done'"
```

### Alternative: Explicit Frame ID

If you can't use session resumption, `flame_pop` now accepts an optional `frameID` parameter:

```bash
# Pop a specific frame by ID (from any session)
opencode run "flame_pop frameID='ses_abc123xyz' status=completed summary='Done'"
```

Note: `generateSummary` only works for current session frames.

### Background Testing with State Inspection

Run OpenCode in background and inspect state after completion:

```bash
opencode run "Test prompt" --model anthropic/claude-sonnet-4-5-20250929 2>&1 &
sleep 60
cat .opencode/flame/state.json
```

## Key Files to Inspect

| File | Purpose |
|------|---------|
| `.opencode/flame/state.json` | Root state with all frames and relationships |
| `.opencode/flame/frames/*.json` | Individual frame metadata files |
| `.opencode/flame/validation-state.json` | Hook invocation tracking (if validation plugin active) |

## Test Scenarios

### 1. Frame Lifecycle

Test the basic push/pop workflow:

```
"Execute these tools in sequence:
1. flame_tree to see current state
2. flame_push with goal 'Test subtask'
3. flame_add_artifact with artifact 'src/example.ts'
4. flame_add_decision with decision 'Using approach X'
5. flame_tree to verify changes"
```

### 2. Planned Frames

Test the planning feature:

```
"Execute these tools:
1. flame_plan with goal 'Future task'
2. flame_plan_children with children: ['Subtask 1', 'Subtask 2']
3. flame_tree to see planned frames
4. flame_activate with the planned frame ID"
```

**Note:** Frame IDs are now shown in full (not truncated) in tool output.

### 3. Frame Invalidation

Test invalidating a planned frame:

```
"Execute these tools:
1. flame_plan with goal 'Task to invalidate'
2. Copy the full Frame ID from the output
3. flame_invalidate with that sessionID and reason 'No longer needed'
4. flame_tree to verify status is 'invalidated'"
```

### 4. Context Injection

Verify context is injected by checking logs for:
- `Context generated` with token counts
- `Frame context injected` with context length
- `Cache hit for context generation` on subsequent calls

### 5. Frame Completion (Two Approaches)

**Approach A: Session Resumption (Recommended)**
```bash
# Create child frame
CHILD_SESSION=$(opencode run "flame_push goal='My subtask'" --format json | jq -r '.sessionID')

# Work in that session
opencode run --session $CHILD_SESSION "Do the work"

# Pop from within the session
opencode run --session $CHILD_SESSION "flame_pop status=completed summary='Work done'"
```

**Approach B: Explicit Frame ID**
```bash
# Pop any frame by ID (from any session)
opencode run "flame_pop frameID='$CHILD_SESSION' status=completed summary='Work done'"
```

### 6. Multi-Step Workflow Test

```bash
# Clean state
rm -rf .opencode/flame/frames .opencode/flame/state.json

# Create parent session
PARENT=$(opencode run "flame_set_goal goal='Main project'" --format json | jq -r '.sessionID')

# Create planned children
opencode run --session $PARENT "flame_plan_children children=['Task 1', 'Task 2', 'Task 3']"

# Get planned frame ID and activate
TASK1=$(cat .opencode/flame/state.json | jq -r '.frames | to_entries | map(select(.value.goal == "Task 1")) | .[0].key')
opencode run --session $PARENT "flame_activate sessionID='$TASK1'"

# Verify state
cat .opencode/flame/state.json | jq '.frames | to_entries | .[] | {id: .key[:12], status: .value.status, goal: .value.goal}'
```

## Understanding the Architecture

### Session-Frame Relationship

- Each OpenCode session maps to exactly one frame
- `flame_push` creates a **new child session** in OpenCode, which becomes a child frame
- The parent session stays active; you'd work in the child session for that subtask
- `flame_pop` completes a frame - either the current session's frame OR a specific frame by ID

### Session Resumption

OpenCode natively supports session resumption:
- `--continue` flag: Resume the most recent non-child session
- `--session <id>` flag: Resume a specific session by ID

This eliminates the "session isolation" problem mentioned in earlier testing.

### Frame IDs

- Session frames: `ses_*` (e.g., `ses_49ecaea6bffetm1CiKwJopu8S5`)
- Planned frames: `plan-{timestamp}-{suffix}` (e.g., `plan-1766862721007-meryop`)

### State Structure

```json
{
  "version": 1,
  "frames": {
    "ses_xxx": {
      "sessionID": "ses_xxx",
      "parentSessionID": "ses_parent",  // undefined for root frames
      "status": "in_progress",          // or planned/completed/failed/blocked/invalidated
      "goal": "Frame description",
      "artifacts": ["file1.ts"],
      "decisions": ["Decision text"],
      "plannedChildren": ["plan-xxx"]   // IDs of planned child frames
    }
  },
  "activeFrameID": "ses_xxx",
  "rootFrameIDs": ["ses_root1", "ses_root2"]
}
```

## Available Tools

### Core Frame Management
- `flame_push` - Create child frame for subtask
- `flame_pop` - Complete frame and return to parent (accepts optional `frameID`)
- `flame_status` - Show frame tree with status
- `flame_tree` - ASCII visualization of frame tree
- `flame_set_goal` - Update current frame's goal
- `flame_add_artifact` - Record produced artifact
- `flame_add_decision` - Record key decision

### Planning
- `flame_plan` - Create a planned frame (shows full frame ID)
- `flame_plan_children` - Create multiple planned children (shows full frame IDs)
- `flame_activate` - Start work on planned frame
- `flame_invalidate` - Invalidate frame with cascade

### Context & Debug
- `flame_context_info` - Show token usage metadata
- `flame_context_preview` - Preview XML context
- `flame_cache_clear` - Clear context cache
- `flame_get_state` - Get complete state for inspection (returns JSON)

### Autonomy (Phase 1.7)
- `flame_autonomy_config` - View/modify autonomy settings
- `flame_should_push` - Evaluate push heuristics
- `flame_should_pop` - Evaluate pop heuristics

## Debugging Tips

1. **Check plugin initialization**: Look for `=== FLAME PLUGIN INITIALIZED ===` in logs

2. **Verify hooks firing**: Look for:
   - `CHAT.MESSAGE` - Message hook
   - `SESSION CREATED` - Session lifecycle
   - `Frame context injected` - Context injection working

3. **State not persisting**: Check file permissions on `.opencode/flame/`

4. **Context not injecting**: Verify `experimental.chat.messages.transform` hook is firing

5. **Reset state for clean test**:
   ```bash
   rm -rf .opencode/flame/frames/
   echo '{"version":1,"frames":{},"activeFrameID":"","rootFrameIDs":[],"updatedAt":0}' > .opencode/flame/state.json
   ```

6. **Get session ID from output**:
   ```bash
   opencode run "flame_push goal='Test'" --format json | jq -r '.sessionID'
   ```

## Environment Variables

Configure plugin behavior via environment variables:

```bash
# Token budgets
FLAME_TOKEN_BUDGET_TOTAL=4000
FLAME_TOKEN_BUDGET_ANCESTORS=1500
FLAME_TOKEN_BUDGET_SIBLINGS=1500
FLAME_TOKEN_BUDGET_CURRENT=800

# Subagent detection
FLAME_SUBAGENT_ENABLED=true
FLAME_SUBAGENT_MIN_DURATION=60000
FLAME_SUBAGENT_MIN_MESSAGES=3

# Autonomy
FLAME_AUTONOMY_LEVEL=suggest  # manual, suggest, or auto
FLAME_PUSH_THRESHOLD=70
FLAME_POP_THRESHOLD=80
```
