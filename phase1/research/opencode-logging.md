# OpenCode Logging & Persistence Research

## Executive Summary

**OpenCode already provides comprehensive persistence of all conversation history.** The Flame plugin does NOT need to implement its own logging layer. OpenCode persists every message and every part (tool calls, text, etc.) to disk as JSON files, and this data remains accessible even after compaction.

## Key Findings

### 1. Where OpenCode Stores Data

OpenCode uses XDG base directories for storage:

```
~/.local/share/opencode/storage/
├── session/{projectID}/{sessionID}.json   # Session metadata
├── message/{sessionID}/{messageID}.json   # Individual messages
├── part/{messageID}/{partID}.json         # Message parts (text, tool calls, etc.)
├── session_diff/{sessionID}.json          # File diffs
└── share/{sessionID}.json                 # Share metadata
```

**Source:** `/Users/sl/code/opencode/packages/opencode/src/storage/storage.ts` lines 143-158, `/Users/sl/code/opencode/packages/opencode/src/global/index.ts`

### 2. What Gets Persisted

Every message and part is immediately written to disk:

- **Messages** (`MessageV2.Info`): User and assistant messages with full metadata (role, timestamps, model used, tokens, cost, error info)
- **Parts** (`MessageV2.Part`): Text, reasoning, tool calls, file attachments, step markers, etc.
- **Tool State**: Complete input, output, and timing for every tool call

**Source:** `/Users/sl/code/opencode/packages/opencode/src/session/index.ts`:
```typescript
export const updateMessage = fn(MessageV2.Info, async (msg) => {
  await Storage.write(["message", msg.sessionID, msg.id], msg)
  // ...
})

export const updatePart = fn(UpdatePartInput, async (input) => {
  await Storage.write(["part", part.messageID, part.id], part)
  // ...
})
```

### 3. What Happens During Compaction

Compaction does NOT delete historical messages. It:

1. **Prunes tool output**: Marks old tool results as "compacted" by setting `part.state.time.compacted = Date.now()`
2. **Generates a summary**: Creates a new assistant message with `summary: true` that summarizes the conversation
3. **Preserves originals**: The original messages and parts remain on disk

**Source:** `/Users/sl/code/opencode/packages/opencode/src/session/compaction.ts`:
```typescript
// Line 83-84: Pruning marks parts as compacted, doesn't delete
part.state.time.compacted = Date.now()
await Session.updatePart(part)
```

When building context for the LLM, compacted tool outputs are replaced with `"[Old tool result content cleared]"` but the original data is still on disk.

### 4. Parent/Child Session Support (Already Exists!)

OpenCode already supports parent-child session relationships:

```typescript
// Session schema includes parentID
export const Info = z.object({
  id: Identifier.schema("session"),
  parentID: Identifier.schema("session").optional(),
  // ...
})

// Task tool creates child sessions
const session = await Session.create({
  parentID: ctx.sessionID,
  title: params.description + ` (@${agent.name} subagent)`,
})
```

**Source:** `/Users/sl/code/opencode/packages/opencode/src/session/index.ts` lines 43, 285-294, `/Users/sl/code/opencode/packages/opencode/src/tool/task.ts` line 41

### 5. Access via SDK/API

Full access to session history is available:

```typescript
// SDK Methods
client.session.list()                    // List all sessions
client.session.get({ path: { id } })     // Get session metadata
client.session.messages({ path: { id }}) // Get all messages with parts
client.session.children({ path: { id }}) // Get child sessions

// Export command exists for full JSON export
opencode export [sessionID]
```

**Source:** `/Users/sl/code/opencode/packages/web/src/content/docs/sdk.mdx`, `/Users/sl/code/opencode/packages/opencode/src/cli/cmd/export.ts`

## Comparison to SPEC.md Requirements

| SPEC.md Requirement | OpenCode Capability | Gap? |
|---------------------|---------------------|------|
| "Full Logs Persist to Disk" | YES - Every message/part saved to JSON files | NO |
| "agents can browse previous frame logs" | YES - `Session.messages()`, `MessageV2.stream()` | NO |
| "pointer to full log file" in compaction | PARTIAL - compacted parts reference original via messageID | MINOR |
| Tree structure of frames | PARTIAL - parent/child sessions exist | YES - needs frame metadata |
| Compaction summaries | YES - summary messages with `summary: true` flag | NO |

## Recommendation: What Phase 1.4 Should Be

**Phase 1.4 should NOT implement logging.** Instead, it should focus on:

### Actually Needed

1. **Frame Metadata Extension**: Add frame-specific metadata to sessions:
   - Frame status (in_progress, completed, failed, blocked, invalidated)
   - Goal/purpose description
   - Artifacts list
   - Planned children

2. **Context Assembly**: Logic to build active context from:
   - Current frame's messages
   - Ancestor compaction summaries
   - Sibling compaction summaries

3. **Compaction Hook**: Use `experimental.session.compacting` hook to inject frame-aware context into compaction prompts

### NOT Needed

1. ~~Log files~~ - OpenCode already has these
2. ~~Message persistence~~ - OpenCode already does this
3. ~~Session history access~~ - SDK already provides this
4. ~~Parent/child relationships~~ - Already in the schema

## Code References

| File | Key Functions |
|------|---------------|
| `/Users/sl/code/opencode/packages/opencode/src/storage/storage.ts` | `read()`, `write()`, `list()` - Core storage |
| `/Users/sl/code/opencode/packages/opencode/src/session/index.ts` | `Session.messages()`, `Session.children()`, `Session.create()` |
| `/Users/sl/code/opencode/packages/opencode/src/session/message-v2.ts` | `MessageV2.stream()`, `MessageV2.get()`, `MessageV2.filterCompacted()` |
| `/Users/sl/code/opencode/packages/opencode/src/session/compaction.ts` | `SessionCompaction.process()`, `SessionCompaction.prune()` |
| `/Users/sl/code/opencode/packages/opencode/src/global/index.ts` | `Global.Path.data` - Storage location |

## Conclusion

The user's intuition was correct: OpenCode already handles conversation logging comprehensively. The Flame plugin should leverage the existing infrastructure rather than reimplementing it. Phase 1.4 should be renamed from "Log Persistence Layer" to something like "Frame Metadata Extension" and should focus on:

1. Adding frame-specific metadata to session records
2. Implementing context assembly logic that uses existing session/message APIs
3. Hooking into the existing compaction system to make summaries frame-aware

This significantly reduces implementation complexity and ensures Flame works with OpenCode's existing data model rather than creating a parallel storage system.
