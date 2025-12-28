# Flame Graph Context Management - Specification

## The Problem

Current agent implementations organize conversation history as a **linear sequence** of messages. This creates several issues:

1. **Context window pressure**: Full linear history fills the context window, requiring lossy compaction
2. **Misaligned mental model**: Engineers think of work as a call stack (push subtask, complete it, pop back), not as a linear transcript
3. **Irrelevant context pollution**: When working on Task B, the full history of sibling Task A is unnecessarily included
4. **No structural memory**: Task relationships (parent/child/sibling) are implicit rather than explicit

## The Solution: Tree-Structured Context (Flame Graph)

Organize agent context as a **tree of frames** rather than a linear chat log:

```
                    [Root Frame: "Build App"]
                           │
           ┌───────────────┴───────────────┐
           │                               │
     [Frame A: Auth]                [Frame B: API Routes]
      (completed)                      (in progress)
           │                               │
      ┌────┴────┐                    ┌─────┴─────┐
      │         │                    │           │
    [A1]      [A2]                 [B1]        [B2]
   (done)    (done)            (in progress) (planned)
```

## Core Mechanics

### 1. Frame Push/Pop Semantics
- **Push**: Create a new child frame when starting a distinct subtask
- **Pop**: Return to parent frame when subtask completes (or fails/blocks)
- Heuristics for when to push: "Failure Boundary" (could be retried as unit) or "Context Switch" (different files/concepts)

### 2. Full Logs Persist to Disk
- Every frame's complete history is saved to a log file
- Nothing is truly lost - agents can browse previous frame logs if needed

### 3. Frame Identity (Immutable)
Each frame has immutable identity set at creation:
- **title**: Short name (2-5 words) - e.g., "User Authentication"
- **successCriteria**: What defines "done" in concrete, verifiable terms
- **successCriteriaCompacted**: Dense version for tree/context display

### 4. Frame Results (Set on Completion)
When a frame completes, results are recorded:
- **results**: Detailed summary of what was accomplished
- **resultsCompacted**: Dense version for context injection
- **artifacts**: Files/resources produced
- **decisions**: Key decisions made

### 5. Active Context Construction
When working in Frame B1, the active context includes:
- B1's own working history
- Compaction of parent B (its successCriteria and any partial results)
- Compaction of grandparent Root
- Compaction of completed sibling A (its results) - **this is the cross-talk**
- **Not included**: The full linear history of A1, A2, or any deep exploration

### 6. Structure as XML, Content as Prose
```xml
<frame id="root" status="in_progress">
  <title>Build the application</title>
  <success-criteria>Complete working app with auth and API</success-criteria>
  <child id="A" status="completed">
    <title>User Authentication</title>
    <results>Implemented JWT-based auth with refresh tokens.
    Created User model, auth middleware, login/logout routes.</results>
    <artifacts>src/auth/*, src/models/User.ts</artifacts>
  </child>
  <child id="B" status="in_progress">
    <title>API Routes</title>
    <success-criteria>RESTful CRUD endpoints with pagination</success-criteria>
    <child id="B1" status="in_progress">
      <title>CRUD Endpoints</title>
      <success-criteria>GET/POST/PUT/DELETE for resources</success-criteria>
      <!-- Current working context -->
    </child>
    <child id="B2" status="planned">
      <title>Pagination</title>
      <success-criteria>Cursor-based pagination with configurable limits</success-criteria>
    </child>
  </child>
</frame>
```

### 7. Planned Frames (Non-Linear TODO)
- Frames can exist in `planned` state before execution begins
- Planned frames can have planned children (sketch B→B1,B2,B3 before starting B)
- Plans are mutable - discoveries during execution can add/remove/modify planned frames
- When a frame is invalidated, all planned children cascade to invalidated

### 8. Control Authority
- **Human**: Explicit commands (/push, /pop, /plan, /status)
- **Agent**: Autonomous decisions based on context injection instructions
- The plugin strongly instructs agents to use flame tools as PRIMARY task management

## Key Insight: Why This Helps

The crucial insight is **structural separation of concerns**:

| Linear History | Flame Graph |
|----------------|-------------|
| Task A exploration → Task A solution → Task B exploration → Task B solution | Task A's full history in Frame A, Task B's full history in Frame B, only compactions cross-pollinate |
| Context grows monotonically | Active context = current frame + ancestor compactions + sibling compactions |
| Compaction loses detail | Full logs persist, compaction is additive context not replacement |
| No retry boundary | Frame = natural retry/rollback unit |

---

## Components Required for Implementation

1. **Frame State Manager**: Track tree of frames, their status, relationships
2. **Log Persistence Layer**: Write full frame logs to disk
3. **Results Generator**: Produce summaries when frames complete
4. **Context Assembler**: Build active context from current frame + relevant results
5. **Frame Controller**: Handle push/pop commands (human or agent-initiated)
6. **Plan Manager**: Handle planned frames, cascade invalidation
