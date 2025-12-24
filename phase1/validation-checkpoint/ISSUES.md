# Issues, Gaps, and Concerns Report

**Date:** 2025-12-24
**Validation Agent:** Claude Opus 4.5
**Purpose:** Document all issues found during Phase 1.0-1.3 validation

---

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | - |
| High | 0 | - |
| Medium | 3 | All planned for later phases |
| Low | 4 | Minor improvements |
| Observation | 3 | Non-blocking notes |

**Overall Assessment: NO BLOCKERS for Phase 1.4**

---

## Critical Issues

**None found.**

---

## High Priority Issues

**None found.**

---

## Medium Priority Issues

### ISSUE-001: Log Export Not Implemented

**Category:** Missing Feature
**SPEC Reference:** "Every frame's complete history is saved to a log file"
**Status:** PLANNED (Phase 1.4)

**Description:**
The `logPath` field exists in FrameMetadata but full conversation log export is not yet implemented. The SPEC requires that nothing is truly lost and agents can browse previous frame logs.

**Impact:**
- Users cannot review full conversation history after compaction
- The "pointer to full log file" in summaries is not functional

**Mitigation:**
Planned for Phase 1.4 per SYNTHESIS.md roadmap.

**Location:** `FrameMetadata.logPath` field (line 156 in flame.ts)

---

### ISSUE-002: Planned Frame Management Not Implemented

**Category:** Missing Feature
**SPEC Reference:** "Frames can exist in `planned` state before execution begins"
**Status:** PLANNED (Phase 6)

**Description:**
While the `planned` status exists in the type system, there is no tooling to:
- Create planned frames
- Sketch out planned children before starting
- Manage planned frame hierarchies

**Impact:**
- Cannot pre-plan work breakdown structure
- No support for non-linear TODO management

**Mitigation:**
Planned for Phase 6 per SYNTHESIS.md roadmap.

**Location:** `FrameStatus` type (line 37 in flame.ts)

---

### ISSUE-003: Invalidation Cascade Not Implemented

**Category:** Missing Feature
**SPEC Reference:** "When a frame is invalidated, all planned children cascade to invalidated"
**Status:** PLANNED (Phase 6)

**Description:**
The `invalidated` status exists but cascade logic is not implemented. Invalidating a parent frame does not automatically invalidate children.

**Impact:**
- Manual cleanup required when plans change
- Risk of orphaned planned frames

**Mitigation:**
Planned for Phase 6 per SYNTHESIS.md roadmap.

---

## Low Priority Issues

### ISSUE-004: flame_pop Does Not Accept `invalidated` Status

**Category:** API Limitation
**Status:** Enhancement needed for Phase 6

**Description:**
The `flame_pop` tool only accepts "completed", "failed", "blocked" statuses:
```typescript
status: tool.schema.enum(["completed", "failed", "blocked"])
```

The `invalidated` status is valid per SPEC but cannot be set via flame_pop.

**Impact:**
- Cannot mark frames as invalidated through the pop flow
- Would need separate mechanism or tool update

**Recommendation:**
Add `invalidated` to the allowed statuses in flame_pop when implementing Phase 6.

---

### ISSUE-005: Duplicate Plugin Initialization

**Category:** Minor Bug
**Status:** Non-blocking

**Description:**
Plugin initialization logs appear twice in the output:
```
[flame] === FLAME PLUGIN INITIALIZED (Phase 1.3) ===
[flame] Plugin context { ... }
[flame] === FLAME PLUGIN INITIALIZED (Phase 1.3) ===
[flame] Plugin context { ... }
```

This suggests the plugin factory is being called twice by OpenCode.

**Impact:**
- Extra log noise
- No functional impact

**Root Cause:**
OpenCode may be loading the plugin for both CLI and server contexts, or there's a duplicate registration.

**Recommendation:**
Investigate OpenCode plugin loading behavior. May be expected behavior for how OpenCode handles plugins.

---

### ISSUE-006: Session Title Not Used for Frame Goal

**Category:** UX Enhancement
**Status:** Low priority

**Description:**
When a new session is created and auto-initialized as a frame, the goal is set to a truncated session ID rather than the session title:
```
goal: "Session ses_4af9"
```

The session title is available at creation but not being used.

**Impact:**
- Less descriptive frame goals
- User needs to manually update goal with `flame_set_goal`

**Recommendation:**
Update `ensureFrame()` to use the full session title when available:
```typescript
const goal = title || `Session ${sessionID.substring(0, 8)}`
```
Should be:
```typescript
const goal = title || `Session ${sessionID.substring(0, 8)}`
// And in session.created handler, pass the full title
```

**Location:** Line 1052-1058 in flame.ts

---

### ISSUE-007: No Frame Tree Visualization Command

**Category:** Missing UX Feature
**Status:** Low priority

**Description:**
SYNTHESIS.md mentions a frame tree visualization command for Phase 6. Currently `flame_status` provides a text representation, but there's no graphical or interactive tree view.

**Impact:**
- Harder to understand complex frame hierarchies
- Text output can be verbose for large trees

**Recommendation:**
Consider adding a more visual tree representation in Phase 6, possibly using TUI capabilities.

---

## Observations (Non-Blocking)

### OBS-001: OpenCode NotFoundError

**Category:** External Issue

**Description:**
OpenCode logs show unhandled rejection errors:
```
ERROR service=acp-command promise={} reason=NotFoundError Unhandled rejection
```

This is not related to the Flame plugin but appears in test logs.

**Impact:** None to Flame functionality.

---

### OBS-002: Compaction Event Not Triggered in Testing

**Category:** Test Coverage Gap

**Description:**
The `session.compacted` event handler was not triggered during E2E testing because:
1. Context window did not overflow
2. No `generateSummary: true` flag was used

**Impact:**
Summary extraction flow not validated in production conditions.

**Recommendation:**
Consider a dedicated test that fills context to trigger compaction, or manually test the summary generation flow.

---

### OBS-003: Token Budget Estimation Approximation

**Category:** Technical Debt

**Description:**
Token counting uses a simple character-based approximation:
```typescript
function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4)
}
```

This is a rough estimate that may not match actual model tokenization.

**Impact:**
- May under/over-estimate token usage
- Could lead to context overflow or unnecessary truncation

**Recommendation:**
Consider using a proper tokenizer library (e.g., tiktoken) for accurate counts in a future enhancement.

**Location:** Lines 311-316 in flame.ts

---

## Architectural Concerns

### No Current Concerns

The architecture is sound and follows the SYNTHESIS.md design. Key decisions validated:

1. **Message prepend for context injection** - Working correctly, visible in logs
2. **File-based state storage** - Simple, reliable, portable
3. **Plugin-only approach** - No OpenCode core changes needed
4. **Token budget system** - Effective for managing context size
5. **Cache with TTL** - Improves performance for repeated calls

---

## Technical Debt Tracker

| Item | Phase Introduced | Estimated Effort | Priority |
|------|-----------------|------------------|----------|
| Token estimation approximation | 1.2 | Low | Low |
| Session title for frame goal | 1.1 | Low | Low |
| Duplicate plugin init investigation | 1.0 | Low | Low |

---

## Deferred Features (Per Roadmap)

| Feature | Target Phase | SPEC Reference |
|---------|--------------|----------------|
| Log export to Markdown | 1.4 | Full logs persist |
| Log browsing command | 1.4 | Agents can browse logs |
| Subagent auto-framing | 1.5 | TaskTool integration |
| Planned frame creation | 6 | Planned frames |
| Invalidation cascade | 6 | Cascade to invalidated |
| Frame tree visualization | 6 | Visual navigation |
| Push heuristics | 7 | Failure Boundary / Context Switch |
| Agent-initiated push/pop | 7 | Agent autonomy |

---

## Conclusion

The validation found **no critical or high-priority issues**. All identified gaps are:

1. **Planned features** scheduled for later phases (1.4-7)
2. **Minor UX improvements** that don't block functionality
3. **Observations** about external behavior or test coverage

**Recommendation: PROCEED to Phase 1.4**

The implementation is solid, well-structured, and aligned with both SPEC.md and SYNTHESIS.md. The remaining gaps are intentional deferrals per the incremental development approach.
