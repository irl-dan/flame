# Flame Graph Context Management - Developer Guide

**Version**: 1.0
**Last Updated**: 2025-12-24

---

## Table of Contents

1. [Overview](#1-overview)
2. [Quick Start](#2-quick-start)
3. [Phase 1: Core Tools (Plugin)](#3-phase-1-core-tools-plugin)
4. [Phase 2: UI Components](#4-phase-2-ui-components)
5. [Architecture](#5-architecture)
6. [API Reference](#6-api-reference)
7. [Configuration](#7-configuration)
8. [Development](#8-development)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Overview

### What is Flame Graph Context Management?

Flame is a tree-structured context management system for AI coding agents. It organizes agent work as a **tree of frames** (like a call stack / flame graph) rather than a linear chat history.

### The Problem

Current AI agents use linear conversation history:

```
Message 1 -> Message 2 -> ... -> Message 47 (debugging auth) -> Message 48 (API routes)
```

When working on API routes, the full 47-message auth debugging session is still in context - wasting tokens on irrelevant exploration.

### The Solution

Organize context as a frame tree:

```
                [Root: "Build App"]
                       |
       +---------------+---------------+
       |                               |
 [Auth Frame]                    [API Frame]
  COMPLETED                       IN PROGRESS
  "JWT + refresh tokens"              |
                               +------+------+
                               |             |
                            [CRUD]      [Pagination]
                          IN PROGRESS     PLANNED
```

When working in the CRUD frame:
- **Included**: CRUD's own history + API frame summary + Auth summary + Root goal
- **Excluded**: Auth's 47 debugging messages (only the summary matters)

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Frame** | A unit of work with its own goal, status, and context |
| **Push** | Create a child frame to focus on a subtask |
| **Pop** | Complete a frame and return to the parent |
| **Compaction** | Summary generated when a frame completes |
| **Context Assembly** | Building LLM context from frame tree structure |

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Flame Plugin | `/Users/sl/code/flame/.opencode/plugin/flame.ts` | Core logic, 28 tools, state management |
| Flame UI | `/Users/sl/code/opencode/packages/app/src/components/flame/` | React/SolidJS visualization |
| Server Endpoints | `/Users/sl/code/opencode/packages/opencode/src/server/server.ts` | REST API for UI |

---

## 2. Quick Start

### Prerequisites

- [OpenCode](https://opencode.ai) installed and running
- Bun 1.0+ runtime
- Node.js 18+

### Step 1: Set Up the Flame Plugin

```bash
# Clone the flame repository
git clone https://github.com/yourname/flame
cd flame

# The plugin is already in the correct location:
# .opencode/plugin/flame.ts
```

### Step 2: Run OpenCode with Flame

```bash
# Navigate to your project directory where flame plugin is installed
cd /Users/sl/code/flame

# Start OpenCode - plugin loads automatically
opencode
```

### Step 3: Use Flame Tools

In the OpenCode chat, you can now use flame tools:

```
# View the frame tree
Use flame_status to show me the current frames

# Create a new frame
Use flame_push with goal "Implement user authentication"

# Complete a frame
Use flame_pop with status "completed" and summary "Added JWT auth"

# Plan multiple subtasks
Use flame_plan_children with children ["Design API", "Implement endpoints", "Add tests"]
```

### Step 4: Enable the UI (Optional)

The Phase 2 UI components are in OpenCode's app package. After applying the OpenCode changes:

```bash
cd /Users/sl/code/opencode
bun install
bun run build
```

Then toggle the flame panel with `Cmd+Shift+F` in the web UI.

---

## 3. Phase 1: Core Tools (Plugin)

### Plugin Location

```
/Users/sl/code/flame/.opencode/plugin/flame.ts
```

### Complete Tool Reference (28 Tools)

#### Core Frame Management

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_push` | Create a new child frame for a subtask | `goal: string` |
| `flame_pop` | Complete current frame and return to parent | `status: "completed" | "failed" | "blocked"`, `summary?: string`, `generateSummary?: boolean` |
| `flame_status` | Show the current frame tree with status icons | (none) |

**Example: flame_push**
```typescript
// Creates a child frame under the current active frame
flame_push({ goal: "Implement user authentication" })
// Returns: Frame ID, parent ID, instructions
```

**Example: flame_pop**
```typescript
// Completes the current frame with AI-generated summary
flame_pop({
  status: "completed",
  summary: "Implemented JWT-based authentication",
  generateSummary: true  // Triggers compaction-based summary
})
```

#### Frame Metadata

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_set_goal` | Update the goal of the current frame | `goal: string` |
| `flame_add_artifact` | Record an artifact (file, resource) produced | `artifact: string` |
| `flame_add_decision` | Record a key decision made in this frame | `decision: string` |

#### Context Assembly (Phase 1.2)

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_context_info` | Show context generation metadata (token usage, caching) | (none) |
| `flame_context_preview` | Preview the XML context that would be injected | `maxLength?: number` |
| `flame_cache_clear` | Clear the context cache | `sessionID?: string` |

#### Compaction (Phase 1.3)

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_summarize` | Manually trigger summary generation without completing | `note?: string` |
| `flame_compaction_info` | Show compaction tracking state | (none) |
| `flame_get_summary` | Get the compaction summary for a frame | `sessionID?: string` |

#### Subagent Integration (Phase 1.5)

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_subagent_config` | View/modify subagent integration settings | Multiple optional config params |
| `flame_subagent_stats` | Show subagent session statistics | `reset?: boolean`, `showActive?: boolean` |
| `flame_subagent_complete` | Manually complete a subagent session | `sessionID?: string`, `status?: string`, `summary?: string` |
| `flame_subagent_list` | List all tracked subagent sessions | `filter?: "all" | "active" | "completed" | "with-frame" | "without-frame"` |

#### Planning & Invalidation (Phase 1.6)

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_plan` | Create a planned frame for future work | `goal: string`, `parentSessionID?: string` |
| `flame_plan_children` | Create multiple planned children at once | `children: string[]`, `parentSessionID?: string` |
| `flame_activate` | Start working on a planned frame | `sessionID: string` |
| `flame_invalidate` | Invalidate a frame with cascade to children | `sessionID?: string`, `reason: string` |
| `flame_tree` | Visual ASCII tree of all frames | `showFull?: boolean`, `rootID?: string`, `showDetails?: boolean` |

**Example: flame_plan_children**
```typescript
// Plan out subtasks before starting work
flame_plan_children({
  children: [
    "Design API schema",
    "Implement CRUD endpoints",
    "Add pagination",
    "Write integration tests"
  ]
})
```

#### Agent Autonomy (Phase 1.7)

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_autonomy_config` | View/modify autonomy settings | `level?: "manual" | "suggest" | "auto"`, and more |
| `flame_should_push` | Evaluate push heuristics | `potentialGoal?: string`, `recentMessages?: number`, etc. |
| `flame_should_pop` | Evaluate pop heuristics | `successSignals?: string[]`, `failureSignals?: string[]`, etc. |
| `flame_auto_suggest` | Toggle/view auto-suggestions | `enable?: boolean`, `clearPending?: boolean`, `showHistory?: boolean` |
| `flame_autonomy_stats` | View autonomy statistics | `reset?: boolean` |

#### UI Integration

| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_get_state` | Get complete flame state for UI rendering | (none) |

### Frame Status Types

```typescript
type FrameStatus =
  | "planned"      // Not started yet
  | "in_progress"  // Currently being worked on
  | "completed"    // Successfully finished
  | "failed"       // Failed with errors
  | "blocked"      // Blocked by external dependency
  | "invalidated"  // No longer relevant
```

### Context Injection

The plugin injects frame context into LLM calls via the `experimental.chat.messages.transform` hook:

```xml
<flame-context session="ses_abc123...">
  <ancestors>
    <frame id="ses_xyz..." status="in_progress">
      <goal>Build the application</goal>
      <summary>Setting up project structure...</summary>
    </frame>
  </ancestors>
  <completed-siblings>
    <frame id="ses_def..." status="completed">
      <goal>Set up authentication</goal>
      <summary>Implemented JWT-based auth with refresh tokens</summary>
      <artifacts>src/auth/*, src/models/User.ts</artifacts>
    </frame>
  </completed-siblings>
  <current-frame id="ses_abc..." status="in_progress">
    <goal>Build API routes</goal>
  </current-frame>
</flame-context>
```

---

## 4. Phase 2: UI Components

### Component Directory

```
/Users/sl/code/opencode/packages/app/src/components/flame/
```

### File Structure

```
flame/
  index.tsx               # Public exports
  types.ts               # TypeScript interfaces
  constants.ts           # Colors, dimensions, config
  styles.css             # Component styles

  FlamePanel.tsx         # Main panel container
  FlameProvider.tsx      # State management context
  FlameGraph.tsx         # D3 visualization
  FrameRect.tsx          # Individual frame rectangle
  Connection.tsx         # Parent-child connection lines

  FrameDetails/
    index.tsx            # Details panel container
    Header.tsx           # Frame header with status
    Artifacts.tsx        # Artifacts list
    Decisions.tsx        # Decisions list
    Summary.tsx          # Compaction summary

  dialogs/
    PushFrame.tsx        # Create frame dialog
    PopFrame.tsx         # Complete frame dialog
    PlanChildren.tsx     # Plan children dialog
    InvalidateFrame.tsx  # Invalidate dialog
    EditGoal.tsx         # Inline goal editor

  Tooltip.tsx            # Hover tooltip
  ContextMenu.tsx        # Right-click menu
  ZoomControls.tsx       # Zoom buttons
  Legend.tsx             # Status legend
  SearchBar.tsx          # Search input
  FilterDropdown.tsx     # Status filter
  ConnectionStatus.tsx   # SSE connection indicator
  ErrorBoundary.tsx      # Error handling
  LoadingStates.tsx      # Loading UI

  hooks/
    useZoom.ts           # Pan/zoom behavior
    useLayout.ts         # Layout computation
    useKeyboard.ts       # Keyboard navigation
    useFlameEvents.ts    # SSE subscription
    useAnimation.ts      # Transition utilities

  utils/
    tree.ts              # Tree manipulation
    api.ts               # API client

  __tests__/
    flame.test.ts        # Unit tests
```

### Key Components

#### FlameProvider

State management context that provides:

```typescript
interface FlameContextValue {
  // State
  state: FlameState
  loading: () => boolean
  error: () => Error | null
  selectedFrameID: () => string | null
  connectionStatus: () => "connected" | "reconnecting" | "disconnected"

  // Computed
  activeFrame: () => FrameMetadata | null
  selectedFrame: () => FrameMetadata | null
  treeData: () => D3HierarchyNode | null
  flatFrames: () => FrameMetadata[]

  // Actions
  actions: FlameActions
}
```

**Usage:**

```tsx
import { FlameProvider, useFlame } from "@/components/flame"

function App() {
  return (
    <FlameProvider>
      <FlamePanel />
    </FlameProvider>
  )
}

function MyComponent() {
  const flame = useFlame()

  return (
    <div>
      {flame.flatFrames().map(frame => (
        <div key={frame.sessionID}>{frame.goal}</div>
      ))}
    </div>
  )
}
```

#### FlamePanel

Main container with header, visualization, and details panel:

```tsx
import { FlamePanel } from "@/components/flame"

function SessionPage() {
  return (
    <div class="flex h-full">
      <ChatArea />
      <FlamePanel />
    </div>
  )
}
```

#### FlameGraph

D3-based visualization component:

```tsx
import { FlameGraph } from "@/components/flame"

// Typically used inside FlamePanel, but can be standalone
<FlameGraph
  onFrameClick={(id) => console.log("Clicked:", id)}
  onFrameDoubleClick={(id) => navigateToSession(id)}
/>
```

### Hooks

#### useZoom

```typescript
import { useZoom } from "@/components/flame/hooks/useZoom"

const {
  zoom,           // Current zoom state
  zoomIn,         // Zoom in function
  zoomOut,        // Zoom out function
  resetZoom,      // Reset to default
  setZoomLevel,   // Set specific level
} = useZoom({
  minScale: 0.5,
  maxScale: 4,
  defaultScale: 1,
  onZoomChange: (scale) => console.log("Zoom:", scale),
})
```

#### useKeyboard

```typescript
import { useKeyboard } from "@/components/flame/hooks/useKeyboard"

useKeyboard({
  actions: flame.actions,
  panelVisible: () => true,
  onTogglePanel: () => layout.flame.toggle(),
  onPushFrame: () => openPushDialog(),
  onPopFrame: () => openPopDialog(),
})

// Keyboard shortcuts:
// Arrow Up/Down: Navigate parent/child
// Arrow Left/Right: Navigate siblings
// Enter: Select focused frame
// Escape: Deselect
// Cmd+Enter: Push new frame
// Cmd+Backspace: Pop current frame
// Cmd+Shift+F: Toggle panel
```

#### useFlameEvents

```typescript
import { useFlameEvents } from "@/components/flame/hooks/useFlameEvents"

const events = useFlameEvents({
  onRefresh: () => flame.actions.refresh(),
  onConnectionChange: (status) => setConnectionStatus(status),
  debounceMs: 100,
  enabled: true,
})

// Access:
events.connectionStatus()  // "connected" | "reconnecting" | "disconnected"
events.lastEventTime()     // Timestamp of last event
```

### Utilities

#### tree.ts

```typescript
import {
  buildHierarchy,
  getAncestors,
  getChildren,
  getSiblings,
  getDescendants,
  getPathToFrame,
  countFrames,
  searchFrames,
  getMaxDepth,
} from "@/components/flame/utils/tree"

// Build D3 hierarchy from flat frames
const tree = buildHierarchy(frames, rootFrameIDs)

// Get all ancestors of a frame
const ancestors = getAncestors(frames, "ses_abc123")

// Search frames by goal text
const matches = searchFrames(frames, "authentication")
```

#### api.ts

```typescript
import {
  fetchFlameState,
  executeFlameAction,
  validateFlameState,
} from "@/components/flame/utils/api"

// Fetch state from server
const state = await fetchFlameState(baseUrl, directory)

// Execute a flame tool
await executeFlameAction(baseUrl, directory, "push", {
  goal: "New subtask"
})
```

---

## 5. Architecture

### Data Flow

```
                    +------------------+
                    |   Flame Plugin   |
                    |  (flame.ts)      |
                    +--------+---------+
                             |
                             | Writes state to file
                             |
                    +--------v---------+
                    |  .opencode/      |
                    |  flame/state.json|
                    +--------+---------+
                             |
                             | Read via REST API
                             |
              +--------------v---------------+
              |    OpenCode Server           |
              |  /flame/state (GET)          |
              |  /flame/tool (POST)          |
              +--------------+---------------+
                             |
                             | HTTP / SSE
                             |
              +--------------v---------------+
              |    Flame UI (SolidJS)        |
              |  FlameProvider -> FlamePanel |
              +------------------------------+
```

### State Structure

```typescript
interface FlameState {
  version: number                        // Schema version
  frames: Record<string, FrameMetadata>  // All frames by sessionID
  activeFrameID?: string                 // Currently active frame
  rootFrameIDs: string[]                 // Top-level frames
  updatedAt: number                      // Last modification timestamp
}

interface FrameMetadata {
  sessionID: string              // Unique identifier
  parentSessionID?: string       // Parent frame (undefined for roots)
  status: FrameStatus            // Current status
  goal: string                   // What this frame aims to accomplish
  createdAt: number              // Creation timestamp
  updatedAt: number              // Last update timestamp
  artifacts: string[]            // Files/resources produced
  decisions: string[]            // Key decisions made
  compactionSummary?: string     // AI-generated summary
  invalidationReason?: string    // Why invalidated (if applicable)
  invalidatedAt?: number         // When invalidated
  plannedChildren?: string[]     // IDs of planned child frames
}
```

### Server Endpoints

#### GET /flame/state

Reads the flame state directly from `.opencode/flame/state.json`:

```typescript
// Request
GET /flame/state?directory=/path/to/project

// Response
{
  "version": 1,
  "frames": { ... },
  "activeFrameID": "ses_abc123",
  "rootFrameIDs": ["ses_root"],
  "updatedAt": 1735055500000
}
```

#### POST /flame/tool

Executes a flame tool:

```typescript
// Request
POST /flame/tool?directory=/path/to/project
{
  "tool": "push",
  "args": {
    "goal": "New subtask"
  }
}

// Response
{
  "success": true,
  "result": "Created new frame for: \"New subtask\"..."
}
```

### Plugin Hooks

The flame plugin uses OpenCode's hook system:

| Hook | Purpose |
|------|---------|
| `event` | Track session lifecycle events |
| `chat.message` | Capture current session ID |
| `experimental.chat.messages.transform` | Inject frame context |
| `experimental.session.compacting` | Custom compaction prompts |

---

## 6. API Reference

### Status Colors

```typescript
const STATUS_COLORS: Record<FrameStatus, string> = {
  planned: "#9CA3AF",      // gray-400
  in_progress: "#3B82F6",  // blue-500
  completed: "#22C55E",    // green-500
  failed: "#EF4444",       // red-500
  blocked: "#F59E0B",      // amber-500
  invalidated: "#6B7280",  // gray-500
}
```

### Panel Dimensions

```typescript
const PANEL_DIMENSIONS = {
  defaultWidth: 320,
  minWidth: 240,
  maxWidthPercent: 0.4,
}

const FRAME_DIMENSIONS = {
  minHeight: 24,
  padding: 4,
  gap: 2,
  minLabelWidth: 40,
  borderRadius: 4,
}
```

### Animation Durations

```typescript
const ANIMATION_DURATIONS = {
  statusChange: 300,  // ms
  layout: 300,
  zoom: 200,
  hover: 150,
}
```

### Zoom Configuration

```typescript
const ZOOM_CONFIG = {
  minScale: 0.5,
  maxScale: 4,
  defaultScale: 1,
  zoomStep: 0.25,
}
```

---

## 7. Configuration

### Environment Variables

#### Token Budget (Phase 1.2)

```bash
# Total token budget for context injection
FLAME_TOKEN_BUDGET_TOTAL=4000

# Budget allocation
FLAME_TOKEN_BUDGET_ANCESTORS=1500
FLAME_TOKEN_BUDGET_SIBLINGS=1500
FLAME_TOKEN_BUDGET_CURRENT=800
```

#### Subagent Integration (Phase 1.5)

```bash
# Enable/disable subagent detection
FLAME_SUBAGENT_ENABLED=true

# Minimum session duration for frame creation (ms)
FLAME_SUBAGENT_MIN_DURATION=60000

# Minimum message count
FLAME_SUBAGENT_MIN_MESSAGES=3

# Auto-complete frames when session goes idle
FLAME_SUBAGENT_AUTO_COMPLETE=true

# Delay before auto-complete (ms)
FLAME_SUBAGENT_IDLE_DELAY=5000

# Detection patterns (comma-separated regex)
FLAME_SUBAGENT_PATTERNS="@.*subagent,subagent,\\[Task\\]"
```

#### Agent Autonomy (Phase 1.7)

```bash
# Autonomy level: manual, suggest, or auto
FLAME_AUTONOMY_LEVEL=suggest

# Confidence threshold for auto-push (0-100)
FLAME_PUSH_THRESHOLD=70

# Confidence threshold for auto-pop (0-100)
FLAME_POP_THRESHOLD=80

# Include suggestions in LLM context
FLAME_SUGGEST_IN_CONTEXT=true

# Enabled heuristics (comma-separated)
FLAME_ENABLED_HEURISTICS=failure_boundary,context_switch,complexity,duration,goal_completion,stagnation,context_overflow
```

### File Storage

Flame stores state in:

```
.opencode/
  flame/
    state.json                 # Global frame tree state
    frames/
      <sessionID>.json         # Individual frame files
```

---

## 8. Development

### Running the Plugin

```bash
# Navigate to the project with the flame plugin
cd /Users/sl/code/flame

# Start OpenCode - plugin loads automatically
opencode

# Or specify plugin directory explicitly
opencode --plugin-dir /Users/sl/code/flame/.opencode/plugin
```

### Running Tests

```bash
# Phase 1.1 State Manager tests
/Users/sl/code/flame/phase1/1.1-state-manager/tests/test-state-manager.sh

# Phase 1.7 Autonomy tests
/Users/sl/code/flame/phase1/1.7-agent-autonomy/tests/test-autonomy.sh

# Full validation
/Users/sl/code/flame/phase1/final-validation/run-validation.sh
```

### Building the UI

```bash
cd /Users/sl/code/opencode

# Install dependencies
bun install

# Build all packages
bun run build

# Run in development mode
bun run dev
```

### UI Tests

```bash
cd /Users/sl/code/opencode/packages/app

# Run vitest tests
bun run test

# Run specific test file
bun run test src/components/flame/__tests__/flame.test.ts
```

### Adding a New Tool

1. Add tool definition in `flame.ts`:

```typescript
flame_my_new_tool: tool({
  description: "What this tool does",
  args: {
    param1: tool.schema.string().describe("Parameter description"),
    param2: tool.schema.number().optional(),
  },
  async execute(args, toolCtx) {
    // Implementation
    return "Result message"
  },
}),
```

2. Add the tool to the `tool: { }` object in the plugin export.

3. Update documentation.

### Adding a New UI Component

1. Create component file in appropriate directory
2. Add TypeScript types to `types.ts`
3. Export from `index.tsx`
4. Add to FlamePanel if needed
5. Write tests

---

## 9. Troubleshooting

### Common Issues

#### Plugin Not Loading

**Symptoms**: No flame_* tools available

**Solutions**:
1. Check plugin is in `.opencode/plugin/flame.ts`
2. Verify OpenCode is running from the correct directory
3. Check console for plugin load errors

```bash
# Verify plugin location
ls -la .opencode/plugin/flame.ts

# Check plugin syntax
bun run .opencode/plugin/flame.ts
```

#### State File Not Found

**Symptoms**: UI shows "No frames" despite using tools

**Solutions**:
1. Check state file exists:
   ```bash
   cat .opencode/flame/state.json | jq
   ```
2. Verify write permissions
3. Check for JSON parse errors

#### UI Not Connecting

**Symptoms**: Connection status shows "disconnected"

**Solutions**:
1. Verify OpenCode server is running
2. Check server logs for /flame/state errors
3. Verify CORS settings allow requests

```bash
# Test API directly
curl http://localhost:3000/flame/state?directory=/Users/sl/code/flame
```

#### Context Not Injecting

**Symptoms**: LLM doesn't see frame context

**Solutions**:
1. Check `flame_context_preview` output
2. Verify transform hook is registered
3. Check for double-hook registration issues

#### Tool Execution Fails

**Symptoms**: "Tool not found" errors

**Solutions**:
1. Use full tool name with `flame_` prefix
2. Check tool is exported in plugin
3. Verify OpenCode version supports plugin tools

### Debug Logging

Enable verbose logging:

```bash
# In the plugin, logs go to console
# Check OpenCode logs for plugin output
```

### Resetting State

```bash
# Clear all frame state
rm -rf .opencode/flame/

# Restart OpenCode
opencode
```

### Performance Issues

For large frame trees (>100 frames):

1. Increase cache TTL:
   ```bash
   FLAME_CACHE_TTL=60000  # 60 seconds
   ```

2. Reduce context budget:
   ```bash
   FLAME_TOKEN_BUDGET_TOTAL=2000
   ```

3. Use filters in UI to show relevant subset

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-24 | Initial comprehensive documentation |

---

*This documentation covers both Phase 1 (Plugin) and Phase 2 (UI) of the Flame Graph Context Management system. For theoretical background, see [SPEC.md](./SPEC.md). For project history, see [GOAL.md](./GOAL.md).*
