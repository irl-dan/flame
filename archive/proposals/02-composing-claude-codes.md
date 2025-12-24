# Proposal: Flame Graph Context Management via Composing Claude Code Instances

**Date:** 2025-12-23
**Status:** Analysis Complete
**Verdict:** FEASIBLE WITH CAVEATS - True context isolation achievable, but orchestration complexity is significant

---

## Executive Summary

This proposal analyzes implementing "Flame Graph Context Management" by **composing multiple Claude Code instances** - using a meta-agent/orchestrator that controls separate Claude Code CLI sessions. This approach directly addresses the fundamental limitation identified in Proposal 01: we cannot EXCLUDE linear history from context when working INSIDE a single Claude Code session.

**Key Finding:** Claude Code's CLI provides powerful non-interactive (`-p`/`--print`) and session management (`-r`/`--resume`, `-c`/`--continue`) capabilities that CAN enable true context isolation between frames:

| Capability | Supported | How |
|------------|-----------|-----|
| Non-interactive/headless mode | **YES** | `claude -p "query"` |
| Capture session output | **YES** | stdout in text/JSON/stream-JSON formats |
| Inject context into sessions | **YES** | `--system-prompt`, `--append-system-prompt`, piped stdin |
| Resume/continue sessions | **YES** | `-r <session-id>`, `-c` |
| Session ID control | **YES** | `--session-id <uuid>` |
| Custom system prompts | **YES** | `--system-prompt`, `--system-prompt-file` |
| Output format control | **YES** | `--output-format json/stream-json/text` |
| Tool restrictions | **YES** | `--tools`, `--allowedTools`, `--disallowedTools` |
| Max turns limit | **YES** | `--max-turns N` |
| Subagent definition | **YES** | `--agents` JSON |

**Bottom Line:** By running each frame as a SEPARATE Claude Code session, we achieve TRUE context isolation. The child session only contains:
1. Its own working history
2. Injected context (ancestor compactions, sibling compactions)
3. NOT the full linear history of unrelated frames

This solves the core problem that Proposal 01 could not solve.

---

## Table of Contents

1. [The Problem Restated](#1-the-problem-restated)
2. [Why Composition Solves This](#2-why-composition-solves-this)
3. [Claude Code CLI Capabilities Analysis](#3-claude-code-cli-capabilities-analysis)
4. [Architecture Design](#4-architecture-design)
5. [Frame Lifecycle Mapping](#5-frame-lifecycle-mapping)
6. [Implementation Details](#6-implementation-details)
7. [Concrete Examples](#7-concrete-examples)
8. [Gaps and Challenges](#8-gaps-and-challenges)
9. [Alternative Orchestrator Designs](#9-alternative-orchestrator-designs)
10. [Comparison with Proposal 01](#10-comparison-with-proposal-01)
11. [Recommendations](#11-recommendations)

---

## 1. The Problem Restated

From SPEC.md, the flame graph context management system requires:

### The Core Context Construction Challenge

When working in Frame B1, the active context should include:
- B1's own working history
- Compaction of parent B (what B is trying to achieve)
- Compaction of grandparent Root
- Compaction of uncle A (completed sibling branch)
- **NOT INCLUDED**: The full linear history of A1, A2, or any deep exploration

### Why Proposal 01 (Inside Claude Code) Failed

Proposal 01 found that Claude Code extensions (hooks, plugins, MCP servers) can:
- ADD context (via `additionalContext` in hooks)
- OBSERVE events (tool use, session lifecycle)
- LOG to external files

But they CANNOT:
- REMOVE messages from linear history
- RESTRUCTURE how context is built
- Exclude sibling frame full history from context

This is the fundamental barrier: **Claude Code's context is always constructed from linear message history**.

---

## 2. Why Composition Solves This

By running SEPARATE Claude Code instances for each frame:

```
Orchestrator
    |
    +-- claude -p "Root frame: Build app" --session-id root-xxx
    |       |
    |       +-- (completes auth subtask)
    |       +-- (generates compaction)
    |
    +-- claude -p "Child frame: Implement auth" --session-id frame-a-xxx
    |       |
    |       +-- Context: Root compaction + "Implement auth" goal
    |       +-- (works on auth)
    |       +-- (completes, generates summary)
    |
    +-- claude -p "Child frame: Build API routes" --session-id frame-b-xxx
            |
            +-- Context: Root compaction + Frame A compaction + "Build API routes" goal
            +-- (Frame A's FULL history is NOT in this session!)
```

**Each frame's session ONLY has its own history**, plus explicitly injected compactions from ancestors/siblings.

This achieves TRUE context isolation because:
1. Each `claude` invocation starts fresh (or resumes its own session)
2. The orchestrator controls what context is passed to each session
3. Sibling frame full history never enters the child's context
4. Compactions are injected as system prompt or initial context

---

## 3. Claude Code CLI Capabilities Analysis

### 3.1 Non-Interactive Mode (`-p` / `--print`)

The `-p` flag enables headless/batch operation:

```bash
# Simple query, exits after response
claude -p "Explain this function"

# With piped input
cat file.txt | claude -p "Summarize this"

# With output format
claude -p "Generate code" --output-format json
```

**Key Behaviors:**
- Runs to completion without user interaction
- Outputs response to stdout
- Exits after Claude finishes responding
- Supports all tools (Bash, Read, Write, Edit, etc.)
- Can use `--max-turns N` to limit agentic loops

### 3.2 Session Management

```bash
# Start with explicit session ID
claude --session-id "550e8400-e29b-41d4-a716-446655440000" "Start work"

# Continue most recent session
claude -c

# Continue in non-interactive mode
claude -c -p "Continue the work"

# Resume specific session by ID or name
claude -r "my-session-name" "Continue from here"

# Fork a session (create new ID, copy history)
claude --resume abc123 --fork-session
```

**Session Persistence:**
- Sessions are stored per working directory
- Each session has a transcript file (`.jsonl`)
- Sessions can be resumed across process restarts
- Session IDs are UUIDs

### 3.3 Context Injection Mechanisms

#### System Prompt Control

```bash
# Replace entire system prompt
claude --system-prompt "You are a Python expert focused on testing"

# Replace from file
claude -p --system-prompt-file ./frame-context.txt "Start work"

# Append to default system prompt (RECOMMENDED)
claude --append-system-prompt "Focus on Frame B1: Implement CRUD endpoints"
```

#### Piped Input

```bash
# Pipe context directly
echo "Context: ${FRAME_CONTEXT}" | claude -p "Continue work"

# Pipe file contents
cat frame-state.json | claude -p "Resume work based on this state"
```

### 3.4 Output Capture

```bash
# Plain text output
OUTPUT=$(claude -p "Generate summary")

# JSON output (structured)
OUTPUT=$(claude -p "Generate code" --output-format json)

# Streaming JSON (for real-time processing)
claude -p "Long task" --output-format stream-json | process_stream.py
```

**JSON Output Format:**
```json
{
  "type": "result",
  "result": "The generated response text...",
  "session_id": "abc-123-def",
  "cost_usd": 0.0123,
  "input_tokens": 1234,
  "output_tokens": 567
}
```

### 3.5 Tool Control

```bash
# Restrict to specific tools
claude -p --tools "Bash,Read" "List files and read README"

# Auto-approve specific tools
claude -p --allowedTools "Read" "Bash(git log:*)" "Review the git history"

# Disable specific tools
claude -p --disallowedTools "Write" "Analyze but don't modify"

# Skip all permission prompts (DANGEROUS)
claude --dangerously-skip-permissions -p "Autonomous task"
```

### 3.6 Subagent Definition

```bash
# Define inline subagents
claude --agents '{
  "frame-worker": {
    "description": "Executes focused subtask within frame boundary",
    "prompt": "You are working on a specific frame. Stay focused on the goal.",
    "tools": ["Read", "Edit", "Bash"],
    "model": "sonnet"
  }
}'
```

---

## 4. Architecture Design

### 4.1 High-Level Architecture

```
+-------------------+
|   Orchestrator    |  (could be: script, separate Claude session, or dedicated program)
|                   |
|  - Frame State    |
|  - Session Map    |
|  - Compaction     |
|    Generator      |
+--------+----------+
         |
         | spawns/manages
         |
+--------v----------+     +-------------------+     +-------------------+
|  Claude Session   |     |  Claude Session   |     |  Claude Session   |
|  (Root Frame)     |     |  (Frame A)        |     |  (Frame B)        |
|                   |     |                   |     |                   |
|  session-id: xxx  |     |  session-id: yyy  |     |  session-id: zzz  |
|  context: root    |     |  context: A's own |     |  context: B's own |
|           goal    |     |  + root compact   |     |  + root compact   |
|                   |     |                   |     |  + A's compact    |
+-------------------+     +-------------------+     +-------------------+
```

### 4.2 Orchestrator Responsibilities

1. **Frame State Management**
   - Maintain tree of frames (ID, parent, children, status)
   - Track which session ID belongs to which frame
   - Persist frame state to disk

2. **Session Lifecycle**
   - Spawn new Claude sessions for new frames
   - Resume sessions when returning to frames
   - Terminate/cleanup sessions on frame completion

3. **Context Construction**
   - Generate compactions when frames complete
   - Assemble context for new frames (ancestor + sibling compactions)
   - Inject context via system prompt or piped input

4. **Output Processing**
   - Capture session output
   - Detect frame completion signals
   - Extract artifacts and key decisions

5. **Human Interface**
   - Accept /push, /pop, /plan, /status commands
   - Display frame tree
   - Route commands to appropriate sessions

### 4.3 Frame State Schema

```json
{
  "frames": {
    "frame-root": {
      "id": "frame-root",
      "session_id": "550e8400-e29b-41d4-a716-446655440000",
      "parent": null,
      "children": ["frame-a", "frame-b"],
      "status": "in_progress",
      "goal": "Build the application",
      "compaction": null,
      "log_path": ".flame/logs/frame-root.jsonl",
      "created_at": "2025-12-23T10:00:00Z"
    },
    "frame-a": {
      "id": "frame-a",
      "session_id": "660e8400-e29b-41d4-a716-446655440001",
      "parent": "frame-root",
      "children": ["frame-a1", "frame-a2"],
      "status": "completed",
      "goal": "Implement authentication",
      "compaction": {
        "summary": "Implemented JWT-based auth with refresh tokens. Created User model, auth middleware, login/logout routes.",
        "artifacts": ["src/auth/*", "src/models/User.ts"],
        "decisions": ["Used JWT over sessions for statelessness", "Added refresh token rotation"]
      },
      "log_path": ".flame/logs/frame-a.jsonl",
      "created_at": "2025-12-23T10:05:00Z",
      "completed_at": "2025-12-23T11:30:00Z"
    }
  },
  "current_frame": "frame-b",
  "version": 1
}
```

---

## 5. Frame Lifecycle Mapping

### 5.1 Push Frame

**Trigger:** Human command `/push <goal>` or agent decision

**Orchestrator Actions:**
1. Generate new frame ID (UUID)
2. Generate new session ID (UUID)
3. Record frame in state (parent = current frame)
4. Assemble context for new frame:
   - Goal description
   - Ancestor compactions (walk up tree)
   - Sibling compactions (completed siblings only)
5. Spawn new Claude session:
   ```bash
   claude -p \
     --session-id "<new-session-id>" \
     --append-system-prompt "$(cat frame-context.txt)" \
     "Begin work on: <goal>"
   ```
6. Update current_frame to new frame

### 5.2 Pop Frame

**Trigger:** Human command `/pop [status] [summary]` or agent completion signal

**Orchestrator Actions:**
1. Capture final output from current session
2. Generate compaction:
   - If summary provided, use it
   - Otherwise, prompt the current session for summary
   - Or use a separate summarization call
3. Record compaction in frame state
4. Mark frame as completed (or failed/blocked)
5. Switch current_frame to parent
6. Resume parent session:
   ```bash
   claude -c -p \
     --session-id "<parent-session-id>" \
     "Child frame completed: <compaction summary>"
   ```

### 5.3 Resume Frame

**Trigger:** Human command `/frame <id>` to switch to existing frame

**Orchestrator Actions:**
1. Validate frame exists and is not completed
2. Switch current_frame to target frame
3. Resume target session:
   ```bash
   claude -r "<session-id>" "Continue work"
   ```

### 5.4 Context Assembly Algorithm

```python
def assemble_frame_context(frame_id, state):
    context_parts = []

    # 1. Add ancestor compactions (root to parent)
    ancestors = get_ancestors(frame_id, state)
    for ancestor in reversed(ancestors):  # root first
        if ancestor.compaction:
            context_parts.append(f"""
## Ancestor Frame: {ancestor.goal}
Status: {ancestor.status}
Summary: {ancestor.compaction.summary}
Key Artifacts: {', '.join(ancestor.compaction.artifacts)}
""")

    # 2. Add sibling compactions (only completed siblings)
    parent = state.frames[state.frames[frame_id].parent]
    for sibling_id in parent.children:
        if sibling_id != frame_id:
            sibling = state.frames[sibling_id]
            if sibling.status == 'completed' and sibling.compaction:
                context_parts.append(f"""
## Sibling Frame: {sibling.goal}
Status: completed
Summary: {sibling.compaction.summary}
""")

    # 3. Add current frame goal
    frame = state.frames[frame_id]
    context_parts.append(f"""
## Current Frame
Goal: {frame.goal}
Status: {frame.status}

Focus on this frame's goal. When complete, signal with: "FRAME_COMPLETE: <summary>"
""")

    return '\n'.join(context_parts)
```

---

## 6. Implementation Details

### 6.1 Orchestrator Implementation Options

#### Option A: Shell Script Orchestrator

**Pros:** Simple, portable, uses native bash
**Cons:** Complex state management, limited error handling

```bash
#!/bin/bash
# flame-orchestrator.sh

FLAME_DIR="${CLAUDE_PROJECT_DIR:-.}/.flame"
STATE_FILE="$FLAME_DIR/state.json"

push_frame() {
    local goal="$1"
    local frame_id=$(uuidgen)
    local session_id=$(uuidgen)

    # Assemble context
    local context=$(assemble_context "$frame_id")

    # Spawn new session
    echo "$context" | claude -p \
        --session-id "$session_id" \
        --append-system-prompt "$(cat)" \
        "Begin work on: $goal"

    # Update state
    update_state "$frame_id" "$session_id" "$goal"
}

pop_frame() {
    local status="${1:-completed}"
    local summary="$2"

    # Get current frame
    local current=$(jq -r '.current_frame' "$STATE_FILE")
    local parent=$(jq -r ".frames[\"$current\"].parent" "$STATE_FILE")
    local parent_session=$(jq -r ".frames[\"$parent\"].session_id" "$STATE_FILE")

    # Generate compaction if not provided
    if [ -z "$summary" ]; then
        summary=$(claude -c -p --session-id "$(get_current_session)" \
            "Summarize what was accomplished in this frame in 2-3 sentences.")
    fi

    # Update frame state
    jq ".frames[\"$current\"].status = \"$status\" |
        .frames[\"$current\"].compaction.summary = \"$summary\" |
        .current_frame = \"$parent\"" "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"

    # Resume parent with compaction
    claude -c -p --session-id "$parent_session" \
        "Child frame completed ($status): $summary"
}
```

#### Option B: Python Orchestrator

**Pros:** Better state management, structured output parsing, subprocess control
**Cons:** Requires Python environment

```python
#!/usr/bin/env python3
# flame_orchestrator.py

import json
import subprocess
import uuid
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Optional, Dict, List

@dataclass
class FrameCompaction:
    summary: str
    artifacts: List[str]
    decisions: List[str]

@dataclass
class Frame:
    id: str
    session_id: str
    parent: Optional[str]
    children: List[str]
    status: str
    goal: str
    compaction: Optional[FrameCompaction]
    log_path: str
    created_at: str
    completed_at: Optional[str] = None

class FlameOrchestrator:
    def __init__(self, project_dir: Path):
        self.flame_dir = project_dir / ".flame"
        self.flame_dir.mkdir(exist_ok=True)
        self.state_file = self.flame_dir / "state.json"
        self.logs_dir = self.flame_dir / "logs"
        self.logs_dir.mkdir(exist_ok=True)
        self.load_state()

    def load_state(self):
        if self.state_file.exists():
            self.state = json.loads(self.state_file.read_text())
        else:
            # Initialize with root frame
            root_id = str(uuid.uuid4())
            self.state = {
                "frames": {},
                "current_frame": None,
                "version": 1
            }

    def save_state(self):
        self.state_file.write_text(json.dumps(self.state, indent=2))

    def push_frame(self, goal: str) -> str:
        frame_id = f"frame-{uuid.uuid4().hex[:8]}"
        session_id = str(uuid.uuid4())

        current = self.state.get("current_frame")

        # Create frame
        frame = {
            "id": frame_id,
            "session_id": session_id,
            "parent": current,
            "children": [],
            "status": "in_progress",
            "goal": goal,
            "compaction": None,
            "log_path": str(self.logs_dir / f"{frame_id}.jsonl"),
            "created_at": datetime.now().isoformat()
        }

        self.state["frames"][frame_id] = frame

        # Add as child of parent
        if current:
            self.state["frames"][current]["children"].append(frame_id)

        self.state["current_frame"] = frame_id
        self.save_state()

        # Assemble context and spawn session
        context = self.assemble_context(frame_id)
        self.spawn_session(session_id, goal, context)

        return frame_id

    def assemble_context(self, frame_id: str) -> str:
        parts = ["# Flame Graph Context\n"]

        # Walk ancestors
        ancestors = self.get_ancestors(frame_id)
        for ancestor in ancestors:
            if ancestor.get("compaction"):
                parts.append(f"""
## Ancestor: {ancestor['goal']}
{ancestor['compaction']['summary']}
""")

        # Get sibling compactions
        frame = self.state["frames"][frame_id]
        if frame["parent"]:
            parent = self.state["frames"][frame["parent"]]
            for sib_id in parent["children"]:
                if sib_id != frame_id:
                    sib = self.state["frames"][sib_id]
                    if sib["status"] == "completed" and sib.get("compaction"):
                        parts.append(f"""
## Sibling (completed): {sib['goal']}
{sib['compaction']['summary']}
""")

        parts.append(f"""
## Current Frame
Goal: {frame['goal']}

When you complete this frame's goal, include "FRAME_COMPLETE:" followed by a summary.
""")

        return "\n".join(parts)

    def spawn_session(self, session_id: str, goal: str, context: str):
        # Write context to temp file
        context_file = self.flame_dir / "temp_context.txt"
        context_file.write_text(context)

        cmd = [
            "claude", "-p",
            "--session-id", session_id,
            "--append-system-prompt", context,
            "--output-format", "json",
            f"Begin work on: {goal}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        # Parse output
        if result.returncode == 0:
            output = json.loads(result.stdout)
            self.process_output(output)
        else:
            print(f"Session error: {result.stderr}")

    def pop_frame(self, status: str = "completed", summary: str = None):
        current_id = self.state["current_frame"]
        frame = self.state["frames"][current_id]

        # Generate summary if not provided
        if not summary:
            summary = self.generate_compaction(frame["session_id"])

        # Update frame
        frame["status"] = status
        frame["compaction"] = {
            "summary": summary,
            "artifacts": [],  # Could be extracted from session
            "decisions": []
        }
        frame["completed_at"] = datetime.now().isoformat()

        # Switch to parent
        parent_id = frame["parent"]
        self.state["current_frame"] = parent_id
        self.save_state()

        # Notify parent session
        if parent_id:
            parent = self.state["frames"][parent_id]
            self.resume_with_compaction(parent["session_id"], summary)

    def generate_compaction(self, session_id: str) -> str:
        cmd = [
            "claude", "-c", "-p",
            "--session-id", session_id,
            "--output-format", "json",
            "Summarize what was accomplished in this frame in 2-3 sentences. Focus on: what was built, key decisions made, and any important artifacts created."
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            output = json.loads(result.stdout)
            return output.get("result", "No summary available")
        return "Compaction generation failed"

    def resume_with_compaction(self, session_id: str, compaction: str):
        cmd = [
            "claude", "-c", "-p",
            "--session-id", session_id,
            "--output-format", "json",
            f"Child frame completed. Summary: {compaction}\n\nContinue with the parent frame's work."
        ]

        subprocess.run(cmd, capture_output=True, text=True)
```

#### Option C: Claude Code as Orchestrator

**Pros:** Full agent capabilities, natural language understanding, self-modifying
**Cons:** Recursive complexity, potential for confusion, context overhead

The orchestrator ITSELF could be a Claude Code session that spawns child sessions:

```bash
# Meta-agent session
claude --append-system-prompt "
You are a Flame Graph Orchestrator. You manage a tree of Claude Code sessions.

Available tools:
- Bash: spawn new 'claude -p' sessions
- Read/Write: manage .flame/state.json

When user says /push <goal>:
1. Generate frame ID and session ID
2. Assemble context from state
3. Run: claude -p --session-id <id> --append-system-prompt '<context>' '<goal>'

When child session outputs 'FRAME_COMPLETE: <summary>':
1. Update frame state with compaction
2. Resume parent session

Commands: /push, /pop, /status, /plan
"
```

**This is a fascinating recursive approach** but adds complexity.

### 6.2 Detecting Frame Completion

The child session needs to signal when its frame is complete. Options:

#### Option A: Magic String Detection

Child sessions include "FRAME_COMPLETE: <summary>" in output.

```python
def process_output(self, output: dict):
    result = output.get("result", "")
    if "FRAME_COMPLETE:" in result:
        _, summary = result.split("FRAME_COMPLETE:", 1)
        self.pop_frame(summary=summary.strip())
```

#### Option B: Max Turns Limit

Use `--max-turns N` to limit session length, then prompt for summary:

```bash
claude -p --max-turns 5 --session-id "$SESSION" "Work on: $GOAL"
# After completion:
claude -c -p --session-id "$SESSION" "Summarize what was accomplished"
```

#### Option C: Structured Output

Use `--json-schema` for structured completion signals:

```bash
claude -p --json-schema '{
  "type": "object",
  "properties": {
    "complete": {"type": "boolean"},
    "summary": {"type": "string"},
    "artifacts": {"type": "array", "items": {"type": "string"}}
  }
}' "Work on this task and report completion"
```

### 6.3 Logging and Persistence

Each frame's session transcript is already persisted by Claude Code at:
```
~/.claude/projects/<project-hash>/<session-id>.jsonl
```

The orchestrator can:
1. Copy/link these transcripts to `.flame/logs/`
2. Reference them in compaction summaries
3. Allow browsing via `/frame-log <id>` command

---

## 7. Concrete Examples

### 7.1 Complete Push/Pop Flow

**User starts project:**
```bash
# Initialize flame orchestrator
./flame-orchestrator.sh init "Build a REST API with authentication"
```

**Orchestrator creates root frame:**
```bash
claude -p \
  --session-id "$(uuidgen)" \
  --append-system-prompt "
# Flame Graph Context
You are working in a flame graph context management system.
Current Frame Goal: Build a REST API with authentication

When you identify a distinct subtask, say: PUSH_FRAME: <subtask goal>
When you complete the current frame, say: FRAME_COMPLETE: <summary>
" \
  "Begin planning the REST API project"
```

**Claude responds:**
```
I'll help you build a REST API with authentication. Let me break this down into subtasks:

1. Set up the project structure and dependencies
2. Implement authentication system
3. Build API routes

Let me start with authentication since it's foundational.

PUSH_FRAME: Implement JWT-based authentication system
```

**Orchestrator detects PUSH_FRAME, creates child session:**
```bash
claude -p \
  --session-id "$(uuidgen)" \
  --append-system-prompt "
# Flame Graph Context

## Ancestor: Build a REST API with authentication
(in progress)

## Current Frame
Goal: Implement JWT-based authentication system

Focus on this specific goal. When complete, say: FRAME_COMPLETE: <summary>
" \
  "Begin implementing JWT authentication"
```

**After auth work completes, Claude says:**
```
I've implemented the JWT authentication system with the following components:
- User model with password hashing
- JWT token generation and validation
- Auth middleware for protected routes
- Login and logout endpoints

FRAME_COMPLETE: Implemented JWT-based auth with User model, bcrypt password hashing, token generation/validation middleware, and login/logout routes. Uses RS256 algorithm with 1-hour token expiry.
```

**Orchestrator pops frame, resumes parent:**
```bash
# Update state with compaction
# Resume parent session
claude -c -p \
  --session-id "$PARENT_SESSION" \
  "Child frame completed: Implemented JWT-based auth with User model, bcrypt password hashing, token generation/validation middleware, and login/logout routes. Uses RS256 algorithm with 1-hour token expiry.

Continue with the parent frame's goals."
```

### 7.2 Context Isolation Demonstration

**Scenario:** Working on Frame B (API Routes) after Frame A (Auth) completed.

**Frame B's injected context:**
```
# Flame Graph Context

## Ancestor: Build a REST API with authentication
(root frame, in progress)

## Sibling (completed): Implement JWT-based authentication
Summary: Implemented JWT-based auth with User model, bcrypt password hashing,
token generation/validation middleware, and login/logout routes.
Uses RS256 algorithm with 1-hour token expiry.
Artifacts: src/auth/*, src/models/User.ts, src/middleware/auth.ts

## Current Frame
Goal: Build API routes for resources

Focus on building CRUD API routes. You can assume authentication is available
via the auth middleware from the sibling frame.
```

**What Frame B does NOT see:**
- The 47 back-and-forth messages where Frame A debugged JWT signing issues
- The exploration of different password hashing libraries
- The failed attempt at using sessions before switching to JWT
- All the code iterations during auth development

**This is the key win: TRUE context isolation.**

### 7.3 Human Control Interface

```bash
# Start interactive session with flame context
flame repl

> /status
Flame Graph Status:
  root: "Build REST API" (in_progress)
    ├── frame-a: "Implement auth" (completed)
    │     └── Summary: JWT auth with User model...
    └── frame-b: "Build API routes" (in_progress) <-- CURRENT
          └── (working...)

> /push "Add pagination to list endpoints"
Creating child frame...
Spawning session...

[Now in frame-b1: Add pagination to list endpoints]

> /pop completed "Added offset/limit pagination with default 20 items per page"
Frame completed. Returning to parent.

[Now in frame-b: Build API routes]

> /plan "Add caching layer"
Created planned frame: frame-c (planned)

> /tree
root: "Build REST API" (in_progress)
  ├── frame-a: "Implement auth" (completed)
  ├── frame-b: "Build API routes" (in_progress) <-- CURRENT
  │     └── frame-b1: "Add pagination" (completed)
  └── frame-c: "Add caching layer" (planned)
```

---

## 8. Gaps and Challenges

### 8.1 Orchestrator Complexity

**Challenge:** The orchestrator is non-trivial software:
- State management across multiple sessions
- Process lifecycle management
- Error handling and recovery
- Output parsing and detection

**Mitigation:** Start with a simple Python implementation, iterate based on usage.

### 8.2 Session Context Limits

**Challenge:** Even with isolation, individual frames may fill their context window.

**Mitigation:**
- Use `claude -p "/compact"` when sessions get large
- Inject compaction into the system prompt, not growing history
- Limit frame scope via clear goal definitions

### 8.3 Agent-Initiated Frame Decisions

**Challenge:** How does Claude autonomously decide to push/pop frames?

**Solutions:**
1. **Detection patterns:** Orchestrator looks for "PUSH_FRAME:" and "FRAME_COMPLETE:" in output
2. **Structured output:** Use `--json-schema` to enforce structured responses
3. **Hook-based:** Child sessions have hooks that signal orchestrator
4. **Polling:** Orchestrator periodically checks session state

### 8.4 Shared State Across Frames

**Challenge:** What if Frame B needs to read a file that Frame A created?

**Solution:** File system is shared. All frames operate in same working directory. Claude can read files created by sibling frames. The isolation is in CONVERSATION CONTEXT, not file system.

### 8.5 Concurrent Frames

**Challenge:** Can multiple frames work in parallel?

**Yes, but with caveats:**
- Each frame is a separate process
- File system writes may conflict
- Orchestrator needs to track parallel execution
- Compaction timing becomes complex

**Recommendation:** Start with sequential frames, add parallelism later.

### 8.6 Session Resume After Restart

**Challenge:** What if the orchestrator process dies?

**Solution:**
- State file persists to disk
- Session IDs are stored
- Can resume with `claude -r <session-id>`
- Orchestrator restart reads state and reconnects

### 8.7 Compaction Quality

**Challenge:** Generated summaries may miss important details.

**Mitigations:**
- Include "key artifacts" and "key decisions" sections
- Allow human override with `/pop "custom summary"`
- Use larger model for compaction generation
- Include file paths of modified files

---

## 9. Alternative Orchestrator Designs

### 9.1 MCP Server as Orchestrator

An MCP server that exposes frame management tools:

```json
{
  "mcpServers": {
    "flame-orchestrator": {
      "command": "./flame-mcp-server",
      "args": ["--state-dir", ".flame"]
    }
  }
}
```

**Exposed Tools:**
- `flame_push_frame(goal: string)`: Create child frame
- `flame_pop_frame(status: string, summary: string)`: Complete frame
- `flame_get_context()`: Get current frame context
- `flame_status()`: Get frame tree

**This allows Claude to call frame operations as tools**, making agent-initiated frame management natural.

### 9.2 Hooks-Based Orchestration

Use Claude Code hooks to detect frame boundaries:

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "./check-frame-complete.sh"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "./log-to-frame.sh"
      }]
    }]
  }
}
```

**The hooks can:**
- Detect completion signals
- Log activity to frame logs
- Trigger compaction on completion

### 9.3 Wrapper Binary

A `flame` binary that wraps `claude`:

```bash
# Instead of: claude "query"
# Use: flame "query"

flame "Build a REST API"
flame /push "Implement auth"
flame /pop
flame /status
```

The `flame` binary:
1. Maintains frame state
2. Wraps claude CLI calls
3. Injects frame context automatically
4. Detects completion signals

---

## 10. Comparison with Proposal 01

| Aspect | Proposal 01 (Inside Claude Code) | Proposal 02 (Composing Sessions) |
|--------|-----------------------------------|----------------------------------|
| Context Isolation | **IMPOSSIBLE** - linear history always present | **ACHIEVED** - separate sessions |
| Sibling Full History | Present in context | NOT present in context |
| Compaction Injection | Via hooks (additive only) | Via system prompt (exclusive) |
| Frame State | MCP server / hooks | Orchestrator + state file |
| Agent-Initiated Frames | Tools + Skills (advisory) | Detection patterns + structured output |
| Human Control | Slash commands | Orchestrator commands |
| Complexity | Plugin development | Orchestrator development |
| Claude Code Changes | None needed | None needed |
| Session Management | Single session | Multiple sessions |
| File System | Shared | Shared |

### Key Advantages of Composition Approach

1. **TRUE Context Isolation**: The fundamental requirement from SPEC.md is achievable
2. **Clean Sessions**: Each frame starts with exactly the context it needs
3. **No Core Changes**: Works with Claude Code as-is
4. **Explicit Control**: Orchestrator has full control over context construction
5. **Recoverable**: Sessions can be resumed after failures

### Key Disadvantages

1. **Orchestrator Complexity**: Significant software to build and maintain
2. **Process Overhead**: Multiple `claude` processes
3. **State Synchronization**: Orchestrator and sessions must stay in sync
4. **Detection Challenges**: Parsing output for frame signals is fragile

---

## 11. Recommendations

### 11.1 Verdict: FEASIBLE WITH CAVEATS

**The composition approach CAN solve the context isolation problem.** This is a significant finding. However, success requires:

1. **Non-trivial orchestrator development**
2. **Careful output parsing and signal detection**
3. **Robust state management**
4. **Clear frame completion protocols**

### 11.2 Recommended Implementation Path

#### Phase 1: Proof of Concept (1-2 days)

Build minimal Python orchestrator with:
- Basic push/pop operations
- Simple state file
- System prompt injection
- Magic string detection for completion

```bash
# Test command
python flame.py push "Implement feature X"
# Spawns claude session, captures output
# Detects FRAME_COMPLETE: in output
# Updates state
```

#### Phase 2: Interactive Shell (3-5 days)

Add interactive REPL:
- `/push`, `/pop`, `/status` commands
- Frame tree visualization
- Session resume capability
- Compaction generation

#### Phase 3: Agent Integration (1 week)

Enable agent-initiated frame management:
- Structured output schema for frame signals
- MCP server for frame tools
- Automatic frame detection heuristics

#### Phase 4: Polish (ongoing)

- Parallel frame support
- Compaction quality improvements
- IDE integration
- Error recovery
- Performance optimization

### 11.3 Alternative Quick Start

For immediate experimentation without full orchestrator:

```bash
#!/bin/bash
# Simple flame experiment

# Root frame
ROOT_SESSION=$(uuidgen)
echo "Starting root frame: $ROOT_SESSION"
claude -p --session-id "$ROOT_SESSION" --output-format json \
  --append-system-prompt "When you need a subtask, say PUSH_FRAME: <goal>" \
  "Plan building a REST API" > root-output.json

# Check for PUSH_FRAME
if grep -q "PUSH_FRAME:" root-output.json; then
  SUBTASK=$(grep -o "PUSH_FRAME:.*" root-output.json | cut -d: -f2)
  CHILD_SESSION=$(uuidgen)

  # Child frame with root context
  ROOT_SUMMARY="Planning phase for REST API"
  claude -p --session-id "$CHILD_SESSION" --output-format json \
    --append-system-prompt "Ancestor: $ROOT_SUMMARY" \
    "Work on: $SUBTASK" > child-output.json

  # Get child summary
  CHILD_SUMMARY=$(claude -c -p --session-id "$CHILD_SESSION" \
    "Summarize what you accomplished in one sentence")

  # Resume root with summary
  claude -c -p --session-id "$ROOT_SESSION" \
    "Subtask completed: $CHILD_SUMMARY. Continue."
fi
```

### 11.4 Comparison to External Tool Development

This approach is similar to building tools like:
- **Cursor Composer** (multi-file editing)
- **Aider** (git-aware coding assistant)
- **Continue.dev** (IDE-integrated AI)

All of these are EXTERNAL to the LLM, orchestrating context and sessions programmatically. The flame graph approach fits this pattern.

---

## Appendix A: Claude Code CLI Quick Reference

```bash
# Non-interactive mode
claude -p "query"                              # Basic query
claude -p --output-format json "query"         # JSON output
claude -p --max-turns 5 "query"                # Limit turns

# Session management
claude --session-id <uuid> "query"             # Explicit session
claude -c "query"                              # Continue recent
claude -r <id> "query"                         # Resume by ID/name
claude --resume <id> --fork-session "query"    # Fork session

# Context injection
claude --system-prompt "You are..."            # Replace prompt
claude --append-system-prompt "Also..."        # Append to prompt
cat file | claude -p "Process this"            # Pipe input

# Tool control
claude -p --tools "Bash,Read" "query"          # Restrict tools
claude --dangerously-skip-permissions          # Auto-approve all
claude -p --allowedTools "Read" "query"        # Pre-approve specific

# Subagents
claude --agents '{"name":{"description":"...","prompt":"..."}}'
```

## Appendix B: State File Example

```json
{
  "version": 1,
  "project_dir": "/Users/dev/my-project",
  "current_frame": "frame-b",
  "frames": {
    "frame-root": {
      "id": "frame-root",
      "session_id": "550e8400-e29b-41d4-a716-446655440000",
      "parent": null,
      "children": ["frame-a", "frame-b"],
      "status": "in_progress",
      "goal": "Build REST API with authentication",
      "compaction": null,
      "log_path": ".flame/logs/frame-root.jsonl",
      "created_at": "2025-12-23T10:00:00Z",
      "completed_at": null
    },
    "frame-a": {
      "id": "frame-a",
      "session_id": "660e8400-e29b-41d4-a716-446655440001",
      "parent": "frame-root",
      "children": [],
      "status": "completed",
      "goal": "Implement JWT authentication",
      "compaction": {
        "summary": "Implemented JWT-based auth with User model, bcrypt password hashing, token generation/validation middleware, and login/logout routes.",
        "artifacts": ["src/auth/", "src/models/User.ts", "src/middleware/auth.ts"],
        "decisions": ["Used JWT over sessions", "RS256 algorithm", "1-hour expiry"]
      },
      "log_path": ".flame/logs/frame-a.jsonl",
      "created_at": "2025-12-23T10:05:00Z",
      "completed_at": "2025-12-23T11:30:00Z"
    },
    "frame-b": {
      "id": "frame-b",
      "session_id": "770e8400-e29b-41d4-a716-446655440002",
      "parent": "frame-root",
      "children": [],
      "status": "in_progress",
      "goal": "Build API routes",
      "compaction": null,
      "log_path": ".flame/logs/frame-b.jsonl",
      "created_at": "2025-12-23T11:35:00Z",
      "completed_at": null
    }
  }
}
```

## Appendix C: Context Injection Template

```markdown
# Flame Graph Context

## Session Information
Frame ID: {frame_id}
Frame Goal: {goal}
Created: {created_at}

## Ancestor Chain
{for ancestor in ancestors}
### {ancestor.goal}
Status: {ancestor.status}
Summary: {ancestor.compaction.summary}
Key Artifacts: {ancestor.compaction.artifacts | join(", ")}
{endfor}

## Sibling Frames (Completed)
{for sibling in completed_siblings}
### {sibling.goal}
Status: completed
Summary: {sibling.compaction.summary}
{endfor}

## Current Frame Instructions
You are working on: **{goal}**

Guidelines:
1. Focus exclusively on this frame's goal
2. When you complete the goal, include: FRAME_COMPLETE: <summary>
3. If you need a subtask, include: PUSH_FRAME: <subtask goal>
4. You can reference artifacts from sibling frames but don't repeat their work
5. Keep your work bounded and completable

Begin your work.
```

---

**End of Proposal**
