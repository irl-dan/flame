# Key Theoretical Goal: Flame Graph Context Management

## The Problem

Current agent implementations (including Claude Code) organize conversation history as a **linear sequence** of messages. This creates several issues:

1. **Context window pressure**: As work progresses, the full linear history fills the context window, eventually requiring lossy compaction
2. **Misaligned mental model**: Engineers naturally think of work as a call stack (push subtask, complete it, pop back), not as a linear transcript
3. **Irrelevant context pollution**: When working on Task B, the full exploration/debugging history of sibling Task A is unnecessarily prefixed, consuming attention and tokens
4. **No structural memory**: The relationship between tasks (parent/child/sibling) is implicit in the linear history rather than explicit

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
- Heuristics for when to push: "Failure Boundary" (could be retried as unit) or "Context Switch" (different files/concepts/goals)

### 2. Full Logs Persist to Disk
- Every frame's complete history is saved to a log file
- Nothing is truly lost - agents can browse previous frame logs if needed
- The log file path is referenced in compaction summaries

### 3. Compaction on Pop
When a frame completes, a **compacted summary** is generated containing:
- Status (completed/failed/blocked/invalidated)
- Key artifacts produced
- Critical decisions made
- Pointer to full log file

This compaction is **injected into the parent context** before continuing work.

### 4. Active Context Construction
When working in Frame B1, the active context includes:
- B1's own working history
- Compaction of parent B (what B is trying to achieve)
- Compaction of grandparent Root
- Compaction of uncle A (completed sibling branch) - **this is the cross-talk**
- **Not included**: The full linear history of A1, A2, or any deep exploration

### 5. Structure as XML, Content as Prose
```xml
<frame id="root" status="in_progress">
  <goal>Build the application</goal>
  <child id="A" status="completed">
    <summary>Implemented JWT-based auth with refresh tokens.
    Created User model, auth middleware, login/logout routes.</summary>
    <artifacts>src/auth/*, src/models/User.ts</artifacts>
    <log>./logs/frame-A.md</log>
  </child>
  <child id="B" status="in_progress">
    <goal>Build API routes</goal>
    <child id="B1" status="in_progress">
      <goal>Implement CRUD for resources</goal>
      <!-- Current working context -->
    </child>
    <child id="B2" status="planned">
      <goal>Add pagination and filtering</goal>
    </child>
  </child>
</frame>
```

### 6. Planned Frames (Non-Linear TODO)
- Frames can exist in `planned` state before execution begins
- Planned frames can have planned children (sketch B→B1,B2,B3 before starting B)
- Plans are mutable - discoveries during execution can add/remove/modify planned frames
- When a frame is invalidated, all planned children cascade to invalidated

### 7. Control Authority
- **Human**: Explicit commands (/push, /pop, /plan, /status)
- **Agent**: Autonomous decisions based on heuristics
- Possibly mediated by a "Controller/Meta Agent" separate from the worker agent

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
3. **Compaction Generator**: Produce summaries when frames complete
4. **Context Assembler**: Build active context from current frame + relevant compactions
5. **Frame Controller**: Handle push/pop commands (human or agent-initiated)
6. **Plan Manager**: Handle planned frames, cascade invalidation
