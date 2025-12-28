# Proposal: Fixing flame_pop Usability in Non-Interactive Contexts

## Problem Analysis

### The Core Issue

`flame_pop` is designed to complete the "current" frame and return control to its parent. However, the current implementation relies on `runtime.currentSessionID`, which is set by OpenCode's session lifecycle hooks:

```typescript
// From flame.ts - the problematic pattern
async execute(args, toolCtx) {
  const currentSessionID = runtime.currentSessionID  // Set by session hooks

  if (!currentSessionID) {
    return "Error: No active session"
  }

  const frame = await manager.getFrame(currentSessionID)
  // ... complete this frame
}
```

### Why This Breaks in Non-Interactive Contexts

Each `opencode run` command creates a **new independent session**. The session lifecycle looks like this:

1. **Session A**: Run `flame_push` with goal "Child task"
   - Creates child frame `ses_abc123`
   - `runtime.currentSessionID` = `ses_abc123`
   - Session A ends, runtime state is lost

2. **Session B**: Run `flame_pop` with status "completed"
   - New session `ses_xyz789` is created
   - `runtime.currentSessionID` = `ses_xyz789` (the NEW session)
   - `flame_pop` tries to complete `ses_xyz789`, NOT `ses_abc123`

The fundamental issue is that **runtime state (currentSessionID) is ephemeral**, but **frame relationships are persistent** (stored in state.json). This creates a mismatch between what the user intends to pop and what actually gets popped.

### Impact

This issue affects:
- CLI automation workflows (`opencode run` commands in scripts)
- Multi-step testing of frame workflows
- Any non-interactive use of the Flame plugin
- Potentially MCP tool invocations from external systems

---

## Evaluation of Proposed Solutions

### Approach A: Add `frameID` parameter to `flame_pop`

**Description:** Modify `flame_pop` to accept an optional `frameID` parameter. When provided, pop that specific frame instead of the current session.

**Implementation Sketch:**
```typescript
flame_pop: tool({
  args: {
    frameID: tool.schema.string().optional()
      .describe("Specific frame ID to complete (uses current session if not provided)"),
    status: tool.schema.enum(["completed", "failed", "blocked"]),
    summary: tool.schema.string().optional(),
    generateSummary: tool.schema.boolean().optional(),
  },
  async execute(args, toolCtx) {
    // Use provided frameID or fall back to current session
    const targetFrameID = args.frameID || runtime.currentSessionID

    if (!targetFrameID) {
      return "Error: No frame ID provided and no active session"
    }

    const frame = await manager.getFrame(targetFrameID)
    if (!frame) {
      return `Error: Frame not found: ${targetFrameID}`
    }

    // Rest of completion logic...
  }
})
```

**Alignment with SPEC.md:**
- **Pro:** Maintains push/pop semantics - still conceptually a "pop" operation
- **Pro:** "Pop: Return to parent frame when subtask completes" - explicit targeting still follows this
- **Con:** Slightly weakens the stack metaphor (can pop arbitrary frames, not just "top")

**Pros:**
- Minimal API surface change (one optional parameter)
- Backward compatible - existing code works unchanged
- Simple to implement and test
- Consistent with other tools that accept optional `sessionID` (e.g., `flame_invalidate`)

**Cons:**
- Allows "out of order" pops (completing a grandchild before its parent)
- Requires caller to track frame IDs manually

**Verdict:** **Recommended as primary solution**

---

### Approach B: Add new `flame_complete` tool

**Description:** Create a dedicated tool for completing any frame by ID, leaving `flame_pop` strictly for the current frame.

**Implementation Sketch:**
```typescript
flame_complete: tool({
  description: "Complete a specific frame by ID. Use when you need to close a frame that isn't the current session.",
  args: {
    frameID: tool.schema.string()
      .describe("The frame ID to complete"),
    status: tool.schema.enum(["completed", "failed", "blocked"]),
    summary: tool.schema.string().optional(),
  },
  async execute(args, toolCtx) {
    const frame = await manager.getFrame(args.frameID)
    if (!frame) {
      return `Error: Frame not found: ${args.frameID}`
    }

    await manager.completeFrame(args.frameID, args.status, args.summary)
    return `Frame ${args.frameID.substring(0, 8)} completed with status: ${args.status}`
  }
})
```

**Alignment with SPEC.md:**
- **Pro:** Preserves pure pop semantics for `flame_pop`
- **Con:** "Complete" is less evocative than "pop" for the stack metaphor
- **Neutral:** Spec doesn't explicitly require a single completion mechanism

**Pros:**
- Clear separation of concerns: `flame_pop` = current, `flame_complete` = any
- Explicit tool for the explicit use case
- No changes to existing `flame_pop` behavior

**Cons:**
- Increases tool surface area (one more tool to learn)
- Redundant functionality (both tools complete frames)
- Users might be confused about when to use which

**Verdict:** **Acceptable alternative, but adds unnecessary complexity**

---

### Approach C: Add `flame_switch` tool

**Description:** Allow changing the active frame context without creating a new session. Then `flame_pop` would work on the switched-to frame.

**Implementation Sketch:**
```typescript
flame_switch: tool({
  description: "Switch the active frame context. Subsequent operations will act on this frame.",
  args: {
    frameID: tool.schema.string()
      .describe("The frame ID to switch to"),
  },
  async execute(args, toolCtx) {
    const frame = await manager.getFrame(args.frameID)
    if (!frame) {
      return `Error: Frame not found: ${args.frameID}`
    }

    // Update runtime state
    runtime.currentSessionID = args.frameID

    // Update persisted active frame
    await manager.setActiveFrame(args.frameID)

    return `Switched to frame: ${frame.goal} (${args.frameID.substring(0, 8)})`
  }
})
```

**Alignment with SPEC.md:**
- **Pro:** Supports "Control Authority" concept - human directing frame navigation
- **Con:** Conflates OpenCode sessions with Flame frames (they're related but distinct)
- **Con:** Breaks the "frame = session" mental model

**Pros:**
- Keeps `flame_pop` pure (always pops "current")
- Enables multi-step workflows: switch, pop, switch, pop
- More flexible navigation

**Cons:**
- Overloads the meaning of "current session"
- Could cause confusion: runtime.currentSessionID vs actual OpenCode session
- Session hooks would fight against manual switches
- Complex interaction with context injection

**Verdict:** **Not recommended - creates conceptual confusion**

---

### Approach D: Session continuation

**Description:** Add a way to resume an existing session rather than creating a new one. This would require changes to OpenCode itself.

**Alignment with SPEC.md:**
- **Pro:** Aligns with session = frame model
- **Con:** Outside the scope of the Flame plugin

**Pros:**
- Cleanest solution conceptually
- Would fix many related workflow issues

**Cons:**
- Requires OpenCode changes (outside plugin scope)
- `opencode run` is designed for stateless invocations
- May not be feasible with current OpenCode architecture

**Verdict:** **Out of scope - requires platform changes**

---

### Approach E: Automatic completion on session end

**Description:** When a session ends, automatically complete its frame (perhaps with status "completed" or configurable).

**Implementation Sketch:**
```typescript
// In event hook
"event": async (event) => {
  if (event.type === "session.ended" || event.type === "session.idle") {
    const sessionID = event.properties.info?.id
    const frame = await manager.getFrame(sessionID)

    if (frame && frame.status === "in_progress" && frame.parentSessionID) {
      // Auto-complete child frames when their session ends
      await manager.completeFrame(sessionID, "completed", "(Session ended)")
    }
  }
}
```

**Alignment with SPEC.md:**
- **Con:** "Pop: Return to parent frame when subtask completes" - session end != task completion
- **Con:** Conflates session lifecycle with task lifecycle
- **Con:** Status would often be wrong (session timeout vs intentional completion)

**Pros:**
- Zero user intervention required
- Clean session lifecycle

**Cons:**
- Session end doesn't mean task completion
- No way to specify completion status or summary
- Would need to distinguish intentional vs timeout vs error
- Already partially implemented for subagents (with different semantics)

**Verdict:** **Not recommended for general frames - loses semantic meaning**

---

## Recommended Solution

### Primary: Approach A - Add `frameID` parameter to `flame_pop`

This is the recommended solution because it:

1. **Minimizes API surface change** - One optional parameter
2. **Maintains backward compatibility** - Existing code continues to work
3. **Follows existing patterns** - Other tools like `flame_invalidate` already accept optional `sessionID`
4. **Aligns with SPEC philosophy** - Still a "pop" operation, just with explicit targeting
5. **Simple to implement and test** - Localized change in one tool

### Implementation Details

```typescript
flame_pop: tool({
  description:
    "Complete a frame and return to its parent. Uses current session by default, or specify frameID for non-interactive contexts.",
  args: {
    frameID: tool.schema
      .string()
      .optional()
      .describe("Specific frame ID to complete (uses current session if not provided)"),
    status: tool.schema
      .enum(["completed", "failed", "blocked"])
      .describe("The completion status of this frame"),
    summary: tool.schema
      .string()
      .optional()
      .describe("Optional summary of what was accomplished or why it failed/blocked"),
    generateSummary: tool.schema
      .boolean()
      .optional()
      .describe("If true, request a compaction-based summary before completing (default: false)"),
  },
  async execute(args, toolCtx) {
    // CHANGE: Use provided frameID or fall back to current session
    const targetFrameID = args.frameID || runtime.currentSessionID

    if (!targetFrameID) {
      return "Error: No frame ID provided and no active session"
    }

    const frame = await manager.getFrame(targetFrameID)
    if (!frame) {
      return `Error: Frame not found: ${targetFrameID}`
    }

    if (!frame.parentSessionID) {
      return "Error: Cannot pop from root frame. This is the top-level frame."
    }

    const parentID = frame.parentSessionID

    // NOTE: generateSummary flow may not work correctly for non-current frames
    // since compaction events are tied to the current session
    if (args.generateSummary) {
      // Warn if trying to generate summary for non-current frame
      if (targetFrameID !== runtime.currentSessionID) {
        return `Warning: generateSummary is not reliable for non-current frames.
Use explicit summary parameter instead, or pop from within the frame's session.

Frame: ${targetFrameID.substring(0, 8)}
Goal: ${frame.goal}`
      }

      // ... existing generateSummary logic
    }

    // Standard completion
    await manager.completeFrame(
      targetFrameID,
      args.status as FrameStatus,
      args.summary
    )

    // Invalidate caches
    invalidateCache(targetFrameID)
    invalidateCache(parentID)

    log("POP: Completed frame", {
      sessionID: targetFrameID,
      status: args.status,
      parentID,
      wasCurrentSession: targetFrameID === runtime.currentSessionID
    })

    return `Frame completed with status: ${args.status}

Frame: ${targetFrameID.substring(0, 8)}
Goal: ${frame.goal}
Summary: ${args.summary || "(no summary provided)"}
Parent frame: ${parentID.substring(0, 8)}

Returning to parent frame. The completed frame's context will be available as a summary in the parent.`
  },
})
```

### Usage Examples

**Interactive (unchanged):**
```
> flame_push with goal "Implement auth"
> ... work on auth ...
> flame_pop with status completed
```

**Non-interactive CLI:**
```bash
# Create child frame, capture ID from output
opencode run "flame_push with goal 'Child task'" > output.txt
FRAME_ID=$(grep -o 'ses_[a-zA-Z0-9]*' output.txt | head -1)

# Later, complete the specific frame
opencode run "flame_pop with frameID '$FRAME_ID' and status completed"
```

**Scripted workflow:**
```bash
# Create frame
CHILD_FRAME=$(opencode run "flame_push 'Fix bug #123'" --json | jq -r '.frameID')

# Do work in separate session
opencode run "Fix the bug in auth.ts"

# Complete the frame explicitly
opencode run "flame_pop frameID=$CHILD_FRAME status=completed summary='Fixed null check'"
```

---

## Impact on Existing Functionality

### No Breaking Changes

- Existing `flame_pop` calls without `frameID` continue to work exactly as before
- All current tests should pass without modification

### Edge Cases to Consider

1. **Popping non-existent frame**: Return clear error message
2. **Popping already-completed frame**: Either error or no-op (recommend error)
3. **Popping root frame**: Already handled - returns error
4. **generateSummary with non-current frame**: Limited functionality - warn user

### Documentation Updates Needed

- Update `flame_pop` tool description
- Add examples for non-interactive usage
- Document the `frameID` parameter in IMPLEMENTATION.md

---

## Open Questions for Project Owner

1. **Should non-current frame pops support `generateSummary`?**
   - The compaction hook fires for the current session, not arbitrary frames
   - Recommendation: Warn and require explicit summary for non-current frames

2. **Should we validate frame status before popping?**
   - Currently can pop a "planned" frame (which was never started)
   - Should we require status="in_progress" before allowing pop?

3. **Should frame IDs be exposed more prominently in output?**
   - Currently truncated to 8 chars in most output
   - Full IDs needed for scripting - should we add `--json` output mode?

4. **Should we add `flame_complete` as well?**
   - Even with `frameID` on `flame_pop`, a dedicated tool might be clearer
   - Trade-off: simplicity vs explicitness

5. **Should there be a `flame_frames` command that lists frames with full IDs?**
   - Would help with non-interactive scripting
   - `flame_tree` truncates IDs and is meant for visualization

6. **Interaction with planned frames:**
   - Can you pop a planned frame? (It was never started)
   - Should pop implicitly activate if frame is planned?

---

## Implementation Checklist

When implementing this fix:

- [ ] Add `frameID` parameter to `flame_pop` args schema
- [ ] Update execute() to use `args.frameID || runtime.currentSessionID`
- [ ] Add frame existence validation
- [ ] Handle `generateSummary` limitation for non-current frames
- [ ] Update tool description
- [ ] Update IMPLEMENTATION.md documentation
- [ ] Add test cases:
  - [ ] Pop with explicit frameID
  - [ ] Pop with non-existent frameID (error case)
  - [ ] Pop with already-completed frame
  - [ ] Pop with generateSummary on non-current frame (warning)
- [ ] Consider adding `flame_frames` tool for listing frame IDs

---

## Summary

The `flame_pop` usability issue stems from the mismatch between ephemeral runtime state (currentSessionID) and persistent frame relationships. The recommended fix is to add an optional `frameID` parameter to `flame_pop`, allowing explicit frame targeting while maintaining backward compatibility.

This solution:
- Aligns with SPEC.md push/pop semantics
- Follows existing patterns in the codebase
- Minimizes API surface change
- Enables non-interactive and scripted workflows
- Requires no platform-level changes

The fix is localized, testable, and should resolve BUG-002 as documented in POST_TEST_ACTION_ITEMS.md.
