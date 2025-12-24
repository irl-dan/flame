# Flame Graph Context Management - Architecture Proposal C

## Executive Summary

This proposal outlines a high-level architecture for implementing Flame Graph Context Management as an OpenCode plugin. The core insight is that OpenCode already has a nascent tree structure through its parent/child session model and the `task` tool for subagent invocation. Flame extends this by making the tree structure explicit, adding frame semantics (push/pop), and implementing intelligent context assembly that includes compacted sibling summaries alongside ancestor context.

## 1. Core Architecture: Frames as Enhanced Sessions

### 1.1 The Frame Concept

A **Frame** in Flame maps directly to an OpenCode **Session**, but with enhanced metadata and explicit tree semantics:

```
Frame = OpenCode Session + {
  status: "planned" | "in_progress" | "completed" | "failed" | "blocked" | "invalidated"
  goal: string              // What this frame aims to accomplish
  compaction: string        // LLM-generated summary (on completion)
  artifacts: string[]       // Key files/outputs produced
  logPath: string           // Full conversation log file path
}
```

OpenCode sessions already support:
- `parentID` field linking child to parent sessions
- `session.children()` API to retrieve child sessions
- The `task` tool which creates child sessions for subagents

Flame enhances this with explicit frame lifecycle management and cross-sibling context sharing.

### 1.2 Tree Structure Realization

The session hierarchy already exists in OpenCode:
- Sessions have optional `parentID`
- The `task` tool creates child sessions via `Session.create({ parentID: ctx.sessionID })`
- Sessions store messages and parts in a linear sequence per session

Flame adds:
- Explicit "planned" frames that exist before execution
- Frame status tracking beyond OpenCode's implicit states
- Bidirectional navigation (siblings, not just parent/children)
- Cascade invalidation for planned frames

## 2. Component Mapping

### 2.1 Frame State Manager

**OpenCode Foundation:**
- `Session` namespace provides CRUD operations
- Storage system persists session data as JSON files
- Bus system publishes session events (`session.created`, `session.updated`, etc.)

**Flame Extension:**
```
FrameStateManager = {
  frames: Map<sessionID, FrameMetadata>
  tree: {
    root: sessionID
    current: sessionID
    planned: Map<sessionID, PlannedFrame[]>
  }
}
```

**Implementation Approach:**
- Store frame metadata alongside session data using Storage API
- Track additional frame state in plugin memory
- Persist frame tree to `.opencode/flame/frames.json`
- Subscribe to session events to keep frame state synchronized

### 2.2 Log Persistence Layer

**OpenCode Foundation:**
- Sessions store messages in `["message", sessionID, messageID]` storage paths
- Parts (text, tools, files) stored in `["part", messageID, partID]` paths
- Full conversation history accessible via `Session.messages()`

**Flame Extension:**
- Export complete frame conversation to Markdown file on pop
- Store in `.opencode/flame/logs/frame-{id}.md`
- Include structured metadata header (goal, status, artifacts, timing)

**Implementation Approach:**
- Hook into `session.idle` event to detect frame completion
- Use `Session.messages()` to retrieve full history
- Format as readable Markdown with tool call details preserved
- Store reference path in frame metadata

### 2.3 Compaction Generator

**OpenCode Foundation:**
- `SessionCompaction` namespace handles context summarization
- `experimental.session.compacting` hook allows customization
- Compaction generates continuation prompts when context overflows

**Flame Extension:**
- Generate frame-completion summaries distinct from overflow compaction
- Produce structured summaries: status, artifacts, decisions, log pointer
- Format in XML for injection into parent context

**Implementation Approach:**
```typescript
"experimental.session.compacting": async (input, output) => {
  if (isFrameCompletion(input.sessionID)) {
    output.prompt = FLAME_COMPACTION_PROMPT
    // Custom prompt focused on frame summary rather than continuation
  }
}
```

**Alternative:** Create dedicated summarization via LLM call on frame pop, independent of OpenCode's compaction system. This gives more control over summary format.

### 2.4 Context Assembler

**OpenCode Foundation:**
- `SystemPrompt` namespace builds system prompts with environment, custom instructions
- `MessageV2.toModelMessage()` converts session messages to LLM format
- `experimental.chat.messages.transform` hook allows message modification
- `experimental.chat.system.transform` hook allows system prompt modification

**Flame Extension:**
- Build context from: current frame history + ancestor compactions + sibling compactions
- Inject frame context as XML system prompt prefix
- Filter out full sibling histories (only include compactions)

**Implementation Approach:**
```typescript
"experimental.chat.system.transform": async (input, output) => {
  const frameContext = await buildFrameContext(currentSession)
  output.system.unshift(frameContext)
}

"experimental.chat.messages.transform": async (input, output) => {
  // Current frame messages stay unchanged
  // Add compaction summaries as synthetic preamble messages
  const preamble = await buildContextPreamble(currentSession)
  output.messages.unshift(...preamble)
}
```

### 2.5 Frame Controller

**OpenCode Foundation:**
- Commands defined in `.opencode/command/` directories
- Commands can trigger agent invocations, model switches
- `SessionPrompt.command()` executes command templates
- TUI integration via `tui.command.execute` events

**Flame Extension:**
- `/push <goal>` - Create child frame and switch to it
- `/pop [status]` - Complete current frame, return to parent
- `/plan <goal>` - Create planned (non-active) child frame
- `/status` - Display frame tree with current position
- `/frame <id>` - Navigate to specific frame

**Implementation Approach:**
Commands as Markdown files with custom execution logic:
```markdown
---
description: Push a new frame onto the context stack
agent: build
---

Create a new focused context frame for: $ARGUMENTS
```

Plus plugin hooks to intercept and implement frame semantics.

### 2.6 Plan Manager

**OpenCode Foundation:**
- TodoWrite tool tracks task lists per session
- Todo state persisted and displayed in TUI
- Sessions can exist before receiving messages

**Flame Extension:**
- Planned frames are sessions with `status: "planned"` in frame metadata
- No messages until "started"
- Tree structure allows nested planned frames
- Invalidation cascades: invalidating parent invalidates children

**Implementation Approach:**
- Create sessions with special marker in title or custom storage
- Track planned vs active status in FrameStateManager
- Implement cascade invalidation as plugin logic
- Potentially visualize plans in TUI via custom rendering

## 3. Data Flow

### 3.1 Push Operation

```
User: /push "Implement authentication"
  |
  v
1. FrameController intercepts command
2. Generate goal summary from arguments
3. Create child session via Session.create({ parentID: currentSession })
4. Initialize FrameMetadata { status: "in_progress", goal: "..." }
5. Store frame metadata to disk
6. Switch current frame to new session
7. Context Assembler builds initial context:
   - Parent compaction (if available)
   - Grandparent compactions
   - Sibling compactions (completed siblings)
8. New session begins with rich context preamble
```

### 3.2 Pop Operation

```
User: /pop completed
  |
  v
1. FrameController intercepts command
2. Trigger Compaction Generator:
   a. Call LLM with frame history + summary prompt
   b. Generate structured summary (status, artifacts, decisions)
   c. Store in frame metadata
3. Log Persistence Layer:
   a. Export full conversation to Markdown
   b. Store at .opencode/flame/logs/frame-{id}.md
   c. Record path in metadata
4. Update frame status to "completed"
5. Switch current frame to parent session
6. Inject compaction into parent context:
   a. Add as synthetic message or system prompt addendum
   b. Parent now has summarized view of child's work
```

### 3.3 Context Assembly (per LLM call)

```
LLM Request for Frame B1 (child of B, sibling of B2)
  |
  v
1. Current frame history: B1's messages (full detail)
2. Ancestor chain compactions:
   - B's goal/status (in progress, so partial info)
   - Root's goal/status
3. Sibling compactions:
   - A's summary (completed, full compaction)
   - B2's summary (if completed) or goal (if planned)
4. Format as XML prefix:
   <flame_context>
     <frame id="root" status="in_progress">
       <goal>Build the application</goal>
       <child id="A" status="completed">
         <summary>Implemented auth...</summary>
         <log>./logs/frame-A.md</log>
       </child>
       <child id="B" status="in_progress">
         <goal>Build API routes</goal>
         <current>B1</current>
       </child>
     </frame>
   </flame_context>
5. Inject into system prompt or as user message preamble
```

## 4. Key Design Decisions

### 4.1 Session Reuse vs. New Primitives

**Decision:** Reuse OpenCode sessions as the frame primitive.

**Rationale:**
- Sessions already have parent/child relationships
- Storage, messaging, and event infrastructure is battle-tested
- The `task` tool already creates child sessions
- Less invasive to OpenCode codebase

**Trade-offs:**
- Coupled to session semantics (may need workarounds)
- Session titles/IDs may not map cleanly to frame semantics
- OpenCode session list may show all frames (could be noisy)

### 4.2 Context Injection Point

**Decision:** Use `experimental.chat.system.transform` for frame context injection.

**Rationale:**
- System prompt is the natural place for structural context
- Doesn't pollute message history
- Can be cached effectively (prompt caching)

**Trade-offs:**
- System prompt has token limits
- May need fallback to message-based injection for deep trees
- Less visible to user than inline messages

### 4.3 Compaction Timing

**Decision:** Generate compaction on explicit pop, not on context overflow.

**Rationale:**
- Frame boundaries are semantic, not just token-based
- User controls when a frame is "complete"
- Cleaner separation from OpenCode's auto-compaction

**Trade-offs:**
- May still hit context limits within a frame
- Need to handle interaction with auto-compaction gracefully
- Two compaction mechanisms could confuse users

### 4.4 Log Format

**Decision:** Markdown with YAML frontmatter for frame logs.

**Rationale:**
- Human-readable and browseable
- Can include tool outputs, code blocks naturally
- Compatible with documentation and RAG systems

**Trade-offs:**
- Not queryable like a database
- Large logs may be slow to parse
- Need structured extraction for metadata

### 4.5 Planned Frame Representation

**Decision:** Planned frames are sessions with empty message history.

**Rationale:**
- Consistent with frame-as-session model
- Can be "started" by simply adding messages
- Already supported by OpenCode session creation

**Trade-offs:**
- Empty sessions may trigger edge cases
- Session list shows planned frames as equal to active ones
- May need filtering in UI

## 5. Plugin Hook Utilization

| Hook | Purpose |
|------|---------|
| `event` | Track session lifecycle (created, idle, deleted) |
| `tool` | Custom tools: `flame_status`, `flame_navigate` |
| `experimental.chat.system.transform` | Inject frame context into system prompt |
| `experimental.chat.messages.transform` | Add compaction preambles to message history |
| `experimental.session.compacting` | Customize compaction for frame completion |
| `tool.execute.before` | Track tool usage for artifact detection |
| `tool.execute.after` | Record tool outputs for logging |

## 6. Open Questions

### 6.1 Integration with Existing Subagent Flow

The `task` tool already creates child sessions. How should Flame integrate?
- Option A: Wrap task tool calls in frame semantics automatically
- Option B: Provide parallel `/push` flow, leave task tool unchanged
- Option C: Modify task tool to use Flame frames

### 6.2 UI/TUI Representation

How should the frame tree be visualized?
- Tree view in session selector?
- Breadcrumb in prompt area?
- Dedicated `/status` output format?

### 6.3 Cross-Session Navigation

When popping to a parent, how is the TUI notified?
- Use existing session switching mechanisms?
- Need new events for frame navigation?

### 6.4 Persistence Across Restarts

How should frame state persist if OpenCode restarts mid-tree?
- Store frame tree in `.opencode/flame/state.json`
- Reconstruct from session parentID relationships?
- Handle orphaned frames?

### 6.5 Token Budget Management

How to handle deep trees where compaction summaries exceed token budget?
- Truncate older sibling compactions?
- Hierarchical compaction (compact the compactions)?
- User-configurable depth limits?

### 6.6 Interaction with OpenCode Auto-Compaction

What happens when OpenCode's context overflow triggers while inside a frame?
- Let OpenCode compact, treat as internal frame event?
- Disable auto-compaction within Flame-managed sessions?
- Combine with frame compaction somehow?

## 7. Implementation Phases (High-Level)

### Phase 1: Core Frame Management
- FrameStateManager with in-memory state
- Basic /push and /pop commands
- Simple context injection (goals only)

### Phase 2: Compaction and Logging
- Frame completion compaction
- Full log persistence
- Artifact detection

### Phase 3: Context Assembly
- Rich context with sibling compactions
- XML formatting
- Token budget management

### Phase 4: Planned Frames
- /plan command
- Cascade invalidation
- Status visualization

### Phase 5: Polish and Integration
- TUI enhancements
- Agent heuristics for auto-push
- Documentation and examples

## 8. Architectural Diagram

```
+------------------------------------------------------------------+
|                        Flame Plugin                               |
+------------------------------------------------------------------+
|                                                                   |
|   +-------------------+       +---------------------+             |
|   | Frame State       |       | Context Assembler   |             |
|   | Manager           |<----->| (system.transform)  |             |
|   | - tree structure  |       | - ancestor comps    |             |
|   | - current frame   |       | - sibling comps     |             |
|   | - planned frames  |       | - current history   |             |
|   +-------------------+       +---------------------+             |
|           ^                           ^                           |
|           |                           |                           |
|           v                           v                           |
|   +-------------------+       +---------------------+             |
|   | Frame Controller  |       | Compaction          |             |
|   | - /push, /pop     |       | Generator           |             |
|   | - /plan, /status  |       | - frame summaries   |             |
|   +-------------------+       +---------------------+             |
|           |                           |                           |
|           v                           v                           |
|   +-------------------+       +---------------------+             |
|   | Plan Manager      |       | Log Persistence     |             |
|   | - cascade inval.  |       | Layer               |             |
|   | - status tracking |       | - markdown export   |             |
|   +-------------------+       +---------------------+             |
|                                                                   |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                     OpenCode Core                                 |
+------------------------------------------------------------------+
|                                                                   |
|   +------------+  +------------+  +------------+  +------------+  |
|   | Session    |  | Storage    |  | Bus        |  | Agent      |  |
|   | - CRUD     |  | - JSON     |  | - events   |  | - configs  |  |
|   | - parent/  |  | - files    |  | - pub/sub  |  | - prompts  |  |
|   |   child    |  +------------+  +------------+  +------------+  |
|   +------------+                                                  |
|                                                                   |
|   +------------+  +------------+  +------------+                  |
|   | Tool       |  | Command    |  | Plugin     |                  |
|   | Registry   |  | Execution  |  | System     |                  |
|   +------------+  +------------+  +------------+                  |
|                                                                   |
+------------------------------------------------------------------+
```

## 9. Summary

This proposal leverages OpenCode's existing session hierarchy as the foundation for Flame's frame tree structure. Key innovations include:

1. **Frame = Enhanced Session** - Minimal new primitives, maximum reuse
2. **Plugin-Based Implementation** - Uses hooks, not core modifications
3. **Structured Context Injection** - XML-formatted frame context in system prompts
4. **Explicit Frame Lifecycle** - User-controlled push/pop with semantic status
5. **Cross-Sibling Context** - Compactions flow to siblings, not just descendants

The architecture maintains OpenCode's existing capabilities while adding the structural memory and context isolation that Flame's flame graph model provides.
