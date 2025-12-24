# Phase 2: Flame Graph Web UI - Implementation Plan

## Document Version
- **Version**: 1.0
- **Date**: 2025-12-24
- **Status**: Draft Proposal

---

## Executive Summary

Phase 2 extends the Flame Graph Context Management system with a web-based visualization that renders the frame call stack as an interactive flame graph. This UI will allow users to visualize frame hierarchy, observe real-time frame changes, and control frame operations (push/pop, planning, navigation) through an intuitive graphical interface.

The web UI integrates with the existing Phase 1 OpenCode plugin infrastructure, leveraging the OpenCode SDK for real-time event subscriptions and API interactions.

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
+------------------------------------------------------------------+
|                        OpenCode Web Client                        |
|  +-------------------------------------------------------------+  |
|  |                    Flame Graph UI Panel                      |  |
|  |  +-------------------------------------------------------+   |  |
|  |  |            Flame Graph Visualization (D3.js)          |   |  |
|  |  |  +----+ +----+ +----+ +----+ +----+ +----+ +----+      |   |  |
|  |  |  | F1 | | F2 | | F3 | | F4 | | F5 | | F6 | | F7 |      |   |  |
|  |  |  +----+ +----+ +----+ +----+ +----+ +----+ +----+      |   |  |
|  |  +-------------------------------------------------------+   |  |
|  |  +-------------------------------------------------------+   |  |
|  |  |                Frame Details Panel                     |   |  |
|  |  |  - Goal, Status, Artifacts, Decisions                  |   |  |
|  |  +-------------------------------------------------------+   |  |
|  |  +-------------------------------------------------------+   |  |
|  |  |              Control Panel (Push/Pop/Plan)             |   |  |
|  |  +-------------------------------------------------------+   |  |
|  +-------------------------------------------------------------+  |
+------------------------------------------------------------------+
          |                          ^
          | SDK API Calls            | SSE Events
          v                          |
+------------------------------------------------------------------+
|                      OpenCode Server (HTTP)                       |
|  - Session Management APIs                                        |
|  - Flame Plugin Tools (via tool.execute)                          |
|  - Event Streaming (SSE)                                          |
+------------------------------------------------------------------+
          |                          ^
          | Tool Execution           | State Events
          v                          |
+------------------------------------------------------------------+
|                   Flame Plugin (flame.ts)                         |
|  - FrameStateManager                                              |
|  - State Persistence (.opencode/flame/state.json)                 |
|  - Context Generation                                             |
|  - 28 flame_* Tools                                               |
+------------------------------------------------------------------+
```

### 1.2 Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Flame Graph UI Panel** | Renders the flame graph, handles user interactions, displays frame details |
| **OpenCode SDK Client** | Communicates with server via HTTP APIs, subscribes to SSE events |
| **OpenCode Server** | Routes API requests, manages sessions, proxies tool execution to plugins |
| **Flame Plugin** | Manages frame state tree, persists to disk, executes flame_* tools |

### 1.3 Integration Approach

The UI will integrate as a new panel/view within the OpenCode web client (packages/app), following the existing component patterns. Two integration strategies are viable:

**Option A: Embedded Panel (Recommended)**
- Add a new `FlameGraphPanel` component to the existing OpenCode app
- Mount as a sidebar, modal, or tab within the session view
- Leverages existing SDK connections and event subscriptions
- Shares session context with the main chat interface

**Option B: Standalone Application**
- Separate web application that connects to OpenCode server
- Independent lifecycle but requires duplicate SDK setup
- Better for development isolation but less integrated experience

We recommend **Option A** for tighter UX integration with the existing conversation flow.

---

## 2. Data Flow

### 2.1 Frame State Data Flow

```
                   Initial Load
+---------+       +-----------+       +-----------+
| UI Boot | ----> | SDK Call  | ----> | Plugin    |
|         |       | (custom)  |       | flame_*   |
+---------+       +-----------+       +-----------+
                                            |
                                            v
                                      +-------------+
                                      | state.json  |
                                      +-------------+
                                            |
                                            v
                                      +-----------+
                                      | Response  | --->  UI Renders
                                      +-----------+


                   Real-time Updates
+---------+       +-----------+       +-----------+
| Plugin  | ----> | Bus Event | ----> | SSE       | ---> UI Updates
| Action  |       | Emit      |       | Stream    |
+---------+       +-----------+       +-----------+
```

### 2.2 Data Sources

1. **Initial State Load**: On panel mount, the UI calls `flame_status` tool to retrieve the complete frame tree state.

2. **Real-time Updates**: The plugin emits events through OpenCode's event bus when frame state changes. The UI subscribes to these events via SSE.

3. **State Persistence**: All frame data is persisted in `.opencode/flame/state.json` and individual frame files in `.opencode/flame/frames/`.

### 2.3 State Shape for UI

The UI will consume frame state in this shape:

```typescript
interface FlameUIState {
  // Core frame tree
  frames: Record<string, FrameNode>;
  activeFrameID: string | null;
  rootFrameIDs: string[];

  // Computed for visualization
  flattenedTree: FlatFrame[];
  maxDepth: number;

  // UI state
  selectedFrameID: string | null;
  hoveredFrameID: string | null;
  expandedFrameIDs: Set<string>;
}

interface FrameNode {
  id: string;
  parentID?: string;
  childIDs: string[];
  status: FrameStatus;
  goal: string;
  summary?: string;
  artifacts: string[];
  decisions: string[];
  createdAt: number;
  updatedAt: number;
  depth: number; // computed
  width: number; // computed for visualization
}

type FrameStatus =
  | "planned"
  | "in_progress"
  | "completed"
  | "failed"
  | "blocked"
  | "invalidated";
```

### 2.4 Event Types for Real-time Sync

The plugin should emit these events (requires Phase 1 enhancement):

| Event Type | Payload | Trigger |
|------------|---------|---------|
| `flame.frame.created` | `{ frame: FrameMetadata }` | New frame created |
| `flame.frame.updated` | `{ frame: FrameMetadata }` | Frame status/summary changed |
| `flame.frame.activated` | `{ frameID: string }` | Active frame changed |
| `flame.frame.invalidated` | `{ frameID: string, cascaded: string[] }` | Frame invalidated |
| `flame.state.reset` | `{ state: FlameState }` | Full state reset |

---

## 3. Flame Graph Visualization

### 3.1 Flame Graph Anatomy

Traditional flame graphs display hierarchical data as stacked rectangles:

```
+---------------------------------------------------------------+
|                     Root Frame: "Build App"                    |
+----------------------------------+----------------------------+
|        Frame A: Auth (done)      |    Frame B: API (active)   |
+-----------------+----------------+-------------+--------------+
|   A1 (done)     |    A2 (done)   |  B1 (wip)   |  B2 (plan)   |
+-----------------+----------------+-------------+--------------+
```

**Key characteristics:**
- Width represents relative "weight" (time, importance, or equal distribution)
- Depth represents call stack depth
- Color encodes status (green=complete, blue=active, yellow=planned, red=failed)
- Interactive: hover for details, click to navigate

### 3.2 Visualization Library Selection

| Library | Pros | Cons | Verdict |
|---------|------|------|---------|
| **D3.js + d3-flame-graph** | Battle-tested, flexible, widely used | Steeper learning curve | **Recommended** |
| **Flame Chart JS** | Simple API | Less customizable | Backup option |
| **Custom Canvas/SVG** | Full control | Significant effort | Not recommended |
| **ECharts** | Feature-rich | Overkill, large bundle | Not recommended |

**Recommendation**: Use **D3.js** with the `d3-flame-graph` package as the foundation, customizing rendering for frame-specific semantics.

### 3.3 D3 Flame Graph Implementation

```typescript
import * as d3 from 'd3';
import { flamegraph } from 'd3-flame-graph';

interface FlameGraphConfig {
  width: number;
  height: number;
  cellHeight: number;
  colorScheme: Record<FrameStatus, string>;
  onFrameClick: (frame: FrameNode) => void;
  onFrameHover: (frame: FrameNode | null) => void;
}

const STATUS_COLORS: Record<FrameStatus, string> = {
  planned: '#fbbf24',      // yellow-400
  in_progress: '#3b82f6',  // blue-500
  completed: '#22c55e',    // green-500
  failed: '#ef4444',       // red-500
  blocked: '#f97316',      // orange-500
  invalidated: '#9ca3af',  // gray-400
};

function createFlameGraph(
  container: HTMLElement,
  state: FlameUIState,
  config: FlameGraphConfig
) {
  const hierarchyData = buildHierarchy(state.frames, state.rootFrameIDs);

  const chart = flamegraph()
    .width(config.width)
    .cellHeight(config.cellHeight)
    .transitionDuration(300)
    .color((d) => STATUS_COLORS[d.data.status])
    .label((d) => truncate(d.data.goal, 40))
    .onClick((d) => config.onFrameClick(d.data))
    .onHover((d) => config.onFrameHover(d?.data ?? null));

  d3.select(container)
    .datum(hierarchyData)
    .call(chart);

  return chart;
}

function buildHierarchy(
  frames: Record<string, FrameNode>,
  rootIDs: string[]
): d3.HierarchyNode<FrameNode> {
  // Transform flat frame map into hierarchical structure
  const buildNode = (id: string): any => {
    const frame = frames[id];
    return {
      ...frame,
      name: frame.goal,
      value: 1, // or compute based on time/tokens
      children: frame.childIDs.map(buildNode),
    };
  };

  const root = {
    name: 'Flame Context',
    value: 1,
    children: rootIDs.map(buildNode),
  };

  return d3.hierarchy(root).sum((d) => d.value);
}
```

### 3.4 Visual Elements

| Element | Representation |
|---------|---------------|
| Frame rectangle | Proportional width, status color fill |
| Active frame | Highlighted border, slightly elevated |
| Selected frame | Strong border, connected detail panel |
| Planned frame | Dashed border, muted color |
| Invalidated frame | Strikethrough text, gray color |
| Hover state | Tooltip with goal + summary preview |

### 3.5 Layout Algorithm

For frames without "weight" data (equal children):
- Each child gets `parent_width / num_children`
- Minimum width enforced to maintain readability
- Overflow handling: horizontal scroll or zoom controls

For weighted display (optional enhancement):
- Weight by message count or token count
- Weight by elapsed time in frame
- Weight by artifact count

---

## 4. User Interactions

### 4.1 Flame Graph Interactions

| Action | Trigger | Result |
|--------|---------|--------|
| **View frame details** | Click on frame | Open details panel, highlight in graph |
| **Navigate to frame** | Double-click or context menu | Set as active frame, update session context |
| **Expand/Collapse** | Click +/- icon | Show/hide children in graph |
| **Hover preview** | Mouse hover | Show tooltip with goal, status, summary |
| **Zoom** | Scroll wheel / pinch | Zoom in/out of graph area |
| **Pan** | Drag empty area | Navigate large graphs |
| **Reset view** | Button click | Reset zoom/pan to fit all |

### 4.2 Control Panel Actions

| Action | UI Element | Tool Called | Description |
|--------|------------|-------------|-------------|
| **Push Frame** | "New Frame" button + modal | `flame_push` | Create child of active frame |
| **Pop Frame** | "Complete Frame" button | `flame_pop` | Complete active frame, return to parent |
| **Set Goal** | Inline edit field | `flame_set_goal` | Update frame goal |
| **Add Artifact** | "Add Artifact" button | `flame_add_artifact` | Record artifact |
| **Add Decision** | "Add Decision" button | `flame_add_decision` | Record decision |
| **Plan Frame** | "Plan" button + modal | `flame_plan` | Create planned child |
| **Activate Frame** | "Activate" button | `flame_activate` | Start planned frame |
| **Invalidate Frame** | Context menu action | `flame_invalidate` | Invalidate with reason |
| **Generate Summary** | "Summarize" button | `flame_summarize` | Trigger compaction summary |

### 4.3 Details Panel Content

When a frame is selected, the details panel shows:

```
+--------------------------------------------------+
| Frame: "Implement user authentication"           |
| Status: [in_progress] | Created: 2 hours ago     |
+--------------------------------------------------+
| Goal:                                            |
| Build JWT-based authentication with refresh      |
| tokens, user model, and auth middleware.         |
+--------------------------------------------------+
| Summary: (if completed)                          |
| Successfully implemented auth with...            |
+--------------------------------------------------+
| Artifacts (3):                                   |
| - src/auth/jwt.ts                                |
| - src/models/User.ts                             |
| - src/middleware/auth.ts                         |
+--------------------------------------------------+
| Decisions (2):                                   |
| - Using bcrypt for password hashing              |
| - Refresh tokens stored in httpOnly cookies      |
+--------------------------------------------------+
| Children: [A1] [A2] [A3+]                        |
+--------------------------------------------------+
| [Complete] [Add Artifact] [Add Decision] [More]  |
+--------------------------------------------------+
```

---

## 5. Real-time Updates

### 5.1 Event Subscription Architecture

The UI subscribes to the OpenCode SSE event stream and filters for flame-related events:

```typescript
// In FlameGraphContext.tsx
import { useGlobalSDK } from '@/context/global-sdk';
import { createEffect, onCleanup } from 'solid-js';

export function useFlameEvents(onStateChange: (state: FlameUIState) => void) {
  const { event } = useGlobalSDK();

  createEffect(() => {
    const cleanup = event.listen((e) => {
      const payload = e.details;

      switch (payload.type) {
        case 'flame.frame.created':
        case 'flame.frame.updated':
        case 'flame.frame.activated':
        case 'flame.frame.invalidated':
          // Fetch fresh state or apply delta
          refreshFlameState().then(onStateChange);
          break;

        case 'tool.execute.after':
          // Check if it was a flame tool
          if (payload.properties.tool.startsWith('flame_')) {
            refreshFlameState().then(onStateChange);
          }
          break;
      }
    });

    onCleanup(cleanup);
  });
}
```

### 5.2 State Synchronization Strategies

**Option A: Full State Refresh (Simple)**
- On any flame event, re-fetch complete state via `flame_status`
- Pros: Simple, always consistent
- Cons: Unnecessary data transfer, potential flicker

**Option B: Delta Updates (Optimized)**
- Events include the changed frame data
- Apply incremental updates to local state
- Pros: Efficient, smooth animations
- Cons: More complex, risk of desync

**Recommendation**: Start with Option A for reliability, optimize to Option B if performance issues arise.

### 5.3 Optimistic Updates

For better UX, apply optimistic updates before server confirmation:

```typescript
async function handlePushFrame(goal: string) {
  // Optimistic: Add frame to local state
  const tempID = `temp_${Date.now()}`;
  setFlameState(addFrame(tempID, goal, 'in_progress'));

  try {
    // Execute actual push
    const result = await callFlameTool('flame_push', { goal });
    // Replace temp with real frame
    setFlameState(replaceFrame(tempID, result.frame));
  } catch (error) {
    // Rollback optimistic update
    setFlameState(removeFrame(tempID));
    showError('Failed to create frame');
  }
}
```

---

## 6. Technology Choices

### 6.1 Stack Summary

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Framework** | SolidJS | Matches existing OpenCode app |
| **Visualization** | D3.js + d3-flame-graph | Industry standard for flame graphs |
| **Styling** | CSS Modules or Tailwind | Matches OpenCode UI patterns |
| **State Management** | SolidJS Store | Reactive, efficient updates |
| **API Client** | OpenCode SDK | Already integrated |
| **Build** | Vite | Existing OpenCode toolchain |

### 6.2 Package Dependencies

```json
{
  "dependencies": {
    "d3": "^7.x",
    "d3-flame-graph": "^4.x"
  },
  "devDependencies": {
    "@types/d3": "^7.x"
  }
}
```

### 6.3 Component Structure

```
packages/app/src/
  components/
    flame/
      FlameGraphPanel.tsx       # Main panel container
      FlameGraphVisualization.tsx  # D3 flame graph
      FrameDetailsPanel.tsx     # Selected frame details
      FrameControlPanel.tsx     # Push/pop/plan controls
      FrameTooltip.tsx          # Hover tooltip
      FlameGraphContext.tsx     # State management
      flame.css                 # Styling
```

---

## 7. Implementation Phases

### Phase 2.0: Foundation (Week 1)

**Goals**: Basic flame graph rendering with static data

**Tasks**:
1. Create `FlameGraphPanel` component skeleton
2. Integrate D3.js and d3-flame-graph
3. Implement `buildHierarchy` transform
4. Static rendering of mock frame data
5. Basic status coloring

**Deliverable**: Static flame graph rendering mock frame tree

### Phase 2.1: Data Integration (Week 2)

**Goals**: Connect to live plugin state

**Tasks**:
1. Implement `flame_get_state` tool (if not existing) or use `flame_status`
2. Create `FlameGraphContext` for state management
3. Initial data loading on panel mount
4. Parse and transform plugin state to UI state
5. Error handling for missing/invalid state

**Deliverable**: Flame graph renders live frame state

### Phase 2.2: Real-time Updates (Week 3)

**Goals**: SSE subscription for live updates

**Tasks**:
1. Extend flame plugin to emit bus events on state changes
2. Subscribe to SSE stream in UI
3. Filter and handle flame events
4. Implement state refresh mechanism
5. Add loading/updating indicators

**Deliverable**: Flame graph updates in real-time when frames change

### Phase 2.3: Frame Details (Week 4)

**Goals**: Details panel and frame inspection

**Tasks**:
1. Create `FrameDetailsPanel` component
2. Implement frame selection state
3. Display goal, status, artifacts, decisions
4. Show summary for completed frames
5. Link to log files (if available)

**Deliverable**: Click frame to see details in side panel

### Phase 2.4: Basic Controls (Week 5)

**Goals**: Push and pop frame operations

**Tasks**:
1. Create `FrameControlPanel` component
2. Implement "Push Frame" modal with goal input
3. Implement "Complete Frame" with status selection
4. Wire up to `flame_push` and `flame_pop` tools
5. Optimistic updates for responsiveness

**Deliverable**: Create and complete frames from UI

### Phase 2.5: Advanced Controls (Week 6)

**Goals**: Full planning and editing capabilities

**Tasks**:
1. Add artifact and decision inputs
2. Implement planned frame creation
3. Implement frame activation
4. Implement frame invalidation with cascade preview
5. Inline goal editing

**Deliverable**: Full CRUD operations for frames

### Phase 2.6: Polish & Integration (Week 7-8)

**Goals**: UX refinement and OpenCode integration

**Tasks**:
1. Zoom/pan controls for large graphs
2. Keyboard navigation
3. Responsive layout
4. Panel positioning options (sidebar, modal, tab)
5. Integration testing with OpenCode TUI
6. Documentation and examples

**Deliverable**: Production-ready flame graph UI

---

## 8. API Design

### 8.1 Required Plugin Enhancements

The Phase 1 plugin needs these additions for Phase 2:

#### 8.1.1 New Tool: `flame_get_state`

Returns complete frame state for UI rendering:

```typescript
flame_get_state: tool({
  description: "Get complete flame frame state for UI rendering",
  args: {},
  async execute(args, ctx) {
    const state = await manager.getAllFrames();
    return {
      frames: state.frames,
      activeFrameID: state.activeFrameID,
      rootFrameIDs: state.rootFrameIDs,
      updatedAt: state.updatedAt,
    };
  },
}),
```

#### 8.1.2 Event Emission

Add event emission to state-changing operations:

```typescript
// In FrameStateManager methods
async createFrame(sessionID: string, goal: string, parentSessionID?: string): Promise<FrameMetadata> {
  // ... existing code ...

  // NEW: Emit event for UI
  this.emitEvent('flame.frame.created', { frame });

  return frame;
}

private emitEvent(type: string, payload: any) {
  // Integrate with OpenCode event bus
  // This requires understanding OpenCode's internal event system
}
```

### 8.2 SDK Extensions

If custom endpoints are needed (vs using existing tool execution):

```typescript
// Hypothetical extensions to SDK
interface FlameClient {
  getState(): Promise<FlameState>;
  pushFrame(goal: string): Promise<FrameMetadata>;
  popFrame(status: FrameStatus, summary?: string): Promise<string | undefined>;
  planFrame(goal: string, parentID?: string): Promise<FrameMetadata>;
  activateFrame(frameID: string): Promise<FrameMetadata>;
  invalidateFrame(frameID: string, reason: string): Promise<InvalidationResult>;
}
```

**Note**: Custom endpoints may require server-side changes. Evaluate whether the existing tool execution path (`session.prompt` with tool calls) is sufficient.

### 8.3 Tool Invocation Pattern

UI invokes flame tools through session prompt with `noReply`:

```typescript
async function callFlameTool(tool: string, args: Record<string, any>) {
  const sdk = useSDK();
  const session = useActiveSession();

  // Send as user message that triggers tool
  await sdk.session.prompt({
    path: { id: session.id },
    body: {
      noReply: true,
      parts: [{
        type: 'text',
        text: `@flame_${tool} ${JSON.stringify(args)}`
      }]
    }
  });

  // Alternatively, use direct tool invocation if available
}
```

**Alternative**: Create a custom HTTP endpoint that directly invokes plugin tools without going through the LLM message flow.

---

## 9. Integration Points

### 9.1 OpenCode UI Integration

**Panel Placement Options**:

1. **Right Sidebar**: Always visible, shows flame graph alongside chat
2. **Bottom Panel**: Collapsible, similar to terminal panel
3. **Separate Tab**: Full-width view, accessible via tab bar
4. **Floating Dialog**: Draggable, resizable overlay

**Recommended**: Start with **Right Sidebar** for persistent visibility, with option to pop out to full view.

### 9.2 Session Context Synchronization

The active frame should sync with the conversation context:

```typescript
// When active frame changes in plugin
onFrameActivated(frameID) {
  // Update flame graph highlight
  setActiveFrameInUI(frameID);
}

// When user navigates in flame graph
onFrameNavigated(frameID) {
  // Notify plugin to switch active frame
  await callFlameTool('flame_navigate', { frameID });
  // Plugin injects new context to session
}
```

### 9.3 Chat Integration

Optional enhancements for deeper integration:

1. **Inline Frame References**: Click frame in graph to insert `@frame:ID` mention in chat
2. **Frame Context Preview**: Show current frame goal in chat header
3. **Push Suggestion Toast**: When autonomy suggests a push, show toast linking to flame graph

---

## 10. Open Questions

### 10.1 Technical Questions

1. **Event Bus Access**: How do plugins emit events to the OpenCode event bus? Need to verify the plugin API supports this.

2. **Direct Tool Invocation**: Can the UI invoke flame tools directly without going through message/LLM flow? This would be cleaner for UI operations.

3. **State File Access**: Should the UI read `.opencode/flame/state.json` directly, or always go through tools? Direct access is faster but bypasses plugin logic.

4. **Session Scope**: Is flame state per-session or global? Currently appears global; need to clarify multi-session behavior.

### 10.2 UX Questions

1. **Panel Default State**: Should flame graph be visible by default or hidden until frames exist?

2. **Auto-Navigation**: When a new frame is pushed, should the UI auto-navigate to it?

3. **Compaction Visibility**: Should the UI show when context is being compacted?

4. **Mobile/Small Screen**: How to handle flame graph on narrow viewports?

### 10.3 Scope Questions

1. **Log File Viewing**: Should the UI include a log viewer for frame history?

2. **Frame Diff View**: Should users see what changed between frames?

3. **Export/Import**: Allow exporting flame graph as image or JSON?

---

## 11. Success Criteria

### 11.1 Functional Requirements

- [ ] Flame graph renders complete frame tree
- [ ] Real-time updates when frames change
- [ ] Click frame to view details
- [ ] Create new frames (push) from UI
- [ ] Complete frames (pop) from UI
- [ ] Plan and activate frames from UI
- [ ] Invalidate frames with cascade preview
- [ ] Edit frame goals inline
- [ ] Add artifacts and decisions

### 11.2 Non-Functional Requirements

- [ ] Initial render < 500ms for typical frame trees (< 50 frames)
- [ ] Event-to-render update < 100ms
- [ ] No UI flicker on updates
- [ ] Accessible (keyboard navigation, screen reader friendly)
- [ ] Works in Chrome, Firefox, Safari (latest versions)

### 11.3 Integration Requirements

- [ ] Integrates cleanly with OpenCode app architecture
- [ ] Uses existing SDK patterns
- [ ] Follows OpenCode component conventions
- [ ] No breaking changes to Phase 1 plugin

---

## 12. Appendix

### A. File References

| File | Purpose |
|------|---------|
| `/Users/sl/code/flame/SPEC.md` | Theoretical specification for flame graph context |
| `/Users/sl/code/flame/.opencode/plugin/flame.ts` | Phase 1 plugin implementation (5000+ lines) |
| `/Users/sl/code/flame/.opencode/flame/state.json` | Frame state persistence format |
| `/Users/sl/code/opencode/packages/app/src/` | OpenCode web app source |
| `/Users/sl/code/opencode/packages/ui/src/` | OpenCode shared UI components |
| `/Users/sl/code/opencode/packages/sdk/js/src/` | OpenCode JS SDK source |

### B. Flame Plugin Tools Summary

The Phase 1 plugin exposes 28 tools:

| Tool | Description |
|------|-------------|
| `flame_push` | Create child frame and make it active |
| `flame_pop` | Complete current frame, return to parent |
| `flame_status` | Get current frame tree status |
| `flame_set_goal` | Update frame goal |
| `flame_add_artifact` | Add artifact to frame |
| `flame_add_decision` | Add decision to frame |
| `flame_context_info` | Get context budget metadata |
| `flame_context_preview` | Preview generated context XML |
| `flame_cache_clear` | Clear context cache |
| `flame_summarize` | Generate manual summary |
| `flame_compaction_info` | Get compaction tracking info |
| `flame_get_summary` | Get frame summary |
| `flame_subagent_config` | Configure subagent detection |
| `flame_subagent_stats` | Get subagent statistics |
| `flame_subagent_complete` | Complete subagent session |
| `flame_subagent_list` | List tracked subagent sessions |
| `flame_plan` | Create planned frame |
| `flame_plan_children` | Create multiple planned children |
| `flame_activate` | Activate planned frame |
| `flame_invalidate` | Invalidate frame with cascade |
| `flame_tree` | ASCII visualization of frame tree |
| `flame_autonomy_config` | Configure autonomy settings |
| `flame_should_push` | Evaluate push heuristics |
| `flame_should_pop` | Evaluate pop heuristics |
| `flame_auto_suggest` | Manage auto-suggestions |
| `flame_autonomy_stats` | Get autonomy statistics |

### C. Frame Status Types

```typescript
type FrameStatus =
  | "planned"      // Not yet started
  | "in_progress"  // Currently active
  | "completed"    // Successfully finished
  | "failed"       // Ended with failure
  | "blocked"      // Waiting on external dependency
  | "invalidated"  // No longer relevant
```

### D. Visualization Mockup

```
+------------------------------------------------------------------+
|  Flame Graph                                             [X] [-]  |
+------------------------------------------------------------------+
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                    Build E-Commerce App                      |  |
|  +---------------------------+---------------------------------+  |
|  |       Auth System         |         Product Catalog         |  |
|  |       (completed)         |         (in_progress)           |  |
|  +-------------+-------------+-----------------+---------------+  |
|  |   Login     |  Register   |   List Products | Add Product   |  |
|  |   (done)    |   (done)    |     (active)    |  (planned)    |  |
|  +-------------+-------------+-----------------+---------------+  |
|                                                                   |
+------------------------------------------------------------------+
|  Selected: List Products                              [Zoom: 100%]|
|  Status: in_progress | Goal: Implement product listing with...   |
|  [Complete Frame] [Add Artifact] [Add Decision] [Invalidate]     |
+------------------------------------------------------------------+
```

---

## 13. Detailed Component Specifications

### 13.1 FlameGraphPanel Component

The main container component that orchestrates the entire flame graph experience.

```typescript
// FlameGraphPanel.tsx
import { createSignal, createEffect, Show } from 'solid-js';
import { createStore } from 'solid-js/store';
import { FlameGraphVisualization } from './FlameGraphVisualization';
import { FrameDetailsPanel } from './FrameDetailsPanel';
import { FrameControlPanel } from './FrameControlPanel';
import { useFlameState } from './FlameGraphContext';

interface FlameGraphPanelProps {
  sessionID: string;
  position: 'sidebar' | 'bottom' | 'modal';
  collapsed?: boolean;
  onToggleCollapse?: () => void;
}

export function FlameGraphPanel(props: FlameGraphPanelProps) {
  const { state, actions, loading, error } = useFlameState();
  const [selectedFrameID, setSelectedFrameID] = createSignal<string | null>(null);
  const [viewSettings, setViewSettings] = createStore({
    zoom: 1,
    panX: 0,
    panY: 0,
    showPlanned: true,
    showInvalidated: false,
  });

  // Load state on mount
  createEffect(() => {
    if (props.sessionID) {
      actions.loadState();
    }
  });

  const selectedFrame = () => {
    const id = selectedFrameID();
    return id ? state.frames[id] : null;
  };

  return (
    <div class="flame-graph-panel" data-position={props.position}>
      <header class="flame-graph-header">
        <h3>Flame Graph</h3>
        <div class="flame-graph-toolbar">
          <button onClick={() => setViewSettings('zoom', z => z * 1.2)}>Zoom In</button>
          <button onClick={() => setViewSettings('zoom', z => z / 1.2)}>Zoom Out</button>
          <button onClick={() => setViewSettings({ zoom: 1, panX: 0, panY: 0 })}>Reset</button>
          <label>
            <input
              type="checkbox"
              checked={viewSettings.showPlanned}
              onChange={(e) => setViewSettings('showPlanned', e.target.checked)}
            />
            Show Planned
          </label>
        </div>
      </header>

      <Show when={error()}>
        <div class="flame-graph-error">
          Error loading frame state: {error()?.message}
        </div>
      </Show>

      <Show when={loading()}>
        <div class="flame-graph-loading">Loading frame tree...</div>
      </Show>

      <Show when={!loading() && !error()}>
        <main class="flame-graph-content">
          <FlameGraphVisualization
            state={state}
            viewSettings={viewSettings}
            selectedFrameID={selectedFrameID()}
            onFrameSelect={setSelectedFrameID}
            onFrameDoubleClick={actions.navigateToFrame}
          />

          <Show when={selectedFrame()}>
            <FrameDetailsPanel
              frame={selectedFrame()!}
              ancestors={actions.getAncestors(selectedFrameID()!)}
              onClose={() => setSelectedFrameID(null)}
            />
          </Show>
        </main>

        <footer class="flame-graph-controls">
          <FrameControlPanel
            activeFrame={state.frames[state.activeFrameID ?? '']}
            onPush={actions.pushFrame}
            onPop={actions.popFrame}
            onPlan={actions.planFrame}
            onActivate={actions.activateFrame}
          />
        </footer>
      </Show>
    </div>
  );
}
```

### 13.2 State Management Context

```typescript
// FlameGraphContext.tsx
import { createContext, useContext, createSignal } from 'solid-js';
import { createStore, produce } from 'solid-js/store';
import { useSDK } from '@/context/sdk';
import { useGlobalSDK } from '@/context/global-sdk';

interface FlameState {
  frames: Record<string, FrameNode>;
  activeFrameID: string | null;
  rootFrameIDs: string[];
  updatedAt: number;
}

interface FlameActions {
  loadState: () => Promise<void>;
  pushFrame: (goal: string) => Promise<void>;
  popFrame: (status: FrameStatus, summary?: string) => Promise<void>;
  planFrame: (goal: string) => Promise<void>;
  activateFrame: (frameID: string) => Promise<void>;
  invalidateFrame: (frameID: string, reason: string) => Promise<void>;
  navigateToFrame: (frameID: string) => Promise<void>;
  addArtifact: (artifact: string) => Promise<void>;
  addDecision: (decision: string) => Promise<void>;
  getAncestors: (frameID: string) => FrameNode[];
  getChildren: (frameID: string) => FrameNode[];
}

interface FlameContextValue {
  state: FlameState;
  actions: FlameActions;
  loading: () => boolean;
  error: () => Error | null;
}

const FlameContext = createContext<FlameContextValue>();

export function FlameProvider(props: { sessionID: string; children: any }) {
  const sdk = useSDK();
  const { event } = useGlobalSDK();

  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal<Error | null>(null);

  const [state, setState] = createStore<FlameState>({
    frames: {},
    activeFrameID: null,
    rootFrameIDs: [],
    updatedAt: 0,
  });

  // Subscribe to flame events
  event.listen((e) => {
    const payload = e.details;
    if (payload.type?.startsWith('flame.') ||
        (payload.type === 'tool.execute.after' &&
         payload.properties?.tool?.startsWith('flame_'))) {
      loadState(); // Refresh on any flame-related event
    }
  });

  async function callFlameTool(toolName: string, args: Record<string, any> = {}) {
    // Use experimental tool invocation API if available
    // Otherwise fall back to session prompt
    const result = await sdk.session.prompt({
      path: { id: props.sessionID },
      body: {
        noReply: true,
        parts: [{ type: 'text', text: `Use tool ${toolName} with args: ${JSON.stringify(args)}` }],
      },
    });
    return result;
  }

  async function loadState() {
    setLoading(true);
    setError(null);
    try {
      // Call flame_status tool to get complete state
      const result = await callFlameTool('flame_status');
      // Parse the tool response to extract state
      const parsed = parseFlameStatusResponse(result);
      setState(parsed);
    } catch (err) {
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }

  const actions: FlameActions = {
    loadState,

    async pushFrame(goal: string) {
      // Optimistic update
      const tempID = `temp_${Date.now()}`;
      setState(produce((s) => {
        s.frames[tempID] = {
          id: tempID,
          parentID: s.activeFrameID ?? undefined,
          childIDs: [],
          status: 'in_progress',
          goal,
          artifacts: [],
          decisions: [],
          createdAt: Date.now(),
          updatedAt: Date.now(),
          depth: 0,
          width: 1,
        };
        s.activeFrameID = tempID;
      }));

      try {
        await callFlameTool('flame_push', { goal });
        await loadState(); // Sync with server state
      } catch (err) {
        // Rollback
        setState(produce((s) => {
          delete s.frames[tempID];
        }));
        throw err;
      }
    },

    async popFrame(status: FrameStatus, summary?: string) {
      await callFlameTool('flame_pop', { status, summary });
      await loadState();
    },

    async planFrame(goal: string) {
      await callFlameTool('flame_plan', { goal });
      await loadState();
    },

    async activateFrame(frameID: string) {
      await callFlameTool('flame_activate', { frameID });
      await loadState();
    },

    async invalidateFrame(frameID: string, reason: string) {
      await callFlameTool('flame_invalidate', { frameID, reason });
      await loadState();
    },

    async navigateToFrame(frameID: string) {
      // Switch active frame to the selected frame
      await callFlameTool('flame_navigate', { frameID });
      await loadState();
    },

    async addArtifact(artifact: string) {
      await callFlameTool('flame_add_artifact', { artifact });
      await loadState();
    },

    async addDecision(decision: string) {
      await callFlameTool('flame_add_decision', { decision });
      await loadState();
    },

    getAncestors(frameID: string): FrameNode[] {
      const ancestors: FrameNode[] = [];
      let current = state.frames[frameID];
      while (current?.parentID) {
        const parent = state.frames[current.parentID];
        if (parent) {
          ancestors.push(parent);
          current = parent;
        } else break;
      }
      return ancestors;
    },

    getChildren(frameID: string): FrameNode[] {
      return Object.values(state.frames).filter(f => f.parentID === frameID);
    },
  };

  return (
    <FlameContext.Provider value={{ state, actions, loading, error }}>
      {props.children}
    </FlameContext.Provider>
  );
}

export function useFlameState() {
  const context = useContext(FlameContext);
  if (!context) throw new Error('useFlameState must be used within FlameProvider');
  return context;
}

function parseFlameStatusResponse(response: any): FlameState {
  // Parse the tool output which contains frame tree info
  // This parsing logic depends on exact flame_status output format
  // TODO: Implement based on actual response structure
  return {
    frames: {},
    activeFrameID: null,
    rootFrameIDs: [],
    updatedAt: Date.now(),
  };
}
```

### 13.3 D3 Flame Graph Integration

```typescript
// FlameGraphVisualization.tsx
import { onMount, onCleanup, createEffect } from 'solid-js';
import * as d3 from 'd3';
import { flamegraph } from 'd3-flame-graph';
import 'd3-flame-graph/dist/d3-flamegraph.css';

interface FlameGraphVisualizationProps {
  state: FlameState;
  viewSettings: {
    zoom: number;
    panX: number;
    panY: number;
    showPlanned: boolean;
    showInvalidated: boolean;
  };
  selectedFrameID: string | null;
  onFrameSelect: (frameID: string | null) => void;
  onFrameDoubleClick: (frameID: string) => void;
}

const STATUS_COLORS: Record<FrameStatus, string> = {
  planned: '#fbbf24',
  in_progress: '#3b82f6',
  completed: '#22c55e',
  failed: '#ef4444',
  blocked: '#f97316',
  invalidated: '#9ca3af',
};

const STATUS_BORDER_STYLES: Record<FrameStatus, string> = {
  planned: '2px dashed #fbbf24',
  in_progress: '2px solid #1d4ed8',
  completed: '2px solid #16a34a',
  failed: '2px solid #dc2626',
  blocked: '2px solid #ea580c',
  invalidated: '1px solid #6b7280',
};

export function FlameGraphVisualization(props: FlameGraphVisualizationProps) {
  let containerRef: HTMLDivElement | undefined;
  let chartInstance: any = null;
  let resizeObserver: ResizeObserver | null = null;

  onMount(() => {
    if (!containerRef) return;

    // Initialize D3 flame graph
    chartInstance = flamegraph()
      .cellHeight(24)
      .transitionDuration(300)
      .minFrameSize(5)
      .inverted(false) // Traditional flame graph (roots at top)
      .selfValue(false)
      .differential(false)
      .elided(false)
      .setColorMapper((d, originalColor) => {
        const frame = d.data;
        if (frame.id === props.selectedFrameID) {
          return d3.color(STATUS_COLORS[frame.status])?.brighter(0.3)?.toString() ?? originalColor;
        }
        return STATUS_COLORS[frame.status] ?? originalColor;
      })
      .onClick((d) => {
        if (d.data.id) {
          props.onFrameSelect(d.data.id);
        }
      })
      .onHover((d) => {
        // Show tooltip
        if (d) {
          showTooltip(d.data, d3.event);
        } else {
          hideTooltip();
        }
      });

    // Setup resize observer
    resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const width = entry.contentRect.width;
        if (chartInstance && width > 0) {
          chartInstance.width(width);
          updateChart();
        }
      }
    });
    resizeObserver.observe(containerRef);

    // Handle double-click for navigation
    d3.select(containerRef).on('dblclick', (event) => {
      const target = event.target as HTMLElement;
      const frameID = target.closest('[data-frame-id]')?.getAttribute('data-frame-id');
      if (frameID) {
        props.onFrameDoubleClick(frameID);
      }
    });
  });

  onCleanup(() => {
    resizeObserver?.disconnect();
  });

  // Update chart when state changes
  createEffect(() => {
    updateChart();
  });

  function updateChart() {
    if (!containerRef || !chartInstance) return;

    const hierarchyData = buildHierarchyData(
      props.state,
      props.viewSettings.showPlanned,
      props.viewSettings.showInvalidated
    );

    d3.select(containerRef)
      .datum(hierarchyData)
      .call(chartInstance);

    // Apply zoom/pan transforms
    const svg = d3.select(containerRef).select('svg');
    const g = svg.select('g');
    g.attr('transform', `translate(${props.viewSettings.panX}, ${props.viewSettings.panY}) scale(${props.viewSettings.zoom})`);
  }

  return (
    <div
      ref={containerRef}
      class="flame-graph-visualization"
      style={{
        width: '100%',
        height: '400px',
        overflow: 'hidden',
      }}
    />
  );
}

function buildHierarchyData(
  state: FlameState,
  showPlanned: boolean,
  showInvalidated: boolean
): d3.HierarchyNode<any> {
  const { frames, rootFrameIDs } = state;

  function shouldInclude(frame: FrameNode): boolean {
    if (!showPlanned && frame.status === 'planned') return false;
    if (!showInvalidated && frame.status === 'invalidated') return false;
    return true;
  }

  function buildNode(id: string): any {
    const frame = frames[id];
    if (!frame || !shouldInclude(frame)) return null;

    const children = Object.values(frames)
      .filter(f => f.parentID === id)
      .map(f => buildNode(f.id))
      .filter(Boolean);

    return {
      id: frame.id,
      name: truncateGoal(frame.goal, 50),
      status: frame.status,
      value: Math.max(1, children.length || 1),
      children: children.length > 0 ? children : undefined,
      // Additional metadata for rendering
      goal: frame.goal,
      summary: frame.summary,
      artifacts: frame.artifacts,
      decisions: frame.decisions,
      createdAt: frame.createdAt,
    };
  }

  const rootNodes = rootFrameIDs
    .map(buildNode)
    .filter(Boolean);

  // Create a virtual root if multiple roots exist
  const root = rootNodes.length === 1
    ? rootNodes[0]
    : {
        id: '__root__',
        name: 'Flame Context',
        status: 'in_progress' as FrameStatus,
        value: rootNodes.reduce((sum, n) => sum + n.value, 0),
        children: rootNodes,
      };

  return d3.hierarchy(root)
    .sum(d => d.value)
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
}

function truncateGoal(goal: string, maxLength: number): string {
  if (goal.length <= maxLength) return goal;
  return goal.substring(0, maxLength - 3) + '...';
}

// Tooltip helpers
let tooltipElement: HTMLDivElement | null = null;

function showTooltip(frame: any, event: MouseEvent) {
  if (!tooltipElement) {
    tooltipElement = document.createElement('div');
    tooltipElement.className = 'flame-graph-tooltip';
    document.body.appendChild(tooltipElement);
  }

  tooltipElement.innerHTML = `
    <div class="tooltip-header">
      <span class="tooltip-status ${frame.status}">${frame.status}</span>
      <span class="tooltip-goal">${frame.goal}</span>
    </div>
    ${frame.summary ? `<div class="tooltip-summary">${frame.summary}</div>` : ''}
    ${frame.artifacts?.length ? `<div class="tooltip-artifacts">Artifacts: ${frame.artifacts.length}</div>` : ''}
  `;

  tooltipElement.style.left = `${event.pageX + 10}px`;
  tooltipElement.style.top = `${event.pageY + 10}px`;
  tooltipElement.style.display = 'block';
}

function hideTooltip() {
  if (tooltipElement) {
    tooltipElement.style.display = 'none';
  }
}
```

---

## 14. CSS Styling Specifications

```css
/* flame.css */

/* Main Panel Container */
.flame-graph-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--bg-primary);
  border-left: 1px solid var(--border-color);
}

.flame-graph-panel[data-position="sidebar"] {
  width: 400px;
  min-width: 300px;
  max-width: 600px;
  resize: horizontal;
}

.flame-graph-panel[data-position="bottom"] {
  height: 300px;
  min-height: 200px;
  max-height: 500px;
  resize: vertical;
}

/* Header */
.flame-graph-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border-color);
  background: var(--bg-secondary);
}

.flame-graph-header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.flame-graph-toolbar {
  display: flex;
  gap: 8px;
  align-items: center;
}

.flame-graph-toolbar button {
  padding: 4px 8px;
  font-size: 12px;
  border-radius: 4px;
  border: 1px solid var(--border-color);
  background: var(--bg-primary);
  cursor: pointer;
}

.flame-graph-toolbar button:hover {
  background: var(--bg-hover);
}

/* Visualization Container */
.flame-graph-visualization {
  flex: 1;
  overflow: hidden;
  position: relative;
}

.flame-graph-visualization svg {
  width: 100%;
  height: 100%;
}

/* Frame rectangles */
.flame-graph-visualization rect {
  stroke: var(--border-color);
  stroke-width: 1px;
  cursor: pointer;
  transition: opacity 0.2s, stroke-width 0.2s;
}

.flame-graph-visualization rect:hover {
  stroke-width: 2px;
  opacity: 0.9;
}

.flame-graph-visualization rect.selected {
  stroke: var(--accent-color);
  stroke-width: 3px;
}

.flame-graph-visualization rect.active {
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.8; }
}

/* Frame labels */
.flame-graph-visualization text {
  font-size: 11px;
  font-family: var(--font-mono);
  fill: var(--text-on-color);
  pointer-events: none;
  text-anchor: middle;
  dominant-baseline: central;
}

/* Tooltip */
.flame-graph-tooltip {
  position: absolute;
  z-index: 1000;
  padding: 12px;
  background: var(--bg-tooltip);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  max-width: 300px;
  display: none;
}

.tooltip-header {
  display: flex;
  gap: 8px;
  align-items: center;
  margin-bottom: 8px;
}

.tooltip-status {
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
}

.tooltip-status.in_progress { background: #3b82f6; color: white; }
.tooltip-status.completed { background: #22c55e; color: white; }
.tooltip-status.planned { background: #fbbf24; color: black; }
.tooltip-status.failed { background: #ef4444; color: white; }
.tooltip-status.blocked { background: #f97316; color: white; }
.tooltip-status.invalidated { background: #9ca3af; color: white; }

.tooltip-goal {
  font-weight: 500;
  color: var(--text-primary);
}

.tooltip-summary {
  font-size: 12px;
  color: var(--text-secondary);
  margin-top: 4px;
}

/* Details Panel */
.frame-details-panel {
  border-top: 1px solid var(--border-color);
  padding: 16px;
  background: var(--bg-secondary);
  max-height: 300px;
  overflow-y: auto;
}

.frame-details-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 12px;
}

.frame-details-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.frame-details-section {
  margin-bottom: 12px;
}

.frame-details-section h4 {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-tertiary);
  margin: 0 0 4px 0;
}

.frame-details-section ul {
  margin: 0;
  padding-left: 16px;
}

.frame-details-section li {
  font-size: 12px;
  color: var(--text-secondary);
  margin-bottom: 4px;
}

/* Control Panel */
.frame-control-panel {
  display: flex;
  gap: 8px;
  padding: 12px 16px;
  border-top: 1px solid var(--border-color);
  background: var(--bg-secondary);
}

.frame-control-panel button {
  flex: 1;
  padding: 8px 12px;
  font-size: 12px;
  font-weight: 500;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  transition: background 0.2s;
}

.frame-control-panel button.primary {
  background: var(--accent-color);
  color: white;
}

.frame-control-panel button.primary:hover {
  background: var(--accent-color-hover);
}

.frame-control-panel button.secondary {
  background: var(--bg-primary);
  border: 1px solid var(--border-color);
  color: var(--text-primary);
}

.frame-control-panel button.secondary:hover {
  background: var(--bg-hover);
}

/* Loading and Error States */
.flame-graph-loading,
.flame-graph-error {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 200px;
  color: var(--text-secondary);
}

.flame-graph-error {
  color: var(--error-color);
}
```

---

## 15. Testing Strategy

### 15.1 Unit Tests

```typescript
// FlameGraphContext.test.ts
import { describe, it, expect, vi } from 'vitest';
import { renderHook } from '@solidjs/testing-library';
import { FlameProvider, useFlameState } from './FlameGraphContext';

describe('FlameGraphContext', () => {
  it('initializes with empty state', () => {
    const { result } = renderHook(() => useFlameState(), {
      wrapper: (props) => <FlameProvider sessionID="test">{props.children}</FlameProvider>,
    });

    expect(result.state.frames).toEqual({});
    expect(result.state.activeFrameID).toBeNull();
    expect(result.state.rootFrameIDs).toEqual([]);
  });

  it('loads state from plugin', async () => {
    const mockSDK = createMockSDK();
    const { result } = renderHook(() => useFlameState(), {
      wrapper: (props) => (
        <SDKProvider value={mockSDK}>
          <FlameProvider sessionID="test">{props.children}</FlameProvider>
        </SDKProvider>
      ),
    });

    await result.actions.loadState();
    expect(mockSDK.session.prompt).toHaveBeenCalled();
  });

  it('applies optimistic updates on push', async () => {
    const { result } = renderHook(() => useFlameState(), {
      wrapper: createTestWrapper(),
    });

    await result.actions.loadState();

    // Start push
    const pushPromise = result.actions.pushFrame('New task');

    // Optimistic update should be applied immediately
    expect(Object.keys(result.state.frames).length).toBeGreaterThan(0);

    await pushPromise;
  });
});

// buildHierarchyData.test.ts
describe('buildHierarchyData', () => {
  it('builds correct hierarchy from flat frames', () => {
    const state: FlameState = {
      frames: {
        'root': { id: 'root', status: 'in_progress', goal: 'Root', childIDs: ['a', 'b'], ... },
        'a': { id: 'a', parentID: 'root', status: 'completed', goal: 'A', childIDs: [], ... },
        'b': { id: 'b', parentID: 'root', status: 'planned', goal: 'B', childIDs: [], ... },
      },
      activeFrameID: 'a',
      rootFrameIDs: ['root'],
      updatedAt: Date.now(),
    };

    const hierarchy = buildHierarchyData(state, true, true);

    expect(hierarchy.data.id).toBe('root');
    expect(hierarchy.children?.length).toBe(2);
    expect(hierarchy.children?.[0].data.id).toBe('a');
    expect(hierarchy.children?.[1].data.id).toBe('b');
  });

  it('filters out planned frames when showPlanned is false', () => {
    const state = createStateWithPlannedFrames();
    const hierarchy = buildHierarchyData(state, false, true);

    const plannedNodes = findNodesByStatus(hierarchy, 'planned');
    expect(plannedNodes.length).toBe(0);
  });
});
```

### 15.2 Integration Tests

```typescript
// FlameGraphPanel.integration.test.ts
import { describe, it, expect } from 'vitest';
import { render, fireEvent, waitFor } from '@solidjs/testing-library';
import { FlameGraphPanel } from './FlameGraphPanel';

describe('FlameGraphPanel Integration', () => {
  it('renders flame graph from plugin state', async () => {
    const { container, getByText } = render(() => (
      <TestProviders>
        <FlameGraphPanel sessionID="test-session" position="sidebar" />
      </TestProviders>
    ));

    await waitFor(() => {
      expect(getByText('Root Frame')).toBeInTheDocument();
    });

    // Verify frame rectangles are rendered
    const rects = container.querySelectorAll('.flame-graph-visualization rect');
    expect(rects.length).toBeGreaterThan(0);
  });

  it('opens details panel on frame click', async () => {
    const { container, getByText } = render(() => (
      <TestProviders>
        <FlameGraphPanel sessionID="test-session" position="sidebar" />
      </TestProviders>
    ));

    await waitFor(() => getByText('Root Frame'));

    const frameRect = container.querySelector('[data-frame-id="root"]');
    fireEvent.click(frameRect!);

    await waitFor(() => {
      expect(getByText('Frame Details')).toBeInTheDocument();
    });
  });

  it('creates new frame on push', async () => {
    const mockPush = vi.fn().mockResolvedValue({ success: true });
    const { getByText, getByPlaceholderText } = render(() => (
      <TestProviders onPush={mockPush}>
        <FlameGraphPanel sessionID="test-session" position="sidebar" />
      </TestProviders>
    ));

    fireEvent.click(getByText('New Frame'));

    const input = getByPlaceholderText('Frame goal');
    fireEvent.change(input, { target: { value: 'New task' } });
    fireEvent.click(getByText('Create'));

    await waitFor(() => {
      expect(mockPush).toHaveBeenCalledWith({ goal: 'New task' });
    });
  });
});
```

### 15.3 Visual Regression Tests

```typescript
// FlameGraph.visual.test.ts
import { test, expect } from '@playwright/test';

test.describe('Flame Graph Visual', () => {
  test('matches snapshot with typical frame tree', async ({ page }) => {
    await page.goto('/test/flame-graph?fixture=typical-tree');
    await page.waitForSelector('.flame-graph-visualization svg');

    const flameGraph = await page.locator('.flame-graph-visualization');
    await expect(flameGraph).toHaveScreenshot('typical-tree.png');
  });

  test('matches snapshot with deep hierarchy', async ({ page }) => {
    await page.goto('/test/flame-graph?fixture=deep-hierarchy');
    await page.waitForSelector('.flame-graph-visualization svg');

    const flameGraph = await page.locator('.flame-graph-visualization');
    await expect(flameGraph).toHaveScreenshot('deep-hierarchy.png');
  });

  test('matches snapshot with mixed statuses', async ({ page }) => {
    await page.goto('/test/flame-graph?fixture=mixed-status');
    await page.waitForSelector('.flame-graph-visualization svg');

    const flameGraph = await page.locator('.flame-graph-visualization');
    await expect(flameGraph).toHaveScreenshot('mixed-status.png');
  });
});
```

---

## 16. Performance Considerations

### 16.1 Rendering Optimization

1. **Virtual DOM Diff**: D3's data join pattern minimizes DOM updates
2. **Memoization**: Cache hierarchy computations when state is unchanged
3. **Debounced Resize**: Throttle resize handler to avoid excessive re-renders
4. **Lazy Tooltip**: Only render tooltip DOM when hovering

### 16.2 Large Tree Handling

For trees with 100+ frames:

1. **Virtualization**: Only render visible frames in viewport
2. **Collapse by Default**: Auto-collapse completed subtrees
3. **Progressive Loading**: Load children on demand
4. **Level-of-Detail**: Show summaries at zoomed-out levels

### 16.3 Memory Management

```typescript
// Cleanup pattern
onCleanup(() => {
  // Remove D3 event listeners
  d3.select(containerRef).on('.zoom', null);
  d3.select(containerRef).on('.drag', null);

  // Clear tooltip
  if (tooltipElement?.parentNode) {
    tooltipElement.parentNode.removeChild(tooltipElement);
    tooltipElement = null;
  }

  // Disconnect observers
  resizeObserver?.disconnect();
});
```

---

## 17. Accessibility

### 17.1 Keyboard Navigation

| Key | Action |
|-----|--------|
| `Tab` | Move focus between frames (depth-first) |
| `Shift+Tab` | Move focus backwards |
| `Enter` | Select focused frame, open details |
| `Space` | Toggle frame expansion |
| `Escape` | Close details panel, clear selection |
| `Arrow keys` | Navigate within level or between parent/child |

### 17.2 Screen Reader Support

```tsx
// ARIA attributes for flame graph
<svg role="tree" aria-label="Frame call stack visualization">
  <g
    role="treeitem"
    aria-label={`Frame: ${frame.goal}, Status: ${frame.status}`}
    aria-expanded={hasChildren}
    aria-selected={isSelected}
    tabIndex={isFocused ? 0 : -1}
  >
    <rect ... />
    <text ... />
  </g>
</svg>
```

### 17.3 Color Contrast

All status colors meet WCAG AA contrast requirements:
- Text on colored backgrounds uses appropriate contrast
- Alternative patterns (stripes, dots) for colorblind users
- Focus indicators visible regardless of color

---

## Changelog

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-24 | Claude | Initial draft |
| 1.1 | 2025-12-24 | Claude | Added detailed component specs, CSS, testing strategy, performance, accessibility |

