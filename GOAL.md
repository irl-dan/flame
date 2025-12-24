# Flame: Tree-Structured Context Management for AI Agents

Flame organizes AI agent context as a **tree of frames** (like a call stack / flame graph) rather than a linear chat history. This reduces context window pressure, eliminates irrelevant sibling history from active context, and aligns with how engineers naturally think about work.

## The Problem

Current AI coding agents use linear chat history:

```
Message 1 → Message 2 → ... → Message 47 (debugging auth) → Message 48 (now doing API routes)
```

When working on API routes, the full 47-message auth debugging session is still in context - wasting tokens on irrelevant exploration.

## The Solution

Organize context as a frame tree:

```
                [Root: "Build App"]
                       │
       ┌───────────────┴───────────────┐
       │                               │
 [Auth Frame]                    [API Frame]
  COMPLETED                       IN PROGRESS
  "JWT + refresh tokens"              │
                               ┌──────┴──────┐
                               │             │
                            [CRUD]      [Pagination]
                          IN PROGRESS     PLANNED
```

When working in the CRUD frame:
- **Included**: CRUD's own history + API frame compaction + Auth compaction + Root goal
- **Excluded**: Auth's 47 debugging messages (only the summary matters)

## Implementation: OpenCode Plugin

We're implementing Flame as an **OpenCode plugin** that achieves true context isolation without forking.

### Why OpenCode?

OpenCode sessions have **native context isolation** - each session's messages are fetched independently for the LLM. By using sessions as frames, we get true isolation at the architectural level, not just UX.

### How It Works

1. **Frame = Session** - Each frame is an OpenCode session with `parentID` linking to its parent
2. **Push = Create Child Session** - Spawn isolated session, inject assembled context via `noReply: true`
3. **Pop = Complete Session** - Generate compaction summary, mark complete, return to parent
4. **Context Assembly** - Current frame history + ancestor compactions + sibling compactions

---

## Phase 1: Core Plugin (Primary Focus)

**Goal**: Validate that frame-based context management improves agent effectiveness.

### Components to Build

```
.opencode/
├── plugin/
│   └── flame.ts              # Main plugin: hooks + event handling
├── tool/
│   ├── flame_push.ts         # Push new frame onto stack
│   ├── flame_pop.ts          # Pop frame with compaction
│   ├── flame_status.ts       # Show frame tree
│   └── flame_plan.ts         # Create planned frames
├── command/
│   ├── push.md               # /push <goal>
│   ├── pop.md                # /pop [status]
│   └── status.md             # /flame-status
├── skill/
│   └── flame-context/
│       └── SKILL.md          # Frame management heuristics
└── agent/
    └── frame-worker.md       # Specialized frame execution agent
```

### Core Plugin (`flame.ts`)

```typescript
import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"

interface Frame {
  id: string
  sessionId: string
  parentId: string | null
  goal: string
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked'
  compaction?: { summary: string; artifacts: string[] }
}

export const FlamePlugin: Plugin = async ({ client }) => {
  const frames = new Map<string, Frame>()

  return {
    // Handle session lifecycle for frame tracking
    event: async ({ event }) => {
      if (event.type === 'session.idle') {
        // Session completed - prompt for frame completion if applicable
      }
    },

    // Frame-aware compaction
    "experimental.session.compacting": async (input, output) => {
      const frame = getFrameBySession(input.sessionID)
      if (!frame) return

      output.prompt = buildFrameCompactionPrompt(frame, frames)
    },

    // Custom tools
    tool: {
      flame_push,
      flame_pop,
      flame_status,
    }
  }
}
```

### Frame Tools

**`flame_push`** - Create a new child frame:
```typescript
tool({
  description: "Push a new frame for a focused subtask",
  args: { goal: z.string() },
  async execute({ goal }, ctx) {
    // 1. Create child session
    const session = await client.session.create({
      body: { parentID: ctx.sessionID, title: goal }
    })

    // 2. Track frame state
    const frame = { id: generateId(), sessionId: session.id, goal, ... }
    frames.set(frame.id, frame)

    // 3. Inject assembled context (ancestors + siblings)
    await client.session.prompt({
      path: { id: session.id },
      body: { noReply: true, parts: [{ type: "text", text: assembleContext(frame) }] }
    })

    return `Created frame: ${goal}`
  }
})
```

**`flame_pop`** - Complete current frame:
```typescript
tool({
  description: "Complete the current frame and return to parent",
  args: {
    status: z.enum(['completed', 'failed', 'blocked']),
    summary: z.string(),
  },
  async execute({ status, summary }, ctx) {
    const frame = getFrameBySession(ctx.sessionID)

    // 1. Store compaction
    frame.status = status
    frame.compaction = { summary, artifacts: extractArtifacts(ctx.sessionID) }

    // 2. Notify parent of completion
    await injectSiblingContext(frame.parentId, frame)

    return `Frame completed: ${status}`
  }
})
```

### Context Assembly

The key innovation - build context from compactions, not full history:

```typescript
function assembleContext(frame: Frame): string {
  const ancestors = getAncestors(frame.id)
  const siblings = getCompletedSiblings(frame.id)

  return `
<flame_context>
## Current Frame
**Goal**: ${frame.goal}

## Ancestor Context
${ancestors.map(a => `
### ${a.goal}
${a.compaction?.summary || 'In progress'}
`).join('\n')}

## Completed Siblings
${siblings.map(s => `
### ${s.goal} (${s.status})
${s.compaction?.summary}
`).join('\n')}
</flame_context>

Focus on your goal. Use flame_pop when complete.
`
}
```

### Slash Commands

**`/push <goal>`**
```markdown
---
description: Push a new frame onto the stack
subtask: true
agent: frame-worker
---

Starting new frame: **$ARGUMENTS**

Use flame_push to initialize, then work toward the goal.
When complete, use flame_pop with a summary.
```

**`/pop [completed|failed|blocked]`**
```markdown
---
description: Complete current frame
---

Complete your current frame with status: $1

Provide a summary of:
- What was accomplished
- Key artifacts created/modified
- Important decisions made
```

### Frame Worker Agent

```markdown
---
name: frame-worker
description: Executes work within an isolated flame graph frame
mode: subagent
tools:
  flame_push: true
  flame_pop: true
  flame_status: true
  write: true
  edit: true
  bash: true
  read: true
---

You are working within a FRAME - an isolated unit of work.

Your context includes:
- Your specific goal
- Summaries of ancestor frames (what led here)
- Summaries of completed sibling frames (parallel work)

You do NOT have the full history of sibling frames - only their outcomes.

When complete, use flame_pop with a concise summary.
```

### Success Criteria for Phase 1

1. **Context isolation verified** - Child frame LLM calls don't include sibling full history
2. **Push/pop mechanics work** - Can create frame tree, navigate back to parent
3. **Compaction flows correctly** - Completed frame summaries appear in sibling context
4. **Agent can use autonomously** - Frame heuristics guide when to push/pop

---

## Phase 2: External Visualization

**Goal**: Provide flame graph visualization without forking OpenCode.

- Separate web app using OpenCode SDK
- Connects to OpenCode server API
- Real-time frame tree visualization
- Click to navigate between frames

---

## Phase 3: Upstream Contribution

**Goal**: Contribute frame system to OpenCode for all users.

- Propose frame schema extension to Session model
- Propose UI extension API for plugins
- Full integration with Desktop app
- Community feedback and iteration

---

## Getting Started

### Prerequisites

- [OpenCode](https://opencode.ai) installed
- Bun runtime

### Installation

```bash
# Clone this repo
git clone https://github.com/yourname/flame
cd flame

# Copy plugin to your project
cp -r .opencode/plugin/* /path/to/your/project/.opencode/plugin/
cp -r .opencode/tool/* /path/to/your/project/.opencode/tool/
cp -r .opencode/command/* /path/to/your/project/.opencode/command/

# Or use with --plugin-dir for development
opencode --plugin-dir ./flame-plugin
```

### Usage

```bash
# Start OpenCode with flame
opencode

# Push a new frame
/push Implement user authentication

# Work on the task...

# Pop when done
/pop completed

# View frame tree
/flame-status
```

---

## Project Status

**Current Phase**: Phase 1 - Core Plugin Implementation

See [phase1/README.md](./phase1/README.md) for:
- Implementation plan and architecture decisions
- Validation results confirming plugin API assumptions
- Key learnings and next steps

---

## Architecture

See [SPEC.md](./SPEC.md) for the full theoretical framework.

See [BACKSTORY.md](./BACKSTORY.md) for how we arrived at this implementation approach.

See [archive/](./archive/) for historical proposals and exploration.
