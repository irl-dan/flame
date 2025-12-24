# Why Flame Graph Context Management Can't Be Fully Implemented in Claude Code

**Date:** 2025-12-24
**Status:** Verified Against Documentation + Live Implementation
**Purpose:** Fact sheet for tweet thread on limitations

---

## The Goal (from SPEC.md)

Replace Claude Code's linear message history with **tree-structured context**:

```
                    [Root Frame: "Build App"]
                           |
           +---------------+---------------+
           |                               |
     [Frame A: Auth]                [Frame B: API Routes]
      (completed)                      (in progress)
```

**Key Requirements:**
1. Frame push/pop semantics (like a call stack)
2. Full logs persisted to disk per frame
3. Compaction on pop (summary replaces detailed history)
4. Active context = current frame + ancestor compactions + sibling compactions
5. **NOT** linear history of all frames

---

## What We Verified

### Source 1: Official Documentation (`docs-claude-code/`)

| Document | Key Finding |
|----------|-------------|
| `claude-code-subagents.md` | "Each subagent operates in its own context, preventing pollution of the main conversation" |
| `claude-code-subagents.md` | "This prevents infinite nesting of agents (subagents cannot spawn other subagents)" |
| `claude-code-subagents.md` | Subagents can be resumed via `agentId` with full context preserved |
| `claude-code-hooks.md` | Hooks can add `additionalContext` but **cannot remove or restructure** messages |
| `claude-code-hooks.md` | PreCompact hook fires before compaction but **cannot control what's kept/discarded** |

### Source 2: Live Implementation (`~/.claude/`)

**Directory Structure Verified:**
```
~/.claude/
├── agents/           # Custom agent definitions (3 found)
├── projects/         # Per-project session storage
│   └── -Users-sl-code-flame/
│       ├── ac4595af-...jsonl      # Main session transcript
│       ├── agent-aca56da.jsonl    # Subagent transcript (SEPARATE!)
│       └── agent-a14843c.jsonl    # Another subagent
└── session-env/      # Environment per session
```

**Transcript Structure Verified:**

1. **Main Session** (`uuid.jsonl`):
   - Keys: `["leafUuid","summary","type"]`
   - Contains linear conversation history

2. **Subagent Transcript** (`agent-{id}.jsonl`):
   - Keys: `["agentId","isSidechain","sessionId","message","parentUuid",...]`
   - `isSidechain: true` - confirms separate context
   - `agentId: "aca56da"` - unique identifier for resume
   - `sessionId` - references parent session
   - **34 lines in agent file** vs megabytes in parent session

3. **What Returns to Parent** (tool_result):
   ```json
   {
     "type": "tool_result",
     "content": [
       {"type": "text", "text": "Summary of what agent did..."},
       {"type": "text", "text": "agentId: aca56da (for resuming)"}
     ],
     "toolUseResult": {
       "prompt": "Original prompt to subagent",
       "agentId": "aca56da",
       "totalTokens": 65414,
       "totalToolUseCount": 12
     }
   }
   ```

---

## The Blockers: Verified Limitations

### Blocker 1: No Context Removal API

**The Claim:** Claude Code provides no mechanism to remove or filter messages from context.

**Verification:**
- `claude-code-hooks.md` shows only `additionalContext` injection
- No mention of message filtering, removal, or exclusion
- PreCompact hook can inject instructions but not control retention

**Impact:** Even with subagent isolation, the **parent session accumulates all subagent summaries linearly**. After 10 sibling frames, you have 10 summaries in linear history, not tree-structured context.

### Blocker 2: Max Depth = 1 Level

**The Claim:** Subagents cannot spawn other subagents.

**Verification:**
- `claude-code-subagents.md` line 300: "This prevents infinite nesting of agents (subagents cannot spawn other subagents)"

**Impact:** Frame tree is limited to:
```
Root -> [Child1, Child2, Child3, ...]
```
Cannot achieve:
```
Root -> Child -> Grandchild -> Great-grandchild
```

### Blocker 3: No Heuristic Interception

**The Claim:** Cannot automatically push/pop frames based on Claude's decisions.

**Verification:**
- Hooks fire on tool use, not on Claude's "thoughts"
- No "PreThink" or "PrePlan" hook event
- Skills can suggest but not enforce frame management

**Impact:** Frame management requires either:
- Explicit user commands (`/push`, `/pop`)
- Claude voluntarily calling frame tools (unreliable)

### Blocker 4: Parent Context Not Tree-Aware

**The Claim:** Parent session context grows linearly, not structurally.

**Verification:**
- Examined transcript structure - no tree metadata
- Compaction creates summary of linear history, not frame hierarchy
- No "frame" concept in native data model

**Impact:** When Claude works on Frame B, it still sees linear:
```
[A started] [A tool1] [A tool2] [A completed: summary] [B started] [B tool1]...
```
Not structured:
```
Frame A (compacted): summary
Frame B (current): [tool1]...
```

---

## What IS Achievable (Depth 1)

| Capability | How | Limitation |
|------------|-----|------------|
| Context isolation for frames | Subagents have own context window | Max 1 level deep |
| Frame push/pop | Spawn/complete subagent | User or Claude must invoke |
| Context injection at spawn | Prompt parameter | Parent still has linear history |
| Frame resume | `resume` parameter with agentId | Works! |
| Compaction on completion | SubagentStop hook + system prompt | Relies on Claude following instructions |
| Full logging | Native `agent-{id}.jsonl` | Works! |
| Human control | Slash commands | Works! |

---

## The Fundamental Problem

Claude Code's context construction is:

```
System Prompt + CLAUDE.md + Linear Message History + Tool Results
```

Flame Graph needs:

```
System Prompt + Frame Context Assembly + Current Frame History
```

**There is no extension point to replace `Linear Message History` with `Frame Context Assembly`.**

Extensions can:
- ADD to system prompt (SessionStart additionalContext)
- ADD to conversation (tool results)

Extensions CANNOT:
- REMOVE messages from history
- RESTRUCTURE how context is built
- REPLACE linear history with tree-structured assembly

---

## What Would Need to Change

For true flame graph support, Claude Code would need:

1. **Context Construction Hook**
   - Allow extensions to modify/filter context before sending to Claude
   - Something like: `PreContextAssembly` that receives message array

2. **Message Filtering API**
   - Mark messages as "excluded" from context
   - Or: provide a custom context builder function

3. **Recursive Subagents**
   - Allow subagents to spawn subagents (with depth limit)
   - Maintain isolation at each level

4. **Native Tree State**
   - Built-in concept of frames/stacks
   - Automatic context assembly from tree

---

## Summary for Tweet Thread

**Thread Hook:** "I tried to build flame-graph context management for AI agents. Here's why current tooling makes it impossible."

**Key Points:**

1. **The Vision:** Replace linear chat history with call-stack-like frames. Work on Task B without Task A's debugging noise in context.

2. **What Claude Code Gets Right:**
   - Subagents DO have isolated context (verified: separate `.jsonl` files)
   - Subagents CAN be resumed with full context
   - Only summaries return to parent, not full history

3. **The Blockers:**
   - Subagents can't spawn subagents (max depth = 1)
   - No API to filter/remove messages from context
   - Parent accumulates summaries linearly, not as tree
   - Compaction isn't frame-aware

4. **The Core Issue:** Extensions can ADD context but not STRUCTURE it. Linear history is baked into the architecture.

5. **What's Needed:** A context assembly hook that lets extensions replace linear history with custom assembly logic.

---

## Evidence Trail

All findings verified against:
- `/Users/sl/code/flame/docs-claude-code/` (official documentation)
- `~/.claude/projects/-Users-sl-code-flame/` (live session data)
- `~/.claude/agents/` (custom agent definitions)
- Agent transcript: `agent-aca56da.jsonl` (34 lines, isSidechain: true)
- Parent session: `df78735e-ac15-48b0-aa59-45ebd9f19ada.jsonl` (6.3MB)

---

**Last Updated:** 2025-12-24T06:10:00Z
