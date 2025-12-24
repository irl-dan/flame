# Proposal: Flame Graph Context Management via OpenCode SDK

**Date:** 2025-12-23
**Status:** Analysis Complete
**Verdict:** FEASIBLE WITH LIMITATIONS - Parent/child session architecture exists, but true context exclusion requires careful orchestration

---

## Executive Summary

This proposal analyzes implementing "Flame Graph Context Management" using OpenCode's SDK (`@opencode-ai/sdk`). OpenCode provides a TypeScript SDK that offers programmatic access to sessions, messages, agents, and tools through an HTTP server API.

**Key Finding:** OpenCode's SDK provides **session management with parent/child relationships** that could serve as the foundation for frame-based context management. However, the SDK operates at a higher level than the Claude Agents SDK, with less granular control over context construction per API call.

**Critical Insight:** OpenCode already has native support for:
1. **Parent/Child Sessions** - Sessions can have a `parentID`, creating a tree structure
2. **Child Session Navigation** - TUI keybinds exist for cycling through child sessions
3. **Session Summarization** - API endpoint for summarizing sessions
4. **Compaction with Plugin Hooks** - `experimental.session.compacting` hook for customization
5. **Subagent Tool** - `task` tool that spawns child sessions for focused work

**Bottom Line:** OpenCode provides excellent primitives for building flame graph context management. However, achieving TRUE context isolation (excluding sibling history from active context) requires building an orchestration layer that manually constructs context for each session rather than relying on OpenCode's internal context assembly.

---

## Table of Contents

1. [OpenCode SDK Overview](#1-opencode-sdk-overview)
2. [Session Management Architecture](#2-session-management-architecture)
3. [Context and Message Handling](#3-context-and-message-handling)
4. [Existing Subagent/Child Session Model](#4-existing-subagentchild-session-model)
5. [Plugin System for Context Control](#5-plugin-system-for-context-control)
6. [Implementation Architecture](#6-implementation-architecture)
7. [Code Examples](#7-code-examples)
8. [Feasibility Analysis](#8-feasibility-analysis)
9. [Comparison to Claude Agents SDK](#9-comparison-to-claude-agents-sdk)
10. [Recommendations](#10-recommendations)

---

## 1. OpenCode SDK Overview

### 1.1 What OpenCode Is

OpenCode is an open-source coding assistant similar to Claude Code, built on top of various LLM providers. It provides:

- **TUI (Terminal User Interface)** - Interactive chat interface
- **Server Mode** - Headless HTTP server with OpenAPI spec
- **TypeScript SDK** - Type-safe client for programmatic access
- **Plugin System** - Hooks for extending behavior
- **Multi-Agent Support** - Primary agents and subagents

### 1.2 SDK Installation and Usage

```typescript
import { createOpencode, createOpencodeClient } from "@opencode-ai/sdk"

// Start server and create client
const { client, server } = await createOpencode({
  hostname: "127.0.0.1",
  port: 4096,
  config: {
    model: "anthropic/claude-sonnet-4-5",
  }
})

// Or connect to existing server
const client = createOpencodeClient({
  baseUrl: "http://localhost:4096"
})
```

### 1.3 Core API Categories

| Category | Key Methods | Purpose |
|----------|-------------|---------|
| **Session** | `create`, `get`, `list`, `delete`, `fork`, `children`, `summarize` | Manage conversation sessions |
| **Message** | `prompt`, `messages`, `message` | Send/retrieve messages |
| **Config** | `get`, `update`, `providers` | Configuration management |
| **Agent** | `agents` | List available agents |
| **Event** | `subscribe` | Real-time event streaming |
| **File** | `read`, `find`, `status` | File system operations |

---

## 2. Session Management Architecture

### 2.1 Session Data Model

```typescript
type Session = {
  id: string                    // Unique session identifier
  projectID: string             // Associated project
  directory: string             // Working directory
  parentID?: string             // Parent session ID (CRITICAL for flame graph!)
  title: string                 // Session title
  version: string               // OpenCode version
  summary?: {
    additions: number
    deletions: number
    files: number
    diffs?: FileDiff[]
  }
  share?: { url: string }       // Share URL if shared
  time: {
    created: number
    updated: number
    compacting?: number         // Compaction timestamp
  }
  revert?: {                    // Revert state
    messageID: string
    partID?: string
    snapshot?: string
    diff?: string
  }
}
```

### 2.2 Session Hierarchy

OpenCode ALREADY supports parent/child session relationships:

```typescript
// Create child session
const childSession = await client.session.create({
  body: {
    parentID: parentSessionId,  // Links to parent!
    title: "Auth implementation subtask"
  }
})

// Get all children of a session
const children = await client.session.children({
  path: { id: parentSessionId }
})
```

### 2.3 Session Operations for Flame Graph

| Operation | SDK Method | Flame Graph Use |
|-----------|------------|-----------------|
| Create child frame | `session.create({ body: { parentID } })` | Push new frame |
| List children | `session.children({ path: { id } })` | Get child frames |
| Get session | `session.get({ path: { id } })` | Read frame state |
| Summarize | `session.summarize({ path: { id }, body })` | Generate compaction |
| Fork session | `session.fork({ path: { id } })` | Branch conversation |
| Delete | `session.delete({ path: { id } })` | Remove frame |

---

## 3. Context and Message Handling

### 3.1 Message Types

```typescript
type Message = UserMessage | AssistantMessage

type UserMessage = {
  id: string
  sessionID: string
  role: "user"
  time: { created: number }
  agent: string
  model: { providerID: string; modelID: string }
  system?: string              // Custom system prompt!
  tools?: { [key: string]: boolean }
}

type AssistantMessage = {
  id: string
  sessionID: string
  role: "assistant"
  parentID: string             // Links to user message
  modelID: string
  providerID: string
  mode: string
  cost: number
  tokens: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
  summary?: boolean            // Is this a compaction summary?
}
```

### 3.2 Sending Prompts with Context Control

The SDK's `prompt` method has important parameters for context injection:

```typescript
const result = await client.session.prompt({
  path: { id: sessionId },
  body: {
    model: { providerID: "anthropic", modelID: "claude-sonnet-4-5" },
    agent: "build",
    noReply: false,          // Set true to inject context without LLM response
    system: "Custom system prompt for this frame...",  // Frame-specific context!
    tools: {
      write: true,
      bash: false,           // Control tool availability per frame
    },
    parts: [
      { type: "text", text: "Your prompt here" }
    ]
  }
})
```

### 3.3 The `noReply` Option - Critical for Context Injection

```typescript
// Inject context WITHOUT triggering AI response
await client.session.prompt({
  path: { id: sessionId },
  body: {
    noReply: true,  // Just add to context, don't generate response
    parts: [
      { type: "text", text: `
        ## Parent Frame Context
        You are working on a subtask within a flame graph structure.

        ## Completed Sibling Summaries
        - Auth: Implemented JWT with refresh tokens
        - Database: Created User and Session models

        ## Current Goal
        Build API routes for the application.
      ` }
    ]
  }
})

// Then send the actual work prompt
await client.session.prompt({
  path: { id: sessionId },
  body: {
    parts: [{ type: "text", text: "Begin implementing the API routes" }]
  }
})
```

### 3.4 Reading Session Messages

```typescript
// Get all messages in a session
const messages = await client.session.messages({
  path: { id: sessionId },
  query: { limit: 100 }
})

// Each message includes parts (text, tool calls, etc.)
for (const msg of messages.data) {
  console.log(msg.info.role, msg.parts)
}
```

---

## 4. Existing Subagent/Child Session Model

### 4.1 The Task Tool

OpenCode's `task` tool already implements a form of child session management:

```typescript
// From /packages/opencode/src/tool/task.ts
export const TaskTool = Tool.define("task", async () => {
  return {
    description: "...",
    parameters: z.object({
      description: z.string(),
      prompt: z.string(),
      subagent_type: z.string(),
      session_id: z.string().optional(),  // Can resume existing task session
    }),
    async execute(params, ctx) {
      // Creates child session linked to parent
      const session = await Session.create({
        parentID: ctx.sessionID,  // Links child to parent!
        title: params.description + ` (@${agent.name} subagent)`
      })

      // Execute work in child session
      const result = await SessionPrompt.prompt({
        sessionID: session.id,
        // ... work in isolated session
      })

      // Return summary to parent
      return {
        title: params.description,
        metadata: { sessionId: session.id },
        output: text + "\n\n<task_metadata>session_id: " + session.id + "</task_metadata>"
      }
    }
  }
})
```

### 4.2 Subagent Architecture

OpenCode distinguishes between:

| Type | Mode | Purpose |
|------|------|---------|
| **Primary Agents** | `primary` | Main conversation agents (Build, Plan) |
| **Subagents** | `subagent` | Specialized workers spawned for tasks |

Subagents:
- Run in their own child sessions
- Have restricted tools (no `todowrite`, no `task` - prevents infinite nesting)
- Can have custom prompts and models
- Return summaries to parent session

### 4.3 Child Session Navigation in TUI

OpenCode already supports navigating between parent and child sessions:

```json
{
  "keybinds": {
    "session_child_cycle": "\\<Leader>+Right",
    "session_child_cycle_reverse": "\\<Leader>+Left"
  }
}
```

This shows the concept of frame-based work is partially implemented!

---

## 5. Plugin System for Context Control

### 5.1 Plugin Architecture

Plugins can hook into various events and modify behavior:

```typescript
// .opencode/plugin/flame-context.ts
import type { Plugin } from "@opencode-ai/plugin"

export const FlameContextPlugin: Plugin = async ({ client, project }) => {
  return {
    // Hook into session compaction
    "experimental.session.compacting": async (input, output) => {
      // Inject flame graph context into compaction
      output.context.push(`
## Flame Graph Frame
Frame ID: ${input.sessionID}
Status: completing
Log path: .flame/logs/${input.sessionID}.jsonl
      `)
    },

    // Hook before tool execution
    "tool.execute.before": async (input, output) => {
      // Track frame artifacts
    },

    // Hook on session events
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        // Session finished, potentially generate compaction
      }
    }
  }
}
```

### 5.2 Compaction Hook Details

The `experimental.session.compacting` hook allows customization:

```typescript
"experimental.session.compacting": async (input, output) => {
  // Option 1: Add context to default prompt
  output.context.push("Additional context for compaction...")

  // Option 2: Replace entire compaction prompt
  output.prompt = `
    You are generating a flame graph frame compaction.

    ## Requirements
    1. Summarize what was accomplished
    2. List artifacts created
    3. Note key decisions
    4. Provide pointer to full log

    Generate in this format:
    STATUS: completed|failed|blocked
    SUMMARY: ...
    ARTIFACTS: file1, file2, ...
    DECISIONS: ...
  `
}
```

### 5.3 Event Subscription

```typescript
const events = await client.event.subscribe()
for await (const event of events.stream) {
  switch (event.type) {
    case "session.created":
      // New frame created
      break
    case "session.idle":
      // Frame work completed
      break
    case "session.compacted":
      // Compaction generated
      break
    case "message.updated":
      // Message added/modified
      break
    case "tool.execute.after":
      // Track artifacts from tool calls
      break
  }
}
```

---

## 6. Implementation Architecture

### 6.1 Flame Graph Orchestrator Using OpenCode SDK

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    Flame Graph Orchestrator                               │
│                                                                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────────┐  │
│  │  Frame State    │  │    Context      │  │    Compaction            │  │
│  │   Manager       │  │   Assembler     │  │    Generator             │  │
│  │                 │  │                 │  │                          │  │
│  │ • Frame tree    │  │ • Build context │  │ • Summarize on pop       │  │
│  │ • Session→Frame │  │ • Inject via    │  │ • Extract artifacts      │  │
│  │ • Status track  │  │   noReply/sys   │  │ • Store compactions      │  │
│  └────────┬────────┘  └────────┬────────┘  └────────────┬─────────────┘  │
│           │                    │                        │                 │
│           └────────────────────┼────────────────────────┘                 │
│                                │                                          │
│  ┌─────────────────────────────┴──────────────────────────────────────┐  │
│  │                    OpenCode SDK Client                              │  │
│  │                                                                     │  │
│  │   • session.create(parentID)  → New child frame                     │  │
│  │   • session.prompt(noReply)   → Inject frame context               │  │
│  │   • session.prompt(system)    → Custom system prompt per frame     │  │
│  │   • session.messages()        → Read frame history                 │  │
│  │   • session.summarize()       → Generate compaction                │  │
│  │   • event.subscribe()         → Monitor session events             │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                │                                          │
└────────────────────────────────┼──────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         OpenCode Server                                     │
│                                                                             │
│   HTTP API → Session Management → LLM Calls → Tool Execution               │
└────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Frame State Data Model

```typescript
interface FlameFrame {
  id: string
  sessionId: string           // OpenCode session ID
  parentId: string | null     // Parent frame ID
  children: string[]          // Child frame IDs
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked'
  goal: string
  compaction: FrameCompaction | null
  logPath: string
  artifacts: string[]
  createdAt: number
  completedAt: number | null
}

interface FrameCompaction {
  summary: string
  artifacts: string[]
  decisions: string[]
  status: 'completed' | 'failed' | 'blocked'
}

interface FlameState {
  frames: Map<string, FlameFrame>
  sessionToFrame: Map<string, string>  // Map OpenCode session → Frame
  currentFrameId: string
  rootFrameId: string
}
```

### 6.3 Context Assembly Strategy

The KEY CHALLENGE is that OpenCode sessions accumulate their own linear history. To achieve true context isolation:

**Strategy 1: Context Injection at Frame Start**

```typescript
async function executeFrame(frameId: string) {
  const frame = state.frames.get(frameId)
  const session = await client.session.create({
    body: {
      parentID: frame.parentId ? state.frames.get(frame.parentId).sessionId : undefined,
      title: frame.goal
    }
  })

  // Inject assembled context as first message (noReply)
  const context = assembleContext(frameId)
  await client.session.prompt({
    path: { id: session.data.id },
    body: {
      noReply: true,
      parts: [{ type: "text", text: context }]
    }
  })

  // Now execute work
  await client.session.prompt({
    path: { id: session.data.id },
    body: {
      parts: [{ type: "text", text: `Begin work on: ${frame.goal}` }]
    }
  })
}
```

**Strategy 2: Custom System Prompt Per Frame**

```typescript
async function executeFrame(frameId: string) {
  const context = assembleContext(frameId)

  await client.session.prompt({
    path: { id: session.id },
    body: {
      system: context,  // Inject as system prompt
      parts: [{ type: "text", text: `Work on: ${frame.goal}` }]
    }
  })
}
```

### 6.4 Limitations of OpenCode SDK Approach

| Aspect | Limitation | Workaround |
|--------|------------|------------|
| **Context Isolation** | Each session accumulates its own history | Inject context at start, rely on compaction |
| **Mid-Session Context** | Cannot dynamically modify past messages | Use `noReply` to inject updates |
| **Session History Exclusion** | Cannot exclude sibling session content | Orchestrator builds context, never includes raw sibling history |
| **Compaction Control** | Limited control over compaction content | Use plugin hook or orchestrator-generated summaries |

---

## 7. Code Examples

### 7.1 Complete Flame Graph Orchestrator

```typescript
// flame-opencode.ts
import { createOpencode, type OpencodeClient } from "@opencode-ai/sdk"

interface FlameFrame {
  id: string
  sessionId: string | null
  parentId: string | null
  children: string[]
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked'
  goal: string
  compaction: { summary: string; artifacts: string[] } | null
}

class FlameOrchestrator {
  private client: OpencodeClient
  private frames = new Map<string, FlameFrame>()
  private currentFrameId: string = ''
  private rootFrameId: string = ''

  constructor(client: OpencodeClient) {
    this.client = client
  }

  async init(rootGoal: string): Promise<string> {
    const frameId = `frame-${crypto.randomUUID().slice(0, 8)}`
    this.frames.set(frameId, {
      id: frameId,
      sessionId: null,
      parentId: null,
      children: [],
      status: 'in_progress',
      goal: rootGoal,
      compaction: null
    })
    this.rootFrameId = frameId
    this.currentFrameId = frameId
    return frameId
  }

  async pushFrame(goal: string): Promise<string> {
    const parentFrame = this.frames.get(this.currentFrameId)!
    const frameId = `frame-${crypto.randomUUID().slice(0, 8)}`

    // Create OpenCode child session
    const session = await this.client.session.create({
      body: {
        parentID: parentFrame.sessionId ?? undefined,
        title: goal
      }
    })

    const frame: FlameFrame = {
      id: frameId,
      sessionId: session.data!.id,
      parentId: this.currentFrameId,
      children: [],
      status: 'in_progress',
      goal,
      compaction: null
    }

    this.frames.set(frameId, frame)
    parentFrame.children.push(frameId)
    this.currentFrameId = frameId

    // Inject context
    const context = this.assembleContext(frameId)
    await this.client.session.prompt({
      path: { id: session.data!.id },
      body: {
        noReply: true,
        parts: [{ type: "text", text: context }]
      }
    })

    return frameId
  }

  async popFrame(status: 'completed' | 'failed' | 'blocked', summary: string): Promise<void> {
    const frame = this.frames.get(this.currentFrameId)!

    frame.status = status
    frame.compaction = {
      summary,
      artifacts: await this.extractArtifacts(frame.sessionId!)
    }

    if (frame.parentId) {
      this.currentFrameId = frame.parentId

      // Inject child completion into parent context
      const parentFrame = this.frames.get(frame.parentId)!
      if (parentFrame.sessionId) {
        await this.client.session.prompt({
          path: { id: parentFrame.sessionId },
          body: {
            noReply: true,
            parts: [{
              type: "text",
              text: `
## Child Frame Completed
**Goal:** ${frame.goal}
**Status:** ${status}
**Summary:** ${summary}
**Artifacts:** ${frame.compaction.artifacts.join(', ') || 'none'}
              `.trim()
            }]
          }
        })
      }
    }
  }

  async executeCurrentFrame(): Promise<void> {
    const frame = this.frames.get(this.currentFrameId)!

    // Create session if needed
    if (!frame.sessionId) {
      const session = await this.client.session.create({
        body: {
          parentID: frame.parentId
            ? this.frames.get(frame.parentId)?.sessionId ?? undefined
            : undefined,
          title: frame.goal
        }
      })
      frame.sessionId = session.data!.id

      // Inject initial context
      const context = this.assembleContext(frame.id)
      await this.client.session.prompt({
        path: { id: frame.sessionId },
        body: {
          noReply: true,
          parts: [{ type: "text", text: context }]
        }
      })
    }

    // Execute work
    const result = await this.client.session.prompt({
      path: { id: frame.sessionId },
      body: {
        parts: [{
          type: "text",
          text: `Begin work on: ${frame.goal}

When complete, respond with FRAME_COMPLETE: <summary>
To create a subtask, respond with PUSH_FRAME: <subtask goal>
If blocked, respond with FRAME_BLOCKED: <reason>`
        }]
      }
    })

    // Handle frame signals in response
    await this.handleFrameSignals(result.data)
  }

  private assembleContext(frameId: string): string {
    const frame = this.frames.get(frameId)!
    const ancestors = this.getAncestors(frameId)
    const siblings = this.getCompletedSiblings(frameId)

    const parts: string[] = []

    parts.push(`# Flame Graph Context

You are operating within a FLAME GRAPH context management system.
Your work is organized as a tree of frames, not linear chat history.
`)

    // Ancestor compactions
    if (ancestors.length > 0) {
      parts.push(`## Ancestor Context (Compacted)`)
      for (const ancestor of ancestors.reverse()) {
        if (ancestor.compaction) {
          parts.push(`
### ${ancestor.goal}
**Status:** ${ancestor.status}
**Summary:** ${ancestor.compaction.summary}
**Artifacts:** ${ancestor.compaction.artifacts.join(', ') || 'none'}
`)
        }
      }
    }

    // Sibling compactions
    if (siblings.length > 0) {
      parts.push(`## Completed Sibling Frames`)
      for (const sibling of siblings) {
        parts.push(`
### ${sibling.goal}
**Status:** ${sibling.status}
**Summary:** ${sibling.compaction?.summary || 'No summary'}
**Artifacts:** ${sibling.compaction?.artifacts.join(', ') || 'none'}
`)
      }
    }

    // Current frame
    parts.push(`
## Current Frame
**Frame ID:** ${frame.id}
**Goal:** ${frame.goal}

### Instructions
1. Focus exclusively on this frame's goal
2. When complete, output: FRAME_COMPLETE: <summary>
3. For subtasks, output: PUSH_FRAME: <subtask goal>
4. If blocked, output: FRAME_BLOCKED: <reason>
`)

    return parts.join('\n')
  }

  private getAncestors(frameId: string): FlameFrame[] {
    const ancestors: FlameFrame[] = []
    let current = this.frames.get(frameId)
    while (current?.parentId) {
      const parent = this.frames.get(current.parentId)
      if (parent) {
        ancestors.push(parent)
        current = parent
      } else break
    }
    return ancestors
  }

  private getCompletedSiblings(frameId: string): FlameFrame[] {
    const frame = this.frames.get(frameId)
    if (!frame?.parentId) return []

    const parent = this.frames.get(frame.parentId)
    if (!parent) return []

    return parent.children
      .filter(id => id !== frameId)
      .map(id => this.frames.get(id)!)
      .filter(f => f.status === 'completed' && f.compaction)
  }

  private async extractArtifacts(sessionId: string): Promise<string[]> {
    const messages = await this.client.session.messages({
      path: { id: sessionId }
    })

    const artifacts: string[] = []
    for (const msg of messages.data || []) {
      for (const part of msg.parts) {
        if (part.type === 'tool' && part.state.status === 'completed') {
          if (part.tool === 'write' || part.tool === 'edit') {
            const filePath = part.state.input?.file_path
            if (filePath && !artifacts.includes(filePath)) {
              artifacts.push(filePath)
            }
          }
        }
      }
    }
    return artifacts
  }

  private async handleFrameSignals(response: any): Promise<void> {
    // Parse response for frame signals
    const text = response?.parts?.find((p: any) => p.type === 'text')?.text ?? ''

    if (text.includes('FRAME_COMPLETE:')) {
      const summary = text.split('FRAME_COMPLETE:')[1]?.trim().split('\n')[0] ?? ''
      await this.popFrame('completed', summary)
    } else if (text.includes('PUSH_FRAME:')) {
      const goal = text.split('PUSH_FRAME:')[1]?.trim().split('\n')[0] ?? ''
      await this.pushFrame(goal)
      await this.executeCurrentFrame()
    } else if (text.includes('FRAME_BLOCKED:')) {
      const reason = text.split('FRAME_BLOCKED:')[1]?.trim().split('\n')[0] ?? ''
      await this.popFrame('blocked', reason)
    }
  }

  printTree(): void {
    const printFrame = (frameId: string, indent: number): void => {
      const frame = this.frames.get(frameId)
      if (!frame) return

      const prefix = '  '.repeat(indent)
      const current = frameId === this.currentFrameId ? ' <-- CURRENT' : ''
      console.log(`${prefix}[${frame.status}] ${frame.goal}${current}`)

      if (frame.compaction) {
        console.log(`${prefix}  Summary: ${frame.compaction.summary}`)
      }

      for (const childId of frame.children) {
        printFrame(childId, indent + 1)
      }
    }

    console.log('\n=== Flame Graph Tree ===')
    printFrame(this.rootFrameId, 0)
    console.log('========================\n')
  }
}

// Usage
async function main() {
  const { client } = await createOpencode()

  const orchestrator = new FlameOrchestrator(client)
  await orchestrator.init("Build REST API with authentication")

  // Push a child frame
  await orchestrator.pushFrame("Implement JWT authentication")

  // Execute work
  await orchestrator.executeCurrentFrame()

  // Print tree
  orchestrator.printTree()
}

main().catch(console.error)
```

### 7.2 Flame Graph Plugin for OpenCode

```typescript
// .opencode/plugin/flame-graph.ts
import type { Plugin } from "@opencode-ai/plugin"
import * as fs from "fs"
import * as path from "path"

interface FrameState {
  id: string
  sessionId: string
  parentId: string | null
  status: string
  goal: string
  compaction?: { summary: string; artifacts: string[] }
}

export const FlameGraphPlugin: Plugin = async ({ project, client }) => {
  const statePath = path.join(project.worktree, '.flame', 'state.json')

  function loadState(): { frames: Record<string, FrameState>, current: string } {
    if (fs.existsSync(statePath)) {
      return JSON.parse(fs.readFileSync(statePath, 'utf-8'))
    }
    return { frames: {}, current: '' }
  }

  function saveState(state: any) {
    fs.mkdirSync(path.dirname(statePath), { recursive: true })
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2))
  }

  return {
    // Customize compaction to include frame context
    "experimental.session.compacting": async (input, output) => {
      const state = loadState()
      const frame = Object.values(state.frames).find(f => f.sessionId === input.sessionID)

      if (frame) {
        output.prompt = `
You are generating a FLAME GRAPH frame compaction summary.

## Frame Information
- ID: ${frame.id}
- Goal: ${frame.goal}
- Status: completing

## Requirements
Generate a concise summary that includes:
1. What was accomplished
2. Key files/artifacts created or modified
3. Important decisions made
4. Any blockers or issues encountered

Format:
STATUS: completed|failed|blocked
SUMMARY: [2-3 sentence summary]
ARTIFACTS: [comma-separated list of file paths]
DECISIONS: [key technical decisions]
`
      }
    },

    // Track session events
    event: async ({ event }) => {
      const state = loadState()

      if (event.type === "session.created") {
        const info = event.properties.info
        if (info.parentID) {
          // This is a child session - could be a new frame
          console.log(`[FLAME] Potential child frame created: ${info.id}`)
        }
      }

      if (event.type === "session.idle") {
        const sessionId = event.properties.sessionID
        const frame = Object.values(state.frames).find(f => f.sessionId === sessionId)

        if (frame && frame.status === 'in_progress') {
          console.log(`[FLAME] Frame ${frame.id} work completed, awaiting signal`)
        }
      }
    },

    // Track file modifications for artifacts
    "tool.execute.after": async (input, output) => {
      if (input.tool === 'write' || input.tool === 'edit') {
        const state = loadState()
        const frame = Object.values(state.frames).find(f => f.sessionId === input.sessionID)

        if (frame) {
          console.log(`[FLAME] Artifact created in frame ${frame.id}: ${input.args.filePath}`)
        }
      }
    }
  }
}
```

---

## 8. Feasibility Analysis

### 8.1 What OpenCode SDK DOES Provide

| Feature | Support | Notes |
|---------|---------|-------|
| **Session Creation** | FULL | `session.create({ parentID })` supports hierarchy |
| **Parent/Child Relationship** | FULL | Native `parentID` field |
| **Child Session Listing** | FULL | `session.children()` API |
| **Context Injection** | PARTIAL | Via `noReply: true` or `system` parameter |
| **Session Summarization** | PARTIAL | `session.summarize()` exists but LLM-generated |
| **Event Streaming** | FULL | `event.subscribe()` for real-time updates |
| **Plugin Hooks** | FULL | `experimental.session.compacting` and more |
| **Custom Agents** | FULL | Define agents with custom prompts/tools |
| **Tool Control** | FULL | Enable/disable tools per prompt |

### 8.2 What OpenCode SDK Does NOT Provide

| Feature | Gap | Impact |
|---------|-----|--------|
| **Context Exclusion** | Cannot exclude sibling session history | Must build context externally |
| **Dynamic Context Modification** | Cannot modify past messages | Inject updates via new messages |
| **Session Fork with Isolation** | Fork copies messages, doesn't isolate | New sessions are truly isolated |
| **Programmatic Compaction** | LLM generates compaction | Use plugin to customize prompt |

### 8.3 Verdict: FEASIBLE WITH LIMITATIONS

**TRUE context isolation is ACHIEVABLE** via OpenCode SDK by:

1. **Creating new sessions for each frame** - Each frame gets its own OpenCode session
2. **Building context externally** - Orchestrator assembles context from compactions only
3. **Injecting context at frame start** - Use `noReply: true` to add assembled context
4. **Never including raw sibling history** - Only include compacted summaries

**The key insight:** While OpenCode sessions accumulate linear history internally, by:
- Using separate sessions per frame
- Building our own context from compactions
- Injecting that context into new sessions

We effectively achieve the same isolation as the Claude Agents SDK approach.

---

## 9. Comparison to Claude Agents SDK

### 9.1 Feature Comparison

| Feature | Claude Agents SDK (Proposal 03) | OpenCode SDK (This Proposal) |
|---------|--------------------------------|------------------------------|
| **Context Control** | Full - we build entire context | Partial - inject at start |
| **Session Model** | We manage sessions ourselves | OpenCode manages sessions |
| **Native Hierarchy** | Must implement ourselves | Built-in parent/child |
| **Message Streaming** | Direct SDK streaming | HTTP + SSE events |
| **Tool Execution** | SDK handles tools | OpenCode handles tools |
| **Compaction** | Implement ourselves | Plugin hook available |
| **TUI Integration** | None | Full TUI available |
| **Multi-Provider** | Anthropic only (primarily) | Any provider via OpenCode |
| **Implementation Effort** | Medium-High | Medium |

### 9.2 Architectural Differences

```
Claude Agents SDK (Proposal 03):
================================
[Orchestrator] → [SDK query()] → [Anthropic API]
     │
     └── Full context control per call
     └── Direct streaming access
     └── Must implement all frame logic

OpenCode SDK (This Proposal):
==============================
[Orchestrator] → [OpenCode SDK] → [OpenCode Server] → [Any LLM Provider]
     │
     └── Leverage existing session hierarchy
     └── Plugin hooks for customization
     └── TUI available for debugging
     └── Less direct context control
```

### 9.3 When to Choose Which

| Use Case | Recommended Approach |
|----------|---------------------|
| **Maximum context control** | Claude Agents SDK |
| **Multi-provider support** | OpenCode SDK |
| **Faster development** | OpenCode SDK (primitives exist) |
| **TUI debugging** | OpenCode SDK |
| **Production deployment** | Either (tradeoffs differ) |
| **Single-process solution** | Claude Agents SDK |
| **Leverage existing codebase** | OpenCode SDK |

---

## 10. Recommendations

### 10.1 Verdict Summary

**OpenCode SDK is FEASIBLE for Flame Graph Context Management** with these caveats:

| Aspect | Assessment |
|--------|------------|
| **Core Requirement: Context Isolation** | ACHIEVABLE via orchestrator-managed context |
| **Parent/Child Session Structure** | NATIVE SUPPORT |
| **Compaction Customization** | GOOD via plugin hooks |
| **Implementation Complexity** | MEDIUM |
| **TUI Debugging Capability** | EXCELLENT |
| **Multi-Provider Flexibility** | EXCELLENT |

### 10.2 Recommended Implementation Strategy

#### Phase 1: Orchestrator Foundation (2-3 days)
1. Implement `FlameOrchestrator` class using OpenCode SDK
2. Build frame state management (external to OpenCode)
3. Implement context assembly from compactions
4. Create push/pop mechanics with session creation

#### Phase 2: Plugin Integration (1-2 days)
1. Create `FlameGraphPlugin` for compaction customization
2. Hook into session events for artifact tracking
3. Add logging for flame graph debugging

#### Phase 3: CLI Interface (1 day)
1. `/push`, `/pop`, `/status` commands
2. Integrate with OpenCode TUI for debugging

#### Phase 4: Testing and Polish (2-3 days)
1. Test context isolation with real workloads
2. Tune compaction prompts
3. Handle edge cases (blocked frames, failures)

**Total Estimated Effort: 6-9 days**

### 10.3 Key Differences from Claude Agents SDK Approach

1. **Higher-Level Abstraction**: OpenCode handles more infrastructure
2. **Less Direct Control**: Context injection rather than construction
3. **Native Hierarchy**: Parent/child sessions already exist
4. **Plugin Extensibility**: Can modify behavior without forking
5. **Multi-Provider**: Not locked to Anthropic

### 10.4 Recommendation

**For organizations already using or planning to use OpenCode:**
- OpenCode SDK approach is recommended
- Leverages existing infrastructure
- Faster development path

**For maximum control and Anthropic-focused deployments:**
- Claude Agents SDK (Proposal 03) is recommended
- More direct context control
- Slightly higher development effort

**Both approaches are viable.** The choice depends on:
1. Existing infrastructure investments
2. Multi-provider requirements
3. Desire for TUI debugging
4. Preference for control vs. leverage

---

## Appendix A: OpenCode SDK Type Reference

```typescript
// Key types from @opencode-ai/sdk

interface Session {
  id: string
  projectID: string
  directory: string
  parentID?: string
  title: string
  version: string
  summary?: { additions: number; deletions: number; files: number }
  share?: { url: string }
  time: { created: number; updated: number; compacting?: number }
}

interface Message {
  id: string
  sessionID: string
  role: "user" | "assistant"
  time: { created: number; completed?: number }
}

interface Part {
  id: string
  sessionID: string
  messageID: string
  type: "text" | "tool" | "file" | "reasoning" | "compaction" | ...
}

interface ToolPart {
  type: "tool"
  tool: string
  callID: string
  state: ToolState
}

type ToolState =
  | { status: "pending"; input: Record<string, unknown> }
  | { status: "running"; input: Record<string, unknown>; time: { start: number } }
  | { status: "completed"; input: Record<string, unknown>; output: string; title: string; time: { start: number; end: number } }
  | { status: "error"; input: Record<string, unknown>; error: string }
```

## Appendix B: Plugin Hook Reference

```typescript
// Available plugin hooks

type PluginHooks = {
  // Event subscription
  event: (input: { event: Event }) => Promise<void>

  // Tool hooks
  "tool.execute.before": (input: ToolInput, output: ToolOutput) => Promise<void>
  "tool.execute.after": (input: ToolInput, output: ToolOutput) => Promise<void>

  // Compaction hook
  "experimental.session.compacting": (
    input: { sessionID: string },
    output: { context: string[]; prompt?: string }
  ) => Promise<void>

  // Custom tools
  tool: Record<string, ToolDefinition>
}
```

---

**End of Proposal**
