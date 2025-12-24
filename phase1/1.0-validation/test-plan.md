# Flame Graph Context Management - Validation Test Plan

This document describes how to test the validation plugin and interpret results to confirm our architectural assumptions.

## Overview

The validation plugin (`/.opencode/plugin/flame-validation.ts`) tests five critical assumptions:

1. **Hook invocation timing** - When do transform hooks get called relative to other hooks?
2. **Session ID access** - How to reliably get session ID in transform hooks that receive `input: {}`
3. **Compaction output capture** - Can we capture generated summaries via `session.compacted` event?
4. **File storage** - Can plugins write to `.opencode/flame/` directory?
5. **Message prepend behavior** - Do synthetic messages appear in LLM context and TUI?

---

## Prerequisites

1. OpenCode installed and working
2. The flame project directory at `/Users/sl/code/flame`
3. Valid API credentials configured for at least one provider

---

## Running the Plugin

### Step 1: Navigate to Project Directory

```bash
cd /Users/sl/code/flame
```

### Step 2: Start OpenCode

```bash
opencode
```

The plugin will automatically load from `.opencode/plugin/flame-validation.ts`.

### Step 3: Verify Plugin Loaded

Look for console output:
```
[timestamp] [flame-validation] === FLAME VALIDATION PLUGIN INITIALIZED ===
[timestamp] [flame-validation] Plugin context received {...}
[timestamp] [flame-validation] Storage test result {...}
```

---

## Test Cases

### Test 1: File Storage Validation

**Purpose**: Confirm plugins can write to `.opencode/flame/` directory.

**Steps**:
1. Start opencode
2. Wait for plugin initialization

**Expected Output**:
```
Storage test result { success: true, path: ".../flame/validation-log.json", ... }
```

**Verification**:
```bash
cat /Users/sl/code/flame/.opencode/flame/validation-log.json
```

Should contain:
```json
{
  "validationStarted": <timestamp>,
  "lastUpdated": <timestamp>,
  "message": "Flame validation plugin storage test successful"
}
```

**Result Interpretation**:
- `success: true` - File storage works, we can persist frame state
- `success: false` - Need to investigate directory permissions or paths

---

### Test 2: Session ID Tracking

**Purpose**: Confirm we can track session ID across hooks.

**Steps**:
1. Start opencode (creates or resumes a session)
2. Send a simple prompt like "hello"

**Watch Console For**:
```
[flame-validation] SESSION CREATED { sessionID: "...", parentID: undefined, ... }
[flame-validation] CHAT.MESSAGE HOOK INVOKED { sessionID: "...", ... }
[flame-validation] === MESSAGES TRANSFORM HOOK === { trackedSessionID: "...", ... }
[flame-validation] === SYSTEM TRANSFORM HOOK === { trackedSessionID: "...", ... }
```

**Key Observations**:
1. `chat.message` hook receives `sessionID` directly in input
2. Transform hooks (`messages.transform`, `system.transform`) receive `input: {}`
3. The plugin tracks sessionID from `chat.message` to use in transform hooks

**Result Interpretation**:
- If `trackedSessionID` in transform hooks matches the session ID from events, our tracking approach works
- If `trackedSessionID` is null or mismatched, we need to adjust our tracking strategy

---

### Test 3: Hook Invocation Timing

**Purpose**: Understand the order of hook calls during a prompt.

**Steps**:
1. Send a prompt in opencode

**Expected Order** (observe timestamps in logs):
```
1. session.created (event) - or session.updated if resuming
2. chat.message - when user message is processed
3. experimental.chat.system.transform - system prompt modification
4. experimental.chat.messages.transform - message array modification
5. tool.execute.before (if tools called)
6. tool.execute.after (if tools called)
7. session.idle (event) - when response completes
```

**Verification**:
Check `.opencode/flame/validation-state.json` for `hookInvocations` array with timestamps.

**Result Interpretation**:
- `chat.message` fires BEFORE transform hooks - this is where we capture sessionID
- Transform hooks fire immediately before LLM call - ideal for context injection
- The order is consistent and predictable

---

### Test 4: Message Prepend Behavior

**Purpose**: Verify that prepended synthetic messages reach the LLM.

**Steps**:
1. Send a prompt: "What context do you see from Flame?"
2. Observe the LLM's response

**Watch Console For**:
```
[flame-validation] Synthetic message prepended { newMessageCount: X, syntheticId: "flame-synthetic-..." }
```

**Expected LLM Behavior**:
The LLM should acknowledge or reference the `<flame-context>` XML block that was injected.

**Verification Questions**:
1. Does the LLM mention seeing a "flame-context" block?
2. Does it reference the validation="true" attribute?
3. Does the response indicate awareness of the injected message?

**TUI Visibility Check**:
Look at the message list in opencode TUI:
- Does the synthetic message appear in the conversation history?
- Is it distinguishable from regular messages?

**Result Interpretation**:
- If LLM references the context: Message prepend works correctly
- If LLM ignores it: May need to adjust message format or placement
- If TUI shows it: Users will see injected context (may need hiding)
- If TUI hides it: The `synthetic: true` flag may filter display

---

### Test 5: Compaction Capture

**Purpose**: Verify we can capture compaction summaries.

**Steps**:
1. Have a longer conversation (10+ exchanges) to trigger auto-compaction
2. OR manually trigger compaction via keybind or command

**Watch Console For**:
```
[flame-validation] === COMPACTING HOOK === { sessionID: "...", ... }
```
(This fires BEFORE compaction LLM call)

Then later:
```
[flame-validation] SESSION COMPACTED EVENT RECEIVED { sessionID: "...", ... }
[flame-validation] COMPACTION SUMMARY FOUND { messageId: "...", textContent: "..." }
```

**Key Observations**:
1. `experimental.session.compacting` hook fires BEFORE compaction
   - Receives `sessionID` directly in input
   - Can modify `output.context` to add custom context
   - Can set `output.prompt` to replace entire compaction prompt

2. `session.compacted` event fires AFTER compaction completes
   - Only contains `sessionID`
   - Must fetch messages to find summary

**Verification**:
After compaction, check if we found the summary message by looking for:
```
COMPACTION SUMMARY FOUND { messageId: "...", textContent: "..." }
```

**Result Interpretation**:
- If summary found: We can capture and store frame compaction summaries
- If not found: May need to adjust message query or timing
- The `summary: true` flag on AssistantMessage identifies compaction summaries

---

### Test 6: Child Session / Subagent Detection

**Purpose**: Verify we can detect child sessions (for frame hierarchy).

**Steps**:
1. Start a task that spawns a subagent (e.g., a complex code analysis)
2. Or manually create a child session via SDK/API

**Watch Console For**:
```
[flame-validation] SESSION CREATED {
  sessionID: "child-session-id",
  parentID: "parent-session-id",  // THIS IS KEY
  title: "...",
  isChildSession: true
}
```

**Key Observations**:
- `parentID` is populated for child sessions
- `isChildSession: true` in our log indicates frame hierarchy detection

**Result Interpretation**:
- If parentID present: We can build frame trees from session hierarchy
- If parentID missing: May need different detection mechanism

---

## State File Inspection

After running tests, inspect the validation state:

```bash
cat /Users/sl/code/flame/.opencode/flame/validation-state.json | jq .
```

Key sections to examine:

```json
{
  "pluginInitTime": 1234567890,
  "hookInvocations": [
    {
      "hook": "chat.message",
      "sessionID": "abc123",
      "notes": "Receives sessionID - can track current session here"
    },
    {
      "hook": "experimental.chat.messages.transform",
      "sessionID": "abc123",  // Should match!
      "notes": "Input is {} - sessionID not available directly..."
    }
  ],
  "sessionEvents": [...],
  "compactionEvents": [...],
  "storageTestResult": { "success": true, ... }
}
```

---

## Expected Findings Summary

| Assumption | Expected Result | Validation Method |
|------------|-----------------|-------------------|
| Hook timing | Predictable order: events -> chat.message -> transform hooks | Compare timestamps in hookInvocations |
| Session ID access | Track via `chat.message` hook, use in transform hooks | Check trackedSessionID matches across hooks |
| Compaction capture | Summary accessible via `session.compacted` event + message fetch | Look for COMPACTION_SUMMARY_FOUND log |
| File storage | Can write to `.opencode/flame/` | Check storageTestResult.success |
| Message prepend | Synthetic messages included in LLM context | Ask LLM about flame-context; observe response |

---

## Potential Issues and Mitigations

### Issue: Transform hooks receive wrong sessionID

**Symptom**: `trackedSessionID` in transform hooks doesn't match actual session

**Cause**: Multiple sessions active; state.currentSessionID overwritten

**Mitigation**:
- Track sessionID per-hook-call rather than globally
- Use message.sessionID from output.messages if available

### Issue: Compaction summary not found

**Symptom**: `COMPACTION SUMMARY NOT FOUND` after session.compacted event

**Cause**: Timing issue; messages not yet persisted

**Mitigation**:
- Add small delay before fetching messages
- Subscribe to `message.updated` events and filter for `summary: true`

### Issue: Synthetic messages not reaching LLM

**Symptom**: LLM doesn't acknowledge injected context

**Cause**: Message format incorrect or filtered out

**Mitigation**:
- Ensure message structure matches MessageWithParts type exactly
- Check if `synthetic: true` flag affects processing
- Try different message role (user vs assistant)

### Issue: Storage permission denied

**Symptom**: `success: false` with permission error

**Cause**: Directory permissions or path issues

**Mitigation**:
- Verify `.opencode` directory exists and is writable
- Check if running in sandboxed environment

---

## Next Steps After Validation

If all tests pass:

1. **Proceed with Phase 1 implementation** as outlined in SYNTHESIS.md
2. **Session ID tracking approach confirmed**: Use `chat.message` hook to track current sessionID for use in transform hooks
3. **Compaction integration confirmed**: Use `experimental.session.compacting` for custom prompts and `session.compacted` event + message fetch for capturing summaries
4. **Context injection confirmed**: Message prepend via `experimental.chat.messages.transform` works for frame context

If issues found:

1. Document specific failures in validation-state.json
2. Research alternative approaches based on failure mode
3. Consider requesting OpenCode enhancements if hooks are insufficient
4. Update SYNTHESIS.md with revised approach

---

## Cleanup

To remove test artifacts:

```bash
rm -rf /Users/sl/code/flame/.opencode/flame/
```

To disable the validation plugin (but keep for reference):

```bash
mv /Users/sl/code/flame/.opencode/plugin/flame-validation.ts \
   /Users/sl/code/flame/.opencode/plugin/flame-validation.ts.disabled
```
