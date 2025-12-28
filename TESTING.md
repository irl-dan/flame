# Testing the Flame Plugin

This document describes how to test the Flame Graph Context Management plugin.

## Prerequisites

- OpenCode CLI installed (`opencode` command available)
- Plugin located at `.opencode/plugin/flame.ts`

## Quick Start

```bash
# Navigate to the flame directory
cd /path/to/flame

# Clear any existing state for a fresh test
rm -rf .opencode/flame/frames .opencode/flame/state.json

# Run a test prompt
opencode run "Create a plan for building a REST API with three endpoints"
```

## Test Patterns

### Basic Testing

```bash
# Single command execution
opencode run "Your test prompt here"

# With verbose logs
opencode run "Your test prompt" --print-logs 2>&1

# With specific model
opencode run "Your test prompt" --model anthropic/claude-sonnet-4-5-20250929
```

### Session Resumption

Resume existing sessions for multi-step workflows:

```bash
# Continue the last session
opencode run --continue "Continue working on this task"

# Resume a specific session by ID
opencode run --session ses_abc123xyz "Continue from where we left off"
```

## Core Test Scenarios

### 1. Frame Planning

Test that the agent uses flame tools for task decomposition:

```bash
opencode run "Build a user authentication system with login, logout, and password reset. Break this into subtasks and work through each one."
```

**Expected behavior:**
- Agent uses `flame_plan_children` to create subtasks
- Each subtask has a title and successCriteria
- Agent uses `flame_activate` to start each subtask
- Agent uses `flame_pop` with results when completing

### 2. Verify Frame State

Check the state file after running:

```bash
cat .opencode/flame/state.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
frames = d.get('frames', {})
print(f'Total frames: {len(frames)}')
for fid, f in frames.items():
    print(f'  [{f.get(\"status\")[:4]}] {f.get(\"title\", \"?\")[:40]}')
"
```

### 3. Frame Hierarchy (Nested Frames)

Test dynamic frame creation within frames:

```bash
opencode run "Build a complex feature that requires multiple sub-components. When you encounter complexity, create child frames. Target depth > 2."
```

**Expected behavior:**
- Agent creates frames within frames
- State shows `plannedChildren` relationships
- Max depth > 2 in frame tree

### 4. Context Injection

Verify context is being injected:

```bash
opencode run "Use flame_context_preview to show me what context is being injected" --print-logs 2>&1
```

Look for logs showing:
- `Context generated`
- `Frame context injected`

### 5. Frame Completion

Test the pop workflow:

```bash
# Get the active frame ID
FRAME_ID=$(cat .opencode/flame/state.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('activeFrameID', ''))")

# Pop with explicit frame ID
opencode run "Complete this frame with flame_pop. Use status=completed and provide results summarizing what was done."
```

## Key Files to Inspect

| File | Purpose |
|------|---------|
| `.opencode/flame/state.json` | Root state with frame tree |
| `.opencode/flame/frames/*.json` | Individual frame metadata |

## State Structure

```json
{
  "version": 1,
  "frames": {
    "ses_xxx": {
      "sessionID": "ses_xxx",
      "parentSessionID": "ses_parent",
      "status": "in_progress",
      "title": "Frame name",
      "successCriteria": "What defines done",
      "successCriteriaCompacted": "Dense version",
      "results": "What was accomplished",
      "resultsCompacted": "Dense version",
      "artifacts": ["file1.ts"],
      "decisions": ["Decision text"],
      "plannedChildren": ["plan-xxx"]
    }
  },
  "activeFrameID": "ses_xxx",
  "rootFrameIDs": ["ses_root"]
}
```

## Available Tools

### Core Frame Management

| Tool | Description |
|------|-------------|
| `flame_push` | Create child frame with title/criteria |
| `flame_pop` | Complete frame with status/results |
| `flame_status` | Show frame tree with status icons |
| `flame_tree` | ASCII visualization of frame tree |
| `flame_frame_details` | View full frame metadata |

### Planning

| Tool | Description |
|------|-------------|
| `flame_plan` | Create a single planned frame |
| `flame_plan_children` | Create multiple planned children |
| `flame_activate` | Start work on planned frame |
| `flame_invalidate` | Invalidate frame with cascade |

### Context & Debug

| Tool | Description |
|------|-------------|
| `flame_context_info` | Show token usage metadata |
| `flame_context_preview` | Preview XML context |
| `flame_cache_clear` | Clear context cache |
| `flame_get_state` | Get complete state JSON |

## Debugging Tips

1. **Check plugin initialization**: Look for `=== FLAME PLUGIN INITIALIZED ===` in logs

2. **Verify hooks firing**: Look for:
   - `CHAT.MESSAGE` - Message hook
   - `Frame context injected` - Context injection working

3. **State not persisting**: Check file permissions on `.opencode/flame/`

4. **Reset for clean test**:
   ```bash
   rm -rf .opencode/flame/
   ```

## E2E Test Results

The plugin has been validated with:

- **Simple tasks**: 5 frames, proper tool usage, no TodoWrite
- **Complex tasks**: 63 frames, depth 4, nested hierarchies
- **Real applications**: TypeScript projects with 17+ source files

Key validation:
- Agents use flame tools as PRIMARY task management (not TodoWrite)
- Dynamic frame creation when complexity discovered
- Proper completion with results summaries
- Session resumption with `--session` flag works correctly

## Environment Variables

```bash
# Token budgets
FLAME_TOKEN_BUDGET_TOTAL=4000
FLAME_TOKEN_BUDGET_ANCESTORS=1500
FLAME_TOKEN_BUDGET_SIBLINGS=1500
FLAME_TOKEN_BUDGET_CURRENT=800

# Autonomy
FLAME_AUTONOMY_LEVEL=suggest  # manual, suggest, or auto
FLAME_PUSH_THRESHOLD=70
FLAME_POP_THRESHOLD=80
```
