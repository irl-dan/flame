# Proposal: Flame Graph Context Management Using OpenCode Native Extensions

**Date:** 2025-12-23
**Status:** Analysis Complete
**Verdict:** HIGHLY FEASIBLE with significant advantages over Claude Code approach

---

## Executive Summary

This proposal analyzes the feasibility of implementing "Flame Graph Context Management" using OpenCode's native extension mechanisms: plugins, agents (subagents), commands, custom tools, skills, MCP servers, and the SDK/server architecture.

### Bottom Line

OpenCode provides a **significantly more capable extension architecture** than Claude Code for implementing flame graph context management:

| Capability | Claude Code | OpenCode | Winner |
|------------|-------------|----------|--------|
| Context Isolation (Subagents) | Limited depth-1 only | Full hierarchical subagent system | OpenCode |
| Plugin System | Hooks + commands | Full JS/TS plugins with event system | OpenCode |
| Compaction Control | PreCompact hook (inject-only) | `experimental.session.compacting` hook with full prompt override | **OpenCode** |
| State Management | External MCP server required | Native SDK + persistent sessions | OpenCode |
| Event System | Limited hook events | Comprehensive event bus | **OpenCode** |
| Session API | None exposed | Full HTTP API + SDK | **OpenCode** |
| Custom Tools | Via MCP only | Native TS/JS + MCP | OpenCode |
| Programmatic Control | Very limited | Full SDK for orchestration | **OpenCode** |

**Key Finding:** OpenCode's SDK and server architecture enables an **external orchestrator pattern** that can achieve true flame graph semantics by programmatically creating and managing sessions as frames.

---

## Table of Contents

1. [The Specification Requirements](#1-the-specification-requirements)
2. [OpenCode Extension Mechanisms Analysis](#2-opencode-extension-mechanisms-analysis)
3. [Component-by-Component Feasibility](#3-component-by-component-feasibility)
4. [Implementation Architecture](#4-implementation-architecture)
5. [What's Possible vs Claude Code](#5-whats-possible-vs-claude-code)
6. [Code Examples](#6-code-examples)
7. [Conclusion and Recommendations](#7-conclusion-and-recommendations)

---

## 1. The Specification Requirements

From SPEC.md, the flame graph context management system requires:

### Core Mechanics
1. **Frame Push/Pop Semantics** - Create/exit child frames for subtasks
2. **Full Logs to Disk** - Complete frame history persisted
3. **Compaction on Pop** - Summary generated when frame completes
4. **Active Context Construction** - Current frame + ancestor compactions + sibling compactions (NOT full linear history)
5. **Planned Frames** - TODO-like planned frames with planned children
6. **Control Authority** - Human commands AND agent-initiated decisions

### Required Components
1. **Frame State Manager** - Track tree of frames, status, relationships
2. **Log Persistence Layer** - Write full frame logs to disk
3. **Compaction Generator** - Produce summaries when frames complete
4. **Context Assembler** - Build active context from current frame + compactions
5. **Frame Controller** - Handle push/pop commands
6. **Plan Manager** - Handle planned frames, cascade invalidation

---

## 2. OpenCode Extension Mechanisms Analysis

### 2.1 Plugins (JavaScript/TypeScript)

**What Plugins Provide:**
OpenCode plugins are full JavaScript/TypeScript modules that receive a rich context and can hook into the entire event system.

```typescript
import type { Plugin } from "@opencode-ai/plugin"

export const FlamePlugin: Plugin = async ({ project, client, $, directory, worktree }) => {
  return {
    // Event handlers
    event: async ({ event }) => { /* ... */ },

    // Tool execution hooks
    "tool.execute.before": async (input, output) => { /* ... */ },
    "tool.execute.after": async (input, output) => { /* ... */ },

    // CRITICAL: Compaction control
    "experimental.session.compacting": async (input, output) => {
      // Can inject context OR completely replace prompt
      output.prompt = "Custom compaction prompt..."
      output.context.push("Additional context...")
    },

    // Custom tools
    tool: {
      flame_push: tool({ /* ... */ }),
      flame_pop: tool({ /* ... */ }),
    },
  }
}
```

**Plugin Context Includes:**
- `project`: Current project information
- `directory`: Working directory
- `worktree`: Git worktree path
- `client`: **OpenCode SDK client** for programmatic control
- `$`: Bun shell API for command execution

**Event System:**
| Event Category | Events | Use for Flame Graph |
|----------------|--------|---------------------|
| Session Events | `session.created`, `session.compacted`, `session.deleted`, `session.idle`, `session.error`, `session.updated` | Frame lifecycle, compaction triggers |
| Message Events | `message.updated`, `message.part.updated`, `message.removed` | Logging, context tracking |
| Tool Events | `tool.execute.before`, `tool.execute.after` | Frame-worthy action detection |
| Command Events | `command.executed` | Human control |
| Todo Events | `todo.updated` | Planned frame tracking |
| TUI Events | `tui.prompt.append`, `tui.command.execute` | UI integration |

**CRITICAL CAPABILITY: `experimental.session.compacting` Hook**

This is a game-changer compared to Claude Code. OpenCode allows:
1. **Injecting additional context** into compaction via `output.context.push()`
2. **Completely replacing the compaction prompt** via `output.prompt = "..."`

This means we can implement **frame-aware compaction** where:
- Current frame's history is preserved
- Sibling frames are compacted to summaries
- Ancestor frames provide goal context

```typescript
"experimental.session.compacting": async (input, output) => {
  const frameTree = await getFrameTree()
  const currentFrame = await getCurrentFrame()

  output.prompt = `
You are generating a continuation prompt for a flame graph context session.

CURRENT FRAME: ${currentFrame.goal}
Frame ID: ${currentFrame.id}

ANCESTOR CONTEXT (preserve goals and decisions):
${formatAncestorCompactions(frameTree, currentFrame)}

SIBLING CONTEXT (completed/compacted):
${formatSiblingCompactions(frameTree, currentFrame)}

CURRENT FRAME HISTORY (prioritize preserving):
This is the active work context. Preserve:
1. Current task progress and key decisions
2. Important artifacts created/modified
3. Blockers or challenges encountered

COMPACTION RULES:
- Maintain the current frame's working state
- Summarize sibling frames to key outcomes only
- Keep ancestor goals visible for context
- Reference log files for detailed history
`
}
```

---

### 2.2 Agents & Subagents

**What Agents Provide:**
OpenCode has a sophisticated agent system with two types:
- **Primary Agents**: Main conversation handlers (Build, Plan, or custom)
- **Subagents**: Specialized assistants invoked for specific tasks

**Key Features:**
| Feature | Capability |
|---------|------------|
| Agent Modes | `primary`, `subagent`, or `all` |
| Tool Control | Per-agent tool enabling/disabling |
| Model Override | Different models per agent |
| Permission Override | Custom permissions per agent |
| Custom Prompts | Agent-specific system prompts |
| Temperature Control | Per-agent temperature settings |
| Max Steps | Limit agentic iterations |

**Subagent Invocation:**
- Automatic by primary agents based on description
- Manual via `@agentname` mention
- Programmatic via SDK

**Session Navigation:**
OpenCode supports parent-child session relationships with navigation:
- `session.children({ path })` API to get child sessions
- `session.create({ body: { parentID } })` to create child sessions
- TUI keybinds for cycling through parent/child sessions

**Frame Mapping:**
```
Frame Tree                     OpenCode Sessions
-----------                    -----------------
Root Frame          <-->       Parent Session
  Child Frame A     <-->       Child Session A (parentID: root)
    A1, A2          <-->       Subagent invocations in Session A
  Child Frame B     <-->       Child Session B (parentID: root)
```

---

### 2.3 Commands

**What Commands Provide:**
Custom slash commands with rich templating:

```markdown
---
description: Push a new frame onto the stack
agent: build
subtask: true  # Forces subagent mode for isolation!
---

# Push New Frame

Create a new child frame with goal: $ARGUMENTS

## Current Frame State
!`cat ~/.flame/current.json`

## Instructions
1. Create new session as child of current
2. Set frame goal: $ARGUMENTS
3. Assemble context from frame tree
4. Begin work in isolated subagent context
```

**Key Features:**
| Feature | Description |
|---------|-------------|
| `$ARGUMENTS`, `$1`, `$2` | Argument substitution |
| `!`command`` | Inline bash execution |
| `@file.ts` | File content inclusion |
| `agent` | Specify which agent handles command |
| `subtask: true` | **Force subagent mode** for isolation |
| `model` | Override model for this command |

**The `subtask: true` Option:**
This is crucial for flame graph implementation. Setting `subtask: true` forces the command to run in a subagent context, providing isolation from the parent conversation.

---

### 2.4 Custom Tools

**What Custom Tools Provide:**
Native TypeScript/JavaScript tool definitions with full type safety:

```typescript
import { tool } from "@opencode-ai/plugin"

export const flame_push = tool({
  description: "Push a new frame onto the flame graph stack",
  args: {
    goal: tool.schema.string().describe("Goal for the new frame"),
    parent: tool.schema.string().optional().describe("Parent frame ID"),
  },
  async execute(args, context) {
    const { sessionID, messageID, agent } = context

    // Create new child session via SDK
    const childSession = await client.session.create({
      body: {
        parentID: sessionID,
        title: args.goal
      }
    })

    // Store frame state
    await storeFrameState({
      frameId: childSession.id,
      parentId: sessionID,
      goal: args.goal,
      status: 'in_progress'
    })

    return `Created frame ${childSession.id} with goal: ${args.goal}`
  },
})

export const flame_pop = tool({
  description: "Pop the current frame and return to parent with summary",
  args: {
    status: tool.schema.enum(['completed', 'failed', 'blocked']),
    summary: tool.schema.string().describe("Compacted summary of frame work"),
  },
  async execute(args, context) {
    const { sessionID } = context
    const frame = await getFrameState(sessionID)

    // Store compaction
    await storeCompaction(frame.id, {
      status: args.status,
      summary: args.summary,
      completedAt: new Date().toISOString()
    })

    // Mark frame complete
    await updateFrameState(frame.id, { status: args.status })

    return `Frame ${frame.id} completed with status: ${args.status}`
  },
})
```

---

### 2.5 Skills

**What Skills Provide:**
Agent-discoverable instruction sets that can be loaded on demand:

```markdown
---
name: flame-context
description: Flame graph context management heuristics and rules
license: MIT
metadata:
  audience: all-agents
---

## Frame Management Heuristics

### When to Push a Frame
Push a new frame when:
- Starting a distinct subtask that could be retried independently
- Switching context to different files/concepts/goals
- The current scope feels too broad
- Beginning exploratory work that might fail

Trigger phrases that indicate frame-push:
- "Let me first..."
- "I need to figure out..."
- "I'll try a different approach..."

### When to Pop a Frame
Pop the current frame when:
- The frame's goal has been achieved
- The frame has failed and should be retried differently
- The frame is blocked on external input
- Ready to return to parent's broader scope

### Compaction Guidelines
When completing a frame, provide:
- STATUS: completed/failed/blocked
- SUMMARY: 1-2 sentences of what was accomplished
- KEY ARTIFACTS: file paths created/modified
- DECISIONS: important choices made
- BLOCKERS: what's preventing progress (if any)

Do NOT include:
- Detailed debugging traces
- Full code snippets (reference files instead)
- Exploration of rejected approaches
```

Skills are loaded via the native `skill` tool when needed.

---

### 2.6 SDK & Server Architecture

**The Game-Changer: Full Programmatic Control**

OpenCode exposes a complete HTTP API and TypeScript SDK that enables external orchestration:

```typescript
import { createOpencode, createOpencodeClient } from "@opencode-ai/sdk"

// Create opencode instance (starts server + client)
const { client, server } = await createOpencode({
  port: 4096,
  config: {
    model: "anthropic/claude-sonnet-4-5"
  }
})

// Or connect to existing server
const client = createOpencodeClient({ baseUrl: "http://localhost:4096" })
```

**Session Management APIs:**

| Method | Description | Flame Graph Use |
|--------|-------------|-----------------|
| `session.create({ body: { parentID, title } })` | Create child session | Frame Push |
| `session.get({ path: { id } })` | Get session details | Frame state |
| `session.children({ path: { id } })` | List child sessions | Get subframes |
| `session.delete({ path: { id } })` | Delete session | Clean up frame |
| `session.abort({ path: { id } })` | Abort running session | Stop frame work |
| `session.summarize({ path, body })` | Summarize session | Compaction |
| `session.messages({ path: { id } })` | Get all messages | Full frame log |
| `session.prompt({ path, body })` | Send message | Frame work |
| `session.prompt({ ..., noReply: true })` | **Inject context only** | Context assembly! |

**Critical Feature: `noReply: true`**

The SDK allows injecting context into a session without triggering an AI response:

```typescript
await client.session.prompt({
  path: { id: sessionId },
  body: {
    noReply: true,  // Context injection only!
    parts: [{
      type: "text",
      text: `
## Frame Context (Injected)

### Your Goal
${frame.goal}

### Ancestor Context
${formatAncestorCompactions(frameTree)}

### Sibling Context
${formatSiblingCompactions(frameTree)}

Focus on your goal. Use /pop when complete.
`
    }]
  }
})
```

This enables **true context assembly** - we can inject exactly the context we want at the start of each frame!

**Event Subscription:**

```typescript
const events = await client.event.subscribe()
for await (const event of events.stream) {
  if (event.type === 'session.idle') {
    // Frame completed, trigger compaction
    await handleFrameCompletion(event.properties.sessionId)
  }
  if (event.type === 'session.created') {
    // New frame created
    await initializeFrame(event.properties.sessionId)
  }
}
```

---

### 2.7 MCP Servers

**What MCP Servers Provide:**
External tool servers with persistent state, similar to Claude Code.

For flame graph, MCP servers could provide the state management layer, though the native SDK may be sufficient for most use cases.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "flame-state": {
      "type": "local",
      "command": ["node", ".opencode/mcp/flame-state/server.js"],
      "environment": {
        "FLAME_DATA_DIR": "${HOME}/.flame"
      }
    }
  }
}
```

---

## 3. Component-by-Component Feasibility

### 3.1 Frame State Manager

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Track tree of frames | **FULL** | OpenCode sessions with parentID form native tree |
| Track frame status | **FULL** | Session metadata + plugin state |
| Track relationships | **FULL** | `session.children()` API provides native tree traversal |

**Implementation:**
OpenCode sessions already form a tree structure via `parentID`. Frame state can be stored as:
1. Session metadata (title, custom fields via SDK)
2. Plugin-managed state file (`.flame/state.json`)
3. MCP server state (if more complex needs)

```typescript
// Frame tree is native to OpenCode
const parentSession = await client.session.get({ path: { id: rootId } })
const childSessions = await client.session.children({ path: { id: rootId } })
```

---

### 3.2 Log Persistence Layer

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Write full frame logs | **FULL** | Sessions persist all messages natively |
| Reference logs in compaction | **FULL** | Session ID = log reference |
| Browse previous logs | **FULL** | `session.messages()` API |

**OpenCode Advantage:**
OpenCode already persists all session history. Frame logs are simply session transcripts:
- `session.messages({ path: { id: frameSessionId } })` returns full history
- Sessions can be shared, exported, or reviewed
- No additional logging layer needed

---

### 3.3 Compaction Generator

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Generate summary on pop | **FULL** | `session.summarize()` or custom tool |
| Include status | **FULL** | Tool parameter or session metadata |
| Include key artifacts | **FULL** | LLM-generated as part of summary |
| Pointer to full log | **FULL** | Session ID is the reference |

**Implementation:**

```typescript
export const flame_pop = tool({
  description: "Complete current frame with compaction",
  args: {
    status: tool.schema.enum(['completed', 'failed', 'blocked']),
    summary: tool.schema.string().optional(),
  },
  async execute(args, context) {
    const { sessionID } = context

    // If no summary provided, trigger LLM to generate one
    if (!args.summary) {
      await client.session.summarize({
        path: { id: sessionID },
        body: {
          providerID: "anthropic",
          modelID: "claude-sonnet-4-5"
        }
      })
    }

    // Store compaction in frame state
    await storeCompaction(sessionID, {
      status: args.status,
      summary: args.summary || await getSessionSummary(sessionID),
      logRef: sessionID
    })

    return "Frame completed and compacted"
  }
})
```

---

### 3.4 Context Assembler - THE CRITICAL CAPABILITY

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Current frame working history | **FULL** | Each session has its own isolated context |
| Ancestor compactions | **FULL** | Inject via `noReply: true` or compacting hook |
| Sibling compactions | **FULL** | Same injection mechanism |
| **Exclude non-relevant history** | **FULL** | Sessions are naturally isolated! |

**This is where OpenCode shines compared to Claude Code.**

Claude Code's fundamental limitation: Extensions cannot exclude messages from the linear context. OpenCode solves this through:

1. **Session Isolation**: Each session has its own independent context
2. **`noReply: true` Injection**: Inject frame context at session start without AI response
3. **Compacting Hook Override**: Full control over what's preserved during compaction

**Context Assembly Flow:**

```typescript
async function assembleFrameContext(frameSessionId: string) {
  const frame = await getFrameState(frameSessionId)
  const tree = await getFrameTree()

  const ancestorCompactions = await getAncestorCompactions(tree, frame)
  const siblingCompactions = await getSiblingCompactions(tree, frame)

  // Inject assembled context into frame session
  await client.session.prompt({
    path: { id: frameSessionId },
    body: {
      noReply: true,  // Context only, no AI response
      parts: [{
        type: "text",
        text: `
<frame_context>
  <current_frame id="${frame.id}" status="${frame.status}">
    <goal>${frame.goal}</goal>
  </current_frame>

  <ancestors>
${ancestorCompactions.map(a => `
    <ancestor id="${a.id}">
      <goal>${a.goal}</goal>
      <summary>${a.summary}</summary>
    </ancestor>
`).join('')}
  </ancestors>

  <siblings>
${siblingCompactions.map(s => `
    <sibling id="${s.id}" status="${s.status}">
      <goal>${s.goal}</goal>
      <summary>${s.summary}</summary>
    </sibling>
`).join('')}
  </siblings>
</frame_context>

Focus on your current frame's goal. Your working context is isolated from sibling frame details.
Use flame_pop when your goal is complete.
`
      }]
    }
  })
}
```

---

### 3.5 Frame Controller

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Human push/pop commands | **FULL** | Custom slash commands with `subtask: true` |
| Agent-initiated push/pop | **FULL** | Custom tools + Skills for heuristics |
| Automatic detection | **PARTIAL** | Skills provide guidance, events enable detection |

**Implementation:**

Human control via commands:
```markdown
---
description: Push a new frame
subtask: true
---
Create frame with goal: $ARGUMENTS
Use flame_push tool to initialize.
```

Agent control via tools + skills:
- `flame_push` and `flame_pop` tools available
- `flame-context` skill teaches heuristics
- Plugin events can suggest frame boundaries

---

### 3.6 Plan Manager

| Requirement | Feasibility | Implementation |
|-------------|-------------|----------------|
| Create planned frames | **FULL** | Sessions with `planned` status |
| Planned children | **FULL** | Child sessions with `planned` status |
| Mutable plans | **FULL** | Session updates via SDK |
| Cascade invalidation | **FULL** | Tree traversal + batch updates |

**Implementation:**
OpenCode's todo system can track planned frames, but sessions themselves work better:

```typescript
export const flame_plan = tool({
  description: "Create a planned frame for future execution",
  args: {
    goal: tool.schema.string(),
    parent: tool.schema.string().optional(),
    children: tool.schema.array(tool.schema.string()).optional(),
  },
  async execute(args) {
    const session = await client.session.create({
      body: {
        parentID: args.parent,
        title: `[PLANNED] ${args.goal}`
      }
    })

    await storeFrameState({
      id: session.id,
      goal: args.goal,
      status: 'planned',
      children: []
    })

    // Create planned children if specified
    for (const childGoal of args.children || []) {
      await this.execute({
        goal: childGoal,
        parent: session.id
      })
    }

    return `Planned frame created: ${session.id}`
  }
})
```

---

## 4. Implementation Architecture

### 4.1 Session-as-Frame Architecture

The recommended architecture uses OpenCode sessions directly as frames:

```
                        OpenCode Server (Port 4096)
                                   |
         +--------------------------+--------------------------+
         |                         |                          |
    Root Session              Child Session A           Child Session B
    (Frame: Root)             (Frame: Auth)             (Frame: API)
         |                         |                          |
    [Full context]            [Isolated context         [Isolated context
     - Root goal               - Auth goal               - API goal
     - All children            - Root compaction         - Root compaction
       visible]                - Sibling A compaction]   - Sibling B compaction]
```

**Key Insight:** Each OpenCode session is naturally isolated. By using sessions as frames, we get:
- True context isolation (each session has its own message history)
- Native tree structure (parentID links)
- Persistent logging (session transcripts)
- API for navigation and management

### 4.2 Plugin Structure

```
.opencode/
├── plugin/
│   └── flame-graph.ts        # Main plugin with hooks and tools
├── tool/
│   ├── flame_push.ts         # Push frame tool
│   ├── flame_pop.ts          # Pop frame tool
│   ├── flame_plan.ts         # Plan frame tool
│   └── flame_status.ts       # Frame tree status tool
├── command/
│   ├── push.md               # /push command
│   ├── pop.md                # /pop command
│   ├── frame-status.md       # /frame-status command
│   └── plan.md               # /plan command
├── skill/
│   └── flame-context/
│       └── SKILL.md          # Frame heuristics skill
└── agent/
    └── frame-worker.md       # Specialized frame agent
```

### 4.3 External Orchestrator (Enhanced Control)

For maximum control, an external orchestrator can use the SDK:

```typescript
// flame-orchestrator.ts
import { createOpencodeClient } from "@opencode-ai/sdk"

class FlameOrchestrator {
  private client: ReturnType<typeof createOpencodeClient>
  private frameTree: FrameTree

  constructor(baseUrl: string) {
    this.client = createOpencodeClient({ baseUrl })
    this.frameTree = new FrameTree()
  }

  async pushFrame(goal: string, parentId?: string): Promise<Frame> {
    // Create new session as frame
    const session = await this.client.session.create({
      body: {
        parentID: parentId || this.frameTree.currentFrameId,
        title: goal
      }
    })

    // Add to frame tree
    const frame = this.frameTree.addFrame(session.id, goal, parentId)

    // Inject assembled context
    await this.injectFrameContext(frame)

    // Set as current
    this.frameTree.setCurrentFrame(frame.id)

    return frame
  }

  async popFrame(status: FrameStatus, summary?: string): Promise<void> {
    const frame = this.frameTree.getCurrentFrame()

    // Generate compaction if not provided
    if (!summary) {
      summary = await this.generateCompaction(frame)
    }

    // Store compaction
    frame.compaction = { status, summary, completedAt: new Date() }

    // Move to parent
    this.frameTree.setCurrentFrame(frame.parentId || 'root')

    // Inject updated sibling context into parent
    await this.refreshParentContext(frame.parentId)
  }

  private async injectFrameContext(frame: Frame): Promise<void> {
    const context = this.frameTree.assembleContext(frame.id)

    await this.client.session.prompt({
      path: { id: frame.sessionId },
      body: {
        noReply: true,
        parts: [{ type: "text", text: context }]
      }
    })
  }

  async subscribeToEvents(): Promise<void> {
    const events = await this.client.event.subscribe()

    for await (const event of events.stream) {
      switch (event.type) {
        case 'session.idle':
          await this.onFrameIdle(event.properties.sessionId)
          break
        case 'session.error':
          await this.onFrameError(event.properties.sessionId)
          break
      }
    }
  }
}
```

---

## 5. What's Possible vs Claude Code

### 5.1 Comparison Table

| Capability | Claude Code | OpenCode | Notes |
|------------|-------------|----------|-------|
| **True Context Isolation** | Subagent depth-1 only | Full session isolation | Sessions are independent |
| **Recursive Frames** | No (subagents can't spawn subagents) | Yes (sessions can have children indefinitely) | Major advantage |
| **Context Injection** | Via hooks (additive only) | `noReply: true` injection + compacting hook | Full control |
| **Context Exclusion** | IMPOSSIBLE | NATIVE (sessions are isolated) | Fundamental difference |
| **Compaction Control** | Inject instructions only | Full prompt override | Can define exactly what to preserve |
| **Programmatic Control** | Very limited | Full SDK | External orchestration possible |
| **Event System** | 8 hook events | 30+ events with SSE stream | More integration points |
| **Session Management** | None exposed | Full CRUD + tree APIs | Native frame tree |
| **State Persistence** | External only | Sessions persist + plugin state | Multiple options |
| **Tool Definition** | MCP only | Native TS + MCP | Easier development |
| **Human Control** | Slash commands | Commands with `subtask` option | Similar capability |
| **Agent Heuristics** | Skills (advisory) | Skills + per-agent config | Similar capability |

### 5.2 Key Advantages of OpenCode

1. **Session Isolation = Frame Isolation**
   - Each session has its own context window
   - No need for workarounds - isolation is native
   - Recursive depth is unlimited

2. **`noReply: true` Context Injection**
   - Inject exactly the context needed at frame start
   - No response required - pure context setup
   - Can be called programmatically from orchestrator

3. **Full Compaction Control**
   - `experimental.session.compacting` hook
   - Can completely replace compaction prompt
   - Inject frame-aware instructions for what to preserve

4. **SDK for Orchestration**
   - Create/manage sessions programmatically
   - Event subscription for reactive behavior
   - Full control over frame lifecycle

5. **Native Session Tree**
   - `parentID` on session creation
   - `session.children()` API
   - Tree navigation built-in

### 5.3 Remaining Challenges

| Challenge | OpenCode Limitation | Workaround |
|-----------|---------------------|------------|
| Agent-initiated frame decisions | Agent must call tools | Skills + strong guidance + tool availability |
| Cross-session state | Sessions don't share state | Plugin state file or MCP server |
| UI navigation | TUI focused on single session | Session cycling keybinds exist |
| Automatic frame detection | No built-in heuristics | Event subscription + LLM classification |

---

## 6. Code Examples

### 6.1 Main Plugin

```typescript
// .opencode/plugin/flame-graph.ts
import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"

interface FrameState {
  id: string
  sessionId: string
  goal: string
  parentId?: string
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked'
  compaction?: {
    summary: string
    artifacts: string[]
    decisions: string[]
  }
}

class FrameStore {
  private frames: Map<string, FrameState> = new Map()
  private currentFrameId: string = 'root'

  // ... implementation
}

const frameStore = new FrameStore()

export const FlameGraphPlugin: Plugin = async ({ client }) => {
  return {
    // Handle session events
    event: async ({ event }) => {
      if (event.type === 'session.created') {
        console.log(`New session (potential frame): ${event.properties.sessionID}`)
      }

      if (event.type === 'session.idle') {
        // Session completed - check if it's a frame
        const sessionId = event.properties.sessionID
        const frame = frameStore.getBySessionId(sessionId)
        if (frame && frame.status === 'in_progress') {
          // Prompt for compaction or auto-generate
          await suggestCompaction(client, frame)
        }
      }
    },

    // Customize compaction for frame awareness
    "experimental.session.compacting": async (input, output) => {
      const currentFrame = frameStore.getCurrent()
      if (!currentFrame) return

      const ancestors = frameStore.getAncestors(currentFrame.id)
      const siblings = frameStore.getSiblings(currentFrame.id)

      output.prompt = `
You are generating a continuation prompt for a flame graph session.

CURRENT FRAME: ${currentFrame.goal}
Status: ${currentFrame.status}

ANCESTOR CONTEXT:
${ancestors.map(a => `- ${a.goal}: ${a.compaction?.summary || 'in progress'}`).join('\n')}

SIBLING FRAMES (completed):
${siblings.filter(s => s.status === 'completed')
  .map(s => `- ${s.goal}: ${s.compaction?.summary}`).join('\n')}

COMPACTION PRIORITY:
1. Preserve current frame's working state and progress
2. Keep ancestor goals visible for context
3. Summarize sibling details to outcomes only
4. Reference session IDs for detailed history

Generate a focused continuation prompt.
`
    },

    // Log tool usage to current frame
    "tool.execute.after": async (input, output) => {
      const currentFrame = frameStore.getCurrent()
      if (currentFrame) {
        await logToFrame(currentFrame.id, {
          type: 'tool_use',
          tool: input.tool,
          timestamp: new Date().toISOString()
        })
      }
    },

    // Custom tools for frame management
    tool: {
      flame_push: tool({
        description: "Push a new frame onto the stack for a focused subtask",
        args: {
          goal: tool.schema.string().describe("The goal for this frame"),
        },
        async execute(args, context) {
          const parentFrame = frameStore.getCurrent()

          // Create new session as child
          const session = await client.session.create({
            body: {
              parentID: context.sessionID,
              title: args.goal
            }
          })

          // Create frame
          const frame: FrameState = {
            id: `frame-${Date.now()}`,
            sessionId: session.data!.id,
            goal: args.goal,
            parentId: parentFrame?.id,
            status: 'in_progress'
          }

          frameStore.add(frame)
          frameStore.setCurrent(frame.id)

          // Inject frame context
          await injectFrameContext(client, frame, frameStore)

          return `Created frame: ${frame.id}\nGoal: ${args.goal}\nSession: ${session.data!.id}`
        }
      }),

      flame_pop: tool({
        description: "Complete the current frame and return to parent",
        args: {
          status: tool.schema.enum(['completed', 'failed', 'blocked']),
          summary: tool.schema.string().describe("Summary of what was accomplished"),
          artifacts: tool.schema.array(tool.schema.string()).optional(),
          decisions: tool.schema.array(tool.schema.string()).optional(),
        },
        async execute(args, context) {
          const frame = frameStore.getCurrent()
          if (!frame) return "No active frame to pop"
          if (!frame.parentId) return "Cannot pop root frame"

          // Update frame state
          frame.status = args.status
          frame.compaction = {
            summary: args.summary,
            artifacts: args.artifacts || [],
            decisions: args.decisions || []
          }

          // Move to parent
          frameStore.setCurrent(frame.parentId)
          const parentFrame = frameStore.getCurrent()

          // Refresh parent context with new sibling compaction
          if (parentFrame) {
            await refreshFrameContext(client, parentFrame, frameStore)
          }

          return `Popped frame: ${frame.id} (${args.status})\nReturned to: ${parentFrame?.goal || 'root'}`
        }
      }),

      flame_status: tool({
        description: "Show the current frame tree status",
        args: {},
        async execute() {
          return frameStore.formatTree()
        }
      })
    }
  }
}

async function injectFrameContext(
  client: any,
  frame: FrameState,
  store: FrameStore
) {
  const ancestors = store.getAncestors(frame.id)
  const siblings = store.getSiblings(frame.id)

  await client.session.prompt({
    path: { id: frame.sessionId },
    body: {
      noReply: true,
      parts: [{
        type: "text",
        text: `
<flame_context>
## Current Frame
- **Goal**: ${frame.goal}
- **Frame ID**: ${frame.id}
- **Status**: ${frame.status}

## Ancestor Context
${ancestors.map(a => `
### ${a.goal}
${a.compaction?.summary || 'Currently in progress'}
`).join('\n')}

## Sibling Context (Completed)
${siblings.filter(s => s.compaction).map(s => `
### ${s.goal} (${s.status})
${s.compaction!.summary}
- Artifacts: ${s.compaction!.artifacts.join(', ') || 'none'}
`).join('\n')}

---

**Focus on your goal.** When complete, use \`flame_pop\` with a summary.
</flame_context>
`
      }]
    }
  })
}
```

### 6.2 Frame Worker Agent

```markdown
---
name: frame-worker
description: Specialized agent for executing work within a flame graph frame
mode: subagent
tools:
  flame_push: true
  flame_pop: true
  flame_status: true
  write: true
  edit: true
  bash: true
  read: true
  grep: true
  glob: true
  todowrite: false  # Use flame graph instead
  todoread: false
---

# Frame Worker Agent

You are executing work within a FRAME - an isolated unit of work in a flame graph context management system.

## Your Context

At the start of your session, you received a `<flame_context>` block containing:
1. **Your Goal**: The specific task for this frame
2. **Ancestor Summaries**: What parent frames have accomplished
3. **Sibling Summaries**: What completed sibling frames achieved

## Working Principles

1. **Stay Focused**: Only work on your specific goal
2. **No Scope Creep**: Don't venture into sibling frame territory
3. **Bounded Work**: When your goal is complete, stop
4. **Retry-Friendly**: If you fail, your entire frame can be retried

## When to Create Child Frames

Use `flame_push` if you identify a subtask that:
- Could be retried independently
- Represents a significant context switch
- Would benefit from isolated tracking

## On Completion

When your goal is achieved (or you hit a blocker), use `flame_pop` with:
- **status**: completed, failed, or blocked
- **summary**: 1-2 sentences of what was accomplished
- **artifacts**: file paths created/modified
- **decisions**: important choices made

This becomes your "compaction" visible to parent and sibling frames.

## What NOT to Include in Summary

- Detailed debugging traces
- Full code snippets (reference files instead)
- Exploration of rejected approaches

Your full history remains in your session for reference if needed.
```

### 6.3 Push Command

```markdown
---
description: Push a new frame onto the flame graph stack
subtask: true
agent: frame-worker
---

# Push Frame: $ARGUMENTS

## Instructions

You are starting a new frame with the goal: **$ARGUMENTS**

1. Acknowledge the frame context you received
2. Plan your approach for this specific goal
3. Execute the work, staying focused
4. When complete, use `flame_pop` to return to parent

!`echo "Frame started at $(date)" >> ~/.flame/log.txt`

Begin working on your goal now.
```

### 6.4 External Orchestrator Script

```typescript
// scripts/flame-orchestrator.ts
import { createOpencodeClient } from "@opencode-ai/sdk"

const client = createOpencodeClient({ baseUrl: "http://localhost:4096" })

async function runFlameSession() {
  // Create root session
  const root = await client.session.create({
    body: { title: "Build Application" }
  })
  console.log(`Root session: ${root.data!.id}`)

  // Start with a goal
  await client.session.prompt({
    path: { id: root.data!.id },
    body: {
      parts: [{ type: "text", text: "Build a REST API with authentication and CRUD endpoints" }]
    }
  })

  // Subscribe to events
  const events = await client.event.subscribe()

  for await (const event of events.stream) {
    console.log(`Event: ${event.type}`, event.properties)

    if (event.type === 'session.idle') {
      // Session completed a response, check for frame actions
      const sessionId = event.properties.sessionId

      // Check if a child session was created (frame push)
      const children = await client.session.children({ path: { id: sessionId } })
      if (children.data && children.data.length > 0) {
        console.log(`Frame pushed: ${children.data[children.data.length - 1].id}`)
      }
    }
  }
}

runFlameSession().catch(console.error)
```

---

## 7. Conclusion and Recommendations

### 7.1 Feasibility Summary

| Component | Feasibility | Implementation |
|-----------|-------------|----------------|
| Frame State Manager | **FULL** | Native session tree + plugin state |
| Log Persistence | **FULL** | Native session persistence |
| Compaction Generator | **FULL** | Custom tool + summarize API |
| Context Assembler | **FULL** | `noReply` injection + compacting hook |
| Frame Controller (Human) | **FULL** | Commands with `subtask: true` |
| Frame Controller (Agent) | **FULL** | Custom tools + skills |
| Plan Manager | **FULL** | Sessions with planned status |
| **True Context Isolation** | **FULL** | Session isolation is native |
| **Recursive Frames** | **FULL** | Unlimited session depth |

### 7.2 Verdict

**OpenCode is HIGHLY SUITABLE for Flame Graph Context Management.**

The key advantages over Claude Code:

1. **Session-based isolation solves the fundamental problem** - Each session has its own context, eliminating the need for workarounds

2. **SDK enables external orchestration** - Full programmatic control for sophisticated frame management

3. **Compaction hook provides context control** - Can override compaction behavior for frame-awareness

4. **`noReply` injection enables context assembly** - Can inject exactly the context needed at frame boundaries

5. **Event system enables reactive behavior** - Can respond to session lifecycle events

### 7.3 Comparison to Claude Code Approach

| Aspect | Claude Code (Proposal 01) | OpenCode (This Proposal) |
|--------|---------------------------|--------------------------|
| **Context Isolation** | Subagents (depth-1 only) | Full session isolation (unlimited depth) |
| **Implementation Complexity** | High (many workarounds) | Medium (uses native features) |
| **True Frame Semantics** | Partial | Full |
| **Recursive Support** | No (subagent limitation) | Yes (session tree) |
| **Compaction Control** | Inject-only | Full override |
| **External Control** | Very limited | Full SDK |
| **Verdict** | "Substantially Feasible" with constraints | **Highly Feasible** with native support |

### 7.4 Recommendations

#### Immediate (Build Now)

1. **Create the plugin** with frame state management and custom tools
2. **Implement `experimental.session.compacting` hook** for frame-aware compaction
3. **Create frame-worker agent** with frame heuristics
4. **Build `/push` and `/pop` commands** with `subtask: true`
5. **Create flame-context skill** for agent guidance

#### Enhanced (Phase 2)

1. **Build external orchestrator** using SDK for maximum control
2. **Add event-driven frame detection** via subscription
3. **Create UI plugin** for frame tree visualization
4. **Implement planned frame management** with cascade invalidation

#### Future (Request from OpenCode Team)

1. **Session metadata API** - Store custom data on sessions for frame state
2. **Session context injection API** - More direct way to set initial context
3. **Frame-aware compaction** - Native support for multi-session context assembly

### 7.5 Next Steps

1. Set up OpenCode development environment
2. Create proof-of-concept plugin with core frame tools
3. Test session isolation and context injection
4. Validate compacting hook behavior
5. Build external orchestrator for enhanced control
6. Compare real-world performance to Claude Code approach

---

**End of Proposal**
