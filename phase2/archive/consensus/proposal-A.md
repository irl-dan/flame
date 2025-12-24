# Phase 2 Implementation Plan: Flame Graph Web UI

## Executive Summary

Phase 2 builds upon the Phase 1 Flame plugin to create an interactive web-based visualization of the frame call stack as a flame graph. This document provides a comprehensive implementation plan covering architecture, data flow, visualization approach, user interactions, and phased delivery milestones.

### Key Deliverables

1. **Web-based Flame Graph Viewer** - Interactive SVG-based visualization showing frame hierarchy
2. **Real-time Synchronization** - Live updates via Server-Sent Events (SSE)
3. **Frame Management UI** - Push, pop, plan, activate, invalidate frames from the browser
4. **Integration with OpenCode** - Seamless connection to OpenCode server and sessions
5. **Developer-friendly Architecture** - SolidJS + Vite stack for fast development

### Estimated Timeline

- **Total Duration**: 12 weeks
- **Phase 2.1-2.2** (Weeks 1-4): Foundation and core visualization
- **Phase 2.3-2.4** (Weeks 5-8): Interactions and frame operations
- **Phase 2.5-2.6** (Weeks 9-12): Polish, real-time, and deployment

### Prerequisites

- Phase 1 Flame plugin installed and functional
- OpenCode server running with plugin loaded
- Node.js 18+ for development
- Modern browser (Chrome, Firefox, Safari, Edge)

---

## Table of Contents

1. [Background and Context](#1-background-and-context)
2. [Architecture Overview](#2-architecture-overview)
3. [Data Flow Design](#3-data-flow-design)
4. [API Design](#4-api-design)
5. [Flame Graph Visualization](#5-flame-graph-visualization)
6. [User Interactions](#6-user-interactions)
7. [Real-time Updates](#7-real-time-updates)
8. [Technology Choices](#8-technology-choices)
9. [Integration Points](#9-integration-points)
10. [Implementation Phases](#10-implementation-phases)
11. [Testing Strategy](#11-testing-strategy)
12. [Future Considerations](#12-future-considerations)

---

## 1. Background and Context

### 1.1 The Problem (from SPEC.md)

Current agent implementations organize conversation history as a linear sequence of messages, creating:

- **Context window pressure**: Full linear history fills the context window
- **Misaligned mental model**: Engineers think in call stacks, not transcripts
- **Irrelevant context pollution**: Sibling task history unnecessarily prefixed
- **No structural memory**: Parent/child/sibling relationships are implicit

### 1.2 Phase 1 Accomplishments

The Phase 1 plugin (`flame.ts`, ~5,000 lines) implements:

- **FrameStateManager** class with file-based persistence
- **28 flame_* tools** for frame manipulation
- **Frame states**: planned, in_progress, completed, failed, blocked, invalidated
- **Token budget management** with intelligent ancestor/sibling selection
- **Context caching** with TTL and state-hash invalidation
- **Compaction integration** for frame summaries
- **Subagent session tracking** and auto-completion
- **Agent autonomy** with push/pop heuristics and suggestions

### 1.3 State File Format

The plugin persists state to `.opencode/flame/state.json`:

```json
{
  "version": 1,
  "frames": {
    "ses_xxx": {
      "sessionID": "ses_xxx",
      "parentSessionID": "ses_yyy",
      "status": "in_progress",
      "goal": "Build authentication system",
      "createdAt": 1766587042888,
      "updatedAt": 1766587042888,
      "artifacts": ["src/auth/*"],
      "decisions": ["Use JWT tokens"],
      "compactionSummary": "...",
      "invalidationReason": "...",
      "plannedChildren": ["plan-xxx"]
    }
  },
  "activeFrameID": "ses_xxx",
  "rootFrameIDs": ["ses_yyy"],
  "updatedAt": 1766587045174
}
```

---

## 2. Architecture Overview

### 2.0 Key Architectural Decision: How to Expose Flame State

There are three viable approaches to expose Flame plugin state to the Web UI:

#### Option 1: Direct File Reading (Not Recommended)

The Web UI directly reads `.opencode/flame/state.json`:

```
Web UI --> File System --> state.json
```

**Pros:**
- Simplest implementation
- No server changes needed

**Cons:**
- Requires file system access (not browser-native)
- Security concerns with file paths
- No real-time updates without polling
- Tightly couples UI to file format

#### Option 2: New Dedicated HTTP Endpoints (Recommended)

Add new `/flame/*` routes to OpenCode server that read plugin state:

```
Web UI --> OpenCode Server --> Plugin State Manager
```

**Pros:**
- Clean API design
- Proper abstraction layer
- Real-time via existing SSE infrastructure
- Can add validation, caching, access control

**Cons:**
- Requires OpenCode server modifications
- More implementation work

#### Option 3: Tool Execution via SDK (Hybrid)

Use existing session.command to execute flame tools:

```
Web UI --> SDK --> session.command("flame_status") --> Plugin
```

**Pros:**
- Works with current plugin structure
- No server changes needed
- Reuses existing tools

**Cons:**
- Requires active session
- Slower (full LLM round-trip)
- Tools designed for agent, not UI consumption

**Decision: Option 2 with Option 3 Fallback**

Primary path uses new dedicated endpoints for efficiency. Fallback to tool execution for operations that modify state (ensures proper plugin lifecycle).

### 2.1 High-Level Architecture

```
+-------------------+     +-------------------+     +-------------------+
|                   |     |                   |     |                   |
|   Flame Plugin    |<--->|  OpenCode Server  |<--->|    Web UI         |
|   (Phase 1)       |     |  (HTTP + SSE)     |     |  (Phase 2)        |
|                   |     |                   |     |                   |
+--------+----------+     +--------+----------+     +--------+----------+
         |                         |                         |
         v                         v                         v
+-------------------+     +-------------------+     +-------------------+
|  .opencode/flame/ |     |  Event Bus        |     |  React/Solid      |
|  state.json       |     |  (SSE Stream)     |     |  Components       |
|  frames/*.json    |     |                   |     |                   |
+-------------------+     +-------------------+     +-------------------+
```

### 2.2 Component Breakdown

#### 2.2.1 Flame Plugin Extensions

The Phase 1 plugin needs minimal extensions:
- **New flame event types** for broadcasting state changes
- **REST API tools** for direct state queries (beyond existing tools)
- **WebSocket/SSE integration** for real-time updates

#### 2.2.2 OpenCode Server Integration

Leverage existing OpenCode server infrastructure:
- **HTTP endpoints** via OpenAPI spec
- **SSE event stream** at `/event` for real-time updates
- **SDK client** (`@opencode-ai/sdk`) for type-safe access

#### 2.2.3 Web UI Application

A standalone web application that:
- Connects to OpenCode server
- Renders flame graph visualization
- Provides interactive controls
- Updates in real-time

### 2.3 Deployment Options

**Option A: Embedded in OpenCode Server**
- Add routes to existing server
- Served at `/flame` or similar
- Pros: Single deployment, shared auth
- Cons: Couples to OpenCode release cycle

**Option B: Standalone Web App**
- Separate static build
- Connects to OpenCode server URL
- Pros: Independent deployment, easier iteration
- Cons: CORS configuration, separate hosting

**Recommendation**: Start with Option B for faster iteration, with Option A as future integration path.

---

## 3. Data Flow Design

### 3.1 State Retrieval Flow

```
Web UI                    Server                    Plugin
  |                         |                         |
  |-- GET /flame/state ---->|                         |
  |                         |-- Read state.json ----->|
  |                         |<-- FlameState ----------|
  |<-- FlameState ----------|                         |
```

### 3.2 Action Flow (Push/Pop/etc.)

```
Web UI                    Server                    Plugin
  |                         |                         |
  |-- POST /flame/push ---->|                         |
  |  { goal: "..." }        |                         |
  |                         |-- flame_push tool ----->|
  |                         |                         |-- Create frame
  |                         |                         |-- Save state
  |                         |<-- Result --------------|
  |<-- Success -------------|                         |
  |                         |                         |
  |<-- SSE: frame.created --|<-- Event published -----|
```

### 3.3 Real-time Update Flow

```
Web UI                    Server                    Plugin
  |                         |                         |
  |-- GET /event ---------->|                         |
  |   (SSE connection)      |                         |
  |                         |                         |
  |                         |<-- frame.updated -------|
  |<-- SSE: frame.updated --|                         |
  |                         |                         |
  |-- Update visualization  |                         |
```

### 3.4 State Synchronization Strategy

1. **Initial Load**: Fetch complete state via REST
2. **Incremental Updates**: Receive events via SSE
3. **Reconciliation**: On reconnect, fetch full state and diff
4. **Optimistic Updates**: Apply changes locally, reconcile on event

---

## 4. API Design

### 4.1 New REST Endpoints

#### 4.1.1 GET /flame/state

Retrieve complete flame graph state.

**Response:**
```typescript
interface FlameStateResponse {
  version: number
  frames: Record<string, FrameMetadata>
  activeFrameID?: string
  rootFrameIDs: string[]
  updatedAt: number
}
```

#### 4.1.2 GET /flame/frame/:id

Retrieve single frame details.

**Response:**
```typescript
interface FrameDetailResponse {
  frame: FrameMetadata
  ancestors: FrameMetadata[]
  children: FrameMetadata[]
  siblings: FrameMetadata[]
}
```

#### 4.1.3 POST /flame/push

Create new child frame.

**Request:**
```typescript
interface PushRequest {
  goal: string
  parentSessionID?: string  // defaults to active frame
}
```

**Response:**
```typescript
interface PushResponse {
  frame: FrameMetadata
  sessionID: string
}
```

#### 4.1.4 POST /flame/pop

Complete current frame.

**Request:**
```typescript
interface PopRequest {
  sessionID?: string  // defaults to active frame
  status: "completed" | "failed" | "blocked"
  summary?: string
  generateSummary?: boolean
}
```

#### 4.1.5 POST /flame/plan

Create planned frame.

**Request:**
```typescript
interface PlanRequest {
  goal: string
  parentSessionID?: string
}
```

#### 4.1.6 POST /flame/plan-children

Create multiple planned children.

**Request:**
```typescript
interface PlanChildrenRequest {
  parentSessionID?: string
  children: string[]  // goals
}
```

#### 4.1.7 POST /flame/activate

Activate a planned frame.

**Request:**
```typescript
interface ActivateRequest {
  sessionID: string
}
```

#### 4.1.8 POST /flame/invalidate

Invalidate a frame.

**Request:**
```typescript
interface InvalidateRequest {
  sessionID?: string
  reason: string
}
```

#### 4.1.9 PATCH /flame/frame/:id

Update frame metadata.

**Request:**
```typescript
interface UpdateFrameRequest {
  goal?: string
  artifacts?: string[]
  decisions?: string[]
}
```

### 4.2 New Event Types

Extend OpenCode's event system with flame-specific events:

```typescript
// New events to add to the bus
const FlameEvents = {
  FrameCreated: BusEvent.define("flame.frame.created", z.object({
    frame: FrameMetadata,
    parentID: z.string().optional(),
  })),

  FrameUpdated: BusEvent.define("flame.frame.updated", z.object({
    frame: FrameMetadata,
    changes: z.array(z.string()),  // field names that changed
  })),

  FrameCompleted: BusEvent.define("flame.frame.completed", z.object({
    frame: FrameMetadata,
    status: z.enum(["completed", "failed", "blocked"]),
  })),

  FrameActivated: BusEvent.define("flame.frame.activated", z.object({
    frame: FrameMetadata,
    previousActiveID: z.string().optional(),
  })),

  FrameInvalidated: BusEvent.define("flame.frame.invalidated", z.object({
    frame: FrameMetadata,
    cascadedFrames: z.array(FrameMetadata),
    reason: z.string(),
  })),

  StateChanged: BusEvent.define("flame.state.changed", z.object({
    activeFrameID: z.string().optional(),
    frameCount: z.number(),
    updatedAt: z.number(),
  })),
}
```

### 4.3 Plugin API Extensions

Add new tools to the plugin for API bridge:

```typescript
// New tools for REST API bridge
flame_api_state: tool({
  description: "Get complete flame state for API consumers",
  args: {},
  async execute() {
    return manager.getAllFrames()
  },
}),

flame_api_frame: tool({
  description: "Get frame with context for API consumers",
  args: {
    sessionID: tool.schema.string(),
  },
  async execute(args) {
    const frame = await manager.getFrame(args.sessionID)
    const ancestors = await manager.getAncestors(args.sessionID)
    const children = await manager.getAllChildren(args.sessionID)
    const siblings = await manager.getAllSiblings(args.sessionID)
    return { frame, ancestors, children, siblings }
  },
}),
```

---

## 5. Flame Graph Visualization

### 5.1 Visual Design Philosophy

The flame graph should:
- Show hierarchical frame relationships clearly
- Indicate frame status through color coding
- Highlight the active frame prominently
- Support deep hierarchies without visual clutter
- Provide contextual information on hover/click

### 5.2 Layout Algorithm

#### 5.2.1 Horizontal Flame Graph (Recommended)

```
Root Frame [===============================================]
  ├─ Child A [==================]  Child B [=============]
  │    ├─ A1 [====]  A2 [====]      ├─ B1 [=====]
  │    └─ A3 [========]             └─ B2 [===] (planned)
```

**Layout Rules:**
1. Root frames at top
2. Children below parent
3. Width proportional to duration/complexity (or equal for simplicity)
4. Vertical spacing based on hierarchy depth
5. Horizontal arrangement: chronological or status-based

#### 5.2.2 Vertical Flame Graph (Alternative)

Traditional flame graph orientation with frames stacking upward:

```
       [A1] [A2]        [B1]
    [=====Child A=====] [Child B]
    [============Root Frame============]
```

#### 5.2.3 Icicle Chart (Alternative)

Inverted flame graph, frames descend from root:

```
[============Root Frame============]
    [=====Child A=====] [Child B]
       [A1] [A2]        [B1]
```

**Recommendation:** Horizontal layout with icicle orientation (root at top, children below) - matches typical tree visualization mental models.

### 5.3 Color Scheme

| Status | Color | Description |
|--------|-------|-------------|
| in_progress | Blue (#3B82F6) | Currently active work |
| completed | Green (#22C55E) | Successfully finished |
| planned | Gray (#9CA3AF) | Scheduled but not started |
| failed | Red (#EF4444) | Error or failure |
| blocked | Yellow (#F59E0B) | Waiting on dependency |
| invalidated | Strikethrough Gray (#6B7280) | No longer relevant |

### 5.4 Visual Elements

#### 5.4.1 Frame Box

```
+------------------------------------------+
| [Status Icon] Frame Goal                 |
| ID: xxx | Duration: 5m | Artifacts: 3    |
+------------------------------------------+
```

**Interactive States:**
- Default: Background color by status
- Hover: Elevated shadow, tooltip
- Selected: Bold border, expanded info
- Active: Pulsing border animation

#### 5.4.2 Connection Lines

- Solid lines: Parent-child relationships
- Dashed lines: Planned relationships
- Arrow heads: Direction of flow

#### 5.4.3 Minimap

For large graphs, provide a minimap showing:
- Overall structure
- Viewport indicator
- Quick navigation

### 5.5 Responsive Design

- **Desktop**: Full flame graph with details panel
- **Tablet**: Collapsible details, touch interactions
- **Mobile**: Simplified tree view, swipe navigation

### 5.6 Detailed Wireframes

#### 5.6.1 Main Application Layout

```
+------------------------------------------------------------------+
|  [Logo] Flame Graph          [Search...] [Filter v]  [Settings]  |
+------------------------------------------------------------------+
|                           |                                       |
|    MINIMAP               |        MAIN VISUALIZATION              |
|    +------+              |                                        |
|    |      |              |  +----------------------------------+  |
|    | [.]  |              |  |        Root Frame                |  |
|    +------+              |  |  "Build authentication system"   |  |
|                          |  +----------------------------------+  |
|  FRAME TREE              |       /              \                 |
|  +-----------------+     |  +----------+    +----------+          |
|  | > Root Frame    |     |  | Child A  |    | Child B  |          |
|  |   > Child A     |     |  +----------+    +----------+          |
|  |     - A1        |     |       |                                |
|  |     - A2        |     |   +------+                             |
|  |   > Child B     |     |   | A1   |                             |
|  |     - B1 (plan) |     |   +------+                             |
|  +-----------------+     |                                        |
|                          |                                        |
+------------------------------------------------------------------+
|  Status: Connected | Frames: 5 | Active: Child A | Updated: now  |
+------------------------------------------------------------------+
```

#### 5.6.2 Frame Details Panel (Slide-out)

```
+------------------------------------------------------------------+
|                             |  DETAILS PANEL                [X]  |
|                             +------------------------------------+
|    MAIN VISUALIZATION       |  Frame: ses_abc123                 |
|                             |  +---------------------------------+
|                             |  | Goal                            |
|                             |  | "Implement JWT authentication"  |
|  (graph continues)          |  | [Edit]                          |
|                             |  +---------------------------------+
|                             |  | Status: in_progress   [Change]  |
|                             |  | Duration: 12m 34s               |
|                             |  | Created: 10:30:00               |
|                             |  +---------------------------------+
|                             |  | Artifacts:                      |
|                             |  |  * src/auth/jwt.ts              |
|                             |  |  * src/auth/middleware.ts       |
|                             |  |  [+ Add Artifact]               |
|                             |  +---------------------------------+
|                             |  | Decisions:                      |
|                             |  |  * Use RS256 signing            |
|                             |  |  * Rotate refresh tokens        |
|                             |  |  [+ Add Decision]               |
|                             |  +---------------------------------+
|                             |  | Summary:                        |
|                             |  | "Implemented secure JWT auth    |
|                             |  |  with refresh token rotation.."|
|                             |  +---------------------------------+
|                             |  | [View Session] [Complete] [X]   |
|                             +------------------------------------+
+------------------------------------------------------------------+
```

#### 5.6.3 Push Frame Dialog

```
+----------------------------------+
|        New Frame            [X]  |
+----------------------------------+
|                                  |
|  Parent Frame:                   |
|  +----------------------------+  |
|  | Root Frame (ses_abc...)    |  |
|  +----------------------------+  |
|                                  |
|  Goal:                           |
|  +----------------------------+  |
|  | Implement user registration|  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  [x] Start immediately           |
|  [ ] Plan for later              |
|                                  |
|  +----------------------------+  |
|  |  [Cancel]       [Create]   |  |
|  +----------------------------+  |
+----------------------------------+
```

#### 5.6.4 Pop Frame Dialog

```
+----------------------------------+
|      Complete Frame         [X]  |
+----------------------------------+
|                                  |
|  Frame: "Implement JWT auth"     |
|                                  |
|  Status:                         |
|  (*) Completed                   |
|  ( ) Failed                      |
|  ( ) Blocked                     |
|                                  |
|  Summary:                        |
|  +----------------------------+  |
|  | Successfully implemented   |  |
|  | JWT authentication with... |  |
|  +----------------------------+  |
|                                  |
|  [x] Generate AI summary         |
|                                  |
|  +----------------------------+  |
|  |  [Cancel]      [Complete]  |  |
|  +----------------------------+  |
+----------------------------------+
```

#### 5.6.5 Context Menu

```
               +----------------------+
               | Push Child Frame     |
               | Plan Child Frame     |
               +----------------------+
               | Edit Goal            |
               | Add Artifact         |
               | Add Decision         |
               +----------------------+
               | Complete Frame       |
               | Invalidate Frame     |
               +----------------------+
               | View Session         |
               | Copy Frame ID        |
               +----------------------+
```

---

## 6. User Interactions

### 6.1 Navigation

| Action | Interaction | Result |
|--------|-------------|--------|
| Pan | Click + drag | Move viewport |
| Zoom | Scroll wheel / pinch | Zoom in/out |
| Focus | Double-click frame | Center and zoom to frame |
| Reset | "Reset View" button | Return to default view |

### 6.2 Frame Operations

| Action | UI Element | API Call |
|--------|------------|----------|
| Push Frame | "New Frame" button, context menu | POST /flame/push |
| Pop Frame | "Complete" button on active frame | POST /flame/pop |
| Set Goal | Edit icon on frame | PATCH /flame/frame/:id |
| Add Artifact | "Add Artifact" in details | PATCH /flame/frame/:id |
| Invalidate | Context menu "Invalidate" | POST /flame/invalidate |
| Plan Frame | "Plan" button, context menu | POST /flame/plan |
| Activate | "Start" button on planned frame | POST /flame/activate |

### 6.3 Information Display

#### 6.3.1 Frame Tooltip (Hover)

```
+--------------------------------+
| Goal: Implement auth system    |
| Status: in_progress            |
| Duration: 12m 34s              |
| Messages: 15                   |
+--------------------------------+
```

#### 6.3.2 Frame Details Panel (Click)

```
+----------------------------------------+
| Frame Details                     [X]  |
+----------------------------------------+
| Goal: Implement auth system            |
| ID: ses_abc123                         |
| Status: in_progress                    |
| Created: 2024-01-15 10:30:00           |
| Updated: 2024-01-15 10:42:34           |
+----------------------------------------+
| Artifacts:                             |
| - src/auth/jwt.ts                      |
| - src/auth/middleware.ts               |
+----------------------------------------+
| Decisions:                             |
| - Use RS256 for JWT signing            |
| - Implement refresh token rotation     |
+----------------------------------------+
| Summary:                               |
| (compaction summary if available)      |
+----------------------------------------+
| [View Session] [Edit] [Complete]       |
+----------------------------------------+
```

### 6.4 Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Arrow keys | Navigate between frames |
| Enter | Select/expand frame |
| Escape | Deselect, close panel |
| N | New frame (push) |
| C | Complete frame (pop) |
| P | Plan new frame |
| / | Search frames |
| ? | Show help |

### 6.5 Search and Filter

**Search Box:**
- Filter frames by goal text
- Filter by status
- Filter by artifact path
- Highlight matching frames

**Filter Bar:**
- Status toggles (show/hide by status)
- Date range
- Depth limit

---

## 7. Real-time Updates

### 7.1 SSE Connection Management

```typescript
class FlameEventSource {
  private eventSource: EventSource | null = null
  private reconnectAttempts = 0
  private maxReconnectAttempts = 10
  private baseDelay = 1000

  connect(serverUrl: string) {
    this.eventSource = new EventSource(`${serverUrl}/event`)

    this.eventSource.onopen = () => {
      this.reconnectAttempts = 0
      this.onConnected()
    }

    this.eventSource.onerror = () => {
      this.scheduleReconnect()
    }

    this.eventSource.addEventListener('flame.frame.created', (e) => {
      this.handleFrameCreated(JSON.parse(e.data))
    })

    // ... other event listeners
  }

  private scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.onMaxRetriesExceeded()
      return
    }

    const delay = this.baseDelay * Math.pow(2, this.reconnectAttempts)
    this.reconnectAttempts++

    setTimeout(() => this.connect(this.serverUrl), delay)
  }
}
```

### 7.2 State Reconciliation

**On Reconnect:**
1. Fetch full state via REST
2. Compare with local state
3. Apply deltas
4. Re-render affected components

**Conflict Resolution:**
- Server state wins
- Optimistic updates rolled back if conflict
- User notified of conflicts

### 7.3 Animation Strategy

**Frame Creation:**
- Fade in + grow animation
- Connection line draws in

**Frame Update:**
- Color transition on status change
- Pulse on active frame change

**Frame Completion:**
- Shrink + fade to completed state
- Connection lines remain

**Invalidation Cascade:**
- Sequential fade out
- Visual ripple effect

---

## 8. Technology Choices

### 8.1 Framework Comparison

| Framework | Pros | Cons | Recommendation |
|-----------|------|------|----------------|
| **React** | Large ecosystem, familiar | Heavy for this use case | Consider |
| **SolidJS** | Fast, already used in OpenCode TUI | Smaller ecosystem | **Recommended** |
| **Svelte** | Minimal runtime, great perf | Different paradigm | Consider |
| **Vue** | Good balance, easy learning | Another framework | Not recommended |
| **Vanilla** | No dependencies | More code | Not recommended |

**Recommendation: SolidJS** - Aligns with OpenCode TUI, great performance, reactive primitives.

### 8.2 Visualization Library

| Library | Pros | Cons | Recommendation |
|---------|------|------|----------------|
| **D3.js** | Powerful, flexible | Complex, low-level | For custom layout |
| **Recharts** | Easy, React-based | Not flame-graph specific | Not suitable |
| **visx** | React + D3 | React-specific | Consider with React |
| **flame-chart-js** | Flame graph specific | Limited customization | Consider |
| **Custom SVG** | Full control | More work | **Recommended** |

**Recommendation: Custom SVG with D3 layout helpers** - Maximum control over appearance and interactions.

### 8.3 State Management

| Solution | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| **SolidJS Stores** | Native, reactive | Limited for complex state | **Recommended** |
| **Zustand** | Simple, framework-agnostic | Another dependency | Consider |
| **Jotai** | Atomic, flexible | React-focused | Not with Solid |
| **XState** | State machines | Overhead | Not needed |

**Recommendation: SolidJS Stores** - Native solution, sufficient for this use case.

### 8.4 Build System

| Tool | Pros | Cons | Recommendation |
|------|------|------|----------------|
| **Vite** | Fast, modern | - | **Recommended** |
| **esbuild** | Very fast | Less features | Consider |
| **Webpack** | Mature | Slow, complex | Not recommended |

**Recommendation: Vite** - Fast, great DX, SolidJS support.

### 8.5 Styling

| Solution | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| **Tailwind CSS** | Utility-first, fast | Learning curve | **Recommended** |
| **CSS Modules** | Scoped, simple | More files | Consider |
| **Styled Components** | Co-located | Runtime overhead | Not with Solid |
| **Vanilla CSS** | No build step | Global scope issues | Not recommended |

**Recommendation: Tailwind CSS** - Rapid development, consistent styling.

### 8.6 Recommended Tech Stack

```
Framework:     SolidJS
Visualization: Custom SVG + D3 layout utilities
State:         SolidJS Stores
Build:         Vite
Styling:       Tailwind CSS
Types:         TypeScript
Testing:       Vitest + Playwright
```

### 8.7 State Management Architecture

#### 8.7.1 Store Structure

```typescript
// Main application store
interface FlameStore {
  // Connection state
  connection: {
    status: 'disconnected' | 'connecting' | 'connected' | 'error'
    serverUrl: string
    lastConnected: number | null
    error: string | null
  }

  // Flame graph data
  flame: {
    version: number
    frames: Record<string, FrameMetadata>
    activeFrameID: string | null
    rootFrameIDs: string[]
    updatedAt: number
  }

  // UI state
  ui: {
    selectedFrameID: string | null
    hoveredFrameID: string | null
    detailsPanelOpen: boolean
    searchQuery: string
    statusFilter: FrameStatus[]
    zoom: number
    pan: { x: number, y: number }
  }

  // Pending operations (optimistic updates)
  pending: {
    operations: PendingOperation[]
  }
}
```

#### 8.7.2 Actions

```typescript
// Store actions
const actions = {
  // Connection
  connect: (serverUrl: string) => void
  disconnect: () => void

  // State sync
  setFlameState: (state: FlameState) => void
  updateFrame: (frame: FrameMetadata) => void
  removeFrame: (sessionID: string) => void

  // Frame operations
  pushFrame: (goal: string, parentID?: string) => Promise<FrameMetadata>
  popFrame: (status: FrameStatus, summary?: string) => Promise<void>
  planFrame: (goal: string, parentID?: string) => Promise<FrameMetadata>
  activateFrame: (sessionID: string) => Promise<void>
  invalidateFrame: (sessionID: string, reason: string) => Promise<void>
  updateFrameGoal: (sessionID: string, goal: string) => Promise<void>
  addArtifact: (sessionID: string, artifact: string) => Promise<void>
  addDecision: (sessionID: string, decision: string) => Promise<void>

  // UI
  selectFrame: (sessionID: string | null) => void
  hoverFrame: (sessionID: string | null) => void
  toggleDetailsPanel: () => void
  setSearchQuery: (query: string) => void
  setStatusFilter: (statuses: FrameStatus[]) => void
  setZoom: (zoom: number) => void
  setPan: (pan: { x: number, y: number }) => void
}
```

#### 8.7.3 Computed Values

```typescript
// Derived state (computed)
const computed = {
  // Frame hierarchy
  frameTree: () => buildTree(store.flame.frames, store.flame.rootFrameIDs)
  ancestors: (id: string) => getAncestors(store.flame.frames, id)
  children: (id: string) => getChildren(store.flame.frames, id)
  siblings: (id: string) => getSiblings(store.flame.frames, id)

  // Filtered frames
  visibleFrames: () => filterFrames(store.flame.frames, store.ui)
  matchingFrames: () => searchFrames(store.flame.frames, store.ui.searchQuery)

  // Statistics
  frameCount: () => Object.keys(store.flame.frames).length
  activeFrame: () => store.flame.frames[store.flame.activeFrameID]
  selectedFrame: () => store.flame.frames[store.ui.selectedFrameID]
}
```

---

## 9. Integration Points

### 9.1 OpenCode SDK Integration

```typescript
import { createOpencodeClient } from "@opencode-ai/sdk/v2"

const client = createOpencodeClient({
  baseUrl: "http://localhost:4096",
})

// Subscribe to events
const events = await client.event.subscribe()
for await (const event of events.stream) {
  if (event.type.startsWith('flame.')) {
    handleFlameEvent(event)
  }
}
```

### 9.2 Plugin Communication

**Via Existing Tools:**
```typescript
// Tools are already callable via SDK
await client.session.command({
  path: { id: sessionId },
  body: {
    command: "flame_status",
    arguments: "",
  },
})
```

**Via New Endpoints:**
```typescript
// New endpoints for direct access
const state = await fetch(`${serverUrl}/flame/state`).then(r => r.json())
```

### 9.3 Session Integration

Link between flame frames and OpenCode sessions:
- Each frame corresponds to a session
- Frame ID = Session ID
- Navigate to session from frame
- Show session messages in frame details

### 9.4 Configuration Integration

Read/write Flame configuration:
```typescript
// Environment variables
FLAME_TOKEN_BUDGET_TOTAL
FLAME_AUTONOMY_LEVEL
FLAME_SUGGEST_IN_CONTEXT

// Future: UI for configuration
await client.config.get() // Get flame config
await client.config.update({ flame: { ... } })
```

---

## 10. Implementation Phases

### Phase 2.1: Foundation (Week 1-2)

**Goals:**
- Set up project structure
- Basic API endpoints
- Event integration

**Deliverables:**
- [ ] Vite + SolidJS project setup
- [ ] TypeScript types from Phase 1
- [ ] REST endpoints for flame state
- [ ] SSE event subscription
- [ ] Basic state store

**Files:**
```
phase2/
  web/
    src/
      index.tsx
      App.tsx
      api/
        client.ts
        types.ts
      store/
        flame.ts
      hooks/
        useFlameState.ts
        useFlameEvents.ts
    package.json
    vite.config.ts
    tsconfig.json
```

### Phase 2.2: Visualization Core (Week 3-4)

**Goals:**
- Render flame graph
- Basic navigation
- Status coloring

**Deliverables:**
- [ ] SVG-based flame graph renderer
- [ ] Frame component with status styling
- [ ] Pan and zoom controls
- [ ] Connection line rendering
- [ ] Responsive layout

**Components:**
```
components/
  FlameGraph/
    index.tsx
    Frame.tsx
    Connection.tsx
    Layout.ts
    useLayout.ts
    styles.css
```

### Phase 2.3: Interactions (Week 5-6)

**Goals:**
- Frame selection
- Details panel
- Tooltips

**Deliverables:**
- [ ] Click to select frame
- [ ] Hover tooltips
- [ ] Details panel component
- [ ] Keyboard navigation
- [ ] Search functionality

**Components:**
```
components/
  DetailsPanel/
    index.tsx
    FrameInfo.tsx
    Artifacts.tsx
    Decisions.tsx
    Summary.tsx
  Tooltip/
    index.tsx
  SearchBar/
    index.tsx
```

### Phase 2.4: Frame Operations (Week 7-8)

**Goals:**
- Create/complete frames
- Edit frame metadata
- Plan and activate

**Deliverables:**
- [ ] Push frame dialog
- [ ] Pop frame dialog
- [ ] Edit goal inline
- [ ] Add artifacts/decisions
- [ ] Plan children dialog
- [ ] Activate planned frame

**Components:**
```
components/
  Dialogs/
    PushFrame.tsx
    PopFrame.tsx
    PlanChildren.tsx
    EditGoal.tsx
    AddArtifact.tsx
  ContextMenu/
    index.tsx
    MenuItem.tsx
```

### Phase 2.5: Real-time & Polish (Week 9-10)

**Goals:**
- Real-time updates
- Animations
- Error handling
- Performance optimization

**Deliverables:**
- [ ] SSE reconnection logic
- [ ] State reconciliation
- [ ] Create/update/delete animations
- [ ] Error boundaries
- [ ] Loading states
- [ ] Performance profiling
- [ ] Accessibility audit

### Phase 2.6: Integration & Documentation (Week 11-12)

**Goals:**
- OpenCode integration
- Documentation
- Deployment

**Deliverables:**
- [ ] Integration with OpenCode TUI (open flame view)
- [ ] Configuration UI
- [ ] User documentation
- [ ] API documentation
- [ ] Deployment scripts
- [ ] Demo video

### 10.7 Complete Project Structure

```
flame/
  phase2/
    web/                          # Web UI application
      public/
        favicon.ico
        index.html
      src/
        index.tsx                 # Application entry point
        App.tsx                   # Root component with providers

        api/                      # API client layer
          client.ts               # HTTP client wrapper
          types.ts                # API type definitions
          flame.ts                # Flame-specific API calls
          events.ts               # SSE event subscription

        store/                    # State management
          index.ts                # Store creation and exports
          flame.ts                # Flame state slice
          ui.ts                   # UI state slice
          connection.ts           # Connection state slice
          actions.ts              # Store actions
          computed.ts             # Derived state

        components/               # UI components
          FlameGraph/
            index.tsx             # Main flame graph container
            Frame.tsx             # Individual frame component
            FrameGroup.tsx        # Group of sibling frames
            Connection.tsx        # Parent-child connection line
            Layout.ts             # Layout calculation utilities
            useLayout.ts          # Layout hook
            useZoom.ts            # Pan/zoom hook
            styles.css            # Component styles

          DetailsPanel/
            index.tsx             # Details panel container
            Header.tsx            # Panel header with close button
            FrameInfo.tsx         # Basic frame information
            Artifacts.tsx         # Artifact list and add form
            Decisions.tsx         # Decision list and add form
            Summary.tsx           # Compaction summary display
            Actions.tsx           # Action buttons

          Dialogs/
            PushFrame.tsx         # Create new frame dialog
            PopFrame.tsx          # Complete frame dialog
            PlanChildren.tsx      # Plan multiple children dialog
            EditGoal.tsx          # Edit goal inline/dialog
            AddArtifact.tsx       # Add artifact dialog
            AddDecision.tsx       # Add decision dialog
            Confirm.tsx           # Generic confirmation dialog

          Toolbar/
            index.tsx             # Main toolbar
            SearchBar.tsx         # Search input
            FilterDropdown.tsx    # Status filter dropdown
            ZoomControls.tsx      # Zoom in/out/reset
            ConnectionStatus.tsx  # Server connection indicator

          Sidebar/
            index.tsx             # Sidebar container
            Minimap.tsx           # Minimap component
            FrameTree.tsx         # Text-based tree view
            Stats.tsx             # Statistics display

          ContextMenu/
            index.tsx             # Context menu container
            MenuItem.tsx          # Menu item component
            useContextMenu.ts     # Context menu hook

          Tooltip/
            index.tsx             # Tooltip component
            useTooltip.ts         # Tooltip hook

          common/
            Button.tsx            # Styled button
            Input.tsx             # Styled input
            Select.tsx            # Styled select
            Dialog.tsx            # Base dialog component
            Icon.tsx              # Icon wrapper
            Spinner.tsx           # Loading spinner
            Badge.tsx             # Status badge

        hooks/                    # Custom hooks
          useFlameState.ts        # Access flame store
          useFlameEvents.ts       # Subscribe to events
          useFrame.ts             # Single frame operations
          useKeyboard.ts          # Keyboard shortcuts
          useAnimation.ts         # Animation utilities

        utils/                    # Utility functions
          tree.ts                 # Tree manipulation
          layout.ts               # Layout algorithms
          format.ts               # Formatting helpers
          debounce.ts             # Debounce/throttle

        constants/                # Constants
          colors.ts               # Status color mapping
          keybindings.ts          # Keyboard shortcuts
          config.ts               # Configuration defaults

        types/                    # TypeScript types
          flame.ts                # Flame graph types
          api.ts                  # API types
          ui.ts                   # UI types

      tests/                      # Test files
        unit/                     # Unit tests
          components/
          hooks/
          utils/
        integration/              # Integration tests
          api/
        e2e/                      # E2E tests (Playwright)
          flame-graph.spec.ts
          frame-operations.spec.ts

      package.json
      vite.config.ts
      tsconfig.json
      tailwind.config.js
      postcss.config.js
      playwright.config.ts
      vitest.config.ts

    server/                       # Server-side extensions
      routes/                     # New API routes
        flame.ts                  # /flame/* endpoints
      events/                     # Event definitions
        flame-events.ts           # Flame-specific events

    docs/                         # Documentation
      getting-started.md
      api-reference.md
      user-guide.md
      development.md

    scripts/                      # Build/deploy scripts
      build.sh
      deploy.sh

    consensus/                    # Planning documents
      proposal-A.md               # This document
```

---

## 11. Testing Strategy

### 11.1 Unit Tests

```typescript
// Example: Frame component test
import { render, screen } from '@solidjs/testing-library'
import { Frame } from './Frame'

describe('Frame', () => {
  it('renders goal text', () => {
    render(() => <Frame goal="Build auth" status="in_progress" />)
    expect(screen.getByText('Build auth')).toBeInTheDocument()
  })

  it('applies correct status color', () => {
    render(() => <Frame goal="Test" status="completed" />)
    expect(screen.getByRole('button')).toHaveClass('bg-green-500')
  })
})
```

### 11.2 Integration Tests

```typescript
// Example: API integration test
describe('Flame API', () => {
  it('fetches state from server', async () => {
    const state = await flameApi.getState()
    expect(state.version).toBe(1)
    expect(state.frames).toBeDefined()
  })

  it('creates frame via push', async () => {
    const result = await flameApi.push({ goal: 'Test frame' })
    expect(result.frame.status).toBe('in_progress')
  })
})
```

### 11.3 E2E Tests

```typescript
// Example: Playwright E2E test
import { test, expect } from '@playwright/test'

test('flame graph visualization', async ({ page }) => {
  await page.goto('/flame')

  // Wait for graph to load
  await page.waitForSelector('[data-testid="flame-graph"]')

  // Click on a frame
  await page.click('[data-testid="frame-ses_xxx"]')

  // Verify details panel opens
  await expect(page.locator('[data-testid="details-panel"]')).toBeVisible()

  // Verify frame info is displayed
  await expect(page.locator('.frame-goal')).toHaveText('Build auth')
})
```

### 11.4 Visual Regression Tests

Use Playwright's screenshot comparison for layout stability:

```typescript
test('flame graph layout snapshot', async ({ page }) => {
  await page.goto('/flame')
  await page.waitForSelector('[data-testid="flame-graph"]')

  await expect(page).toHaveScreenshot('flame-graph.png', {
    maxDiffPixelRatio: 0.01,
  })
})
```

---

## 12. Future Considerations

### 12.1 Advanced Features (Phase 3+)

- **Time travel**: Replay frame history
- **Collaboration**: Multi-user viewing
- **Export**: PNG/SVG export of flame graph
- **Import**: Load external flame graph data
- **Analytics**: Token usage per frame, duration stats
- **Templates**: Save/load frame tree templates

### 12.2 Performance Optimizations

- **Virtual rendering**: Only render visible frames
- **WebGL**: GPU-accelerated rendering for large graphs
- **Web Workers**: Offload layout calculations
- **IndexedDB**: Local caching of state

### 12.3 Integration Opportunities

- **VS Code Extension**: Show flame graph in IDE
- **Browser Extension**: Quick access from anywhere
- **CLI Visualization**: ASCII flame graph in terminal
- **API for Third Parties**: Allow external tools to consume flame data

### 12.4 Alternative Visualizations

- **Sunburst Chart**: Radial representation
- **Treemap**: Area-based representation
- **Timeline**: Time-based view
- **Network Graph**: Force-directed layout

---

## Appendix A: Type Definitions

```typescript
// Core types from Phase 1 plugin

type FrameStatus =
  | "planned"
  | "in_progress"
  | "completed"
  | "failed"
  | "blocked"
  | "invalidated"

interface FrameMetadata {
  sessionID: string
  parentSessionID?: string
  status: FrameStatus
  goal: string
  createdAt: number
  updatedAt: number
  artifacts: string[]
  decisions: string[]
  compactionSummary?: string
  logPath?: string
  invalidationReason?: string
  invalidatedAt?: number
  plannedChildren?: string[]
}

interface FlameState {
  version: number
  frames: Record<string, FrameMetadata>
  activeFrameID?: string
  rootFrameIDs: string[]
  updatedAt: number
}
```

## Appendix B: API Response Examples

```typescript
// GET /flame/state response
{
  "version": 1,
  "frames": {
    "ses_root": {
      "sessionID": "ses_root",
      "status": "in_progress",
      "goal": "Build the application",
      "createdAt": 1705312800000,
      "updatedAt": 1705316400000,
      "artifacts": [],
      "decisions": ["Use TypeScript", "Use SolidJS"],
      "plannedChildren": ["plan_auth", "plan_api"]
    },
    "ses_auth": {
      "sessionID": "ses_auth",
      "parentSessionID": "ses_root",
      "status": "completed",
      "goal": "Implement authentication",
      "createdAt": 1705313100000,
      "updatedAt": 1705314000000,
      "artifacts": ["src/auth/*"],
      "decisions": ["Use JWT"],
      "compactionSummary": "Implemented JWT auth with refresh tokens..."
    }
  },
  "activeFrameID": "ses_root",
  "rootFrameIDs": ["ses_root"],
  "updatedAt": 1705316400000
}
```

## Appendix C: Event Payload Examples

```typescript
// flame.frame.created event
{
  "type": "flame.frame.created",
  "properties": {
    "frame": {
      "sessionID": "ses_new",
      "parentSessionID": "ses_root",
      "status": "in_progress",
      "goal": "Add user registration",
      // ... other fields
    },
    "parentID": "ses_root"
  }
}

// flame.frame.completed event
{
  "type": "flame.frame.completed",
  "properties": {
    "frame": {
      "sessionID": "ses_auth",
      "status": "completed",
      "compactionSummary": "Successfully implemented...",
      // ... other fields
    },
    "status": "completed"
  }
}
```

---

## Appendix D: Phase 1 Plugin Tool Reference

The Phase 1 plugin provides 28 tools that the Web UI can leverage:

### Frame Lifecycle Tools
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_push` | Create new child frame | `goal: string` |
| `flame_pop` | Complete current frame | `status, summary?, generateSummary?` |
| `flame_status` | Show frame tree | - |
| `flame_set_goal` | Update frame goal | `goal: string` |
| `flame_add_artifact` | Record artifact | `artifact: string` |
| `flame_add_decision` | Record decision | `decision: string` |

### Planning Tools (Phase 1.6)
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_plan` | Create planned frame | `goal, parentSessionID?` |
| `flame_plan_children` | Create multiple plans | `parentSessionID?, children[]` |
| `flame_activate` | Start planned frame | `sessionID` |
| `flame_invalidate` | Invalidate frame | `sessionID?, reason` |
| `flame_tree` | Visual tree display | `showFull?, rootID?, showDetails?` |

### Context Tools (Phase 1.2)
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_context_info` | Show token usage | - |
| `flame_context_preview` | Preview XML context | `maxLength?` |
| `flame_cache_clear` | Clear context cache | `sessionID?` |

### Compaction Tools (Phase 1.3)
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_summarize` | Manual summary trigger | `note?` |
| `flame_compaction_info` | Show compaction state | - |
| `flame_get_summary` | Get frame summary | `sessionID?` |

### Subagent Tools (Phase 1.5)
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_subagent_config` | Configure subagent detection | various config options |
| `flame_subagent_stats` | Show subagent statistics | `reset?, showActive?` |
| `flame_subagent_complete` | Complete subagent session | `sessionID?, status?, summary?` |
| `flame_subagent_list` | List tracked sessions | `filter?` |

### Autonomy Tools (Phase 1.7)
| Tool | Description | Parameters |
|------|-------------|------------|
| `flame_autonomy_config` | Configure autonomy | `level?, pushThreshold?, popThreshold?, ...` |
| `flame_should_push` | Evaluate push heuristics | context parameters |
| `flame_should_pop` | Evaluate pop heuristics | context parameters |
| `flame_auto_suggest` | Toggle/view suggestions | `enable?, clearPending?, showHistory?` |
| `flame_autonomy_stats` | View autonomy statistics | `reset?` |

---

## Appendix E: OpenCode Integration Points

### E.1 Existing Server Endpoints Available

From the OpenCode server, Phase 2 can leverage:

```
GET  /event              - SSE stream (real-time events)
GET  /session            - List sessions
POST /session            - Create session
GET  /session/:id        - Get session details
POST /session/:id/message - Send message (execute tool)
POST /session/:id/command - Execute slash command
GET  /config             - Get configuration
```

### E.2 Existing Events to Monitor

The plugin already emits events via OpenCode's bus:
- `session.created` - New session/frame created
- `session.updated` - Session state changed
- `session.compacted` - Compaction triggered
- `session.idle` - Session became idle
- `session.deleted` - Session removed

### E.3 Plugin Hook Points

The Phase 1 plugin uses these hooks:
- `event` - Subscribe to session lifecycle events
- `chat.message` - Track current session ID
- `experimental.chat.messages.transform` - Inject frame context
- `experimental.session.compacting` - Custom compaction prompts

---

## Appendix F: Risk Assessment and Mitigation

### F.1 Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Large graph performance | High | Medium | Virtual rendering, WebGL fallback |
| Real-time sync issues | Medium | Medium | Optimistic updates with reconciliation |
| Browser compatibility | Low | Low | Target modern browsers only |
| State corruption | High | Low | Versioned state, backup on operations |

### F.2 Integration Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| OpenCode API changes | High | Low | Version-lock SDK, integration tests |
| Plugin compatibility | Medium | Low | Feature detection, graceful degradation |
| CORS issues | Medium | Medium | Proper server configuration |

### F.3 UX Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Cognitive overload | Medium | Medium | Progressive disclosure, defaults |
| Learning curve | Medium | High | Tutorials, tooltips, documentation |
| Mobile usability | Low | High | Responsive design, simplified mobile view |

---

## Appendix G: Success Metrics

### G.1 Technical Metrics

- **Initial load time**: < 2 seconds
- **Real-time update latency**: < 100ms
- **Frame rendering**: 60fps smooth animations
- **Maximum supported frames**: 1000+ frames
- **Memory usage**: < 100MB for large graphs

### G.2 User Experience Metrics

- **Time to first visualization**: < 5 seconds from page load
- **Frame operation success rate**: > 99%
- **User task completion**: Basic operations in < 3 clicks
- **Error recovery**: Graceful with user guidance

### G.3 Adoption Metrics

- **Documentation completeness**: 100% API coverage
- **Test coverage**: > 80% for core components
- **Browser support**: Chrome, Firefox, Safari, Edge (latest 2 versions)

---

## Appendix H: Glossary

| Term | Definition |
|------|------------|
| **Frame** | A unit of work representing a subtask in the flame graph hierarchy |
| **Root Frame** | A top-level frame with no parent |
| **Active Frame** | The currently focused frame receiving context injection |
| **Compaction** | Process of summarizing frame history for context efficiency |
| **Push** | Create a new child frame under the current active frame |
| **Pop** | Complete the current frame and return to parent |
| **Planned Frame** | A frame created for future work, not yet started |
| **Invalidation** | Marking a frame and its planned children as no longer relevant |
| **Sibling** | Frames sharing the same parent |
| **Ancestor** | Parent, grandparent, etc. in the frame hierarchy |
| **Autonomy** | System for automatically suggesting push/pop operations |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-12-24 | Phase 2 Planning | Initial comprehensive plan |
| 1.1 | 2024-12-24 | Phase 2 Planning | Added appendices D-H: tool reference, integration points, risks, metrics, glossary |

---

*This document serves as the implementation blueprint for Phase 2 of the Flame Graph Context Management project. It should be updated as implementation progresses and new requirements emerge.*
