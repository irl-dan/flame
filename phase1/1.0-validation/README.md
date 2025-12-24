# Phase 1.0: Validation

**Status:** Complete
**Completed:** 2024-12-24

---

## Overview

Phase 1.0 validated critical assumptions about the OpenCode plugin API before implementation. All five assumptions were confirmed, proving the architecture is feasible.

## Validation Results

| Assumption | Status | Confidence |
|------------|--------|------------|
| File Storage | PASS | High |
| Session ID Tracking | PASS | High |
| Hook Invocation Timing | PASS | High |
| Message Prepend Behavior | PASS | High |
| Compaction Capture | NOT TESTED | N/A (requires longer conversation) |

## Key Learnings

### 1. Session ID Tracking

**Problem**: Transform hooks (`experimental.chat.messages.transform`, `experimental.chat.system.transform`) receive `input: {}` with no session context.

**Solution**: The `chat.message` hook fires BEFORE transform hooks and provides `sessionID` in its input. Track it in plugin state for use in transform hooks.

```typescript
let currentSessionID: string | null = null

// chat.message hook - fires first, has sessionID
"chat.message": async (input, output) => {
  currentSessionID = input.sessionID
}

// Transform hook - use tracked sessionID
"experimental.chat.messages.transform": async (input, output) => {
  // input is {}, but we have currentSessionID from chat.message
  const frameContext = await buildContext(currentSessionID)
  output.messages.unshift(syntheticMessage)
}
```

### 2. Message Prepend Works

Synthetic messages prepended via `experimental.chat.messages.transform` reach the LLM and are visible in its context.

**Evidence**: When asked "What context do you see from Flame?", the LLM responded:

> I can see two `<flame-context>` XML blocks in my context... Validation: true, Session ID: ses_xxx, Timestamp: ...

**Message structure used**:
```typescript
{
  info: {
    id: "flame-synthetic-<timestamp>",
    sessionID: trackedSessionID,
    role: "user",
    synthetic: true
  },
  parts: [{
    type: "text",
    text: "<flame-context>...</flame-context>"
  }]
}
```

### 3. Hook Execution Order

Hooks fire in a predictable, consistent order:

```
1. session.created event       - Session created
2. session.updated events      - Session state changes
3. chat.message hook           - User message (HAS sessionID)
4. message.updated events      - Message persistence
5. system.transform hooks      - Modify system prompt
6. messages.transform hooks    - Modify message array
7. session.status busy         - Processing started
8. [LLM processing...]
9. session.status idle         - Processing complete
10. session.idle event         - Final lifecycle event
```

### 4. File Storage

Plugins can write to `.opencode/flame/` without permission issues.

```typescript
const flameDir = path.join(projectDir, ".opencode", "flame")
await fs.promises.mkdir(flameDir, { recursive: true })
await fs.promises.writeFile(
  path.join(flameDir, "state.json"),
  JSON.stringify(state, null, 2)
)
```

### 5. Double Hook Registration

Hooks fire twice per invocation. Both invocations have consistent data.

**Mitigation options**:
1. Add deduplication logic (track processed message IDs)
2. Use singleton pattern for plugin state
3. Investigate if this is expected OpenCode behavior

## Running the Validation Plugin

### Prerequisites
- OpenCode installed
- Project directory: `/Users/sl/code/flame`
- Valid API credentials configured

### Steps

1. Navigate to project:
   ```bash
   cd /Users/sl/code/flame
   ```

2. Start OpenCode:
   ```bash
   opencode
   ```
   The plugin loads from `.opencode/plugin/flame-validation.ts`

3. Verify plugin loaded (look for console output):
   ```
   [flame-validation] === FLAME VALIDATION PLUGIN INITIALIZED ===
   [flame-validation] Storage test result { success: true, ... }
   ```

4. Test context injection:
   ```
   What context do you see from Flame?
   ```
   The LLM should mention `<flame-context>` blocks.

### State Files

After running, inspect:
- `.opencode/flame/validation-log.json` - Storage test results
- `.opencode/flame/validation-state.json` - Complete hook invocation log

## Files in This Directory

| File | Description |
|------|-------------|
| `README.md` | This file - key learnings and how to run |
| `flame-validation.ts` | Copy of the validation plugin |
| `test-plan.md` | Detailed test procedures |
| `results.md` | Full test results from 2025-12-24 |

## Cleanup

To remove test artifacts:
```bash
rm -rf /Users/sl/code/flame/.opencode/flame/
```

To disable the validation plugin:
```bash
mv /Users/sl/code/flame/.opencode/plugin/flame-validation.ts \
   /Users/sl/code/flame/.opencode/plugin/flame-validation.ts.disabled
```
