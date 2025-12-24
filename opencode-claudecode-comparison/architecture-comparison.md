# Claude Code vs OpenCode: Architecture Comparison

A documentation-based analysis comparing the architectures of Claude Code (built on Claude Agents SDK) and OpenCode.

*Cross-checked against actual codebases and `~/.claude` directory on 2024-12-24.*

---

## High-Level Architecture

### Claude Code / Claude Agents SDK

**Architecture Pattern**: Closed-source CLI + Open SDK wrapper

- Core runtime is the Claude Code CLI (closed source)
- The SDK (`@anthropic-ai/claude-agent-sdk`) wraps the CLI via subprocess
- Uses a streaming `query()` function that yields messages
- Centralized around Anthropic's Claude models (with third-party provider support via Bedrock, Vertex, Foundry)

```
SDK Layer → Claude Code CLI (runtime) → Anthropic API
```

**Key Directories** (from `~/.claude/`):
- `~/.claude/settings.json` - User settings (e.g., `enabledPlugins`, `alwaysThinkingEnabled`)
- `~/.claude/projects/<project-hash>/` - Per-project session storage
- `~/.claude/agents/` - User-defined agent markdown files (e.g., `chief-of-staff.md`)
- `~/.claude/plugins/` - Installed plugins with marketplace cache
- `~/.claude/todos/` - Todo state per session/agent
- `~/.claude/plans/` - Stored plans from plan mode
- `~/.claude/file-history/` - File checkpointing backups
- `~/.claude/shell-snapshots/` - Shell state snapshots
- `~/.claude/session-env/` - Environment variables per session
- `~/.claude/history.jsonl` - Global prompt history
- `.claude/settings.json` - Project-level settings

**Session Storage Format**:
- Sessions stored as JSONL: `~/.claude/projects/<project>/<session-id>.jsonl`
- Subagent sessions: `agent-<hash>.jsonl`
- Each line is a JSON object with `type` (user/assistant), `message`, `uuid`, `timestamp`

### OpenCode

**Architecture Pattern**: Client/Server with modular frontend

- TypeScript backend server (`packages/opencode`) using **Hono** framework
- Uses **Vercel AI SDK** (`ai` package) for LLM streaming (`streamText`)
- Go-based TUI client communicates via HTTP API (generated with Stainless SDK)
- Provider-agnostic: works with Claude, OpenAI, Google, local models
- Supports multiple frontends (TUI, desktop app via Tauri, web)
- WebSocket support for real-time UI updates

```
Clients (TUI/Desktop/Web) ←WebSocket/HTTP→ Hono Server → Vercel AI SDK → Multiple Provider APIs
```

**Key Directories**:
- `packages/opencode/src/` - Core TypeScript server
- `packages/opencode/src/server/server.ts` - Hono HTTP server with REST API
- `packages/opencode/src/session/` - Session management (processor, llm, compaction)
- `packages/opencode/src/tool/` - Tool implementations
- `opencode.json` or `opencode.jsonc` - Configuration (supports JSONC with comments)
- `.opencode/agent/*.md` - Agent definitions
- `.opencode/command/*.md` - Custom commands
- `.opencode/skill/*/SKILL.md` - Skill definitions

### Architectural Difference Summary

| Aspect | Claude Code | OpenCode |
|--------|-------------|----------|
| **Core** | Closed-source CLI | Open-source TypeScript server (Hono + Vercel AI SDK) |
| **SDK** | Wrapper around CLI subprocess | Direct library usage via HTTP API |
| **Providers** | Anthropic-first (with cloud partners) | Provider-agnostic (any OpenAI-compatible API) |
| **Frontend** | Monolithic CLI + IDE plugins | Client-server separation (TUI, Desktop, Web) |
| **API** | Streaming async generator | HTTP REST + WebSocket for real-time |
| **Config Format** | JSON (`settings.json`) | JSONC with comments (`opencode.jsonc`) |
| **Plugin System** | Git-based marketplaces | NPM packages |
| **Storage** | JSONL files in `~/.claude/` | Abstracted Storage namespace with migrations |

---

## Basic Entities

### Overlapping Entities

| Entity | Claude Code | OpenCode |
|--------|-------------|----------|
| **Session** | Conversation context with messages, can be resumed/forked. Stored as JSONL in `~/.claude/projects/` | Same concept, stored with `Session.Info` schema, supports parent/child relationships |
| **Message** | User/Assistant messages with content blocks (`SDKMessage` types) | `MessageV2` with parts (text, tool, reasoning, patch, step-start/finish) |
| **Tool** | Built-in tools (Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, etc.) | Same core tools + extras (`ls`, `multiedit`, `patch`, `batch`, `codesearch`, `lsp-*`) |
| **Subagent/Agent** | Specialized agents spawned via `Task` tool, defined in `~/.claude/agents/*.md` (user-level) | Similar concept, defined via `Agent.Info` in `.opencode/agent/*.md` |
| **Skills** | Markdown files in `.claude/skills/` with YAML frontmatter | Similar: `.opencode/skill/*/SKILL.md` with YAML frontmatter (`name`, `description`) |
| **MCP** | Model Context Protocol for external integrations (stdio, SSE, HTTP, SDK servers) | Same, with OAuth support for authenticated servers |
| **Hooks/Events** | Event-driven callbacks (PreToolUse, PostToolUse, Stop, etc.) via bash or prompt | Plugin-based hooks + typed Bus/Event pub-sub system |
| **Permission** | Control tool access via `permissionMode` and `canUseTool` callback | Similar, uses glob pattern matching for bash commands (`"git diff*": "allow"`) |
| **Todo/Task List** | `TodoWrite` tool for task tracking. State in `~/.claude/todos/` | `todoread`/`todowrite` tools, can be disabled per agent |
| **Commands** | Custom commands in `.claude/commands/*.md` | Custom commands in `.opencode/command/*.md` |

### Distinct to Claude Code

| Entity | Description |
|--------|-------------|
| **Plugin Marketplace** | Plugins installed from git-based marketplaces (e.g., `claude-code-plugins`, `dev-browser-marketplace`). Stored in `~/.claude/plugins/marketplaces/` |
| **CLAUDE.md** | Project memory/context file loaded into system prompt |
| **Sandbox** | Configurable filesystem and network sandboxing with `SandboxSettings` |
| **File Checkpointing** | Git-like rewind capability for file changes. Backups stored in `~/.claude/file-history/<session-id>/` |
| **Shell Snapshots** | Shell state preservation in `~/.claude/shell-snapshots/` |
| **Structured Outputs** | JSON schema output format via `outputFormat` option |
| **Beta Features** | Opt-in betas like extended context window (`context-1m-2025-08-07`) |
| **IDE Integration** | Lock files in `~/.claude/ide/` for IDE coordination |
| **Always Thinking** | Setting `alwaysThinkingEnabled` for extended reasoning |

### Distinct to OpenCode

| Entity | Description |
|--------|-------------|
| **Project** | First-class entity allowing multiple projects per OpenCode instance |
| **Provider** | Provider abstraction layer (`Provider.Model`, `Provider.getLanguage`, `Provider.parseModel`) |
| **Instance** | Project instance state management via `Instance.state()` |
| **Snapshot** | Automatic file change tracking with `Snapshot.track()` and `Snapshot.patch()` per step |
| **LSP Integration** | Built-in Language Server Protocol client with dedicated tools: `lsp`, `lsp-diagnostics`, `lsp-hover` |
| **VCS** | Version control system abstraction (`packages/opencode/src/project/vcs.ts`) |
| **Bus** | Typed pub-sub event system for internal communication (`BusEvent.define()`, `Bus.publish()`) |
| **Storage** | Abstracted persistence layer with migrations (`Storage.read()`, `Storage.write()`, `Storage.list()`) |
| **Share** | Built-in session sharing functionality with `Session.share()` |
| **NPM Plugins** | Plugins installed via npm (e.g., `opencode-copilot-auth@0.0.9`) rather than marketplaces |
| **PTY Support** | Pseudo-terminal support in `packages/opencode/src/pty/` |
| **Additional Tools** | `ls`, `multiedit`, `patch`, `batch`, `codesearch` not present in Claude Code |

---

## Agent Architectures (The Loop)

### Claude Code Agent Loop

**SDK Entry Point**: `query()` returns an async generator

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "Fix the bug in auth.py",
  options: {
    allowedTools: ["Read", "Edit", "Bash"],
    permissionMode: "acceptEdits"
  }
})) {
  // Yields: SDKAssistantMessage | SDKUserMessage | SDKResultMessage | SDKSystemMessage
  if (message.type === "assistant") {
    // Process assistant response
  } else if (message.type === "result") {
    // Final result with usage stats
  }
}
```

**Loop Mechanics**:
1. Send prompt to Claude API with tool definitions
2. Claude returns text or `tool_use` content blocks
3. **SDK automatically executes tools** (Read, Write, Bash, etc.) - no user implementation needed
4. Tool results fed back as user messages with `tool_result` blocks
5. Loop continues until Claude emits `end_turn` or `max_turns` reached
6. Hooks fire at lifecycle points (PreToolUse, PostToolUse, Stop, etc.)

**Control Points**:
- `allowedTools` / `disallowedTools` - tool whitelist/blacklist
- `permissionMode`:
  - `default` - standard permission prompts
  - `acceptEdits` - auto-accept file edits
  - `bypassPermissions` - no permission checks (requires `allowDangerouslySkipPermissions`)
  - `plan` - planning mode, no execution
- `canUseTool` callback for custom permission logic
- `maxTurns` - limit conversation turns
- `maxBudgetUsd` - cost limit
- **Hooks** execute bash commands or LLM prompts at lifecycle events

**Subagent Invocation**: Via `Task` tool with `AgentDefinition`

```typescript
options: {
  allowedTools: ["Read", "Glob", "Grep", "Task"],
  agents: {
    "code-reviewer": {
      description: "Expert code reviewer for quality and security reviews.",
      prompt: "Analyze code quality and suggest improvements.",
      tools: ["Read", "Glob", "Grep"],
      model: "sonnet"  // or "opus", "haiku", "inherit"
    }
  }
}
```

**Built-in Subagents**:
- `Explore` - Fast, read-only codebase exploration (uses Haiku)
- `general-purpose` - Complex multi-step tasks (uses Sonnet)
- `Plan` - Research agent for plan mode

### OpenCode Agent Loop

**Entry Point**: `SessionProcessor.create()` with `process()` method

```typescript
// From packages/opencode/src/session/processor.ts
const processor = SessionProcessor.create({
  assistantMessage,
  sessionID,
  model,
  abort: AbortSignal
});

const result = await processor.process(streamInput);
// Returns "continue" | "stop"
```

**Loop Mechanics** (from `processor.ts`):
1. Call `LLM.stream()` with messages and tools
2. Process fine-grained stream events:
   - `start`, `text-start`, `text-delta`, `text-end`
   - `reasoning-start`, `reasoning-delta`, `reasoning-end`
   - `tool-input-start`, `tool-call`, `tool-result`, `tool-error`
   - `start-step`, `finish-step`, `finish`
3. Execute tools via `Tool.define()` handlers with Zod validation
4. Track file changes with `Snapshot.track()` at step start, `Snapshot.patch()` at step end
5. **Doom loop detection**: 3 identical tool calls with same arguments triggers warning
6. Retry logic with exponential backoff for API errors (`SessionRetry`)
7. Publish events via `Bus.publish()` for UI updates

**Control Points** (from `agent.ts`):
- Agent permissions object:
  ```typescript
  permission: {
    edit: "allow" | "deny" | "ask",
    bash: { "git diff*": "allow", "*": "ask" },  // pattern-based
    skill: { "*": "allow" },
    webfetch: "allow",
    doom_loop: "ask",
    external_directory: "ask"
  }
  ```
- Tool filtering per agent via `tools` map: `{ edit: false, write: false }`
- `maxSteps` limit per agent
- `temperature` and `topP` per agent

**Agent Definition** (from `agent.ts`):

```typescript
// Native agents defined in Agent namespace
{
  build: {
    name: "build",
    mode: "primary",
    native: true,
    permission: defaultPermission,
    tools: { ...defaultTools },
  },
  plan: {
    name: "plan",
    mode: "primary",
    native: true,
    permission: planPermission,  // More restrictive
    tools: { ...defaultTools },
  },
  general: {
    name: "general",
    description: "General-purpose agent for complex tasks",
    mode: "subagent",
    hidden: true,
    tools: { todoread: false, todowrite: false, ...defaultTools },
  },
  explore: {
    name: "explore",
    description: "Fast codebase exploration agent",
    mode: "subagent",
    tools: { edit: false, write: false, ...defaultTools },
    prompt: PROMPT_EXPLORE,
  }
}
```

**Custom Agent Definition** (`.opencode/agent/*.md`):

```markdown
---
mode: primary
model: opencode/claude-haiku-4-5
tools:
  "*": false
  "github-triage": true
---

You are a triage agent responsible for triaging github issues.
```

### Key Loop Differences

| Aspect | Claude Code | OpenCode |
|--------|-------------|----------|
| **Tool Execution** | SDK handles automatically, no user code | `execute()` method on each `Tool.define()` |
| **Stream Events** | Message-level granularity (`SDKMessage`) | Fine-grained events (reasoning-delta, text-delta, tool-input-delta) |
| **Doom Loop** | Not explicitly documented | Built-in detection (3 identical calls triggers ask/deny) |
| **File Tracking** | Optional via `enableFileCheckpointing` | Automatic `Snapshot` tracking per step |
| **Retry Logic** | Not exposed in SDK docs | Built-in `SessionRetry` with exponential backoff |
| **Event System** | Hooks (bash commands or LLM prompts) | Bus/Event pub-sub (`Bus.publish()`) |
| **Model Selection** | Via `model` option or per-agent alias | `Provider.getModel(providerID, modelID)` abstraction |
| **Permission Patterns** | Tool-level allow/deny | Glob patterns for bash (`"git diff*": "allow"`) |
| **Cost Tracking** | `total_cost_usd` in result message | `Session.getUsage()` with per-model cost calculation |

---

## Hook/Event Systems

### Claude Code Hooks

Hooks are configured in settings JSON and execute at lifecycle points:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "./validate.sh"
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Check if all tasks are complete: $ARGUMENTS"
      }]
    }]
  }
}
```

**Available Events**:
- `PreToolUse` - Before tool execution (can allow/deny/ask)
- `PostToolUse` - After tool execution
- `PermissionRequest` - When permission dialog shown
- `Notification` - System notifications
- `UserPromptSubmit` - Before processing user input
- `Stop` / `SubagentStop` - When agent finishes
- `PreCompact` - Before context compaction
- `SessionStart` / `SessionEnd` - Session lifecycle

**Hook Types**:
- `command` - Execute bash script, receives JSON on stdin
- `prompt` - LLM-based evaluation (returns approve/block decision)

### OpenCode Events

Events use a typed pub-sub system:

```typescript
// Define events
export const Event = {
  Created: BusEvent.define("session.created", z.object({ info: Info })),
  Updated: BusEvent.define("session.updated", z.object({ info: Info })),
  Error: BusEvent.define("session.error", z.object({ sessionID: z.string(), error: ... })),
}

// Publish
Bus.publish(Session.Event.Created, { info: result });

// Subscribe (in TUI or other clients)
Bus.subscribe(Session.Event.Updated, (data) => { ... });
```

**Key Events**:
- `session.created`, `session.updated`, `session.deleted`
- `session.error`, `session.diff`
- `message.updated`, `message.removed`
- `part.updated`, `part.removed`

---

## Configuration

### Claude Code

```typescript
// SDK options
{
  allowedTools: ["Read", "Edit", "Bash"],
  disallowedTools: ["WebSearch"],
  permissionMode: "acceptEdits",
  systemPrompt: "You are a helpful assistant",
  mcpServers: {
    playwright: { command: "npx", args: ["@playwright/mcp@latest"] }
  },
  hooks: { ... },
  agents: { ... },
  settingSources: ["user", "project", "local"],
  model: "claude-sonnet-4-20250514",
  maxTurns: 10,
  maxBudgetUsd: 5.00
}
```

### OpenCode

```typescript
// Config from opencode.json
{
  "provider": {
    "anthropic": { "apiKey": "..." }
  },
  "model": "anthropic/claude-sonnet-4",
  "default_agent": "build",
  "tools": { "*": true },
  "permission": {
    "edit": "allow",
    "bash": { "*": "allow" }
  },
  "agent": {
    "custom-agent": {
      "description": "...",
      "prompt": "...",
      "model": "openai/gpt-4",
      "tools": { ... }
    }
  }
}
```

---

## Summary

### Similarities (Verified)

1. **Agentic Loop**: Both implement tool-use loops with LLM-driven orchestration
2. **Subagents**: Both support specialized agents for task delegation via `Task` tool
3. **Permission Systems**: Both control tool access (allow/deny/ask) with pattern matching
4. **MCP Support**: Both integrate Model Context Protocol for extensibility
5. **Core Tools**: Same fundamental tools (Read, Write, Edit, Bash, Grep, Glob, WebFetch, WebSearch)
6. **Session Management**: Both persist conversations and support resume/fork
7. **Markdown-based Config**: Both use markdown files for agent/command/skill definitions
8. **Skills**: Both support skills defined in markdown with YAML frontmatter
9. **Todo Tracking**: Both have todo tools for task management

### Major Differences (Verified)

| Aspect | Claude Code | OpenCode |
|--------|-------------|----------|
| **Open Source** | SDK open, core closed | Fully open source |
| **Provider Lock-in** | Anthropic-first | Provider-agnostic (via Vercel AI SDK) |
| **Architecture** | Monolithic CLI + SDK wrapper | True client-server (Hono HTTP + WebSocket) |
| **File Tracking** | Opt-in checkpointing (`~/.claude/file-history/`) | Built-in snapshots per step |
| **Event System** | Shell-based hooks (bash/prompt) | Typed pub-sub bus + plugin hooks |
| **LSP** | Via generic tools | Native integration with dedicated tools (`lsp`, `lsp-hover`, `lsp-diagnostics`) |
| **Doom Loop** | Not documented | Built-in detection (3 identical calls) |
| **Multi-project** | One project per session | Multiple projects per instance |
| **Frontends** | CLI + IDE plugins | TUI, Desktop (Tauri), Web |
| **Plugin System** | Git-based marketplaces | NPM packages |
| **Config Format** | JSON | JSONC (with comments) |
| **Additional Tools** | Standard set | Extras: `ls`, `multiedit`, `patch`, `batch`, `codesearch` |

### When to Choose Each

**Claude Code** is better when:
- You want the most polished Claude experience with enterprise support
- You need enterprise features (managed policies, sandbox, IDE integration)
- You prefer Anthropic's ecosystem (plugin marketplace)
- You want automatic tool execution without implementing handlers
- You need file checkpointing with rewind capability
- Extended thinking (`alwaysThinkingEnabled`) is important

**OpenCode** is better when:
- You need full source code access and customization
- You want provider flexibility (use Claude, OpenAI, local models interchangeably)
- You need client-server architecture (remote sessions, multiple frontends)
- You want native LSP integration for code intelligence
- You prefer a TUI-first experience with rich terminal UI
- You want to extend with custom tools (`multiedit`, `patch`, etc.)
- JSONC configuration with comments is preferred

---

## Appendix: File Structure Comparison

### Claude Code (`~/.claude/`)
```
~/.claude/
├── settings.json              # User settings
├── history.jsonl              # Global prompt history
├── agents/                    # User-defined agents (*.md)
├── plugins/
│   ├── installed_plugins.json
│   └── marketplaces/          # Git-cloned plugin repos
├── projects/<hash>/           # Per-project sessions
│   ├── <session-id>.jsonl     # Main session
│   └── agent-<hash>.jsonl     # Subagent sessions
├── todos/                     # Todo state files
├── plans/                     # Saved plans
├── file-history/              # File checkpoints
├── shell-snapshots/           # Shell state
├── session-env/               # Per-session env vars
├── ide/                       # IDE lock files
└── debug/                     # Debug logs
```

### OpenCode (project-level)
```
.opencode/
├── opencode.json[c]           # Configuration
├── agent/                     # Agent definitions (*.md)
├── command/                   # Custom commands (*.md)
└── skill/*/SKILL.md           # Skill definitions
```

**OpenCode Server** (`packages/opencode/src/`):
```
src/
├── server/server.ts           # Hono HTTP server
├── session/
│   ├── processor.ts           # Agent loop
│   ├── llm.ts                 # LLM streaming (Vercel AI SDK)
│   └── message-v2.ts          # Message format
├── tool/                      # Tool implementations
├── agent/agent.ts             # Agent definitions
├── provider/                  # LLM provider abstraction
├── lsp/                       # Language Server Protocol
├── storage/storage.ts         # Persistence layer
└── bus/                       # Event pub-sub system
```
