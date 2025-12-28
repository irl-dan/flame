# Flame Graph Context Management

**Tree-structured context management for AI coding agents.**

Flame organizes AI agent work as a **tree of frames** (like a call stack) rather than a linear chat history. This reduces context window pressure, eliminates irrelevant sibling history, and aligns with how engineers naturally think about work.

## The Problem

Current AI agents use linear conversation history. When working on Task B, the full 50-message debugging session from Task A is still in context - wasting tokens on irrelevant exploration.

## The Solution

Organize work as a frame tree:

```
                [Root: "Build App"]
                       |
       +---------------+---------------+
       |                               |
 [Auth Frame]                    [API Frame]
  COMPLETED                       IN PROGRESS
  "JWT + refresh"                      |
                               +-------+-------+
                               |               |
                            [CRUD]        [Pagination]
                          IN PROGRESS       PLANNED
```

When working in CRUD:
- **Included**: CRUD's history + API summary + Auth summary + Root goal
- **Excluded**: Auth's 50 debugging messages (only the summary matters)

## Installation

### Prerequisites

- [OpenCode](https://opencode.ai) CLI installed
- Node.js 18+ or Bun runtime

### Quick Install

```bash
# Clone this repository
git clone https://github.com/irl-dan/flame.git
cd flame

# The plugin is in .opencode/plugin/flame.ts
# OpenCode automatically loads plugins from this directory
```

### Using in Your Project

Copy the plugin to your project:

```bash
# Create plugin directory
mkdir -p /path/to/your/project/.opencode/plugin

# Copy the plugin
cp .opencode/plugin/flame.ts /path/to/your/project/.opencode/plugin/
```

## Usage

### Start OpenCode

```bash
# Navigate to your project with the flame plugin
cd /path/to/your/project

# Start OpenCode - plugin loads automatically
opencode
```

### Core Workflow

The plugin injects task management instructions that guide the agent to use flame tools automatically. For complex tasks, the agent will:

1. **Plan** - Break down work into frames with `flame_plan_children`
2. **Activate** - Start each frame with `flame_activate`
3. **Work** - Complete the task within the focused frame
4. **Complete** - Pop the frame with `flame_pop` and results

### Key Tools

| Tool | Description |
|------|-------------|
| `flame_plan_children` | Create multiple planned child frames |
| `flame_activate` | Start work on a planned frame |
| `flame_push` | Create a new child frame for immediate work |
| `flame_pop` | Complete current frame with results |
| `flame_tree` | Visualize the frame hierarchy |
| `flame_status` | Show current frame status |
| `flame_frame_details` | View full details for a specific frame |

### Frame Metadata

Each frame has:
- **title**: Short name (2-5 words)
- **successCriteria**: What defines "done" in concrete terms
- **successCriteriaCompacted**: Dense summary for context display
- **results**: What was accomplished (set on completion)
- **resultsCompacted**: Dense summary of results

### Example Session

```
User: Build a user authentication system with login, logout, and password reset

Agent: [Uses flame_plan_children to create:]
  - "Login Flow" - JWT auth, session management
  - "Logout Flow" - Token invalidation
  - "Password Reset" - Email verification, secure reset

Agent: [Uses flame_activate on "Login Flow"]
Agent: [Works on login implementation...]
Agent: [Uses flame_pop with results: "Implemented JWT auth with refresh tokens"]

Agent: [Uses flame_activate on "Logout Flow"]
...
```

## Configuration

### Environment Variables

```bash
# Token budgets for context assembly
FLAME_TOKEN_BUDGET_TOTAL=4000
FLAME_TOKEN_BUDGET_ANCESTORS=1500
FLAME_TOKEN_BUDGET_SIBLINGS=1500
FLAME_TOKEN_BUDGET_CURRENT=800

# Autonomy settings
FLAME_AUTONOMY_LEVEL=suggest  # manual, suggest, or auto
FLAME_PUSH_THRESHOLD=70
FLAME_POP_THRESHOLD=80
```

### File Storage

Flame stores state in your project:

```
.opencode/
  flame/
    state.json           # Frame tree state
    frames/
      <frameID>.json     # Individual frame files
```

## Testing

### Manual Testing

```bash
# Run a single command
opencode run "Use flame_tree to show the current frame hierarchy"

# View logs
opencode run "Your prompt" --print-logs 2>&1

# Resume a session
opencode run --session <sessionID> "Continue working"
```

### Reset State

```bash
# Clear all frame state
rm -rf .opencode/flame/

# Restart OpenCode
opencode
```

## Documentation

| Document | Description |
|----------|-------------|
| [SPEC.md](./SPEC.md) | Theoretical framework and design |
| [BACKSTORY.md](./BACKSTORY.md) | How we arrived at this approach |
| [.opencode/plugin/IMPLEMENTATION.md](./.opencode/plugin/IMPLEMENTATION.md) | Technical implementation details |

## Architecture

```
                    +------------------+
                    |   Flame Plugin   |
                    |  (flame.ts)      |
                    +--------+---------+
                             |
                             | Writes state / Reads state
                             |
                    +--------v---------+
                    |  .opencode/      |
                    |  flame/state.json|
                    +--------+---------+
                             |
                             | Context injection via hooks
                             |
              +--------------v---------------+
              |    OpenCode LLM Calls        |
              |  (frame context prepended)   |
              +------------------------------+
```

### Key Hooks

| Hook | Purpose |
|------|---------|
| `chat.message` | Track current session |
| `experimental.chat.messages.transform` | Inject frame context |
| `experimental.session.compacting` | Custom compaction prompts |

## Project Status

**Current Version**: Phase 1.7 - Agent Autonomy

The plugin is production-ready for:
- Hierarchical task management
- Context assembly with token budgets
- Frame planning and invalidation
- Agent autonomy suggestions

## Contributing

Contributions welcome! Please see the [BACKSTORY.md](./BACKSTORY.md) for architectural context.

## License

MIT

---

*Flame Graph Context Management - Making AI agents think like engineers.*
