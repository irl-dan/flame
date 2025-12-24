# Flame Graph Context Management: Proposal Synthesis

This document synthesizes three independent implementation proposals for Flame Graph Context Management and provides research findings from the OpenCode codebase to guide architectural decisions.

---

## 1. Consensus Summary

All three proposals agree on these fundamental architectural points:

### 1.1 Frames as Enhanced Sessions

All proposals agree that frames should map directly to OpenCode sessions:

```
Frame = OpenCode Session + Frame Metadata
```

This leverages OpenCode's existing:
- `Session.Info.parentID` field for parent-child relationships
- `Session.children(parentID)` API for listing child sessions
- `Session.create({ parentID })` for creating hierarchical sessions
- Built-in navigation via `session_child_cycle` keybinds

**Evidence from OpenCode** (`/Users/sl/code/opencode/packages/opencode/src/session/index.ts`):
```typescript
export const create = fn(
  z.object({
    parentID: Identifier.schema("session").optional(),
    title: z.string().optional(),
  }).optional(),
  async (input) => {
    return createNext({
      parentID: input?.parentID,
      // ...
    })
  }
)
```

### 1.2 Plugin as Orchestration Layer

All proposals agree the implementation should be a plugin that:
- Intercepts session lifecycle events (`session.created`, `session.idle`, `session.compacted`)
- Manages frame state through plugin-managed storage
- Controls context assembly via hooks
- Provides custom commands (`/push`, `/pop`, `/status`, `/plan`)
- Does NOT require modifications to OpenCode core

### 1.3 Frame Metadata Structure

All proposals agree on similar frame metadata:

```typescript
interface FrameMetadata {
  sessionID: string
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked' | 'invalidated'
  goal: string
  artifacts: string[]
  decisions: string[]
  compactionSummary?: string
  logPath: string
}
```

### 1.4 Log Persistence

All proposals agree:
- Full frame logs are persisted to Markdown files on frame completion
- Logs are stored in `.opencode/flame/logs/` directory
- Log paths are referenced in compaction summaries
- Nothing is truly lost - full history is recoverable

### 1.5 Compaction Customization

All proposals leverage `experimental.session.compacting` hook to inject frame-aware prompts:

**Verified from OpenCode** (`/Users/sl/code/opencode/packages/plugin/src/index.ts`):
```typescript
"experimental.session.compacting"?: (
  input: { sessionID: string },
  output: { context: string[]; prompt?: string },
) => Promise<void>
```

**Usage from** (`/Users/sl/code/opencode/packages/opencode/src/session/compaction.ts`):
```typescript
const compacting = await Plugin.trigger(
  "experimental.session.compacting",
  { sessionID: input.sessionID },
  { context: [], prompt: undefined },
)
const defaultPrompt = "Provide a detailed prompt for continuing our conversation..."
const promptText = compacting.prompt ?? [defaultPrompt, ...compacting.context].join("\n\n")
```

### 1.6 XML Context Format (per SPEC)

All proposals adopt the SPEC's XML format for context structure:

```xml
<frame id="root" status="in_progress">
  <goal>Build the application</goal>
  <child id="A" status="completed">
    <summary>Implemented JWT-based auth...</summary>
    <artifacts>src/auth/*, src/models/User.ts</artifacts>
    <log>./logs/frame-A.md</log>
  </child>
  <child id="B" status="in_progress">
    <goal>Build API routes</goal>
  </child>
</frame>
```

### 1.7 TaskTool/Subagent Integration

All proposals recognize that OpenCode's `TaskTool` already creates child sessions:

**Verified from** (`/Users/sl/code/opencode/packages/opencode/src/tool/task.ts`):
```typescript
return await Session.create({
  parentID: ctx.sessionID,
  title: params.description + ` (@${agent.name} subagent)`,
})
```

All proposals suggest treating subagent-created sessions as automatic frame pushes.

---

## 2. Divergence Analysis

### 2.1 Context Injection Method

**The core question**: How should frame context be injected into LLM calls?

#### Option A: Message Prepend (Proposals A, B)

Use `experimental.chat.messages.transform` to prepend context as a synthetic user message.

```typescript
"experimental.chat.messages.transform": async (input, output) => {
  const frameContext = await buildFrameContext(currentSessionID)
  output.messages.unshift({
    info: { role: 'user', synthetic: true, ... },
    parts: [{ type: 'text', text: frameContext.toXML() }]
  })
}
```

**Pros**:
- Context is naturally part of conversation flow
- Updates per LLM call (fresh sibling compactions)
- Clearly separated from system prompt
- More visible/debuggable in message history

**Cons**:
- Adds to message count
- May be treated differently by models than system prompt
- Could be confusing if user inspects message history

#### Option B: System Prompt Modification (Proposal C)

Use `experimental.chat.system.transform` to inject context into system prompt.

```typescript
"experimental.chat.system.transform": async (input, output) => {
  const frameContext = await buildFrameContext(currentSession)
  output.system.unshift(frameContext)
}
```

**Pros**:
- Natural place for structural/meta context
- Better for prompt caching (stable prefix)
- Doesn't pollute message history
- Models typically give higher weight to system prompts

**Cons**:
- System prompts already long in OpenCode
- Token limits more critical in system prompt
- Less visible for debugging

**Research Finding**: Looking at how OpenCode handles system transforms (`/Users/sl/code/opencode/packages/opencode/src/session/llm.ts`):

```typescript
const system = SystemPrompt.header(input.model.providerID)
system.push([...])  // Agent prompts, custom prompts

const header = system[0]
const original = clone(system)
await Plugin.trigger("experimental.chat.system.transform", {}, { system })
if (system.length === 0) {
  system.push(...original)  // Falls back if emptied
}
// Maintains 2-part structure for caching if header unchanged
if (system.length > 2 && system[0] === header) {
  const rest = system.slice(1)
  system.length = 0
  system.push(header, rest.join("\n"))
}
```

The system is designed to support caching by maintaining a 2-part structure. Adding frame context could disrupt this if not done carefully.

**Messages transform** (`/Users/sl/code/opencode/packages/opencode/src/session/prompt.ts`):

```typescript
const sessionMessages = clone(msgs)
await Plugin.trigger("experimental.chat.messages.transform", {}, { messages: sessionMessages })
```

This clones messages before transformation, so modifications are isolated.

### 2.2 Compaction Trigger Mechanism

**The core question**: When should frame compaction be generated?

#### Option A: On Explicit Pop (All proposals, primary)

Generate compaction when user explicitly runs `/pop [status]`.

**Pros**:
- Frame boundaries are semantic, user-controlled
- Cleaner separation from auto-compaction
- User decides when work is "done"

**Cons**:
- May still hit context limits within a frame
- Need to handle interaction with auto-compaction

#### Option B: Both (Proposals A, B)

Use OpenCode's overflow compaction AND frame-completion compaction with different prompts.

```typescript
if (frame.status === "completing") {
  output.prompt = FRAME_COMPLETION_PROMPT  // Summarize for parent
} else {
  output.context.push(frameContext)  // Continuation context
}
```

**Pros**:
- Handles both use cases
- Leverages existing overflow detection
- Flexible

**Cons**:
- Two compaction mechanisms could confuse users
- Need clear differentiation in prompts

**Research Finding**: OpenCode's compaction is triggered on context overflow (`/Users/sl/code/opencode/packages/opencode/src/session/compaction.ts`):

```typescript
export function isOverflow(input: { tokens: MessageV2.Assistant["tokens"]; model: Provider.Model }) {
  if (Flag.OPENCODE_DISABLE_AUTOCOMPACT) return false
  const context = input.model.limit.context
  if (context === 0) return false
  const count = input.tokens.input + input.tokens.cache.read + input.tokens.output
  const output = Math.min(input.model.limit.output, SessionPrompt.OUTPUT_TOKEN_MAX) || SessionPrompt.OUTPUT_TOKEN_MAX
  const usable = context - output
  return count > usable
}
```

Auto-compaction cannot be disabled per-session, only globally via `OPENCODE_DISABLE_AUTOCOMPACT`. This means Flame must handle interaction with auto-compaction gracefully.

### 2.3 Frame State Storage Location

**The core question**: Where should frame metadata be stored?

#### Option A: Plugin-Managed Parallel Storage (All proposals)

Store frame state in separate plugin storage, keyed by session ID.

```typescript
Storage.write(['flame', 'frame', sessionID], frameMetadata)
// Or: .opencode/flame/frames.json
```

**Pros**:
- No OpenCode core changes required
- Clean separation of concerns
- Plugin can manage its own schema

**Cons**:
- State synchronization needed with session events
- Must handle orphaned frames on session deletion

#### Option B: Session Metadata Extension

Extend session info with frame fields (would require core changes).

**Not viable** - All proposals agree plugin should not require core changes.

**Research Finding**: OpenCode's Storage API (`/Users/sl/code/opencode/packages/opencode/src/storage/storage.ts`) supports arbitrary key paths:

```typescript
export async function write<T>(key: string[], content: T) {
  const dir = await state().then((x) => x.dir)
  const target = path.join(dir, ...key) + ".json"
  // ...
}
```

Plugins can use `Storage.write(['flame', 'frame', sessionID], metadata)` but this requires importing Storage from opencode core. Alternative is file-based storage in `.opencode/flame/`.

### 2.4 Subagent/TaskTool Integration Approach

**The core question**: How should Flame integrate with existing subagent flows?

#### Option A: Automatic Frame Wrapping (Proposals A, B)

Automatically treat TaskTool child sessions as frame pushes.

```typescript
// On session.created event
if (event.parentID) {
  await FrameStateManager.initFrame(session.id, {
    status: "in_progress",
    goal: session.title
  })
}
```

**Pros**:
- Unified frame model for all child sessions
- Automatic context propagation
- No user action required

**Cons**:
- May create unwanted frames for quick subagent calls
- Could pollute frame tree with short-lived operations
- Subagent sessions may not fit frame semantics

#### Option B: Parallel Flows (Proposal C mentions both)

Keep TaskTool unchanged, provide separate `/push` flow.

**Pros**:
- Cleaner separation of concerns
- User controls when frames are created
- No interference with existing subagent behavior

**Cons**:
- Two mechanisms for child sessions
- Subagent work not captured in frame tree
- Potential confusion

#### Option C: Heuristic-Based (Synthesis recommendation)

Use session title patterns or duration heuristics to decide:

```typescript
if (session.title.includes("subagent") && duration < 60_000) {
  // Don't create full frame, just log
} else {
  // Initialize as frame
}
```

### 2.5 Context Depth and Sibling Inclusion

**The core question**: How many ancestors and which siblings to include?

All proposals mention this but differ in defaults:

| Proposal | Ancestors | Siblings |
|----------|-----------|----------|
| A | Token-budget-based, min 2 | Completed only |
| B | All | All completed |
| C | All | Completed only |

**SPEC requirement**: Include "compaction of uncle A (completed sibling branch)".

**Recommendation**: Start with all ancestors + completed siblings, add token budget trimming if context grows too large.

---

## 3. Research Findings from OpenCode Codebase

### 3.1 Hook Availability and Signatures

**Verified hooks relevant to Flame**:

| Hook | Signature | Location |
|------|-----------|----------|
| `experimental.chat.messages.transform` | `(input: {}, output: { messages: MessageWithParts[] })` | `/packages/plugin/src/index.ts:179-187` |
| `experimental.chat.system.transform` | `(input: {}, output: { system: string[] })` | `/packages/plugin/src/index.ts:188-193` |
| `experimental.session.compacting` | `(input: { sessionID }, output: { context: string[], prompt?: string })` | `/packages/plugin/src/index.ts:201-204` |
| `event` | `(input: { event: Event })` | `/packages/plugin/src/index.ts:146` |
| `tool` | `{ [key: string]: ToolDefinition }` | `/packages/plugin/src/index.ts:148-150` |

### 3.2 Session Events Available

From `/packages/web/src/content/docs/plugins.mdx`:

- `session.created`
- `session.compacted`
- `session.deleted`
- `session.diff`
- `session.error`
- `session.idle`
- `session.status`
- `session.updated`

### 3.3 SDK Session API

From `/packages/web/src/content/docs/sdk.mdx`:

```javascript
// Create child session
const session = await client.session.create({
  body: { parentID: parentSessionID, title: "Child session" },
})

// List children
const children = await client.session.children({ path: { id: parentSessionID } })

// Send prompt
const result = await client.session.prompt({
  path: { id: session.id },
  body: { parts: [{ type: "text", text: "..." }] }
})
```

### 3.4 Custom Tools via Plugins

From `/packages/web/src/content/docs/plugins.mdx`:

```typescript
return {
  tool: {
    mytool: tool({
      description: "This is a custom tool",
      args: { foo: tool.schema.string() },
      async execute(args, ctx) {
        return `Hello ${args.foo}!`
      },
    }),
  },
}
```

This can be used for `flame_push`, `flame_pop`, `flame_status` tools for agent-initiated control.

### 3.5 Command vs Tool for Frame Control

OpenCode supports both:
1. **Custom commands**: Markdown files in `.opencode/command/` - good for user-initiated actions
2. **Plugin tools**: Defined in plugin hooks - good for agent-initiated actions

Both approaches are viable and not mutually exclusive.

### 3.6 Storage Considerations

OpenCode uses a global storage directory (`~/.local/share/opencode/storage/`). Plugins can:
1. Use OpenCode's Storage API (if available to plugins)
2. Use file-based storage in `.opencode/flame/`
3. Use in-memory state reconstructed from session events

Option 2 is most portable and doesn't depend on internal APIs.

---

## 4. Open Questions

### 4.1 Hook Input Context

**Question**: Do the `experimental.chat.*` hooks receive session ID in their input?

**Finding**: Looking at the type definitions, `input` is `{}` for both hooks. This means the plugin must track current session ID through other means (event subscriptions or global state).

**Research needed**: How to reliably get current session ID within these hooks? Options:
- Track via `session.created`/`session.updated` events
- Infer from message content
- Request hook enhancement from OpenCode team

### 4.2 Compaction Output Capture

**Question**: How do we capture the compaction output to store in frame metadata?

**Finding**: The `experimental.session.compacting` hook only allows modification of inputs, not capture of outputs. The compaction result is stored as a message with `summary: true`.

**Options**:
1. Subscribe to `session.compacted` event and read latest summary message
2. Subscribe to `message.updated` events and detect summary messages
3. Request new hook for post-compaction capture

### 4.3 Session Navigation Integration

**Question**: How should frame navigation interact with existing session switcher?

**Finding**: OpenCode has `session_child_cycle` keybinds that already navigate parent/child sessions. Frames (as sessions) automatically get this navigation.

**Additional UX**: A `/flame-tree` command for visual tree navigation would complement existing keybinds.

### 4.4 Planned Frame Representation

**Question**: Should planned frames be created as actual sessions?

**Considerations**:
- Creating sessions for planned frames adds overhead
- Empty sessions may trigger edge cases
- Session list would show planned frames alongside active ones

**Options**:
1. Create sessions immediately (simpler, consistent with session=frame)
2. Store planned frames only in plugin state, create session on activation (lighter, but dual representation)

### 4.5 Context Injection Timing

**Question**: At what point should frame context be injected?

**Finding**: `experimental.chat.messages.transform` is called just before LLM invocation (line 528 of prompt.ts):

```typescript
const sessionMessages = clone(msgs)
await Plugin.trigger("experimental.chat.messages.transform", {}, { messages: sessionMessages })
const result = await processor.process({
  // ...
  messages: [...MessageV2.toModelMessage(sessionMessages), ...]
})
```

This is the right timing - after filtering compacted messages but before LLM call.

### 4.6 Token Budget Management

**Question**: How to handle deep trees where compaction summaries exceed token budget?

**Options**:
1. Truncate older sibling compactions first
2. Use hierarchical compaction (compact the compactions)
3. User-configurable depth limits
4. Dynamic adjustment based on model context size

**Recommendation**: Start with depth limits (configurable), add hierarchical compaction for V2.

---

## 5. Recommended Path

Based on the synthesis and research, here is the recommended implementation approach:

### 5.1 Architecture Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Context Injection | **Message prepend** via `experimental.chat.messages.transform` | Fresh per-call, visible for debugging, doesn't disrupt system prompt caching |
| Compaction Trigger | **Both** overflow and explicit pop, with different prompts | Handles long frames gracefully, gives user control over completion |
| State Storage | **File-based** in `.opencode/flame/state.json` and `.opencode/flame/logs/` | Portable, doesn't depend on internal APIs |
| Subagent Integration | **Heuristic-based** automatic framing for long-running subagents | Captures meaningful work without noise |
| Context Depth | **All ancestors** + **completed siblings**, with configurable limits | Matches SPEC, can tune later |

### 5.2 Implementation Phases

**Phase 1: Core Frame Management**
- Frame State Manager with file-based storage
- `/push` and `/pop` commands (user-initiated only)
- Basic frame lifecycle (create, complete, navigate)
- Session event subscriptions for state sync

**Phase 2: Context Assembly**
- Message transform hook implementation
- Ancestor compaction retrieval
- Sibling compaction retrieval
- XML context generation

**Phase 3: Compaction Integration**
- Custom compaction prompts for frame completion
- Compaction output capture via message events
- Summary storage in frame metadata

**Phase 4: Log Persistence**
- Markdown export on frame completion
- Log path storage in frame metadata
- Log browsing command

**Phase 5: Subagent Integration**
- TaskTool session detection
- Heuristic-based frame creation
- Frame completion on subagent finish

**Phase 6: Planning and Invalidation**
- Planned frame support
- Invalidation cascade
- Frame tree visualization

**Phase 7: Agent Autonomy**
- `flame_push`/`flame_pop` tools for agent use
- Configuration for autonomy level
- Heuristics for auto-push suggestions

### 5.3 Key Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Hook API instability (experimental.*) | Abstract hook usage behind internal interfaces; monitor OpenCode releases |
| Session ID not available in hooks | Track via event subscriptions; request enhancement if needed |
| Context size explosion | Implement token budget from Phase 2; configurable limits |
| Auto-compaction interference | Detect summary messages; don't double-compact |
| Orphaned frame state | Clean up on `session.deleted` event; periodic garbage collection |

### 5.4 Validation Criteria

Before proceeding to implementation, validate these assumptions:

1. **Hook Testing**: Create minimal plugin that logs hook invocations to verify call timing and available context
2. **Session ID Access**: Confirm mechanism for getting current session ID in transform hooks
3. **Compaction Output**: Verify `session.compacted` event provides access to generated summary
4. **Storage Access**: Confirm file-based storage in `.opencode/flame/` is accessible from plugin context
5. **Message Prepend**: Verify prepended synthetic messages are included in LLM calls and displayed appropriately in TUI

---

## 6. Files Referenced

### OpenCode Source Files

- `/Users/sl/code/opencode/packages/plugin/src/index.ts` - Hook type definitions
- `/Users/sl/code/opencode/packages/opencode/src/session/prompt.ts` - Message transform invocation
- `/Users/sl/code/opencode/packages/opencode/src/session/compaction.ts` - Compaction hook usage
- `/Users/sl/code/opencode/packages/opencode/src/session/llm.ts` - System transform invocation
- `/Users/sl/code/opencode/packages/opencode/src/session/index.ts` - Session API
- `/Users/sl/code/opencode/packages/opencode/src/tool/task.ts` - TaskTool implementation
- `/Users/sl/code/opencode/packages/opencode/src/storage/storage.ts` - Storage API

### OpenCode Documentation

- `/Users/sl/code/opencode/packages/web/src/content/docs/plugins.mdx` - Plugin documentation
- `/Users/sl/code/opencode/packages/web/src/content/docs/sdk.mdx` - SDK documentation
- `/Users/sl/code/opencode/packages/web/src/content/docs/agents.mdx` - Agent documentation

### Flame Specification

- `/Users/sl/code/flame/SPEC.md` - Core specification

---

## 7. Next Steps

1. **Validate assumptions** using minimal test plugin
2. **Resolve open questions** through code research or OpenCode team consultation
3. **Create detailed technical design** for Phase 1
4. **Implement Phase 1** with comprehensive tests
5. **Iterate** based on real-world usage feedback
