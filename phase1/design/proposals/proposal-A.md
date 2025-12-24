# Proposal A: Flame Graph Context Management for OpenCode

## Executive Summary

This proposal outlines a high-level architecture for implementing Flame Graph Context Management as an OpenCode plugin. The core insight is that OpenCode already has several primitives that can be leveraged for frame-based context management: parent/child sessions, compaction hooks, context transformation, and an event-driven architecture. Our design enhances these existing primitives rather than reimplementing them.

---

## 1. Core Architecture

### 1.1 Design Philosophy: Frames as Enhanced Sessions

OpenCode sessions already support parent-child relationships (`parentID` on Session.Info). The Flame plugin treats each OpenCode session as a "frame" and builds additional state management on top:

```
Frame = Session + Frame Metadata (status, goal, artifacts, compaction summary)
```

Key architectural decisions:

1. **Sessions ARE Frames**: Rather than create a parallel structure, we extend the session concept with frame-specific metadata stored in plugin-managed storage.

2. **Plugin as Orchestrator**: The plugin acts as a coordination layer that:
   - Intercepts session/message events
   - Manages frame state transitions
   - Controls context assembly before LLM calls
   - Handles compaction on frame completion

3. **Non-Invasive Extension**: The plugin operates through hooks and events, never modifying OpenCode's core session storage directly.

### 1.2 High-Level Component Diagram

```
                    +---------------------------+
                    |      Frame Controller     |
                    | (Commands: /push /pop)    |
                    +-------------+-------------+
                                  |
                    +-------------v-------------+
                    |     Frame State Manager   |
                    | (Tree structure, status)  |
                    +-------------+-------------+
                                  |
          +----------+------------+------------+----------+
          |          |            |            |          |
     +----v----+ +---v----+ +----v----+ +-----v-----+ +--v--+
     |  Log    | |Compact.| |Context  | |  Plan     | |Event|
     | Persist | |Generat.| |Assembler| | Manager   | |Bus  |
     +---------+ +--------+ +---------+ +-----------+ +-----+
```

---

## 2. Component Mapping to OpenCode Features

### 2.1 Frame State Manager

**SPEC Requirement**: Track tree of frames, their status, relationships

**OpenCode Features Used**:
- `Session.Info.parentID` - native parent-child session relationships
- `Session.children(parentID)` - list child sessions
- `Storage` namespace - plugin-private storage for frame metadata

**Design**:
```typescript
interface FrameMetadata {
  sessionID: string
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked' | 'invalidated'
  goal: string
  artifacts: string[]
  decisions: string[]
  compactionSummary?: string
  logPath: string
  parentFrameID?: string
  childFrameIDs: string[]
}
```

The Frame State Manager maintains a separate storage layer (e.g., `Storage.write(['flame', 'frame', sessionID], metadata)`) that augments session data with frame-specific state. This keeps OpenCode's session storage clean while giving Flame the state it needs.

**Key Operations**:
- `getFrameTree(rootSessionID)` - Reconstruct tree from session parent/child relationships
- `getFrameState(sessionID)` - Get frame metadata
- `updateFrameState(sessionID, updates)` - Update frame status, artifacts, etc.
- `getAncestors(sessionID)` - Walk up parent chain for context assembly

### 2.2 Log Persistence Layer

**SPEC Requirement**: Write full frame logs to disk, nothing truly lost

**OpenCode Features Used**:
- `Session.messages()` - get all messages for a session
- `MessageV2.stream()` - stream messages with parts
- Plugin file system access via `$` (Bun shell)

**Design**:
Frame logs are persisted to disk at configurable paths. The plugin hooks into session events to:

1. **On session completion** (`session.idle` event): Export full message history to markdown file
2. **On compaction** (`session.compacted` event): Update log with compaction marker

Log format preserves full fidelity:
```markdown
# Frame: Build Authentication System
Status: completed
Session ID: session_abc123
Parent: session_root001

## Messages

### User (2024-01-15 10:30:00)
Implement JWT-based authentication...

### Assistant (2024-01-15 10:30:05)
I'll create the auth system with the following approach...

[Tool: edit] src/auth/jwt.ts
[Tool: bash] npm install jsonwebtoken
...

## Compaction Summary
Implemented JWT authentication with refresh tokens. Created User model, auth middleware, and login/logout routes.
```

Log paths are stored in frame metadata, enabling future reference from compaction summaries.

### 2.3 Compaction Generator

**SPEC Requirement**: Generate summaries when frames complete

**OpenCode Features Used**:
- `experimental.session.compacting` hook - customize compaction behavior
- `SessionCompaction.process()` - existing compaction pipeline
- Session summary generation in `SessionSummary`

**Design**:
The Flame plugin hooks into OpenCode's existing compaction infrastructure and extends it:

```typescript
// Plugin hook implementation
"experimental.session.compacting": async (input, output) => {
  const frame = await FrameStateManager.get(input.sessionID)

  // Replace default compaction prompt with frame-aware prompt
  output.prompt = `
You are generating a continuation summary for a frame in a hierarchical task tree.

Frame Goal: ${frame.goal}
Frame Status: ${frame.status}
Key Artifacts: ${frame.artifacts.join(', ')}

Summarize:
1. What was accomplished in this frame
2. Key decisions made and their rationale
3. Files created/modified
4. Any issues encountered or deferred

This summary will be injected into parent context for sibling frames.
Keep it concise but preserve critical information.

Full log available at: ${frame.logPath}
`
}
```

When a frame completes (detected via `session.idle` event + user explicitly marks done), the plugin:
1. Triggers compaction with custom prompt
2. Stores resulting summary in frame metadata
3. Persists full log to disk
4. Updates parent frame's context with child summary

### 2.4 Context Assembler

**SPEC Requirement**: Build active context from current frame + relevant compactions

**OpenCode Features Used**:
- `experimental.chat.messages.transform` hook - modify messages before LLM call
- `experimental.chat.system.transform` hook - modify system prompt

**Design**:
This is the heart of Flame. Before each LLM call, the Context Assembler constructs the active context:

```typescript
"experimental.chat.messages.transform": async (input, output) => {
  const currentSessionID = getCurrentSessionID(output.messages)
  const frame = await FrameStateManager.get(currentSessionID)

  // Build context hierarchy
  const ancestorCompactions = await getAncestorCompactions(frame)
  const siblingCompactions = await getSiblingCompactions(frame)

  // Inject structural context as synthetic user message at start
  const contextMessage = buildContextXML({
    ancestors: ancestorCompactions,
    siblings: siblingCompactions,
    currentGoal: frame.goal
  })

  // Prepend to messages (after any existing system context)
  output.messages.unshift({
    info: { role: 'user', synthetic: true, ... },
    parts: [{ type: 'text', text: contextMessage }]
  })
}
```

**Context XML Format** (per SPEC):
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
    <!-- Current working context -->
  </child>
</frame>
```

### 2.5 Frame Controller

**SPEC Requirement**: Handle push/pop commands (human or agent-initiated)

**OpenCode Features Used**:
- Custom commands via `.opencode/command/` directory
- `Session.create({ parentID })` - create child sessions
- `session.created` event - detect new sessions
- `session.idle` event - detect session completion
- SDK client API for session management

**Design**:
The Frame Controller exposes commands and handles frame lifecycle:

**Commands** (implemented as custom OpenCode commands):

`/flame-push <goal>` - Create new child frame
```typescript
// .opencode/command/flame-push.md
---
description: Create a new child frame for a subtask
agent: build
---
The user wants to push a new frame for: $ARGUMENTS
Create a child session and initialize frame state.
```

`/flame-pop [status]` - Complete current frame and return to parent
```typescript
// Triggers compaction, persists log, returns to parent session
```

`/flame-plan <goal1> | <goal2> | ...` - Sketch planned frames
```typescript
// Creates planned (not yet active) child frames
```

`/flame-status` - Show current frame tree
```typescript
// Renders ASCII tree of frame hierarchy with statuses
```

**Agent-Initiated Control**:
The Frame Controller can also be exposed as a tool, allowing the agent to autonomously decide when to push/pop:

```typescript
const FlameControlTool = Tool.define("flame_control", () => ({
  description: "Manage hierarchical frame stack for task organization",
  parameters: z.object({
    action: z.enum(['push', 'pop', 'status']),
    goal: z.string().optional(),
    status: z.enum(['completed', 'failed', 'blocked']).optional()
  }),
  async execute(args, ctx) {
    // Implementation
  }
}))
```

### 2.6 Plan Manager

**SPEC Requirement**: Handle planned frames, cascade invalidation

**OpenCode Features Used**:
- Plugin storage for planned frame state
- Event system for invalidation propagation

**Design**:
Planned frames are frames that exist in metadata but don't have corresponding OpenCode sessions yet:

```typescript
interface PlannedFrame {
  id: string
  parentID: string
  goal: string
  status: 'planned'
  plannedChildren: PlannedFrame[]
}
```

When a planned frame is activated (user/agent starts working on it):
1. Create actual OpenCode session
2. Move from planned state to active state
3. Initialize frame metadata

When a frame is invalidated:
1. Mark all planned descendants as invalidated
2. Emit events for UI update
3. Keep invalidated frames visible (but clearly marked) for context

---

## 3. Data Flow

### 3.1 Push Flow (Creating Child Frame)

```
User: /flame-push "Implement user authentication"
  |
  v
[Frame Controller]
  |-- Create child session: Session.create({ parentID: currentSession })
  |-- Initialize frame metadata in plugin storage
  |-- Emit 'flame.frame.pushed' event
  v
[OpenCode]
  |-- session.created event
  |-- TUI navigates to child session
  v
[Context Assembler]
  |-- Next LLM call includes parent compaction as context
```

### 3.2 Pop Flow (Completing Frame)

```
User: /flame-pop completed
  |
  v
[Frame Controller]
  |-- Trigger compaction: SessionCompaction.create()
  v
[Compaction Generator] (via hook)
  |-- Custom prompt generates frame-aware summary
  |-- Summary stored in frame metadata
  v
[Log Persistence]
  |-- Export full session history to log file
  |-- Update log path in metadata
  v
[Frame Controller]
  |-- Update frame status to 'completed'
  |-- Emit 'flame.frame.popped' event
  |-- Switch to parent session
  v
[Parent Context]
  |-- Next LLM call in parent includes child's compaction summary
```

### 3.3 Context Assembly Flow (Every LLM Call)

```
User message in session_B1
  |
  v
[experimental.chat.messages.transform hook]
  |
  v
[Context Assembler]
  |-- Get current frame (B1)
  |-- Walk ancestors: B1 -> B -> Root
  |-- Get ancestor compactions: B's goal, Root's goal
  |-- Get sibling compactions: A's completed summary
  |-- Build context XML
  |
  v
[Modified messages]
  [0] Flame context XML (synthetic)
  [1] B1's own message history
  [2] User's new message
  |
  v
[LLM Call]
  Context = Flame XML + B1 history + new message
  (NOT: Root history + A history + B history + B1 history)
```

---

## 4. Key Design Decisions

### 4.1 Sessions vs. Custom Frame Storage

**Decision**: Use OpenCode sessions as the primary structure, augment with plugin storage.

**Rationale**:
- Sessions already have parent/child relationships
- Sessions have navigation (Leader+Right/Left to cycle)
- Reuses message storage, compaction, summarization
- No need to duplicate complex message handling

**Trade-off**: Coupling to OpenCode's session model. If session semantics change, Flame needs updating.

### 4.2 Compaction Hook vs. Custom Compaction

**Decision**: Use `experimental.session.compacting` hook to customize, not replace compaction.

**Rationale**:
- OpenCode's compaction already handles token counting, LLM calls
- Hook allows frame-specific prompts without reimplementing
- Preserves compatibility with other compaction features

**Trade-off**: Dependent on experimental hook stability.

### 4.3 Context Injection Point

**Decision**: Use `experimental.chat.messages.transform` to prepend context.

**Rationale**:
- Runs right before LLM call
- Can modify full message array
- Synthetic messages blend naturally

**Alternative Considered**: Modifying system prompt via `experimental.chat.system.transform`. Rejected because context hierarchy is more naturally expressed as conversation context than system instructions.

### 4.4 Agent Autonomy Level

**Decision**: Support both explicit commands AND agent-initiated frame control.

**Rationale**:
- Users may want full control (explicit /push /pop)
- Power users may want agent to decide (autonomy mode)
- SPEC mentions both human and agent control

**Implementation**:
- Frame control exposed as both command and tool
- Config option: `flame.agent_autonomy: 'off' | 'suggest' | 'autonomous'`
  - `off`: Agent cannot push/pop, only suggest
  - `suggest`: Agent can use tool but requires confirmation
  - `autonomous`: Agent makes frame decisions

### 4.5 Log Format and Location

**Decision**: Markdown logs in `.opencode/flame/logs/`

**Rationale**:
- Human-readable
- Can be opened in editors
- Git-friendly (optional version control)
- Similar to existing OpenCode patterns (.opencode/ directory)

**Trade-off**: More storage than minimal format. Acceptable for recoverability.

---

## 5. Open Questions

### 5.1 Session Navigation Integration

OpenCode has Leader+Right/Left to cycle child sessions. How does this interact with frame navigation?

**Options**:
- Reuse existing navigation (frames ARE sessions)
- Add frame-specific navigation commands
- Both

**Recommendation**: Reuse existing + add `/flame-tree` visual navigator.

### 5.2 Compaction Depth Control

When building context, how many ancestor levels should be included?

**Options**:
- All ancestors (full path to root)
- N most recent ancestors (configurable)
- Token-budget-based (include as much as fits)

**Recommendation**: Token-budget-based with minimum of 2 ancestors.

### 5.3 Sibling Inclusion Strategy

Should ALL sibling compactions be included, or just relevant ones?

**Options**:
- All siblings (comprehensive)
- Only completed siblings (avoid noise from planned/failed)
- Recency-based (N most recent siblings)

**Recommendation**: Start with completed siblings only, make configurable.

### 5.4 Invalidation Semantics

When a frame is invalidated, what happens to its child sessions/logs?

**Options**:
- Keep everything (for potential recovery)
- Mark as invalidated but preserve
- Delete after confirmation

**Recommendation**: Mark as invalidated, preserve logs, hide from default view.

### 5.5 Multi-Session Coordination

OpenCode can have multiple sessions in parallel. How does Flame handle:
- Multiple active frames from same parent?
- Concurrent work in sibling frames?

**Recommendation**: Defer multi-session coordination to V2. Initial implementation assumes single active frame at a time.

### 5.6 Hook Stability

Several hooks used are marked `experimental.*`. What's the stability commitment?

**Risk**: Hooks may change or be removed.

**Mitigation**:
- Implement adapters that abstract hook APIs
- Engage with OpenCode maintainers on stabilization
- Fall back to SDK/Server API if hooks become unreliable

---

## 6. Implementation Phases

### Phase 1: Core Frame Management
- Frame State Manager with plugin storage
- Basic /flame-push and /flame-pop commands
- Session creation with parent linkage

### Phase 2: Context Assembly
- Ancestor compaction retrieval
- Context XML generation
- messages.transform hook integration

### Phase 3: Compaction Integration
- Custom compaction prompts
- Log persistence
- Summary storage

### Phase 4: Planning & Invalidation
- Planned frame support
- Invalidation cascade
- Frame tree visualization

### Phase 5: Agent Autonomy
- Frame control as tool
- Heuristics for auto-push/pop
- Configuration options

---

## 7. Conclusion

This proposal leverages OpenCode's existing session hierarchy and extensibility hooks to implement Flame Graph Context Management. The key insight is that OpenCode sessions already function as proto-frames; Flame adds the state management, context assembly, and navigation to realize the full SPEC vision.

The architecture prioritizes:
1. **Non-invasive integration** via hooks and events
2. **Reuse of OpenCode primitives** (sessions, compaction, storage)
3. **Progressive enhancement** (phases from basic to autonomous)
4. **Recoverability** (full logs, no data loss)

Open questions remain around navigation UX, sibling strategies, and hook stability, but the fundamental approach is sound and implementable with current OpenCode APIs.
