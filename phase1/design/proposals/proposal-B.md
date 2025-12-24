# Flame Graph Context Management: Architecture Proposal B

## Executive Summary

This proposal outlines an architecture for implementing tree-structured context management (Flame Graph) as an OpenCode plugin. The design leverages OpenCode's existing parent/child session model as the foundational primitive, extends the compaction system to generate frame summaries, and introduces a custom context assembly mechanism through plugin hooks.

The key insight driving this architecture: **OpenCode sessions already form trees via `parentID`**. Frames are sessions. The work is primarily extending session metadata, hooking into compaction, and controlling context assembly.

---

## Part 1: Core Architecture

### 1.1 Frames Are Sessions

OpenCode already supports:
- Session creation with optional `parentID` (see `Session.create()`)
- Session child retrieval via `Session.children()`
- Session parent access via `session.parentID`
- Hierarchical deletion that cascades to children

**Design Decision**: Rather than introduce a parallel "frame" abstraction, we redefine sessions AS frames. Each session gains frame-specific metadata through session state extensions.

```
Session.Info extended with:
  - frame: {
      status: "planned" | "in_progress" | "completed" | "failed" | "blocked" | "invalidated"
      goal: string
      summary?: string        // Generated on completion
      artifacts?: string[]    // Files created/modified
      decisions?: string[]    // Key choices made
      logPath?: string        // Path to full log file
    }
```

### 1.2 Plugin as Orchestration Layer

The plugin acts as an orchestration layer that:
1. **Intercepts session lifecycle events** (`session.created`, `session.compacted`, etc.)
2. **Manages frame state transitions** (pending -> in_progress -> completed)
3. **Generates compaction summaries** using the existing compaction machinery
4. **Assembles context** by intercepting message processing

The plugin does NOT replace OpenCode's core session machinery but wraps and extends it.

---

## Part 2: Component Mapping

### 2.1 Frame State Manager

**OpenCode Foundation**: Session storage system (`Storage.read/write/update`)

**Implementation Approach**:
- Store frame state alongside session data
- Create `FrameStateManager` class within the plugin that:
  - Tracks all sessions as frames
  - Maintains frame tree topology
  - Handles status transitions with validation
  - Propagates invalidation to descendants

**Plugin Integration Point**: `session.created` event handler

```typescript
// Within plugin hook
async "session.created"({ event }) {
  const session = event.properties.info
  await FrameStateManager.initFrame(session.id, {
    status: session.parentID ? "planned" : "in_progress",
    goal: session.title
  })
}
```

### 2.2 Log Persistence Layer

**OpenCode Foundation**:
- Message storage (`Storage.list(["message", sessionID])`)
- Session messages streaming (`Session.messages()`)

**Implementation Approach**:
- Log files are already implicitly persisted as session messages in storage
- On frame completion, export the full message history to a dedicated log file
- Store log path in frame metadata for reference in compactions

**Key Consideration**: OpenCode stores messages as structured JSON. For human readability, export to markdown format:

```markdown
# Frame Log: Build Authentication System
Session ID: ses_abc123
Parent: ses_root
Created: 2024-01-15T10:30:00Z
Completed: 2024-01-15T11:45:00Z

## Conversation

### User
Implement JWT authentication...

### Assistant
I'll start by creating the auth middleware...
[Tool: write] src/middleware/auth.ts
...
```

**Plugin Integration Point**: Frame completion handler (custom, triggered on status transition)

### 2.3 Compaction Generator

**OpenCode Foundation**:
- `SessionCompaction.process()` - generates continuation summaries
- `experimental.session.compacting` hook - allows prompt customization
- Built-in compaction agent with customizable prompt

**Implementation Approach**:
- Hook into `experimental.session.compacting` to inject frame-aware context
- When a frame completes, trigger a specialized compaction pass
- Store the generated summary in frame metadata

**Critical Design Choice**: Use OpenCode's existing compaction machinery rather than building a parallel system. The compaction prompt can be fully replaced via `output.prompt`:

```typescript
async "experimental.session.compacting"(input, output) {
  const frame = await FrameStateManager.getFrame(input.sessionID)

  if (frame.status === "completing") {
    // Frame completion compaction - summarize for parent
    output.prompt = FRAME_COMPLETION_PROMPT
    output.context.push(`Frame goal: ${frame.goal}`)
  } else {
    // Normal continuation compaction - include frame context
    output.context.push(await ContextAssembler.getFrameContext(input.sessionID))
  }
}
```

### 2.4 Context Assembler

**OpenCode Foundation**:
- `MessageV2.toModelMessage()` - converts stored messages to LLM format
- `MessageV2.filterCompacted()` - filters to messages since last compaction
- `experimental.chat.messages.transform` hook - transforms messages before LLM call

**Implementation Approach**:
The Context Assembler builds the active context by:
1. Starting with current frame's working history (default behavior)
2. Prepending ancestor frame compactions (root -> ... -> parent)
3. Including sibling frame compactions (completed siblings only)

**Plugin Integration Point**: `experimental.chat.messages.transform`

```typescript
async "experimental.chat.messages.transform"(input, output) {
  const frameContext = await ContextAssembler.build(currentSessionID)

  // Inject frame tree context at the start
  output.messages.unshift({
    info: {
      id: "frame_context",
      role: "user",
      sessionID: currentSessionID,
      time: { created: Date.now() }
    },
    parts: [{
      type: "text",
      text: frameContext.toXML()
    }]
  })
}
```

**Context Format** (XML structure from SPEC):
```xml
<frame_context>
  <ancestor id="root" status="in_progress">
    <goal>Build the application</goal>
  </ancestor>
  <ancestor id="auth" status="completed">
    <summary>Implemented JWT-based auth with refresh tokens.</summary>
    <artifacts>src/auth/*, src/models/User.ts</artifacts>
    <log>./logs/frame-auth.md</log>
  </ancestor>
  <sibling id="api" status="completed">
    <summary>Created REST API endpoints for user management.</summary>
  </sibling>
  <current id="frontend" status="in_progress">
    <goal>Build React frontend</goal>
  </current>
</frame_context>
```

### 2.5 Frame Controller

**OpenCode Foundation**:
- Custom commands via `Command` system
- Custom tools via plugin `tool` hook
- TUI integration via SDK client

**Implementation Approach**:
Create custom commands for frame control:

| Command | Action |
|---------|--------|
| `/push <goal>` | Create child frame, transition to in_progress |
| `/pop [status]` | Complete current frame, return to parent |
| `/plan <goal>` | Create planned child frame |
| `/status` | Show frame tree visualization |
| `/frame <id>` | Navigate to specific frame |

**Plugin Integration**:
```typescript
// Commands defined in .opencode/command/
// e.g., .opencode/command/push.md

// OR via SDK client in plugin:
return {
  tool: {
    frame_push: tool({
      description: "Push a new frame onto the context stack",
      args: { goal: tool.schema.string() },
      async execute(args, ctx) {
        const childSession = await ctx.client.session.create({
          body: { parentID: ctx.sessionID, title: args.goal }
        })
        await FrameStateManager.initFrame(childSession.id, {
          status: "in_progress",
          goal: args.goal
        })
        return { output: `Created frame: ${childSession.id}` }
      }
    })
  }
}
```

### 2.6 Plan Manager

**OpenCode Foundation**:
- Session creation with `parentID`
- Session deletion with cascade to children

**Implementation Approach**:
- Planned frames are sessions with frame status "planned"
- No conversation happens until frame transitions to "in_progress"
- Invalidation cascades via tree traversal

**Key Operations**:
```typescript
class PlanManager {
  async plan(parentID: string, goal: string): Promise<Frame> {
    const session = await Session.create({ parentID, title: goal })
    await FrameStateManager.initFrame(session.id, {
      status: "planned",
      goal
    })
    return session
  }

  async invalidate(frameID: string): Promise<void> {
    await FrameStateManager.updateFrame(frameID, { status: "invalidated" })
    const children = await Session.children(frameID)
    for (const child of children) {
      await this.invalidate(child.id)  // Cascade
    }
  }

  async activate(frameID: string): Promise<void> {
    const frame = await FrameStateManager.getFrame(frameID)
    if (frame.status !== "planned") {
      throw new Error("Can only activate planned frames")
    }
    await FrameStateManager.updateFrame(frameID, { status: "in_progress" })
  }
}
```

---

## Part 3: Data Flow

### 3.1 Push Operation

```
User: /push "Implement caching layer"
          |
          v
    FrameController.push("Implement caching layer")
          |
          v
    Session.create({ parentID: currentSession.id })
          |
          v
    FrameStateManager.initFrame(newSessionID, {
      status: "in_progress",
      goal: "Implement caching layer"
    })
          |
          v
    TUI switches to new session (via SDK)
          |
          v
    User works in new frame context
```

### 3.2 Pop Operation (Completion)

```
User: /pop completed
          |
          v
    FrameController.pop("completed")
          |
          v
    FrameStateManager.updateFrame(currentFrame, { status: "completing" })
          |
          v
    LogPersistence.export(currentSession) -> ./logs/frame-xyz.md
          |
          v
    CompactionGenerator.summarize(currentSession)
      - Intercepts via experimental.session.compacting hook
      - Uses frame completion prompt
      - Generates: { summary, artifacts, decisions }
          |
          v
    FrameStateManager.updateFrame(currentFrame, {
      status: "completed",
      summary: generatedSummary,
      artifacts: extractedArtifacts,
      logPath: "./logs/frame-xyz.md"
    })
          |
          v
    TUI switches to parent session
          |
          v
    ContextAssembler includes child's compaction in parent's context
```

### 3.3 Context Assembly (On Each LLM Call)

```
SessionPrompt.loop() triggers message processing
          |
          v
    experimental.chat.messages.transform hook fires
          |
          v
    ContextAssembler.build(currentSessionID)
          |
          +---> Get current frame info
          |
          +---> Walk to root, collect ancestor compactions
          |
          +---> Get completed sibling compactions
          |
          +---> Format as XML
          |
          v
    Inject frame context into messages
          |
          v
    LLM receives: [frame_context, ...current_frame_messages]
```

---

## Part 4: Key Design Decisions

### 4.1 Frames as Sessions vs. Separate Abstraction

**Decision**: Frames ARE sessions with extended metadata

**Trade-offs**:
- (+) Leverages existing session infrastructure
- (+) Automatic TUI/SDK support
- (+) Existing storage, events, persistence
- (-) Session concept slightly overloaded
- (-) May conflict with other session uses

### 4.2 Frame State Storage Location

**Options**:
1. Extend `Session.Info` schema (requires OpenCode core changes)
2. Parallel storage under `["frame_state", sessionID]` (plugin-only)
3. Session metadata extension field

**Decision**: Option 2 - Parallel storage

**Rationale**: Plugin should not require core changes. Frame state is stored alongside but separately from session data.

### 4.3 Compaction Trigger

**Options**:
1. Automatic on token overflow (existing behavior)
2. Explicit on frame pop
3. Both

**Decision**: Both, with different prompts

- **Overflow compaction**: Uses continuation-focused prompt (existing behavior, with frame context injected)
- **Frame completion compaction**: Uses summary-focused prompt (captures artifacts, decisions for parent)

### 4.4 Context Injection Strategy

**Options**:
1. Inject as system prompt
2. Inject as user message at conversation start
3. Inject as synthetic user message before each LLM call

**Decision**: Option 3 - Per-LLM-call injection via `experimental.chat.messages.transform`

**Rationale**:
- System prompts are already long; additional context risks being ignored
- Frame context may change between LLM calls (sibling completion)
- Placed as first user message provides clear separation

### 4.5 Subagent Integration

**Consideration**: OpenCode's `TaskTool` already creates child sessions for subagent work.

**Decision**: Treat subagent sessions as automatic frame pushes

When `TaskTool` creates a child session, the frame plugin automatically:
- Creates a frame entry with status "in_progress"
- Sets goal from task description
- On subagent completion, triggers frame completion flow

This unifies manual and automatic child session creation under the frame model.

---

## Part 5: Open Questions

### 5.1 Frame Visualization

How should the frame tree be visualized in the TUI?

**Options**:
- Sidebar tree view (like file explorer)
- Status command output (text-based tree)
- Header breadcrumb (root > auth > login)

**Recommendation**: Start with `/status` command, add TUI integration later via custom component plugin if possible.

### 5.2 Cross-Talk Granularity

SPEC mentions including sibling compactions. Should we include:
- All completed siblings?
- Only most recent N siblings?
- Only siblings completed after current frame started?

**Recommendation**: Start with all completed siblings. Add filtering if context becomes too large.

### 5.3 Frame Navigation UX

How should users navigate between frames?

- Dedicated `/frame <id>` command?
- Integrate with existing session switcher (Ctrl+O)?
- Keyboard shortcuts for parent/child?

**Recommendation**: Leverage existing `session_child_cycle` keybinds, add `/frame` command for specific navigation.

### 5.4 Agent-Initiated Push/Pop

SPEC allows agents to autonomously push/pop frames. How to implement?

**Options**:
1. Custom tool `frame_push`/`frame_pop` available to agent
2. Heuristic detection in plugin (tool failures trigger push suggestion)
3. Meta-agent that monitors and manages frames

**Recommendation**: Start with custom tools. Agent already uses `task` tool for subagents; `frame_push` follows same pattern.

### 5.5 Persistence Format for Logs

What format for exported frame logs?

**Options**:
- Markdown (human readable)
- JSON (structured, queryable)
- Both (md for browsing, json for machine access)

**Recommendation**: Markdown primary, with machine-readable metadata in frontmatter.

### 5.6 Hook Stability

Several plugin hooks are marked `experimental`:
- `experimental.session.compacting`
- `experimental.chat.messages.transform`
- `experimental.text.complete`

**Risk**: These APIs may change.

**Mitigation**:
- Abstract hook usage behind internal interfaces
- Monitor OpenCode releases for breaking changes
- Propose stabilization of critical hooks to OpenCode team

---

## Part 6: Implementation Phases

### Phase 1: Foundation (Frame State + Commands)
- Implement `FrameStateManager` with parallel storage
- Create `/push`, `/pop`, `/status` commands
- Basic frame lifecycle (create, complete, navigate)

### Phase 2: Context Assembly
- Implement `ContextAssembler`
- Hook into `experimental.chat.messages.transform`
- Generate and inject frame context XML

### Phase 3: Compaction Integration
- Hook into `experimental.session.compacting`
- Implement frame completion summaries
- Store summaries in frame metadata

### Phase 4: Log Persistence
- Export complete frame logs on completion
- Store log paths in frame metadata
- Allow browsing via command or tool

### Phase 5: Plan Management
- Implement planned frame status
- Invalidation cascade
- Plan visualization in `/status`

### Phase 6: Subagent Integration
- Detect TaskTool child session creation
- Auto-create frame entries
- Handle subagent completion as frame completion

---

## Summary

This architecture treats OpenCode sessions as the foundational primitive for frames, extending them with frame-specific metadata stored in parallel. The plugin orchestrates frame lifecycle through event handlers, controls context assembly via message transformation hooks, and generates summaries through the existing compaction system.

Key strengths:
- Minimal changes to OpenCode core
- Leverages existing session, storage, and compaction infrastructure
- Clean separation between frame orchestration (plugin) and session mechanics (core)
- Incremental implementability

Key risks:
- Dependency on experimental hooks
- Potential conflicts with other session-based features
- Context size management at scale

The approach prioritizes pragmatic integration with OpenCode's existing architecture while providing the tree-structured context management that SPEC.md describes.
