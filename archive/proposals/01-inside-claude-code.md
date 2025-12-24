# Proposal: Flame Graph Context Management Inside Claude Code

**Date:** 2025-12-23
**Status:** Analysis Complete - REVISED with Subagent Deep Dive
**Verdict:** SUBSTANTIALLY FEASIBLE - Subagents provide true context isolation for depth-1 frame trees

---

## Executive Summary

This proposal analyzes the feasibility of implementing "Flame Graph Context Management" using Claude Code's native extension mechanisms: plugins, hooks, slash commands, MCP servers, Skills, and agents.

### REVISED VERDICT (see Section 9 Addendum)

The discovery of subagent context isolation capabilities significantly changes the feasibility assessment:

**Bottom Line (REVISED):** Claude Code's subagent system provides **true context isolation** that can be leveraged for flame graph frame management. Each subagent operates in its own context window, separate from the main conversation. This enables:

- **TRUE context isolation** for frames (via subagents)
- **Frame push/pop semantics** via subagent spawn/complete
- **Resumable frames** via agentId persistence
- **Context injection** at frame spawn with assembled tree context
- **Compaction processing** via SubagentStop hooks
- **Native logging** via agent transcript files

**Key Constraint:** Subagents cannot spawn other subagents, limiting native support to **one level of frame depth** (Root + children). Deeper trees require workarounds (virtual frames or external orchestration).

### Original Analysis Summary

The original analysis (Sections 1-8) remains valid for understanding the full extension ecosystem. The subagent approach (Section 9) represents a breakthrough that addresses the primary blocker identified: true context isolation.

**What we CAN now achieve:**
- True context isolation between frames (at depth 1)
- Context construction from tree structure at frame spawn
- Frame persistence and resumption
- Compaction on frame completion

**What still requires workarounds:**
- Recursive frame depth (>1 level)
- Fully autonomous agent-initiated frame decisions
- Parent context cleanup after many sibling frames

---

## Table of Contents

1. [The Specification Requirements](#1-the-specification-requirements)
2. [Claude Code Extension Mechanisms Analysis](#2-claude-code-extension-mechanisms-analysis)
3. [Component-by-Component Feasibility](#3-component-by-component-feasibility)
4. [Implementation Plan: What IS Possible](#4-implementation-plan-what-is-possible)
5. [What's NOT Possible: The Fundamental Gaps](#5-whats-not-possible-the-fundamental-gaps)
6. [Code Examples](#6-code-examples)
7. [Alternative Approaches](#7-alternative-approaches)
8. [Conclusion and Recommendations](#8-conclusion-and-recommendations)

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

## 2. Claude Code Extension Mechanisms Analysis

### 2.1 Plugins

**What Plugins Provide:**
- Package multiple extension types together (commands, agents, skills, hooks, MCP servers, LSP servers)
- Manifest-based configuration via `plugin.json`
- Scoped installation (user, project, local, managed)
- CLI management (`claude plugin install/uninstall/enable/disable`)

**Capabilities:**
| Capability | Supported | Notes |
|------------|-----------|-------|
| Bundle slash commands | YES | Markdown files in `commands/` |
| Bundle hooks | YES | Event handlers in `hooks/hooks.json` |
| Bundle MCP servers | YES | Custom tools via `.mcp.json` |
| Bundle Skills | YES | Auto-invoked capabilities |
| Bundle agents | YES | Specialized subagents |
| Access to conversation history | PARTIAL | Via `transcript_path` in hooks |
| Modify context construction | NO | No API for this |
| Intercept/replace system prompt | NO | Read-only observation |

**For Flame Graph:** Plugins are the right packaging mechanism to bundle all components together.

---

### 2.2 Hooks

**What Hooks Provide:**
Event-based handlers that execute before/after Claude Code actions.

**Available Hook Events:**
| Event | When Fired | Use for Flame Graph |
|-------|------------|---------------------|
| `PreToolUse` | Before tool execution | Could log tool usage to frame |
| `PostToolUse` | After tool success | Log results, detect frame-worthy subtasks |
| `PreCompact` | Before auto/manual compact | **CRITICAL** - Could inject frame summaries |
| `SessionStart` | Session begins | Initialize frame state |
| `SessionEnd` | Session ends | Persist final state |
| `Stop` | Agent finishes responding | Could trigger frame compaction |
| `SubagentStop` | Subagent finishes | Natural frame boundary! |
| `UserPromptSubmit` | User sends prompt | Inject frame context |
| `Notification` | Various notifications | Alert on frame events |

**Hook Input Data:**
```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../session.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "PreCompact",
  "trigger": "manual" | "auto",
  "custom_instructions": ""
}
```

**Hook Output Capabilities:**
- Exit code 0: Success, stdout for context injection
- Exit code 2: Block action, stderr as error
- JSON output for structured control:
  ```json
  {
    "continue": true,
    "systemMessage": "string",
    "decision": "block" | undefined,
    "reason": "string"
  }
  ```

**Critical Limitations:**
1. **Cannot modify conversation context** - Hooks can only add `additionalContext`, not remove or restructure
2. **Cannot see Claude's current context window** - Only transcript on disk
3. **Cannot intercept context construction** - The fundamental barrier

**For Flame Graph:**
- `PreCompact` hook is the most promising - we can inject frame summaries as compaction instructions
- `SessionStart` can inject frame state as context
- `UserPromptSubmit` can inject frame context
- `SubagentStop` provides natural frame boundaries
- **But hooks cannot exclude sibling frame history from context**

---

### 2.3 Slash Commands

**What Slash Commands Provide:**
User-invokable commands via `/command-name`.

**Features:**
| Feature | Supported | Notes |
|---------|-----------|-------|
| Custom commands | YES | Markdown files in `.claude/commands/` |
| Arguments | YES | `$ARGUMENTS`, `$1`, `$2`, etc. |
| Bash execution | YES | `!` prefix for inline bash |
| File references | YES | `@` prefix for file content |
| Frontmatter config | YES | `allowed-tools`, `description`, `model` |
| Tool restrictions | YES | `allowed-tools` in frontmatter |
| Model override | YES | `model` in frontmatter |

**For Flame Graph:**
Slash commands can implement the human control interface:
- `/push <goal>` - Start new frame
- `/pop [status]` - Complete current frame
- `/plan <goal>` - Create planned frame
- `/status` - Show frame tree
- `/frame <id>` - Switch to frame
- `/compact` - Trigger manual compaction with frame context

**Code Example - `/push` command:**
```markdown
---
description: Push a new frame onto the context stack
allowed-tools: Bash(*)
argument-hint: <goal description>
---

## Push New Frame

Create a new child frame with goal: $ARGUMENTS

### Current Frame State
!`cat ~/.claude/flame/current-frame.json 2>/dev/null || echo '{"id":"root","status":"in_progress"}'`

### Instructions
1. Generate a unique frame ID
2. Create frame metadata with goal: "$ARGUMENTS"
3. Set parent to current frame
4. Write new frame state
5. Log frame creation

The frame structure should be:
```json
{
  "id": "<generated-uuid>",
  "parent": "<current-frame-id>",
  "goal": "$ARGUMENTS",
  "status": "in_progress",
  "created_at": "<timestamp>",
  "children": []
}
```
```

**Limitations:**
- Commands run within Claude's normal context - they don't modify it
- Cannot automatically trigger on agent decisions
- User must explicitly invoke

---

### 2.4 MCP Servers

**What MCP Servers Provide:**
Custom tools that Claude can invoke, providing:
- Stateful server processes
- Database/filesystem access
- External API integration
- Custom tool definitions

**For Flame Graph:**
MCP servers could provide the state management and persistence layer:

```json
{
  "mcpServers": {
    "flame-graph": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/flame-server",
      "args": ["--data-dir", "${CLAUDE_PROJECT_DIR}/.flame"],
      "env": {
        "SESSION_ID": "${SESSION_ID}"
      }
    }
  }
}
```

**Tools an MCP Server Could Expose:**
| Tool | Purpose |
|------|---------|
| `flame_push_frame` | Create new child frame |
| `flame_pop_frame` | Complete current frame with summary |
| `flame_get_context` | Get current frame + ancestor compactions |
| `flame_set_planned` | Create planned frame |
| `flame_get_tree` | Get full frame tree |
| `flame_log_message` | Log message to current frame |

**Advantages:**
- Persistent state across requests
- Full filesystem access
- Can maintain in-memory frame tree
- Can generate compactions

**Limitations:**
- Claude must choose to call these tools - no automatic context injection
- Cannot intercept Claude's context construction
- Cannot force Claude to use tree context instead of linear history

---

### 2.5 Skills

**What Skills Provide:**
Model-invoked capabilities that Claude autonomously uses based on context matching.

**Skill Structure:**
```
skills/
├── flame-context/
│   ├── SKILL.md
│   ├── frame-management.md
│   └── compaction-rules.md
```

**SKILL.md Format:**
```markdown
---
description: Flame graph context management for tree-structured agent work
capabilities: ["frame-management", "context-assembly", "compaction"]
---

# Flame Context Management Skill

This skill helps organize work into a tree of frames rather than linear history.

## When to Use
- Starting a distinct subtask that could be retried as a unit
- Context switching to different files/concepts/goals
- Completing a bounded unit of work

## Frame Semantics
- Push frame when starting focused subtask
- Pop frame when subtask completes (or fails/blocks)
- Planned frames for TODO-like sketching
```

**For Flame Graph:**
Skills could teach Claude WHEN to push/pop frames, but:
- Claude still can't actually modify its own context
- Skills are advisory, not enforcement

**Key Limitation:** Skills influence Claude's behavior through instructions, but Claude's actual context window remains linear. Skills cannot change HOW context is constructed.

---

### 2.6 Agents (Subagents)

**What Agents Provide:**
Specialized subagents for task delegation.

**Agent Definition:**
```markdown
---
description: Handles focused subtask execution within a frame
capabilities: ["isolated-task", "bounded-scope"]
---

# Frame Worker Agent

Execute tasks within a frame boundary. Report results for compaction.
```

**For Flame Graph:**
The `SubagentStop` hook fires when a subagent completes - this is a NATURAL FRAME BOUNDARY!

However:
- Subagents don't get isolated context - they inherit parent context
- Subagent results are appended to parent context, not compacted
- No automatic compaction on subagent completion

---

## 3. Component-by-Component Feasibility

### 3.1 Frame State Manager

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Track tree of frames | FULL | MCP server with in-memory tree + disk persistence |
| Track frame status | FULL | MCP server state |
| Track relationships | FULL | Parent/child/sibling references in state |

**Implementation:** MCP server maintaining frame tree in memory, persisted to JSON files.

---

### 3.2 Log Persistence Layer

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Write full frame logs | FULL | Hook on every tool use to log to frame file |
| Reference logs in compaction | FULL | Include file path in summary |
| Allow browsing previous logs | FULL | `/frame-log <id>` command |

**Implementation:**
- `PostToolUse` hook writes tool inputs/outputs to current frame log file
- `UserPromptSubmit` hook logs user messages
- MCP server manages log file paths

---

### 3.3 Compaction Generator

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Generate summary on pop | FULL | MCP tool or slash command triggers LLM summary |
| Include status | FULL | Passed as parameter |
| Include key artifacts | PARTIAL | Requires Claude to identify them |
| Pointer to full log | FULL | Include log path |

**Implementation:**
- `/pop` command or `flame_pop_frame` MCP tool
- Use prompt-based hook or separate LLM call for summary
- Store compaction in frame metadata

**Challenge:** Generating good compactions requires understanding the full frame context, which may be lost if context window is full.

---

### 3.4 Context Assembler - THE CRITICAL GAP

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Current frame working history | IMPOSSIBLE | Cannot isolate from linear history |
| Ancestor compactions | PARTIAL | Can inject as context, but linear history still present |
| Sibling compactions | PARTIAL | Can inject, but sibling FULL history also present |
| Exclude non-relevant history | IMPOSSIBLE | No API to modify context construction |

**This is the fundamental barrier.** Claude Code's context is constructed as:
```
System Prompt + CLAUDE.md + Linear Message History + Tool Results
```

Extensions can:
- ADD to system prompt (`SessionStart` additionalContext)
- ADD to conversation (via tool results)

Extensions CANNOT:
- REMOVE messages from history
- RESTRUCTURE how context is built
- Exclude sibling frame full history

**Best We Can Do:**
- Inject frame context via `SessionStart` or `UserPromptSubmit` hooks
- Hope Claude respects "focus on current frame" instructions
- Use aggressive manual `/compact` to reduce linear history
- Rely on Claude's attention to prioritize injected frame context

---

### 3.5 Frame Controller

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Human push/pop commands | FULL | Slash commands |
| Agent-initiated push/pop | PARTIAL | Agent can call MCP tools, but we can't force it |
| Heuristic detection | IMPOSSIBLE | No way to intercept and modify Claude's decisions |

**Implementation:**
- Slash commands for human control
- MCP tools for Claude to voluntarily use
- Skills to suggest when to use frame tools
- `SubagentStop` hook as automatic frame boundary

**Gap:** We cannot make Claude AUTOMATICALLY push/pop frames based on heuristics. We can only:
1. Teach it when to (via Skills)
2. Provide tools to do so (via MCP)
3. Hope it does

---

### 3.6 Plan Manager

| Requirement | Feasibility | How |
|-------------|-------------|-----|
| Create planned frames | FULL | MCP tool + slash command |
| Planned children | FULL | Tree structure supports this |
| Mutable plans | FULL | Update operations in MCP |
| Cascade invalidation | FULL | Tree traversal in MCP server |

**Implementation:** Straightforward in MCP server.

---

## 4. Implementation Plan: What IS Possible

Despite fundamental limitations, we can build a useful approximation:

### 4.1 Plugin Structure

```
flame-graph-plugin/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── push.md
│   ├── pop.md
│   ├── plan.md
│   ├── frame-status.md
│   ├── frame-tree.md
│   └── frame-log.md
├── skills/
│   └── flame-context/
│       ├── SKILL.md
│       ├── push-heuristics.md
│       └── pop-heuristics.md
├── hooks/
│   └── hooks.json
├── agents/
│   └── frame-worker.md
├── servers/
│   └── flame-server/
│       ├── main.js
│       └── package.json
└── .mcp.json
```

### 4.2 MCP Server Implementation

The MCP server provides the state management:

```javascript
// servers/flame-server/main.js
const { Server } = require('@modelcontextprotocol/sdk/server');

class FlameServer {
  constructor() {
    this.frames = new Map();
    this.currentFrameId = 'root';
    this.logDir = process.env.FLAME_LOG_DIR || '.flame/logs';
  }

  // Tool: Push new frame
  async pushFrame({ goal, parent }) {
    const id = crypto.randomUUID();
    const frame = {
      id,
      goal,
      parent: parent || this.currentFrameId,
      status: 'in_progress',
      children: [],
      created_at: new Date().toISOString(),
      log_path: `${this.logDir}/${id}.jsonl`
    };

    this.frames.set(id, frame);

    // Add as child of parent
    const parentFrame = this.frames.get(frame.parent);
    if (parentFrame) {
      parentFrame.children.push(id);
    }

    this.currentFrameId = id;
    return frame;
  }

  // Tool: Pop current frame
  async popFrame({ status, summary }) {
    const frame = this.frames.get(this.currentFrameId);
    if (!frame) throw new Error('No current frame');

    frame.status = status || 'completed';
    frame.summary = summary;
    frame.completed_at = new Date().toISOString();

    // Move to parent
    this.currentFrameId = frame.parent || 'root';

    return {
      popped: frame,
      current: this.frames.get(this.currentFrameId)
    };
  }

  // Tool: Get context for current frame
  async getContext() {
    const context = {
      current: this.frames.get(this.currentFrameId),
      ancestors: [],
      siblingCompactions: []
    };

    // Walk up to root collecting ancestor compactions
    let frameId = context.current?.parent;
    while (frameId) {
      const frame = this.frames.get(frameId);
      if (frame) {
        context.ancestors.push({
          id: frame.id,
          goal: frame.goal,
          summary: frame.summary
        });
        frameId = frame.parent;
      } else break;
    }

    // Get sibling compactions
    const parent = this.frames.get(context.current?.parent);
    if (parent) {
      for (const sibId of parent.children) {
        if (sibId !== this.currentFrameId) {
          const sib = this.frames.get(sibId);
          if (sib?.status === 'completed') {
            context.siblingCompactions.push({
              id: sib.id,
              goal: sib.goal,
              summary: sib.summary
            });
          }
        }
      }
    }

    return context;
  }
}
```

### 4.3 Hooks Configuration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"
        }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-tool-use.sh"
        }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{
          "type": "prompt",
          "prompt": "A subagent has completed. Evaluate if this represents a natural frame boundary and whether the current frame should be popped. Context: $ARGUMENTS"
        }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-frame-summaries.sh"
        }]
      }
    ]
  }
}
```

### 4.4 Session Start Script

```bash
#!/bin/bash
# scripts/session-start.sh

FLAME_STATE=$(cat ~/.flame/state.json 2>/dev/null || echo '{"root": true}')
CURRENT_FRAME=$(echo "$FLAME_STATE" | jq -r '.currentFrameId // "root"')
FRAME_CONTEXT=$(${CLAUDE_PLUGIN_ROOT}/scripts/get-frame-context.sh "$CURRENT_FRAME")

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "
## Active Frame Context

You are operating within a FLAME GRAPH context management system.
Your current frame and relevant context:

${FRAME_CONTEXT}

### Frame Management Rules
1. When starting a distinct subtask, use the flame_push_frame tool
2. When completing a subtask, use the flame_pop_frame tool with a summary
3. Focus on the current frame's goal - sibling frame details are compacted
4. Use /push, /pop, /status commands or equivalent MCP tools
"
  }
}
EOF
```

### 4.5 Skill Definition

```markdown
---
description: Manages tree-structured frame context for organized agent work
capabilities: ["frame-push", "frame-pop", "context-focus"]
---

# Flame Graph Context Management

You have access to flame graph context management, which organizes work as a tree of frames rather than linear history.

## When to Push a New Frame
Push a new frame when:
- Starting a distinct subtask that could be retried independently
- Switching context to different files, concepts, or goals
- Beginning work that has a clear completion criteria
- The current scope feels too broad

Use: `flame_push_frame` tool with a clear goal description

## When to Pop a Frame
Pop the current frame when:
- The frame's goal has been achieved
- The frame's goal has failed and should be retried differently
- The frame is blocked and needs to escalate to parent
- You're ready to return to the parent's broader scope

Use: `flame_pop_frame` tool with status and summary

## Context Awareness
- Your working context includes your current frame's history
- You can see compacted summaries of ancestor frames
- You can see compacted summaries of completed sibling frames
- You should NOT see the full detailed history of sibling frames

## Using Frame Tools Effectively
When you observe yourself doing one of these, consider pushing a frame:
- "Let me first..." (indicates subtask)
- "I need to figure out..." (indicates exploration)
- "I'll try..." (indicates attempt that might fail)

When you finish something bounded, pop with a summary:
- What was accomplished
- Key artifacts produced
- Important decisions made
```

---

## 5. What's NOT Possible: The Fundamental Gaps

### Gap 1: True Context Isolation

**The Problem:**
When working in Frame B1, the spec requires:
- B1's own working history
- Compaction of parent B
- Compaction of grandparent Root
- Compaction of uncle A (sibling branch)
- **NOT** the full linear history of A1, A2

**Why Impossible:**
Claude Code constructs context from linear message history. There is no extension API to:
- Remove messages from history
- Filter context by frame membership
- Replace linear history with tree-structured assembly

**Best Approximation:**
- Inject frame context as additional instructions
- Use `/compact` aggressively to reduce history
- Rely on Claude's attention to focus on injected frame context
- This is advisory, not enforced

### Gap 2: Automatic Context Window Management

**The Problem:**
As context fills, we want to keep:
- Current frame's working history
- Ancestor/sibling compactions
- Discard: Other frames' detailed history

**Why Impossible:**
The `PreCompact` hook fires before compaction but:
- We can only inject custom instructions for the compaction
- We cannot specify what to keep/discard
- Claude's built-in compaction is not frame-aware

**Best Approximation:**
```json
{
  "hooks": {
    "PreCompact": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/frame-compact-instructions.sh"
      }]
    }]
  }
}
```

The script outputs:
```
When compacting, prioritize:
1. Current frame (ID: xxx) working history
2. Ancestor frame summaries
3. Sibling frame compactions

De-prioritize:
- Detailed history from non-current frames
- Exploration that led to dead ends in other frames
```

But Claude's compaction may not follow these perfectly.

### Gap 3: Agent-Initiated Frame Decisions

**The Problem:**
The agent should autonomously push/pop frames based on:
- Failure boundaries (could retry as unit)
- Context switches (different files/concepts/goals)

**Why Impossible:**
- We can provide tools (`flame_push_frame`, `flame_pop_frame`)
- We can teach heuristics (via Skills)
- We CANNOT force Claude to use them
- We CANNOT intercept Claude's responses to auto-insert frame changes

**Best Approximation:**
- Strong Skills guidance on when to push/pop
- System prompt emphasis on frame management
- `SubagentStop` hook for natural boundaries
- Human oversight via slash commands

### Gap 4: Cross-Frame Context Construction

**The Problem:**
Building context from:
```
current_frame.history +
ancestors.map(a => a.compaction) +
siblings.filter(s => s.completed).map(s => s.compaction)
```

**Why Impossible:**
Context construction happens inside Claude Code core. Extensions cannot:
- Access the context construction pipeline
- Inject custom context builders
- Replace the linear history model

**Best Approximation:**
Inject the desired context as additional context via hooks, but linear history remains:
```javascript
// In SessionStart or UserPromptSubmit hook
const frameContext = await flameServer.getContext();
return {
  additionalContext: formatFrameContext(frameContext)
};
```

This ADDS to context, doesn't REPLACE.

---

## 6. Code Examples

### 6.1 Complete /push Command

```markdown
---
description: Push a new frame onto the flame graph context stack
allowed-tools: Bash(*), mcp__flame-graph__*
argument-hint: <goal description for the new frame>
---

# Push New Frame

You are creating a new child frame with the goal: **$ARGUMENTS**

## Current State
!`cat ${HOME}/.flame/current.json 2>/dev/null || echo '{"frameId":"root","status":"active"}'`

## Instructions

1. Call the `mcp__flame-graph__push_frame` tool with:
   - goal: "$ARGUMENTS"
   - parent: (current frame ID from state above)

2. Announce the new frame to maintain context:
   "**Entering frame [ID]**: $ARGUMENTS"

3. Focus your subsequent work on this specific goal.

4. When this goal is complete, use `/pop` with a summary.

## Frame Guidelines
- This frame represents a bounded unit of work
- If you fail, this frame can be retried independently
- Stay focused on this specific goal
- Avoid scope creep into parent or sibling concerns
```

### 6.2 Complete /pop Command

```markdown
---
description: Pop the current frame and return to parent with a summary
allowed-tools: Bash(*), mcp__flame-graph__*
argument-hint: [completed|failed|blocked] <summary>
---

# Pop Current Frame

## Current State
!`cat ${HOME}/.flame/current.json 2>/dev/null`

## Instructions

Parse the arguments to determine status and summary:
- First word: status (completed, failed, or blocked) - defaults to "completed"
- Remaining words: summary

Arguments provided: "$ARGUMENTS"

1. Call the `mcp__flame-graph__pop_frame` tool with:
   - status: (extracted status)
   - summary: (extracted summary, or generate one if not provided)

2. If no summary provided, generate one covering:
   - What was accomplished in this frame
   - Key artifacts produced (files created/modified)
   - Important decisions made
   - Blockers or failures if status is not "completed"

3. Announce the transition:
   "**Exiting frame [ID]** (status): Summary..."
   "**Returning to parent frame [PARENT_ID]**: Parent's goal..."

4. Resume work on the parent frame's goal.
```

### 6.3 Frame Context Injection Script

```bash
#!/bin/bash
# scripts/inject-context.sh
# Called by UserPromptSubmit hook

# Read hook input from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

# Get current frame context from MCP server
FRAME_CONTEXT=$(curl -s "http://localhost:3456/context?session=${SESSION_ID}" 2>/dev/null)

if [ -z "$FRAME_CONTEXT" ] || [ "$FRAME_CONTEXT" = "null" ]; then
  exit 0  # No frame context available, proceed normally
fi

CURRENT=$(echo "$FRAME_CONTEXT" | jq -r '.current')
ANCESTORS=$(echo "$FRAME_CONTEXT" | jq -r '.ancestors')
SIBLINGS=$(echo "$FRAME_CONTEXT" | jq -r '.siblingCompactions')

# Format as additional context
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "
---
## Flame Graph Context (Active Frame)

**Current Frame**: $(echo "$CURRENT" | jq -r '.goal')
**Frame ID**: $(echo "$CURRENT" | jq -r '.id')
**Status**: $(echo "$CURRENT" | jq -r '.status')

### Ancestor Context (Compacted)
$(echo "$ANCESTORS" | jq -r '.[] | "- **\(.goal)**: \(.summary // "in progress")"')

### Sibling Frames (Compacted)
$(echo "$SIBLINGS" | jq -r '.[] | "- **\(.goal)** (\(.status)): \(.summary)"')

---
Focus on the current frame's goal. Use /pop when complete.
"
  }
}
EOF
```

### 6.4 Tool Use Logging Script

```bash
#!/bin/bash
# scripts/log-tool-use.sh
# Called by PostToolUse hook

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
TOOL_RESPONSE=$(echo "$INPUT" | jq -c '.tool_response')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get current frame ID
CURRENT_FRAME=$(curl -s "http://localhost:3456/current-frame?session=${SESSION_ID}" | jq -r '.id')

if [ -n "$CURRENT_FRAME" ] && [ "$CURRENT_FRAME" != "null" ]; then
  LOG_FILE="${HOME}/.flame/logs/${CURRENT_FRAME}.jsonl"
  mkdir -p "$(dirname "$LOG_FILE")"

  # Append to frame log
  echo "{\"timestamp\":\"${TIMESTAMP}\",\"type\":\"tool_use\",\"tool\":\"${TOOL_NAME}\",\"input\":${TOOL_INPUT},\"response\":${TOOL_RESPONSE}}" >> "$LOG_FILE"
fi

exit 0
```

---

## 7. Alternative Approaches

Given the fundamental limitations, here are alternative strategies:

### 7.1 Session-Per-Frame Model

Instead of tree-structured context within one session, use separate sessions:

```bash
# Parent session
claude "Build the application"
# When subtask identified, start child session
claude -p "Implement JWT auth" > child-session.log
# When child completes, summarize back
claude "Child task completed: $(cat child-summary.txt)"
```

**Pros:**
- True context isolation
- Natural cleanup on completion

**Cons:**
- Complex orchestration
- No shared tool state
- Manual summary injection

### 7.2 TodoWrite-Based Tracking

Use Claude's built-in TodoWrite tool for frame-like tracking:

```javascript
// TodoWrite is native to Claude Code
{
  "todos": [
    {"content": "Root: Build the application", "status": "in_progress"},
    {"content": "  Frame A: Implement auth", "status": "completed"},
    {"content": "    A1: Create User model", "status": "completed"},
    {"content": "    A2: Add JWT middleware", "status": "completed"},
    {"content": "  Frame B: Build API routes", "status": "in_progress"},
    {"content": "    B1: CRUD endpoints", "status": "in_progress"}
  ]
}
```

**Pros:**
- Native integration
- Visible in UI
- Persistent

**Cons:**
- No context isolation
- Not tree-structured
- No compaction

### 7.3 External Orchestrator (Recommended for Full Implementation)

Run an external process that:
1. Manages frame state
2. Spawns Claude Code sessions per frame
3. Captures outputs
4. Generates compactions
5. Constructs context for child frames
6. Injects ancestor compactions

This moves frame management OUTSIDE Claude Code, achieving true control.

See separate proposal: `02-external-orchestrator.md`

---

## 8. Conclusion and Recommendations

### Feasibility Summary

| Component | Feasibility | Implementation |
|-----------|-------------|----------------|
| Frame State Manager | FULL | MCP Server |
| Log Persistence | FULL | Hooks + MCP |
| Compaction Generator | FULL | MCP Tool + LLM |
| Context Assembler | PARTIAL | Inject-only, no exclusion |
| Frame Controller (Human) | FULL | Slash Commands |
| Frame Controller (Agent) | PARTIAL | Tools + Skills (advisory) |
| Plan Manager | FULL | MCP Server |
| **True Context Isolation** | **IMPOSSIBLE** | **Requires core changes** |

### Recommendation

**For a proof-of-concept that demonstrates value:** Build the plugin as described. It will provide:
- Frame-based organization visible in logs
- Human control via slash commands
- Context injection attempting frame focus
- Full logging for debugging/auditing

**For production-grade context management:** The "inside Claude Code" approach is insufficient. We recommend:

1. **Short term:** Build the plugin to validate the UX and frame semantics
2. **Medium term:** Request Claude Code API for context construction hooks
3. **Long term:** Build external orchestrator for true frame isolation

### What to Request from Claude Code Team

To enable true flame graph context management, Claude Code would need:

1. **Context Construction Hook**: Allow extensions to modify context before it's sent to Claude
2. **Message Filtering API**: Allow marking messages as "excluded" from context
3. **Custom Context Builder**: Register a function that builds context from custom data structure
4. **Structured Session State**: Native tree-structured state management

Without these, the best we can achieve is an advisory overlay that hopes Claude follows our injected context guidance.

---

## Appendix A: Complete Plugin Manifest

```json
{
  "name": "flame-graph-context",
  "version": "0.1.0",
  "description": "Tree-structured context management using flame graph semantics",
  "author": {
    "name": "Flame Graph Team"
  },
  "commands": "./commands/",
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json",
  "agents": "./agents/"
}
```

## Appendix B: MCP Server Configuration

```json
{
  "mcpServers": {
    "flame-graph": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/servers/flame-server/main.js"],
      "env": {
        "FLAME_DATA_DIR": "${CLAUDE_PROJECT_DIR}/.flame",
        "FLAME_LOG_LEVEL": "info"
      }
    }
  }
}
```

## Appendix C: Full Hooks Configuration

```json
{
  "description": "Flame graph context management hooks",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh",
          "timeout": 10
        }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh",
          "timeout": 5
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-tool-use.sh",
          "timeout": 5
        }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{
          "type": "prompt",
          "prompt": "A subagent has completed its task. This is a natural frame boundary. The subagent context: $ARGUMENTS\n\nEvaluate if the parent frame should now pop (if the subagent was the main goal) or continue (if there's more work). Respond with {\"decision\": \"approve\"} to allow stopping, or {\"decision\": \"block\", \"reason\": \"Continue with: <next steps>\"} to continue working.",
          "timeout": 30
        }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compact-with-frames.sh",
          "timeout": 10
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/check-frame-complete.sh",
          "timeout": 5
        }]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/persist-state.sh",
          "timeout": 10
        }]
      }
    ]
  }
}
```

---

## 9. ADDENDUM: Subagent-Based Context Isolation Analysis

**Date Added:** 2025-12-23
**Status:** Deep Dive Complete
**Key Finding:** Subagents provide TRUE context isolation, enabling a viable (though constrained) implementation path

---

### 9.1 The Breakthrough: Subagent Context Isolation

The new subagents documentation reveals a critical capability that was previously underestimated:

> "Each subagent operates in its own context, preventing pollution of the main conversation"

This is **exactly** what flame graph context management requires. When Claude spawns a subagent:
- The subagent has a **fresh context window**
- The main conversation's detailed history is **NOT** included in the subagent
- Only the **prompt** (instructions) passed to the subagent defines its initial context
- When the subagent completes, only its **result/summary** returns to the parent

This maps directly to the frame push/pop semantics:
- **Frame Push** = Spawn subagent with goal as prompt
- **Frame Active** = Subagent works in isolated context
- **Frame Pop** = Subagent completes, returns compacted summary to parent

### 9.2 Key Questions Answered

#### Q1: Can subagents spawn other subagents (recursive)?

**Answer: NO - This is explicitly forbidden.**

From the doc: "This prevents infinite nesting of agents (subagents cannot spawn other subagents)"

**Implications:**
- We can only have **ONE level of frame depth** using native subagents
- Frame tree is limited to: `Root -> [Child1, Child2, Child3, ...]`
- No grandchildren frames possible via native mechanism

**Workarounds Explored:**
1. **Session-per-deep-frame**: For depths > 1, spawn a new Claude Code session entirely
   - Pros: True isolation at any depth
   - Cons: Complex orchestration, loses tool state, requires external coordinator

2. **Virtual Frames in Subagent**: Subagent simulates deeper frames via structured logging
   - Pros: Works within single subagent
   - Cons: No true context isolation for virtual frames, just organizational metadata

3. **External Orchestrator for Deep Trees**: Move to proposal-02 approach for depth > 1
   - Pros: Full tree depth support
   - Cons: Requires external process

**Verdict on Recursion:** Single-level frame trees (Root + children) are **fully supported**. Deeper trees require hybrid approach or external orchestration.

---

#### Q2: Can subagents be RESUMED?

**Answer: YES - This is a game-changer for frame persistence!**

From the doc:
> "Subagents can be resumed to continue previous conversations... Each subagent execution is assigned a unique `agentId`... You can resume a previous agent by providing its `agentId` via the `resume` parameter... When resumed, the agent continues with full context from its previous conversation"

**What this enables:**
- **Frame Persistence**: Create a frame (subagent), pause, resume later with full context
- **Multi-Step Workflows**: Work on frame across multiple user interactions
- **Frame as Long-Running Task**: Start a frame, work on it over time, pop when ready

**Technical Details:**
- Agent transcripts stored in: `agent-{agentId}.jsonl`
- Resume with: `"resume": "abc123"` parameter
- Full context from previous conversation is restored

**How to Use for Frames:**
```typescript
// Frame Push - create new subagent
const frame = await invokeSubagent({
  description: "Frame: Implement authentication",
  prompt: "Goal: Build JWT authentication. Context from parent: ...",
  subagent_type: "frame-worker"
});
// Store frame.agentId as frame ID

// Frame Resume - continue working
const resumed = await invokeSubagent({
  description: "Continue frame",
  prompt: "Continue working on your goal",
  resume: frame.agentId  // Resume with full context!
});

// Frame Pop - complete and summarize
const completion = await invokeSubagent({
  description: "Complete frame",
  prompt: "Summarize what you accomplished and return to parent",
  resume: frame.agentId
});
```

---

#### Q3: How is context injected into subagents?

**Answer: Through the `prompt` parameter and agent definition.**

**Context Injection Points:**

1. **Agent System Prompt** (defined in agent markdown file):
   ```markdown
   ---
   name: frame-worker
   description: Executes work within a frame boundary
   tools: Read, Edit, Bash, Grep, Glob
   model: inherit
   ---

   You are a frame worker agent. Work within your frame's scope.
   When complete, provide a compacted summary for the parent frame.
   ```

2. **Invocation Prompt** (passed when spawning):
   - Contains the frame's goal
   - Contains ancestor compactions
   - Contains sibling compactions
   - This IS the "context assembly" from the spec!

3. **Skills** (optional - loaded into subagent):
   ```yaml
   skills: flame-context, compaction-rules
   ```

**Critical Insight:** We can inject the tree-structured context **at subagent spawn time** because the subagent starts fresh. The prompt becomes:

```markdown
# Frame Context

## Your Goal
Build the authentication system

## Ancestor Context (Compacted)
- **Root Frame**: Building the application. Progress: API setup complete.

## Sibling Context (Compacted)
- **Frame A (completed)**: Built user model. Created User.ts with email/password fields.

## Your Scope
Focus ONLY on authentication. Your sibling already built the user model.

## When Complete
Provide a summary including: what was accomplished, key files modified, important decisions.
```

This achieves the spec's Context Assembler requirement!

---

#### Q4: Can we control what context flows back from subagent to parent?

**Answer: Partially - through the subagent's final response and SubagentStop hook.**

**What Returns to Parent:**
- The subagent's final response/output
- This becomes part of the parent's conversation

**Control Mechanisms:**

1. **Subagent System Prompt Instructions:**
   ```markdown
   When completing work, respond ONLY with a structured summary:
   - Status: completed/failed/blocked
   - Summary: 1-2 sentence overview
   - Key artifacts: file paths modified
   - Decisions: important choices made

   Do NOT include detailed exploration, debugging traces, or verbose logs.
   ```

2. **SubagentStop Hook:**
   ```json
   {
     "hooks": {
       "SubagentStop": [{
         "hooks": [{
           "type": "command",
           "command": "${CLAUDE_PLUGIN_ROOT}/scripts/process-frame-completion.sh"
         }]
       }]
     }
   }
   ```

   The hook can:
   - Parse the subagent's output
   - Store full logs to disk
   - Generate enhanced compaction
   - Inject compacted summary into parent context

3. **Prompt-Based SubagentStop Hook:**
   ```json
   {
     "type": "prompt",
     "prompt": "A frame subagent has completed. Evaluate if the summary is properly compacted: $ARGUMENTS. If too verbose, extract key points only. Respond with {\"decision\": \"approve\"} if summary is good, or provide compacted version."
   }
   ```

**Limitation:** We cannot **prevent** the subagent's full response from entering the parent context. We can only:
- Train the subagent to give concise responses
- Post-process via hooks
- Use the compaction as additional context overlay

---

#### Q5: Could we implement frames as subagents?

**Answer: YES - with specific constraints.**

**What Works Well:**

| Requirement | Subagent Capability | Coverage |
|-------------|---------------------|----------|
| Context Isolation | Native - separate context window | FULL |
| Frame Push | Spawn subagent with goal | FULL |
| Frame Pop | Subagent completes, returns | FULL |
| Context Injection | Prompt parameter | FULL |
| Frame Persistence | Resume with agentId | FULL |
| Compaction Control | System prompt + hooks | PARTIAL |
| Frame State Tracking | MCP server + agentId | FULL |
| Logging | Transcript in agent-{id}.jsonl | FULL |

**What Doesn't Work:**

| Requirement | Limitation | Workaround |
|-------------|------------|------------|
| Recursive Frames | Cannot spawn subagents from subagent | Virtual frames OR external orchestration |
| Automatic Frame Decisions | Subagent can't force frame push | Skills + training |
| Sibling Exclusion in Parent | Parent still has full history | Aggressive /compact + context overlay |
| Deep Tree Navigation | Max depth = 1 native | Hybrid approach |

---

### 9.3 Revised Implementation Architecture

Given the subagent capabilities, here's the revised architecture:

```
                    [Main Claude Code Session]
                              │
                   (context: root frame goal + all sibling compactions)
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
    [Subagent A]         [Subagent B]        [Subagent C]
    (agentId: aaa)       (agentId: bbb)      (agentId: ccc)
    (isolated context)   (isolated context)  (isolated context)
    (resumable!)         (resumable!)        (ACTIVE)
         │                    │                    │
      [completed]          [completed]        [in progress]
      (compacted)          (compacted)        (working...)
```

#### Plugin Structure

```
flame-graph-plugin/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   └── frame-worker.md          # Subagent definition for frames
├── commands/
│   ├── push.md                  # /push <goal> - spawn frame subagent
│   ├── pop.md                   # /pop [status] - complete frame subagent
│   ├── frame-status.md          # /frame-status - show frame tree
│   └── resume-frame.md          # /resume-frame <id> - resume paused frame
├── skills/
│   └── frame-awareness/
│       ├── SKILL.md             # Teach Claude frame heuristics
│       └── compaction-rules.md  # How to generate good compactions
├── hooks/
│   └── hooks.json               # SubagentStop processing
├── servers/
│   └── flame-state-server/      # MCP server for state management
│       ├── main.js
│       └── package.json
└── .mcp.json
```

#### Frame Worker Subagent Definition

```markdown
---
name: frame-worker
description: Executes focused work within a flame graph frame boundary. Use when context isolation is needed for a distinct subtask.
tools: Read, Edit, Write, Bash, Grep, Glob
model: inherit
permissionMode: default
skills: frame-awareness
---

# Frame Worker Agent

You are executing work within a FRAME - an isolated unit of work in a flame graph context management system.

## Your Frame Context

Your initial prompt contains:
1. **Your Goal**: The specific task for this frame
2. **Ancestor Summaries**: What parent frames have accomplished
3. **Sibling Summaries**: What completed sibling frames achieved

## Working Principles

1. **Stay Focused**: Only work on your specific goal
2. **No Scope Creep**: Don't venture into sibling frame territory
3. **Bounded Work**: When your goal is complete, stop
4. **Retry-Friendly**: If you fail, your entire frame can be retried

## On Completion

When your goal is achieved (or you hit a blocker), provide a COMPACTED summary:

```
STATUS: completed | failed | blocked

SUMMARY: (1-2 sentences of what was accomplished)

KEY ARTIFACTS:
- file/path/1.ts (created/modified)
- file/path/2.ts (created/modified)

DECISIONS MADE:
- Chose X approach because Y

BLOCKERS (if any):
- What's preventing progress
```

This summary will be your "compaction" visible to parent and sibling frames.

## What NOT to Include in Summary

- Detailed debugging traces
- Full code snippets (reference files instead)
- Exploration of rejected approaches
- Verbose explanations

Your full history is logged to `agent-{your-id}.jsonl` if needed later.
```

#### Push Command

```markdown
---
description: Push a new frame onto the flame graph stack
allowed-tools: mcp__flame-state__*, Task
argument-hint: <goal description>
---

# Push New Frame

Create a new isolated frame for: **$ARGUMENTS**

## Current Frame State
!`${CLAUDE_PLUGIN_ROOT}/scripts/get-current-frame.sh`

## Context for New Frame

Fetch ancestor and sibling compactions from the flame state server, then spawn a frame-worker subagent with:

1. **Goal**: $ARGUMENTS
2. **Ancestor Context**: Compacted summaries from parent frames
3. **Sibling Context**: Compacted summaries from completed siblings

Use the frame-worker subagent to execute this work in isolation.

Store the agentId returned as the frame ID for later resume/pop operations.

## Instructions

1. Call `mcp__flame-state__push_frame` with goal: "$ARGUMENTS"
2. Get the assembled context from `mcp__flame-state__get_frame_context`
3. Spawn frame-worker subagent with the context as prompt
4. Store the agentId for later reference
```

#### SubagentStop Hook for Compaction

```bash
#!/bin/bash
# hooks/scripts/on-frame-complete.sh

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

if [ -z "$AGENT_ID" ]; then
  exit 0  # Not a tracked frame
fi

# Check if this is a frame-worker agent
IS_FRAME=$(curl -s "http://localhost:3456/is-frame?agentId=${AGENT_ID}" | jq -r '.isFrame')

if [ "$IS_FRAME" = "true" ]; then
  # Extract the subagent's final response
  FINAL_RESPONSE=$(echo "$INPUT" | jq -r '.response // empty')

  # Store compaction
  curl -s -X POST "http://localhost:3456/complete-frame" \
    -H "Content-Type: application/json" \
    -d "{\"agentId\": \"${AGENT_ID}\", \"compaction\": ${FINAL_RESPONSE}}"

  # Log full transcript path
  TRANSCRIPT="agent-${AGENT_ID}.jsonl"
  curl -s -X POST "http://localhost:3456/store-log-path" \
    -H "Content-Type: application/json" \
    -d "{\"agentId\": \"${AGENT_ID}\", \"logPath\": \"${TRANSCRIPT}\"}"
fi

exit 0
```

---

### 9.4 Handling Recursive Frames (Depth > 1)

Since subagents cannot spawn subagents, we need workarounds for deeper frame trees.

#### Option A: Virtual Frames Within Subagent (Recommended for Most Cases)

The frame-worker subagent can **simulate** nested frames using structured logging:

```markdown
# In frame-worker.md system prompt addition:

## Handling Sub-Tasks

If your work requires distinct sub-phases, use VIRTUAL FRAMES:

\`\`\`
=== VIRTUAL FRAME START: <sub-goal> ===
[work on sub-goal]
=== VIRTUAL FRAME END: <status> ===
VIRTUAL SUMMARY: <compacted summary>
\`\`\`

These virtual frames are organizational - they share your context window but provide structure for potential future retry or review.
```

**Limitations:**
- No true context isolation for virtual frames
- Just organizational metadata
- Better than nothing for deep tasks

#### Option B: Session-Per-Deep-Frame (For Critical Isolation)

For cases where true isolation is critical at depth > 1:

```bash
# Parent frame detects need for deep child
claude -p "Execute deep task: Build complex feature" \
  --append-system-prompt "You are a deep frame. Return compacted summary only." \
  > deep-frame-output.txt

# Parse and inject into current frame
SUMMARY=$(cat deep-frame-output.txt | tail -20)
```

**Limitations:**
- Complex orchestration
- Loses tool state
- Requires careful context passing

#### Option C: Hybrid - Native Depth 1 + External for Deeper

```
Main Session (Root)
    │
    ├── Native Subagent Frame A (depth 1, isolated context)
    │
    ├── Native Subagent Frame B (depth 1, isolated context)
    │       │
    │       └── [External session for B.1 if needed]
    │
    └── Native Subagent Frame C (depth 1, isolated context)
```

---

### 9.5 What's Achievable vs Still Missing

#### NOW ACHIEVABLE (with subagent approach):

| Capability | Implementation |
|------------|----------------|
| True context isolation for frames | Native subagent context separation |
| Frame push/pop semantics | Spawn/complete subagent |
| Context injection at frame start | Prompt parameter with assembled context |
| Frame persistence & resume | agentId + resume parameter |
| Compaction on completion | SubagentStop hook + system prompt |
| Frame state tracking | MCP server + agentId mapping |
| Full logging | Native agent-{id}.jsonl transcripts |
| Human control | /push, /pop slash commands |
| One level of frame depth | Fully supported |

#### STILL MISSING (requires workarounds or core changes):

| Capability | Limitation | Best Workaround |
|------------|------------|-----------------|
| Recursive frames (depth > 1) | Subagents can't spawn subagents | Virtual frames OR external sessions |
| Agent-initiated frame push | Agent can't force frame creation | Strong Skills + training |
| Parent context isolation from siblings | Parent still sees full linear history | Aggressive /compact + overlays |
| Automatic heuristic detection | Can't intercept agent decisions | Skills for guidance |

---

### 9.6 Revised Verdict

**Previous Verdict:** PARTIALLY FEASIBLE - Significant gaps require Claude Code core changes

**Revised Verdict:** **SUBSTANTIALLY FEASIBLE** - True context isolation achievable for single-level frame trees

The subagent approach provides:
1. **True Context Isolation** - This was the primary blocker, now solved
2. **Resumable Frames** - Frames can persist across interactions
3. **Natural Compaction Point** - SubagentStop hook enables clean summaries
4. **Native Logging** - Agent transcripts provide full history

**What's Changed:**
- We CAN achieve isolated context per frame (at depth 1)
- We CAN inject tree-structured context at frame start
- We CAN persist frames and resume them
- We CAN process completions via hooks

**What Remains Blocked:**
- Recursive frame depth (requires workarounds)
- Fully autonomous agent-initiated frames (needs training/skills)

### 9.7 Recommendations

#### Immediate (Build Now):

1. **Build the plugin with subagent-based frames** for depth-1 tree
2. **Use virtual frames** within subagent for deeper organization
3. **Create frame-worker subagent** with strong compaction instructions
4. **Implement SubagentStop hook** for compaction processing
5. **Use MCP server** for frame state + agentId tracking

#### Future (Request from Claude Code Team):

1. **Allow subagents to spawn subagents** - Would enable true recursive frames
2. **Subagent context modification** - Filter what returns to parent
3. **Structured subagent output** - Enforce compaction format

#### Alternative Path:

If recursive depth is critical, combine with external orchestrator (proposal-02) for deep frames while using native subagents for depth-1 isolation.

---

### 9.8 Proof of Concept Implementation Steps

1. Create `frame-worker.md` subagent definition with compaction training
2. Create `/push` command that:
   - Calls MCP to create frame record
   - Assembles context from frame tree
   - Spawns frame-worker with assembled prompt
   - Stores agentId as frame reference
3. Create `/pop` command that:
   - Triggers frame completion
   - Processes compaction via hook
   - Updates frame state to completed
4. Create SubagentStop hook for compaction enhancement
5. Create MCP server for frame tree state management
6. Test with real workflow: "Build app with auth and API routes"

This proof of concept would validate whether the subagent-based approach delivers meaningful context isolation in practice.

---

**End of Addendum**

---

**End of Proposal**
