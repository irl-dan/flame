# Proposal 06: OpenCode Fork for Flame Graph Context Management

## Executive Summary

This proposal evaluates the feasibility of implementing Flame Graph Context Management (FGCM) by forking or contributing to OpenCode. After a thorough analysis of OpenCode's architecture, I conclude that **OpenCode is an excellent candidate for implementing FGCM**, primarily because it already has foundational concepts (parent/child sessions, compaction, TODO system) that align with the frame-tree vision. The implementation would require significant but well-scoped modifications that could be structured as a PR-friendly contribution.

**Verdict: PR-able with phased approach. Fork only if upstream rejects the vision.**

---

## Part 1: OpenCode Architecture Overview

### 1.1 High-Level Structure

OpenCode is a TypeScript monorepo using Bun runtime with the following key packages:

```
packages/
  opencode/          # Core CLI and agent logic
    src/
      session/       # Session and message management
      agent/         # Agent definitions and configuration
      tool/          # Tool implementations
      storage/       # Persistence layer
      server/        # HTTP API
      cli/           # CLI commands and TUI
  app/               # Desktop/web frontend
  sdk/               # Client SDKs
  ui/                # Shared UI components
```

### 1.2 Key Files and Their Roles

| File | Purpose | Relevance to FGCM |
|------|---------|-------------------|
| `src/session/index.ts` | Session CRUD, parent/child relationships | **Critical** - needs frame tree extension |
| `src/session/message-v2.ts` | Message types, parts (tool, text, etc.) | **High** - needs frame metadata parts |
| `src/session/prompt.ts` | Main agent loop, context assembly | **Critical** - needs frame-aware context |
| `src/session/compaction.ts` | Context overflow handling | **High** - partial frame compaction exists |
| `src/session/processor.ts` | Stream processing for LLM responses | **Medium** - mostly unchanged |
| `src/session/todo.ts` | TODO list per session | **High** - could integrate with planned frames |
| `src/tool/task.ts` | Subagent/subtask spawning | **High** - creates child sessions (proto-frames) |
| `src/storage/storage.ts` | JSON file persistence | **Medium** - needs frame tree storage |
| `src/agent/agent.ts` | Agent configuration | **Low** - agent definitions unchanged |
| `src/session/system.ts` | System prompt construction | **Medium** - needs frame context injection |

---

## Part 2: How Context Management Currently Works

### 2.1 Session Model

Sessions in OpenCode are already **tree-structured**:

```typescript
// src/session/index.ts
export const Info = z.object({
  id: Identifier.schema("session"),
  projectID: z.string(),
  directory: z.string(),
  parentID: Identifier.schema("session").optional(),  // <-- Tree structure!
  title: z.string(),
  // ...
})
```

Child sessions are created when subagents (like `@general` or `@explore`) are invoked via the `TaskTool`:

```typescript
// src/tool/task.ts
const session = await Session.create({
  parentID: ctx.sessionID,  // <-- Parent linkage
  title: params.description + ` (@${agent.name} subagent)`,
})
```

### 2.2 Message Model

Messages have a **user -> assistant** parent relationship within sessions:

```typescript
// src/session/message-v2.ts
export const Assistant = Base.extend({
  parentID: z.string(),  // Points to the user message that triggered this
  // ...
})
```

Messages consist of "parts" which are typed content blocks:

```typescript
export const Part = z.discriminatedUnion("type", [
  TextPart,
  SubtaskPart,      // <-- Already represents "spawn child work"
  ReasoningPart,
  FilePart,
  ToolPart,
  StepStartPart,
  StepFinishPart,
  SnapshotPart,
  PatchPart,
  AgentPart,
  RetryPart,
  CompactionPart,   // <-- Already represents "summary of previous work"
])
```

### 2.3 Context Assembly

The main loop in `prompt.ts` assembles context by:

1. Filtering messages up to the last compaction point
2. Converting messages to model format
3. Injecting system prompts
4. Handling pending subtasks and compactions

```typescript
// src/session/prompt.ts - loop()
let msgs = await MessageV2.filterCompacted(MessageV2.stream(sessionID))
// ... process subtasks, compactions ...
const sessionMessages = clone(msgs)
const result = await processor.process({
  messages: [...MessageV2.toModelMessage(sessionMessages), ...],
})
```

### 2.4 Existing Compaction

OpenCode already has auto-compaction when context overflows:

```typescript
// src/session/compaction.ts
if (SessionCompaction.isOverflow({ tokens: lastFinished.tokens, model })) {
  await SessionCompaction.create({ sessionID, agent, model, auto: true })
}
```

Compaction generates a summary message that future context uses as a "checkpoint."

---

## Part 3: Gap Analysis - What FGCM Requires vs. What Exists

### 3.1 Feature Comparison

| FGCM Requirement | OpenCode Current State | Gap |
|------------------|----------------------|-----|
| Frame tree structure | Sessions have `parentID` | Conceptual match, needs formalization |
| Push frame (start subtask) | TaskTool creates child session | Close match, needs explicit frame semantics |
| Pop frame (complete subtask) | No explicit "pop" - session just ends | **Gap**: Need pop action + compaction |
| Compaction on pop | Compaction exists but not tied to pop | **Gap**: Need to trigger on frame completion |
| Active context = frame + ancestors | Full message history used | **Gap**: Need frame-scoped context |
| Sibling compactions in context | Not implemented | **Gap**: Need cross-frame visibility |
| Planned frames | TODO tool exists (per session) | **Gap**: Need frame-level planning |
| Frame status (in_progress/completed/blocked) | Session has `time.archived` | **Gap**: Need explicit status enum |
| Human control (/push, /pop) | Commands exist, not frame-aware | **Gap**: Need frame commands |
| Agent control (autonomous push/pop) | TaskTool spawns but doesn't manage | **Gap**: Need frame heuristics |

### 3.2 Architectural Alignment

**Positive alignments:**
- Session tree already exists (parentID relationship)
- Compaction mechanism already exists
- Tool part system can represent frame actions
- Storage layer is simple (JSON files)
- UI already displays child sessions hierarchically

**Gaps requiring design:**
- No concept of "current frame" separate from "current session"
- No frame-scoped context assembly
- No sibling visibility mechanism
- No planned frame system
- No pop/return mechanism

---

## Part 4: Design for Adding Frame Tree Support

### 4.1 Core Concept: Frame = Decorated Session

Rather than introducing a new "Frame" entity, we can **extend the Session concept** with frame semantics. This minimizes structural changes.

```typescript
// Extended Session.Info
export const Info = z.object({
  id: Identifier.schema("session"),
  projectID: z.string(),
  directory: z.string(),
  parentID: Identifier.schema("session").optional(),

  // NEW: Frame semantics
  frame: z.object({
    status: z.enum(["planned", "in_progress", "completed", "failed", "blocked"]),
    goal: z.string().optional(),
    compaction: z.string().optional(),  // Summary when completed
    logPath: z.string().optional(),     // Pointer to full log
  }).optional(),

  // ... existing fields
})
```

### 4.2 New Components

#### 4.2.1 Frame State Manager

```typescript
// NEW FILE: src/session/frame.ts
export namespace Frame {
  // Get current frame (deepest in_progress session in tree)
  export async function current(sessionID: string): Promise<Session.Info>

  // Push new frame (create child session with frame metadata)
  export async function push(input: {
    parentID: string,
    goal: string,
    planned?: boolean
  }): Promise<Session.Info>

  // Pop frame (mark complete, generate compaction, return to parent)
  export async function pop(input: {
    sessionID: string,
    status: "completed" | "failed" | "blocked",
  }): Promise<Session.Info>

  // Get ancestor chain
  export async function ancestors(sessionID: string): Promise<Session.Info[]>

  // Get sibling frames (children of same parent)
  export async function siblings(sessionID: string): Promise<Session.Info[]>
}
```

#### 4.2.2 Frame-Aware Context Assembly

```typescript
// MODIFY: src/session/prompt.ts
async function assembleFrameContext(sessionID: string): Promise<MessageV2.WithParts[]> {
  const frame = await Frame.current(sessionID)
  const ancestors = await Frame.ancestors(sessionID)
  const context: MessageV2.WithParts[] = []

  // 1. Add ancestor compactions (from root to parent)
  for (const ancestor of ancestors.reverse()) {
    if (ancestor.frame?.compaction) {
      context.push(createCompactionMessage(ancestor))
    }
  }

  // 2. Add sibling compactions (completed siblings only)
  for (const sibling of await Frame.siblings(sessionID)) {
    if (sibling.frame?.status === "completed" && sibling.frame.compaction) {
      context.push(createCompactionMessage(sibling))
    }
  }

  // 3. Add current frame's messages
  const currentMessages = await Session.messages({ sessionID })
  context.push(...currentMessages)

  return context
}
```

#### 4.2.3 Planned Frames (Extends TODO)

```typescript
// NEW FILE: src/session/planned-frames.ts
export namespace PlannedFrames {
  export const Info = z.object({
    id: z.string(),
    parentID: z.string(),
    goal: z.string(),
    status: z.enum(["planned", "invalidated"]),
    children: z.lazy(() => Info.array()).optional(),
  })

  // Create planned frame tree
  export async function plan(input: { sessionID: string, tree: Info[] })

  // Convert planned frame to real frame
  export async function activate(frameID: string): Promise<Session.Info>

  // Cascade invalidation
  export async function invalidate(frameID: string)
}
```

#### 4.2.4 Frame Compaction Generator

```typescript
// MODIFY: src/session/compaction.ts
export async function generateFrameCompaction(input: {
  sessionID: string,
  status: "completed" | "failed" | "blocked"
}): Promise<string> {
  const messages = await Session.messages({ sessionID })
  const agent = await Agent.get("compaction")

  // Use existing compaction agent with frame-aware prompt
  const prompt = `
Summarize this frame's work as a compaction for the parent context.
Status: ${input.status}
Focus on: what was done, key decisions, artifacts produced, blocking issues.
Include reference to log: ${getLogPath(input.sessionID)}
`

  return generateSummary(messages, agent, prompt)
}
```

### 4.3 Commands for Human Control

```typescript
// MODIFY: src/command/index.ts
export const FrameCommands = {
  "/push": {
    template: "Push new frame with goal: $ARGUMENTS",
    handler: async (args) => {
      await Frame.push({ parentID: currentSession, goal: args })
    }
  },
  "/pop": {
    template: "Pop current frame",
    handler: async () => {
      await Frame.pop({ sessionID: currentSession, status: "completed" })
    }
  },
  "/frame-status": {
    template: "Show frame tree status",
    handler: async () => {
      const tree = await Frame.getTree(rootSessionID)
      return formatFrameTree(tree)
    }
  },
  "/plan": {
    template: "Plan frame structure: $ARGUMENTS",
    handler: async (args) => {
      // Parse structured plan from args, create planned frames
    }
  }
}
```

### 4.4 Agent Heuristics for Autonomous Control

```typescript
// NEW FILE: src/session/frame-heuristics.ts
export namespace FrameHeuristics {
  // Check if current work should spawn a new frame
  export function shouldPush(context: {
    goal: string,
    currentDepth: number,
    estimatedTokens: number,
  }): boolean {
    // Heuristic: "Failure Boundary" - could this fail and need retry as unit?
    // Heuristic: "Context Switch" - working on different files/concepts?
    // Heuristic: Token budget approaching limit
  }

  // Check if current frame work is complete
  export function shouldPop(context: {
    lastAssistantMessage: MessageV2.Assistant,
    goal: string,
  }): boolean {
    // Heuristic: Goal achieved indicators
    // Heuristic: Stuck/blocked indicators
  }
}
```

---

## Part 5: Files Requiring Modification

### 5.1 Core Session Module

| File | Changes | Complexity |
|------|---------|------------|
| `src/session/index.ts` | Add frame schema extension, update create/update | Medium |
| `src/session/frame.ts` | **NEW**: Frame state manager | High |
| `src/session/message-v2.ts` | Add FrameTransitionPart type | Low |
| `src/session/prompt.ts` | Replace context assembly with frame-aware version | High |
| `src/session/compaction.ts` | Add frame compaction trigger, modify format | Medium |
| `src/session/planned-frames.ts` | **NEW**: Planned frame system | Medium |

### 5.2 Tools and Commands

| File | Changes | Complexity |
|------|---------|------------|
| `src/tool/task.ts` | Update to use Frame.push instead of Session.create | Low |
| `src/tool/frame.ts` | **NEW**: Frame control tool for agent use | Medium |
| `src/command/index.ts` | Add frame commands | Low |

### 5.3 Storage and API

| File | Changes | Complexity |
|------|---------|------------|
| `src/storage/storage.ts` | No changes needed (JSON files work) | None |
| `src/server/server.ts` | Add frame-related endpoints | Medium |

### 5.4 UI/TUI

| File | Changes | Complexity |
|------|---------|------------|
| `src/cli/cmd/tui/routes/session/` | Display frame status, tree view | Medium |
| `packages/app/src/pages/layout.tsx` | Already handles child sessions, needs status badges | Low |

### 5.5 Estimated Total Scope

- **New files**: 3 (frame.ts, planned-frames.ts, frame-heuristics.ts)
- **Modified files**: ~10
- **Lines of code**: ~1500-2500 new/modified
- **Estimated effort**: 3-4 weeks for core implementation

---

## Part 6: Maintaining Backwards Compatibility

### 6.1 Strategy: Opt-In Frame Mode

The frame system can be **opt-in** via configuration:

```json
{
  "experimental": {
    "frameMode": true
  }
}
```

When disabled:
- Sessions work exactly as before
- TaskTool creates child sessions without frame metadata
- Context assembly uses full message history
- No frame commands available

When enabled:
- All sessions get frame semantics
- Context assembly is frame-aware
- Frame commands available

### 6.2 Graceful Degradation

Existing sessions without `frame` metadata are treated as:
- Status: `in_progress`
- No goal
- No compaction
- Full message history in context

This allows gradual migration and mixed-mode operation.

### 6.3 API Compatibility

New frame endpoints are additions, not modifications:
- `POST /frame/push`
- `POST /frame/pop`
- `GET /frame/tree`
- `GET /frame/context`

Existing session endpoints remain unchanged.

---

## Part 7: PR Strategy vs. Fork Decision

### 7.1 Arguments for PR (Recommended)

1. **Architectural alignment**: OpenCode's session tree is conceptually identical to frames
2. **Existing patterns**: Compaction, child sessions, TODO already exist
3. **Modular design**: Changes can be isolated to new files + targeted modifications
4. **Backwards compatible**: Opt-in via config flag
5. **Community benefit**: Frame-based context could be a flagship feature

### 7.2 Arguments for Fork

1. **Radical change**: If frame mode becomes the default, breaks mental model
2. **Maintenance burden**: OpenCode team may not want to maintain frame code
3. **Divergent vision**: If FGCM evolves in ways incompatible with OpenCode's direction

### 7.3 Recommended Approach: Phased PR

**Phase 1: Foundation (PR-able)**
- Add `frame` optional schema to Session
- Add Frame namespace with basic push/pop
- Frame-aware context assembly (behind flag)
- Frame commands (/push, /pop, /frame-status)

**Phase 2: Enhancement (PR-able)**
- Planned frames system
- Sibling compaction visibility
- Frame heuristics for agent autonomy
- UI enhancements for frame tree

**Phase 3: Polish (PR-able)**
- Full log persistence with frame pointers
- Advanced frame navigation
- Frame templates/presets

If any phase is rejected, fork from that point forward.

---

## Part 8: Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| OpenCode team rejects PR | Medium | High | Prepare fork from Phase 1 completion |
| Context assembly performance | Low | Medium | Lazy loading, caching compactions |
| Frame depth explosion | Low | Medium | Max depth config, auto-consolidation |
| Complexity for users | Medium | Medium | Default off, good documentation |
| Breaking existing workflows | Low | High | Strict backwards compatibility |

---

## Part 9: Conclusion

OpenCode is exceptionally well-suited for implementing Flame Graph Context Management. The existing session tree, compaction system, and modular architecture provide a strong foundation. The implementation can be structured as backwards-compatible additions that could be contributed as PRs.

**Recommendation**:
1. Start with Phase 1 implementation as a PR to OpenCode
2. Engage with OpenCode maintainers early to gauge interest
3. If accepted, continue with Phase 2 and 3
4. If rejected, fork and maintain as "FlameCode" or similar

**Estimated timeline**:
- Phase 1: 3-4 weeks
- Phase 2: 3-4 weeks
- Phase 3: 2-3 weeks
- Total: 8-11 weeks for full implementation

The technical feasibility is high. The primary uncertainty is upstream acceptance, which can be mitigated by early engagement and clean, modular code.
