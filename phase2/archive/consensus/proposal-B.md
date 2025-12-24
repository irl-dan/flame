# Phase 2: Flame Graph Web UI Implementation Plan

> **Reference Documents:**
> - Theoretical Specification: `/Users/sl/code/flame/SPEC.md`
> - Phase 1 Implementation: `/Users/sl/code/flame/.opencode/plugin/flame.ts` (5,045 lines)
> - OpenCode App: `/Users/sl/code/opencode/packages/app/`
> - OpenCode Plugin SDK: `/Users/sl/code/opencode/packages/plugin/`

## Executive Summary

Phase 2 transforms the Flame Graph Context Management system from a CLI-only tool into a visual, interactive experience. The web UI will render the frame call stack as an actual flame graph visualization, providing intuitive controls for frame navigation, creation, and management.

The Flame Graph paradigm (as defined in SPEC.md) organizes agent context as a **tree of frames** rather than a linear chat log, solving context window pressure, misaligned mental models, and irrelevant context pollution. Phase 1 implemented the core frame management logic; Phase 2 makes it visually accessible and directly controllable.

---

## 1. Architecture Overview

### 1.1 High-Level System Architecture

```
+------------------+     +------------------+     +------------------+
|                  |     |                  |     |                  |
|   Flame Web UI   |<--->|   OpenCode API   |<--->|   Flame Plugin   |
|   (SolidJS)      |     |   (Hono Server)  |     |   (flame.ts)     |
|                  |     |                  |     |                  |
+------------------+     +------------------+     +------------------+
        |                        |                        |
        v                        v                        v
   [Browser]              [REST + SSE]            [state.json]
                                                  [frames/*.json]
```

### 1.2 Integration Strategy

The Phase 2 UI integrates with OpenCode at three levels:

1. **Plugin Layer**: The existing Flame plugin (`flame.ts`) manages all frame state and exposes 28 tools
2. **API Layer**: New REST endpoints expose frame state to the web client
3. **UI Layer**: A new SolidJS component renders the flame graph within the OpenCode app

### 1.3 Deployment Options

**Option A: Integrated Panel (Recommended)**
- Add a "Flame Graph" panel within the existing OpenCode web UI
- Toggle visibility via keyboard shortcut or command palette
- Shares the existing SDK context and sync infrastructure

**Option B: Standalone Application**
- Separate web application that connects to OpenCode's API
- Can run independently or be embedded as an iframe
- More complex to maintain but offers flexibility

---

## 2. Data Flow

### 2.1 Frame State Storage

The Flame plugin persists state in two locations:

```
.opencode/flame/
  state.json           # Global state: active frame, root frames, frame registry
  frames/
    ses_xxx.json       # Individual frame metadata per session
```

**state.json Structure:**
```json
{
  "version": 1,
  "frames": {
    "ses_abc123": {
      "sessionID": "ses_abc123",
      "parentSessionID": "ses_parent",
      "status": "in_progress",
      "goal": "Implement feature X",
      "createdAt": 1700000000000,
      "updatedAt": 1700000100000,
      "artifacts": ["src/feature.ts"],
      "decisions": ["Used factory pattern"],
      "compactionSummary": "...",
      "plannedChildren": ["ses_child1", "ses_child2"]
    }
  },
  "activeFrameID": "ses_abc123",
  "rootFrameIDs": ["ses_root1"],
  "updatedAt": 1700000100000
}
```

### 2.2 Data Flow Sequence

```
[User Action in UI]
        |
        v
[SDK Client Request] ---> [OpenCode Server] ---> [Flame Plugin Tool]
        |                        |                        |
        |                        v                        v
        |                 [Bus Event]            [State Mutation]
        |                        |                        |
        v                        v                        v
[SSE Event Stream] <--- [GlobalBus.emit] <--- [File Persistence]
        |
        v
[Reactive Store Update]
        |
        v
[UI Re-render]
```

### 2.3 Event Types to Subscribe

The UI should listen for these OpenCode events:
- `session.created` - New session/frame created
- `session.updated` - Session metadata changed
- `session.deleted` - Session removed

And these Flame-specific events (to be added):
- `flame.frame.created` - New frame pushed
- `flame.frame.updated` - Frame status/goal changed
- `flame.frame.completed` - Frame popped
- `flame.frame.activated` - Active frame changed
- `flame.tree.changed` - Tree structure modified

---

## 3. Flame Graph Visualization

### 3.1 Visualization Approach

A flame graph traditionally shows stack traces with:
- X-axis: Alphabetical or call order
- Y-axis: Stack depth (root at bottom, leaves at top)
- Width: Relative time/importance

For Flame Graph Context Management:
- **X-axis**: Child frames ordered by creation time
- **Y-axis**: Frame depth (root at bottom)
- **Width**: Proportional to number of descendants OR token usage
- **Color**: Status-based (green=completed, blue=in_progress, orange=planned, red=failed)

### 3.2 Interactive Features

```
+------------------------------------------------------------------+
|                    [Root Frame: "Build App"]                      |
|                         ████████████████                          |
+------------------------------------------------------------------+
|    [Auth]          |           [API Routes]          | [Tests]   |
|    ████ (done)     |           ██████████            | ▓▓▓▓      |
+------------------------------------------------------------------+
|  [A1] [A2]         |     [B1]        [B2]   [B3]     |           |
|  ██   ██           |     ████        ▓▓▓▓  ░░░░     |           |
+------------------------------------------------------------------+

Legend: ████ completed  ▓▓▓▓ in_progress  ░░░░ planned  ▒▒▒▒ failed
```

**Interactions:**
1. **Hover**: Show frame details (goal, status, duration, token count)
2. **Click**: Select frame, show details panel
3. **Double-click**: Navigate to frame's session
4. **Right-click**: Context menu (push child, pop, invalidate, set goal)
5. **Drag**: Reorder planned siblings (future)

### 3.3 Technology Choice: D3.js + SolidJS

**Rationale:**
- D3.js provides battle-tested flame graph implementations
- SolidJS reactive primitives integrate well with D3's data joins
- Existing OpenCode UI uses SolidJS, ensuring consistency

**Libraries to evaluate:**
1. `d3-flame-graph` - Purpose-built flame graph library
2. Custom D3 implementation with `d3-hierarchy`
3. `flame-chart-js` - Simpler alternative

**Recommended: Custom D3 implementation** because:
- Our data model differs from traditional flame graphs
- Need tight integration with SolidJS reactivity
- Want custom interactions for frame management

---

## 4. User Interactions

### 4.1 Frame Operations

| Action | Trigger | Implementation |
|--------|---------|----------------|
| Push Frame | Click "+" or keyboard shortcut | Call `flame_push` tool |
| Pop Frame | Click "Complete" button | Call `flame_pop` tool |
| Set Goal | Edit field or tool | Call `flame_set_goal` tool |
| Add Artifact | Tool or drop file | Call `flame_add_artifact` tool |
| Record Decision | Tool or button | Call `flame_add_decision` tool |
| Invalidate | Right-click menu | Call `flame_invalidate` tool |
| Plan Children | Multi-select dialog | Call `flame_plan_children` tool |
| Activate Frame | Double-click planned | Call `flame_activate` tool |

### 4.2 Navigation

| Action | Trigger |
|--------|---------|
| Navigate to frame's session | Double-click frame |
| Show frame details | Single-click frame |
| Expand/collapse subtree | Click +/- icon |
| Zoom to frame | Ctrl+click |
| Reset zoom | Home key or button |

### 4.3 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+F` | Toggle Flame Graph panel |
| `Cmd+Enter` | Push new frame |
| `Cmd+Backspace` | Pop current frame |
| `Arrow keys` | Navigate between frames |
| `Space` | Toggle frame details |
| `Enter` | Activate selected planned frame |

---

## 5. Real-time Updates

### 5.1 Event Subscription Strategy

```typescript
// In FlameGraphProvider context
const sdk = useSDK()

sdk.event.on("session.updated", (event) => {
  // Check if this session is a tracked frame
  refreshFrameState(event.properties.info.id)
})

// Custom flame events (plugin must emit these)
sdk.event.on("flame.frame.created", (event) => {
  addFrameToTree(event.properties.frame)
})

sdk.event.on("flame.frame.completed", (event) => {
  updateFrameStatus(event.properties.frame)
})
```

### 5.2 Plugin Event Emission (Required Addition)

The Flame plugin must be extended to emit events:

```typescript
// In flame.ts, after state mutations:
Bus.publish("flame.frame.created", {
  frame: frameMetadata,
  parentID: parentSessionID,
})

Bus.publish("flame.frame.completed", {
  frame: frameMetadata,
  status: "completed",
})
```

### 5.3 Optimistic Updates

For responsive UX, apply optimistic updates:

```typescript
async function pushFrame(goal: string) {
  // 1. Optimistic UI update
  const tempID = `temp_${Date.now()}`
  addOptimisticFrame(tempID, goal)

  // 2. Call API
  const result = await sdk.client.tool.call({
    tool: "flame_push",
    args: { goal }
  })

  // 3. Reconcile with actual data
  removeOptimisticFrame(tempID)
  // Real frame added via SSE event
}
```

---

## 6. Technology Choices

### 6.1 Core Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| UI Framework | SolidJS | Consistency with OpenCode |
| Visualization | D3.js v7 | Mature, flexible, documented |
| State Management | SolidJS Stores | Built-in reactivity |
| Styling | Tailwind CSS | Consistency with OpenCode |
| Icons | Existing icon system | Design consistency |

### 6.2 New Dependencies

```json
{
  "dependencies": {
    "d3": "^7.8.5",
    "@types/d3": "^7.4.3"
  }
}
```

### 6.3 Component Library

Leverage existing OpenCode UI components:
- `Tabs` - For panel navigation
- `Tooltip` - Frame hover details
- `Dialog` - Frame creation/editing dialogs
- `IconButton` - Action buttons
- `ResizeHandle` - Panel resizing
- `DropdownMenu` - Context menus

---

## 7. Implementation Phases

### Phase 2.1: Foundation (Week 1-2)

**Goals:**
- Create FlameGraph context and provider
- Implement frame state fetching and caching
- Build basic tree visualization (no flame graph yet)

**Deliverables:**
- `FlameProvider.tsx` - Context for flame state
- `FlamePanel.tsx` - Container component
- `FrameTree.tsx` - Basic tree list view
- API integration for reading flame state

### Phase 2.2: Visualization (Week 3-4)

**Goals:**
- Implement D3 flame graph rendering
- Add hover tooltips and basic interactions
- Integrate with OpenCode layout system

**Deliverables:**
- `FlameGraph.tsx` - D3-based visualization
- `FrameTooltip.tsx` - Hover details component
- Layout integration (toggle panel, resize)

### Phase 2.3: Interactions (Week 5-6)

**Goals:**
- Implement all frame operations via UI
- Add keyboard shortcuts
- Create frame creation/editing dialogs

**Deliverables:**
- `FrameDialog.tsx` - Create/edit frame dialog
- `FrameContextMenu.tsx` - Right-click menu
- Keyboard shortcut integration
- Tool execution via SDK

### Phase 2.4: Real-time & Polish (Week 7-8)

**Goals:**
- Implement event subscriptions for live updates
- Add optimistic updates for responsiveness
- Polish animations and transitions
- Comprehensive testing

**Deliverables:**
- Event subscription system
- Animation system for state changes
- Edge case handling
- Performance optimization

---

## 8. API Design

### 8.1 New Endpoints (Alternative to Tool Calls)

If we want dedicated REST endpoints instead of tool calls:

```
GET  /flame/state                    # Get full frame tree
GET  /flame/frame/:sessionID         # Get single frame
POST /flame/frame                    # Create frame (push)
PUT  /flame/frame/:sessionID         # Update frame
DEL  /flame/frame/:sessionID         # Complete frame (pop)
POST /flame/frame/:sessionID/plan    # Plan child frames
POST /flame/frame/:sessionID/activate # Activate planned frame
POST /flame/frame/:sessionID/invalidate # Invalidate frame
```

### 8.2 Using Existing Tool System (Recommended)

Better approach: Use the existing tool execution API:

```typescript
// SDK provides tool execution
await sdk.client.tool.call({
  sessionID: currentSessionID,
  tool: "flame_push",
  args: { goal: "New subtask" }
})
```

This leverages:
- Existing permission system
- Tool validation
- Event emission
- No additional server code

### 8.3 State Endpoint (Required Addition)

One new endpoint is needed to fetch frame state:

```typescript
// In server.ts
.get(
  "/flame/state",
  describeRoute({
    summary: "Get flame graph state",
    operationId: "flame.state",
    responses: {
      200: {
        content: {
          "application/json": {
            schema: FlameStateSchema
          }
        }
      }
    }
  }),
  async (c) => {
    const state = await loadFlameState(Instance.directory)
    return c.json(state)
  }
)
```

---

## 9. Integration Points

### 9.1 Plugin Modifications Required

The existing Flame plugin needs these additions:

1. **Event Emission**: Publish bus events on state changes
2. **State Export**: Expose method to get full state
3. **Validation**: Add input validation for UI-originated calls

```typescript
// Example event emission addition to flame.ts
async createFrame(sessionID, goal, parentSessionID) {
  // ... existing logic ...

  // NEW: Emit event for UI
  Bus.publish(BusEvent.define("flame.frame.created", z.object({
    frame: FrameMetadataSchema,
    parentID: z.string().optional()
  })), { frame, parentID: parentSessionID })

  return frame
}
```

### 9.2 OpenCode App Integration

Integration into the main OpenCode app:

```tsx
// In app.tsx or layout component
<Show when={layout.flamePanel.opened()}>
  <FlameProvider>
    <FlamePanel />
  </FlameProvider>
</Show>
```

Command registration:
```typescript
command.register(() => [
  {
    id: "flame.toggle",
    title: "Toggle Flame Graph",
    keybind: "mod+shift+f",
    slash: "flame",
    onSelect: () => layout.flamePanel.toggle()
  }
])
```

### 9.3 Session Integration

The flame graph should highlight the current session's frame:

```typescript
const currentFrame = createMemo(() => {
  const sessionID = params.id
  if (!sessionID) return null
  return flameState.frames[sessionID]
})
```

---

## 10. Component Specifications

### 10.1 FlameProvider

```typescript
interface FlameContextValue {
  // State
  state: Accessor<FlameState>
  activeFrame: Accessor<FrameMetadata | null>
  selectedFrame: Accessor<FrameMetadata | null>

  // Actions
  pushFrame: (goal: string) => Promise<void>
  popFrame: (status: FrameStatus, summary?: string) => Promise<void>
  setGoal: (goal: string) => Promise<void>
  selectFrame: (sessionID: string) => void
  navigateToFrame: (sessionID: string) => void

  // Computed
  treeData: Accessor<D3HierarchyNode>
  flatFrames: Accessor<FrameMetadata[]>
}
```

### 10.2 FlameGraph Component

```typescript
interface FlameGraphProps {
  width?: number
  height?: number
  onFrameClick?: (frame: FrameMetadata) => void
  onFrameDoubleClick?: (frame: FrameMetadata) => void
  onFrameRightClick?: (frame: FrameMetadata, event: MouseEvent) => void
  highlightedFrameID?: string
}
```

### 10.3 FrameDetailsPanel

```typescript
interface FrameDetailsPanelProps {
  frame: FrameMetadata
  onClose: () => void
  onEdit: (updates: Partial<FrameMetadata>) => void
  onPushChild: () => void
  onPop: (status: FrameStatus) => void
}
```

---

## 11. Error Handling

### 11.1 Error States

| Error | Display | Recovery |
|-------|---------|----------|
| No frame state | "No flame graph data" message | Initialize with root frame |
| Frame load failed | Toast notification | Retry button |
| Action failed | Inline error message | Show details, allow retry |
| Sync lost | "Reconnecting..." banner | Auto-reconnect |

### 11.2 Validation

Client-side validation before tool calls:
- Goal must not be empty
- Status must be valid enum value
- Parent frame must exist for push
- Cannot pop root frame

---

## 12. Testing Strategy

### 12.1 Unit Tests

- FlameProvider state management
- Tree computation utilities
- D3 data transformation functions

### 12.2 Integration Tests

- Tool execution round-trips
- Event subscription and handling
- Optimistic update reconciliation

### 12.3 E2E Tests

- Push/pop frame workflow
- Navigation between frames and sessions
- Keyboard shortcut functionality

---

## 13. Performance Considerations

### 13.1 Large Trees

For projects with 100+ frames:
- Implement virtual scrolling for tree list view
- Use D3 enter/update/exit for efficient DOM updates
- Debounce rapid state changes
- Consider lazy loading deep subtrees

### 13.2 Memoization

```typescript
// Memoize expensive computations
const treeData = createMemo(() =>
  computeHierarchy(flameState.frames, flameState.rootFrameIDs)
)

const flatFrames = createMemo(() =>
  Object.values(flameState.frames).sort((a, b) => b.updatedAt - a.updatedAt)
)
```

### 13.3 Event Batching

```typescript
// Batch rapid updates
const pendingUpdates = new Set<string>()
let updateTimer: number | null = null

function scheduleUpdate(frameID: string) {
  pendingUpdates.add(frameID)
  if (!updateTimer) {
    updateTimer = requestAnimationFrame(() => {
      processBatchedUpdates(Array.from(pendingUpdates))
      pendingUpdates.clear()
      updateTimer = null
    })
  }
}
```

---

## 14. Future Enhancements (Phase 3+)

### 14.1 Advanced Visualizations
- Timeline view showing frame duration
- Token usage heatmap
- Dependency graph between frames

### 14.2 Collaboration Features
- Share frame tree snapshots
- Annotate frames with notes
- Export/import frame structures

### 14.3 Analytics
- Frame completion rates
- Average frame duration
- Most common frame patterns

### 14.4 AI Integration
- Suggested frame decomposition
- Automatic goal refinement
- Anomaly detection (stuck frames, unusual patterns)

---

## 15. Open Questions

1. **Panel vs. Overlay**: Should the flame graph be a resizable panel (like terminal) or a modal overlay?

2. **Default Visibility**: Should the flame graph auto-show when frames exist, or always require manual toggle?

3. **Mobile Support**: How should the visualization adapt for mobile/narrow viewports?

4. **State Persistence**: Should UI preferences (zoom level, expanded nodes) persist across sessions?

5. **Multi-Project**: How to handle flame state when switching between projects in the same OpenCode instance?

---

## 16. Success Metrics

Phase 2 is successful when:

1. Users can visualize their entire frame tree at a glance
2. All 28 flame tools are accessible via UI (no CLI required for common operations)
3. Frame state updates in real-time (< 100ms latency)
4. The visualization is intuitive to first-time users
5. Performance remains smooth with 100+ frames

---

## Appendix A: Wire Mockups

### A.1 Flame Panel in OpenCode

```
+--------------------------------------------------------------+
| OpenCode                                    [Model] [Agent]   |
+--------------------------------------------------------------+
|                                                               |
| Session Messages                    | Flame Graph     | Review|
|                                     |                 |       |
| [User]: Fix the auth bug            | [Root: Build]   | Diffs |
|                                     |   ████████████  |       |
| [Assistant]: I'll start by...       |   |  |  |      |       |
|                                     | [A][B][C]       |       |
|                                     | ██ ██ ░░        |       |
|                                     |                 |       |
+--------------------------------------------------------------+
| [Prompt Input]                                                |
+--------------------------------------------------------------+
```

### A.2 Frame Details Panel

```
+----------------------------------+
| Frame: "Implement authentication" |
+----------------------------------+
| Status: [in_progress ▼]          |
| Goal: [Edit goal text...      ]  |
|                                  |
| Artifacts:                       |
|   - src/auth/login.ts            |
|   - src/auth/middleware.ts       |
|   + Add artifact                 |
|                                  |
| Decisions:                       |
|   - Using JWT for tokens         |
|   - 15-minute expiry             |
|   + Add decision                 |
|                                  |
| Duration: 23 minutes             |
| Tokens: ~12,500 input            |
|                                  |
| [Push Child] [Complete] [Cancel] |
+----------------------------------+
```

---

## Appendix B: D3 Flame Graph Implementation Sketch

```typescript
function renderFlameGraph(
  container: HTMLElement,
  data: FrameHierarchy,
  options: FlameGraphOptions
) {
  const { width, height, colorScale } = options

  const root = d3.hierarchy(data)
    .sum(d => d.children?.length || 1)
    .sort((a, b) => b.value! - a.value!)

  const partition = d3.partition<FrameNode>()
    .size([width, height])
    .padding(1)

  partition(root)

  const svg = d3.select(container)
    .append("svg")
    .attr("viewBox", [0, 0, width, height])

  const cell = svg.selectAll("g")
    .data(root.descendants())
    .join("g")
    .attr("transform", d => `translate(${d.x0},${d.y0})`)

  cell.append("rect")
    .attr("width", d => d.x1 - d.x0)
    .attr("height", d => d.y1 - d.y0)
    .attr("fill", d => colorScale(d.data.status))
    .on("click", (event, d) => options.onFrameClick?.(d.data))

  cell.append("text")
    .attr("x", 4)
    .attr("y", 13)
    .text(d => truncate(d.data.goal, (d.x1 - d.x0) / 8))
}
```

---

## Appendix C: Complete Tool Mapping

### C.1 All 28 Flame Tools

The Phase 1 plugin exposes these tools that the UI must support:

| Tool | Purpose | UI Element |
|------|---------|------------|
| `flame_push` | Create child frame | "New Frame" button, context menu |
| `flame_pop` | Complete current frame | "Complete" button with status dropdown |
| `flame_status` | Show frame tree | Main visualization |
| `flame_set_goal` | Update frame goal | Inline edit field |
| `flame_add_artifact` | Record artifact | Artifact list + add button |
| `flame_add_decision` | Record decision | Decision list + add button |
| `flame_context_info` | Show context metadata | Info panel tab |
| `flame_context_preview` | Preview context XML | Debug panel |
| `flame_cache_clear` | Clear context cache | Settings menu |
| `flame_summarize` | Generate summary | "Summarize" action |
| `flame_compaction_info` | Show compaction state | Info panel tab |
| `flame_get_summary` | Get frame summary | Details panel |
| `flame_subagent_config` | Configure subagent detection | Settings dialog |
| `flame_subagent_stats` | Show subagent statistics | Stats panel |
| `flame_subagent_complete` | Complete subagent session | Context menu |
| `flame_subagent_list` | List subagent sessions | Subagent panel |
| `flame_plan` | Create planned frame | "Plan Frame" button |
| `flame_plan_children` | Plan multiple children | Batch planning dialog |
| `flame_activate` | Activate planned frame | Double-click or "Start" button |
| `flame_invalidate` | Invalidate frame tree | Context menu |
| `flame_tree` | ASCII tree view | Alternative view option |
| `flame_autonomy_config` | Configure autonomy | Settings dialog |
| `flame_should_push` | Evaluate push heuristics | Suggestion indicator |
| `flame_should_pop` | Evaluate pop heuristics | Suggestion indicator |
| `flame_auto_suggest` | Toggle auto-suggestions | Settings toggle |
| `flame_autonomy_stats` | Show autonomy stats | Stats panel |

### C.2 Tool Execution Pattern

```typescript
// Unified tool execution helper
async function executeFlameAction<T>(
  tool: string,
  args: Record<string, unknown>
): Promise<T> {
  const sdk = useSDK()

  try {
    // Execute via SDK tool endpoint
    const response = await sdk.client.post('/experimental/tool/execute', {
      body: {
        tool,
        args,
        sessionID: runtime.currentSessionID
      }
    })

    if (!response.ok) {
      throw new Error(`Tool execution failed: ${response.status}`)
    }

    return response.data as T
  } catch (error) {
    console.error(`Flame action ${tool} failed:`, error)
    throw error
  }
}

// Usage in components
const handlePushFrame = async (goal: string) => {
  await executeFlameAction('flame_push', { goal })
}

const handlePopFrame = async (status: FrameStatus, summary?: string) => {
  await executeFlameAction('flame_pop', { status, summary })
}
```

---

## Appendix D: Detailed Component Implementations

### D.1 FlameProvider Implementation

```typescript
// packages/app/src/context/flame.tsx

import { createContext, useContext, createMemo, onMount, onCleanup } from "solid-js"
import { createStore, produce } from "solid-js/store"
import { useSDK } from "./sdk"
import { useNavigate, useParams } from "@solidjs/router"

// Types from flame.ts
interface FrameMetadata {
  sessionID: string
  parentSessionID?: string
  status: "planned" | "in_progress" | "completed" | "failed" | "blocked" | "invalidated"
  goal: string
  createdAt: number
  updatedAt: number
  artifacts: string[]
  decisions: string[]
  compactionSummary?: string
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

interface FlameStore {
  state: FlameState | null
  loading: boolean
  error: string | null
  selectedFrameID: string | null
}

interface D3HierarchyNode {
  id: string
  data: FrameMetadata
  children: D3HierarchyNode[]
  parent: D3HierarchyNode | null
  depth: number
  height: number
}

interface FlameContextValue {
  // State
  store: FlameStore
  activeFrame: () => FrameMetadata | null
  selectedFrame: () => FrameMetadata | null

  // Actions
  refresh: () => Promise<void>
  pushFrame: (goal: string) => Promise<void>
  popFrame: (status: string, summary?: string, generateSummary?: boolean) => Promise<void>
  setGoal: (goal: string) => Promise<void>
  addArtifact: (artifact: string) => Promise<void>
  addDecision: (decision: string) => Promise<void>
  selectFrame: (sessionID: string | null) => void
  navigateToFrame: (sessionID: string) => void
  planFrame: (goal: string, parentID?: string) => Promise<void>
  planChildren: (parentID: string, children: Array<{goal: string}>) => Promise<void>
  activateFrame: (sessionID: string) => Promise<void>
  invalidateFrame: (sessionID: string, reason: string) => Promise<void>

  // Computed
  treeData: () => D3HierarchyNode | null
  flatFrames: () => FrameMetadata[]
  framesByStatus: () => Record<string, FrameMetadata[]>
}

const FlameContext = createContext<FlameContextValue>()

export function useFlame() {
  const context = useContext(FlameContext)
  if (!context) {
    throw new Error("useFlame must be used within FlameProvider")
  }
  return context
}

export function FlameProvider(props: { children: any }) {
  const sdk = useSDK()
  const navigate = useNavigate()
  const params = useParams()

  const [store, setStore] = createStore<FlameStore>({
    state: null,
    loading: true,
    error: null,
    selectedFrameID: null
  })

  // Fetch flame state
  async function refresh() {
    try {
      setStore("loading", true)
      setStore("error", null)

      // Fetch state from file via custom endpoint or file read
      const response = await fetch(`${sdk.url}/flame/state?directory=${sdk.directory}`)

      if (response.ok) {
        const state = await response.json()
        setStore("state", state)
      } else if (response.status === 404) {
        // No flame state yet - that's OK
        setStore("state", {
          version: 1,
          frames: {},
          rootFrameIDs: [],
          updatedAt: Date.now()
        })
      } else {
        throw new Error(`Failed to fetch flame state: ${response.status}`)
      }
    } catch (error) {
      setStore("error", error instanceof Error ? error.message : "Unknown error")
    } finally {
      setStore("loading", false)
    }
  }

  // Subscribe to events
  onMount(() => {
    refresh()

    // Subscribe to flame events via SSE
    sdk.event.on("session.updated", () => {
      // Refresh on any session update - could optimize later
      refresh()
    })

    // Custom flame events (if implemented in plugin)
    sdk.event.on("flame.frame.created" as any, refresh)
    sdk.event.on("flame.frame.updated" as any, refresh)
    sdk.event.on("flame.frame.completed" as any, refresh)
  })

  // Tool execution helper
  async function executeFlameAction(tool: string, args: Record<string, unknown>) {
    // For now, we need the AI to execute tools
    // This is a limitation - ideally we'd have a direct tool execution endpoint
    // Alternative: Read/write flame state directly

    // TODO: Implement direct tool execution or state manipulation
    console.log(`Execute ${tool}:`, args)
    await refresh()
  }

  // Computed values
  const activeFrame = createMemo(() => {
    const state = store.state
    if (!state?.activeFrameID) return null
    return state.frames[state.activeFrameID] ?? null
  })

  const selectedFrame = createMemo(() => {
    const id = store.selectedFrameID
    if (!id || !store.state) return null
    return store.state.frames[id] ?? null
  })

  const treeData = createMemo((): D3HierarchyNode | null => {
    const state = store.state
    if (!state || state.rootFrameIDs.length === 0) return null

    // Build hierarchy from frames
    function buildNode(frameID: string, parent: D3HierarchyNode | null, depth: number): D3HierarchyNode | null {
      const frame = state.frames[frameID]
      if (!frame) return null

      const node: D3HierarchyNode = {
        id: frameID,
        data: frame,
        children: [],
        parent,
        depth,
        height: 0
      }

      // Find children
      const childIDs = Object.keys(state.frames).filter(
        id => state.frames[id].parentSessionID === frameID
      )

      node.children = childIDs
        .map(id => buildNode(id, node, depth + 1))
        .filter((n): n is D3HierarchyNode => n !== null)
        .sort((a, b) => a.data.createdAt - b.data.createdAt)

      // Calculate height
      node.height = node.children.length > 0
        ? Math.max(...node.children.map(c => c.height)) + 1
        : 0

      return node
    }

    // For simplicity, use first root. Could support multiple roots.
    const rootID = state.rootFrameIDs[0]
    return rootID ? buildNode(rootID, null, 0) : null
  })

  const flatFrames = createMemo(() => {
    const state = store.state
    if (!state) return []
    return Object.values(state.frames)
      .sort((a, b) => b.updatedAt - a.updatedAt)
  })

  const framesByStatus = createMemo(() => {
    const frames = flatFrames()
    const result: Record<string, FrameMetadata[]> = {
      planned: [],
      in_progress: [],
      completed: [],
      failed: [],
      blocked: [],
      invalidated: []
    }

    for (const frame of frames) {
      result[frame.status]?.push(frame)
    }

    return result
  })

  const contextValue: FlameContextValue = {
    store,
    activeFrame,
    selectedFrame,

    refresh,

    async pushFrame(goal) {
      await executeFlameAction("flame_push", { goal })
    },

    async popFrame(status, summary, generateSummary) {
      await executeFlameAction("flame_pop", { status, summary, generateSummary })
    },

    async setGoal(goal) {
      await executeFlameAction("flame_set_goal", { goal })
    },

    async addArtifact(artifact) {
      await executeFlameAction("flame_add_artifact", { artifact })
    },

    async addDecision(decision) {
      await executeFlameAction("flame_add_decision", { decision })
    },

    selectFrame(sessionID) {
      setStore("selectedFrameID", sessionID)
    },

    navigateToFrame(sessionID) {
      // Navigate to the session in OpenCode
      const dir = params.dir
      if (dir) {
        navigate(`/${dir}/session/${sessionID}`)
      }
    },

    async planFrame(goal, parentID) {
      await executeFlameAction("flame_plan", { goal, parentID })
    },

    async planChildren(parentID, children) {
      await executeFlameAction("flame_plan_children", {
        parentID,
        children: children.map((c, i) => ({ goal: c.goal, id: `planned_${Date.now()}_${i}` }))
      })
    },

    async activateFrame(sessionID) {
      await executeFlameAction("flame_activate", { frameID: sessionID })
    },

    async invalidateFrame(sessionID, reason) {
      await executeFlameAction("flame_invalidate", { frameID: sessionID, reason })
    },

    treeData,
    flatFrames,
    framesByStatus
  }

  return (
    <FlameContext.Provider value={contextValue}>
      {props.children}
    </FlameContext.Provider>
  )
}
```

### D.2 FlamePanel Component

```typescript
// packages/app/src/components/flame-panel.tsx

import { Show, createMemo, createSignal } from "solid-js"
import { useFlame } from "@/context/flame"
import { FlameGraph } from "./flame-graph"
import { FrameDetails } from "./frame-details"
import { FrameList } from "./frame-list"
import { Tabs } from "@opencode-ai/ui/tabs"
import { IconButton } from "@opencode-ai/ui/icon-button"
import { Spinner } from "@opencode-ai/ui/spinner"

type ViewMode = "graph" | "tree" | "list"

export function FlamePanel() {
  const flame = useFlame()
  const [viewMode, setViewMode] = createSignal<ViewMode>("graph")

  const hasFrames = createMemo(() => {
    return flame.flatFrames().length > 0
  })

  return (
    <div class="h-full flex flex-col bg-background-base">
      {/* Header */}
      <div class="flex items-center justify-between px-4 py-2 border-b border-border-weak-base">
        <div class="flex items-center gap-2">
          <span class="text-14-medium">Flame Graph</span>
          <Show when={flame.store.loading}>
            <Spinner size="small" />
          </Show>
        </div>

        <div class="flex items-center gap-1">
          <IconButton
            icon="grid-view"
            variant={viewMode() === "graph" ? "solid" : "ghost"}
            onClick={() => setViewMode("graph")}
            title="Graph view"
          />
          <IconButton
            icon="list-tree"
            variant={viewMode() === "tree" ? "solid" : "ghost"}
            onClick={() => setViewMode("tree")}
            title="Tree view"
          />
          <IconButton
            icon="list"
            variant={viewMode() === "list" ? "solid" : "ghost"}
            onClick={() => setViewMode("list")}
            title="List view"
          />
          <IconButton
            icon="refresh"
            variant="ghost"
            onClick={() => flame.refresh()}
            title="Refresh"
          />
        </div>
      </div>

      {/* Content */}
      <div class="flex-1 min-h-0 flex">
        {/* Main visualization */}
        <div class="flex-1 min-w-0 overflow-hidden">
          <Show when={flame.store.error}>
            <div class="flex items-center justify-center h-full text-error">
              Error: {flame.store.error}
            </div>
          </Show>

          <Show when={!flame.store.error && !hasFrames()}>
            <div class="flex flex-col items-center justify-center h-full text-text-weak gap-4">
              <span>No frames yet</span>
              <span class="text-12-regular">
                Use flame_push to create your first frame, or start a new session
              </span>
            </div>
          </Show>

          <Show when={!flame.store.error && hasFrames()}>
            <Show when={viewMode() === "graph"}>
              <FlameGraph
                onFrameClick={(frame) => flame.selectFrame(frame.sessionID)}
                onFrameDoubleClick={(frame) => flame.navigateToFrame(frame.sessionID)}
                highlightedFrameID={flame.activeFrame()?.sessionID}
              />
            </Show>

            <Show when={viewMode() === "tree"}>
              <FrameTree />
            </Show>

            <Show when={viewMode() === "list"}>
              <FrameList />
            </Show>
          </Show>
        </div>

        {/* Details sidebar */}
        <Show when={flame.selectedFrame()}>
          <div class="w-80 border-l border-border-weak-base">
            <FrameDetails
              frame={flame.selectedFrame()!}
              onClose={() => flame.selectFrame(null)}
            />
          </div>
        </Show>
      </div>
    </div>
  )
}
```

### D.3 FlameGraph D3 Component

```typescript
// packages/app/src/components/flame-graph.tsx

import { onMount, onCleanup, createEffect, on } from "solid-js"
import * as d3 from "d3"
import { useFlame } from "@/context/flame"

interface FlameGraphProps {
  onFrameClick?: (frame: FrameMetadata) => void
  onFrameDoubleClick?: (frame: FrameMetadata) => void
  highlightedFrameID?: string
}

const STATUS_COLORS: Record<string, string> = {
  planned: "#6b7280",      // gray-500
  in_progress: "#3b82f6",  // blue-500
  completed: "#22c55e",    // green-500
  failed: "#ef4444",       // red-500
  blocked: "#f59e0b",      // amber-500
  invalidated: "#9ca3af"   // gray-400
}

export function FlameGraph(props: FlameGraphProps) {
  let containerRef: HTMLDivElement | undefined
  let svgRef: SVGSVGElement | undefined
  const flame = useFlame()

  onMount(() => {
    if (!containerRef) return

    // Create SVG
    const svg = d3.select(containerRef)
      .append("svg")
      .attr("class", "w-full h-full")

    svgRef = svg.node() as SVGSVGElement

    // Initial render
    renderGraph()

    // Handle resize
    const resizeObserver = new ResizeObserver(() => {
      renderGraph()
    })
    resizeObserver.observe(containerRef)

    onCleanup(() => {
      resizeObserver.disconnect()
    })
  })

  // Re-render when data changes
  createEffect(on(
    () => [flame.treeData(), props.highlightedFrameID],
    () => renderGraph()
  ))

  function renderGraph() {
    if (!svgRef || !containerRef) return

    const treeData = flame.treeData()
    if (!treeData) return

    const width = containerRef.clientWidth
    const height = containerRef.clientHeight
    const margin = { top: 20, right: 20, bottom: 20, left: 20 }
    const innerWidth = width - margin.left - margin.right
    const innerHeight = height - margin.top - margin.bottom

    // Clear previous content
    d3.select(svgRef).selectAll("*").remove()

    const svg = d3.select(svgRef)
      .attr("viewBox", [0, 0, width, height])

    const g = svg.append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Convert to D3 hierarchy
    const root = d3.hierarchy(treeData, d => d.children)

    // Calculate layout using partition (icicle/flame graph style)
    const partition = d3.partition<typeof treeData>()
      .size([innerWidth, innerHeight])
      .padding(2)

    // Sum values for sizing (use descendant count + 1)
    root.sum(d => 1)

    partition(root)

    // Draw cells
    const cells = g.selectAll("g.cell")
      .data(root.descendants())
      .join("g")
      .attr("class", "cell")
      .attr("transform", d => `translate(${d.x0},${d.y0})`)
      .style("cursor", "pointer")
      .on("click", (event, d) => {
        event.stopPropagation()
        props.onFrameClick?.(d.data.data)
      })
      .on("dblclick", (event, d) => {
        event.stopPropagation()
        props.onFrameDoubleClick?.(d.data.data)
      })

    // Rectangles
    cells.append("rect")
      .attr("width", d => Math.max(0, d.x1 - d.x0 - 1))
      .attr("height", d => Math.max(0, d.y1 - d.y0 - 1))
      .attr("fill", d => STATUS_COLORS[d.data.data.status] ?? "#666")
      .attr("stroke", d =>
        d.data.id === props.highlightedFrameID ? "#fff" : "transparent"
      )
      .attr("stroke-width", 2)
      .attr("rx", 2)
      .attr("opacity", d =>
        d.data.data.status === "invalidated" ? 0.5 : 1
      )

    // Labels
    cells.append("text")
      .attr("x", 4)
      .attr("y", 14)
      .attr("fill", "#fff")
      .attr("font-size", "11px")
      .attr("pointer-events", "none")
      .text(d => {
        const width = d.x1 - d.x0
        const maxChars = Math.floor(width / 7)
        const goal = d.data.data.goal
        return goal.length > maxChars
          ? goal.substring(0, maxChars - 2) + "..."
          : goal
      })
      .attr("opacity", d => {
        const width = d.x1 - d.x0
        return width > 40 ? 1 : 0
      })

    // Status indicator
    cells.append("circle")
      .attr("cx", d => d.x1 - d.x0 - 8)
      .attr("cy", 10)
      .attr("r", 4)
      .attr("fill", d => {
        switch (d.data.data.status) {
          case "in_progress": return "#60a5fa"
          case "completed": return "#86efac"
          case "failed": return "#fca5a5"
          default: return "transparent"
        }
      })
      .attr("opacity", d => {
        const width = d.x1 - d.x0
        return width > 60 ? 1 : 0
      })

    // Tooltips (using title element for simplicity)
    cells.append("title")
      .text(d => {
        const frame = d.data.data
        return [
          `Goal: ${frame.goal}`,
          `Status: ${frame.status}`,
          `Created: ${new Date(frame.createdAt).toLocaleString()}`,
          frame.artifacts.length > 0 ? `Artifacts: ${frame.artifacts.length}` : null,
          frame.decisions.length > 0 ? `Decisions: ${frame.decisions.length}` : null,
        ].filter(Boolean).join("\n")
      })
  }

  return (
    <div
      ref={containerRef}
      class="w-full h-full overflow-hidden"
    />
  )
}
```

---

## Appendix E: Plugin Event Emission Additions

### E.1 Required Modifications to flame.ts

```typescript
// Add to flame.ts - BusEvent definitions

const FlameEvents = {
  FrameCreated: BusEvent.define("flame.frame.created", z.object({
    frame: z.object({
      sessionID: z.string(),
      parentSessionID: z.string().optional(),
      status: z.enum(["planned", "in_progress", "completed", "failed", "blocked", "invalidated"]),
      goal: z.string(),
      createdAt: z.number(),
      updatedAt: z.number(),
    }),
  })),

  FrameUpdated: BusEvent.define("flame.frame.updated", z.object({
    frame: z.object({
      sessionID: z.string(),
      status: z.enum(["planned", "in_progress", "completed", "failed", "blocked", "invalidated"]),
      goal: z.string(),
      updatedAt: z.number(),
    }),
    changes: z.array(z.string()), // ["status", "goal", etc.]
  })),

  FrameCompleted: BusEvent.define("flame.frame.completed", z.object({
    frame: z.object({
      sessionID: z.string(),
      status: z.enum(["completed", "failed", "blocked"]),
      compactionSummary: z.string().optional(),
    }),
    parentID: z.string().optional(),
  })),

  ActiveFrameChanged: BusEvent.define("flame.active.changed", z.object({
    previousID: z.string().optional(),
    currentID: z.string().optional(),
  })),

  TreeChanged: BusEvent.define("flame.tree.changed", z.object({
    action: z.enum(["push", "pop", "plan", "activate", "invalidate"]),
    affectedFrames: z.array(z.string()),
  })),
}

// Example: Modify createFrame method
async createFrame(sessionID: string, goal: string, parentSessionID?: string): Promise<FrameMetadata> {
  // ... existing logic ...

  // NEW: Emit event after successful creation
  Bus.publish(FlameEvents.FrameCreated, {
    frame: {
      sessionID: frame.sessionID,
      parentSessionID: frame.parentSessionID,
      status: frame.status,
      goal: frame.goal,
      createdAt: frame.createdAt,
      updatedAt: frame.updatedAt,
    }
  })

  Bus.publish(FlameEvents.TreeChanged, {
    action: "push",
    affectedFrames: [sessionID]
  })

  return frame
}

// Example: Modify completeFrame method
async completeFrame(sessionID: string, status: FrameStatus, summary?: string): Promise<string | undefined> {
  // ... existing logic ...

  // NEW: Emit event after completion
  Bus.publish(FlameEvents.FrameCompleted, {
    frame: {
      sessionID: frame.sessionID,
      status: frame.status,
      compactionSummary: frame.compactionSummary,
    },
    parentID: frame.parentSessionID,
  })

  Bus.publish(FlameEvents.ActiveFrameChanged, {
    previousID: sessionID,
    currentID: frame.parentSessionID,
  })

  Bus.publish(FlameEvents.TreeChanged, {
    action: "pop",
    affectedFrames: [sessionID]
  })

  return parentID
}
```

### E.2 New State Endpoint

```typescript
// Add to server.ts

import * as fs from "fs"
import * as path from "path"

.get(
  "/flame/state",
  describeRoute({
    summary: "Get flame graph state",
    description: "Retrieve the current flame graph context management state",
    operationId: "flame.state",
    responses: {
      200: {
        description: "Flame state",
        content: {
          "application/json": {
            schema: resolver(z.object({
              version: z.number(),
              frames: z.record(z.string(), z.object({
                sessionID: z.string(),
                parentSessionID: z.string().optional(),
                status: z.string(),
                goal: z.string(),
                createdAt: z.number(),
                updatedAt: z.number(),
                artifacts: z.array(z.string()),
                decisions: z.array(z.string()),
                compactionSummary: z.string().optional(),
                invalidationReason: z.string().optional(),
                invalidatedAt: z.number().optional(),
                plannedChildren: z.array(z.string()).optional(),
              })),
              activeFrameID: z.string().optional(),
              rootFrameIDs: z.array(z.string()),
              updatedAt: z.number(),
            }).meta({ ref: "FlameState" })),
          },
        },
      },
      404: {
        description: "No flame state exists",
      },
    },
  }),
  async (c) => {
    const stateFilePath = path.join(Instance.directory, ".opencode", "flame", "state.json")

    try {
      const content = await fs.promises.readFile(stateFilePath, "utf-8")
      const state = JSON.parse(content)
      return c.json(state)
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return c.json({
          version: 1,
          frames: {},
          rootFrameIDs: [],
          updatedAt: Date.now(),
        }, 200)
      }
      throw error
    }
  }
)
```

---

## Appendix F: Layout Integration

### F.1 Adding Flame Panel to Layout Context

```typescript
// Modify packages/app/src/context/layout.tsx

interface LayoutState {
  // ... existing fields ...
  flame: {
    opened: Accessor<boolean>
    width: Accessor<number>
    toggle: () => void
    open: () => void
    close: () => void
    resize: (width: number) => void
  }
}

// In the init function:
const [flameOpened, setFlameOpened] = createSignal(false)
const [flameWidth, setFlameWidth] = createSignal(320)

return {
  // ... existing ...
  flame: {
    opened: flameOpened,
    width: flameWidth,
    toggle: () => setFlameOpened(!flameOpened()),
    open: () => setFlameOpened(true),
    close: () => setFlameOpened(false),
    resize: (width) => setFlameWidth(Math.max(200, Math.min(600, width))),
  }
}
```

### F.2 Adding Panel to Session Page

```tsx
// Modify packages/app/src/pages/session.tsx

// Add to imports
import { FlameProvider } from "@/context/flame"
import { FlamePanel } from "@/components/flame-panel"

// In the render, add flame panel next to review panel:
<Show when={layout.flame.opened()}>
  <div
    class="relative shrink-0 h-full border-l border-border-weak-base"
    style={{ width: `${layout.flame.width()}px` }}
  >
    <ResizeHandle
      direction="horizontal"
      size={layout.flame.width()}
      min={200}
      max={600}
      onResize={layout.flame.resize}
    />
    <FlameProvider>
      <FlamePanel />
    </FlameProvider>
  </div>
</Show>
```

---

## Appendix G: Risk Assessment

### G.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| D3 + SolidJS integration complexity | Medium | High | Start with simple rendering, add reactivity incrementally |
| Event system latency | Low | Medium | Implement optimistic updates, batch state refreshes |
| Large tree performance | Medium | Medium | Virtual rendering, lazy child loading |
| Tool execution without AI context | High | High | Design direct state manipulation API as fallback |
| Plugin modification compatibility | Low | High | Version plugin API, maintain backwards compatibility |

### G.2 UX Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Visualization confusion | Medium | High | User testing, clear legend, progressive disclosure |
| Panel space competition | Medium | Medium | Smart defaults, remember user preferences |
| Feature discoverability | High | Medium | Contextual hints, command palette integration |

---

*Document Version: 1.1*
*Last Updated: 2025-12-24*
*Author: Claude (Phase 2 Planning)*
