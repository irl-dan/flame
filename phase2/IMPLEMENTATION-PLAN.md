# Phase 2 Implementation Plan: Flame Graph Visualization UI

**Version**: 1.0
**Date**: 2025-12-24
**Status**: APPROVED FOR IMPLEMENTATION

---

## 1. Executive Summary

### 1.1 Project Goal

Build an interactive web-based visualization that renders the Flame Graph context tree as a navigable flame graph within the OpenCode web UI. This Phase 2 implementation transforms the CLI-only Phase 1 plugin into a visual, intuitive experience for managing frame-based context.

### 1.2 Scope

Phase 2 delivers:
- **Flame Graph Panel**: Right sidebar in OpenCode showing frame hierarchy visualization
- **Interactive Operations**: Push, pop, plan, activate, and invalidate frames via UI
- **Real-time Updates**: SSE-based synchronization with frame state changes
- **Frame Details**: Detailed view of goals, artifacts, decisions, and summaries
- **Keyboard Navigation**: Full keyboard accessibility with modifier-key shortcuts

### 1.3 Approved Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Deployment | Integrated panel within OpenCode web UI | Single deployment, shared context |
| API Strategy | Tool execution via SDK + REST state endpoint | Works now, direct tool endpoint later |
| Visualization | Custom D3 implementation (not d3-flame-graph) | Maximum control for frame semantics |
| Panel Position | Right sidebar, resizable | Persistent alongside chat |
| Timeline | 10 weeks balanced approach | Core features + polish |
| New Tools | Add `flame_get_state` tool | UI-optimized state retrieval |
| Frame Width | Equal width for siblings | Start simple |
| Minimap | Defer to Phase 3 | Keep scope focused |
| Keyboard Shortcuts | Modifier keys (Cmd+Enter=push, Cmd+Backspace=pop) | Consistent with OpenCode |
| Tool Invocation | Add direct tool invocation endpoint | Cleaner, faster |

### 1.4 Success Criteria

1. **Functional**: Users can visualize, navigate, and manage the frame tree entirely through UI
2. **Performance**: Initial render <2s, real-time updates <100ms latency
3. **Reliability**: 99%+ operation success rate with graceful error handling
4. **Accessibility**: Full keyboard navigation, WCAG AA color contrast
5. **Integration**: Seamless integration with existing OpenCode app architecture

---

## 2. Prerequisites

### 2.1 Phase 1 Plugin (Required)

The Phase 1 Flame plugin must be installed and validated:

**Location**: `/Users/sl/code/flame/.opencode/plugin/flame.ts`

**Validation Status**: 97.5% pass rate (78/80 tests) - see `/Users/sl/code/flame/phase1/final-validation/VALIDATION-RESULTS.md`

**Required Capabilities**:
- [x] Frame State Manager with file persistence
- [x] 28 flame_* tools implemented
- [x] Frame statuses: planned, in_progress, completed, failed, blocked, invalidated
- [x] Context assembly with token budget
- [x] Compaction integration
- [x] Planning tools (flame_plan, flame_plan_children, flame_activate)
- [x] Invalidation cascade (flame_invalidate)

### 2.2 OpenCode Setup (Required)

**OpenCode Repository**: `/Users/sl/code/opencode/`

**Required Components**:
- `packages/app/` - Web application (SolidJS)
- `packages/opencode/` - Server and core logic
- `packages/ui/` - Shared UI components
- `packages/sdk/` - Client SDK

**Server Version**: Must support:
- SSE event streaming via `/global/event`
- Tool execution via existing session APIs
- Hono-based HTTP routing

### 2.3 Development Environment

| Requirement | Minimum Version |
|-------------|-----------------|
| Node.js | 18.0+ |
| Bun | 1.0+ |
| TypeScript | 5.0+ |
| Modern Browser | Chrome 90+, Firefox 88+, Safari 14+ |

### 2.4 New Dependencies to Add

```json
{
  "dependencies": {
    "d3": "^7.8.5",
    "d3-hierarchy": "^3.1.2",
    "d3-selection": "^3.0.0",
    "d3-transition": "^3.0.1",
    "d3-zoom": "^3.0.0"
  },
  "devDependencies": {
    "@types/d3": "^7.4.3"
  }
}
```

---

## 3. Phased Implementation

### Phase 2.0: Foundation & Project Setup
**Duration**: Week 1
**Goal**: Establish project structure, integrate D3, render static flame graph

#### 3.0.1 Tasks

1. **Create Flame module directory structure**
   ```
   packages/app/src/components/flame/
     index.tsx                  # Module exports
     FlamePanel.tsx             # Main panel container
     FlameProvider.tsx          # Context provider
     types.ts                   # TypeScript interfaces
   ```

2. **Add D3 dependencies to packages/app/package.json**
   ```bash
   cd packages/app && bun add d3 && bun add -d @types/d3
   ```

3. **Create TypeScript types matching Phase 1 plugin**
   ```typescript
   // types.ts
   export type FrameStatus =
     | "planned"
     | "in_progress"
     | "completed"
     | "failed"
     | "blocked"
     | "invalidated"

   export interface FrameMetadata {
     sessionID: string
     parentSessionID?: string
     status: FrameStatus
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

   export interface FlameState {
     version: number
     frames: Record<string, FrameMetadata>
     activeFrameID?: string
     rootFrameIDs: string[]
     updatedAt: number
   }
   ```

4. **Create FlameProvider context with mock data**
   - Initialize SolidJS store for flame state
   - Create tree computation utilities
   - Provide actions interface (stubs)

5. **Create FlamePanel skeleton component**
   - Basic panel layout with header
   - Integration point with OpenCode layout context
   - Empty SVG container for D3

6. **Implement static D3 flame graph render**
   - Convert frame tree to D3 hierarchy
   - Render SVG rectangles with status colors
   - Basic frame labels

#### 3.0.2 Files to Create

| File | Purpose |
|------|---------|
| `packages/app/src/components/flame/index.tsx` | Module exports |
| `packages/app/src/components/flame/types.ts` | TypeScript interfaces |
| `packages/app/src/components/flame/FlameProvider.tsx` | State management context |
| `packages/app/src/components/flame/FlamePanel.tsx` | Main panel container |
| `packages/app/src/components/flame/FlameGraph.tsx` | D3 visualization component |
| `packages/app/src/components/flame/constants.ts` | Color schemes, dimensions |

#### 3.0.3 Verification Criteria

- [ ] `bun run build` succeeds with new dependencies
- [ ] FlamePanel renders without errors in browser
- [ ] Static mock data renders as colored rectangles
- [ ] Frame labels display correctly
- [ ] Status colors match specification:
  - planned: #9CA3AF (gray-400)
  - in_progress: #3B82F6 (blue-500)
  - completed: #22C55E (green-500)
  - failed: #EF4444 (red-500)
  - blocked: #F59E0B (amber-500)
  - invalidated: #6B7280 (gray-500) with 50% opacity

#### 3.0.4 Dependencies

- None (first phase)

---

### Phase 2.1: Data Integration
**Duration**: Week 2
**Goal**: Connect UI to live plugin state via API

#### 3.1.1 Tasks

1. **Add flame_get_state tool to Phase 1 plugin**
   ```typescript
   // Add to flame.ts
   flame_get_state: tool({
     description: "Get complete flame state for UI rendering",
     args: {},
     async execute() {
       const state = await manager.loadState()
       return {
         version: state.version,
         frames: state.frames,
         activeFrameID: state.activeFrameID,
         rootFrameIDs: state.rootFrameIDs,
         updatedAt: state.updatedAt,
       }
     },
   }),
   ```

2. **Add /flame/state endpoint to OpenCode server**
   ```typescript
   // Add to server.ts
   .get(
     "/flame/state",
     describeRoute({
       summary: "Get flame graph state",
       operationId: "flame.state",
       responses: {
         200: {
           content: {
             "application/json": {
               schema: resolver(FlameStateSchema),
             },
           },
         },
       },
     }),
     async (c) => {
       const stateFile = path.join(
         Instance.directory,
         ".opencode",
         "flame",
         "state.json"
       )
       try {
         const content = await fs.promises.readFile(stateFile, "utf-8")
         return c.json(JSON.parse(content))
       } catch (error) {
         return c.json({
           version: 1,
           frames: {},
           rootFrameIDs: [],
           updatedAt: Date.now(),
         })
       }
     }
   )
   ```

3. **Create API client in FlameProvider**
   ```typescript
   async function fetchFlameState(): Promise<FlameState> {
     const response = await fetch(`${sdk.url}/flame/state?directory=${sdk.directory}`)
     if (!response.ok) {
       throw new Error(`Failed to fetch flame state: ${response.status}`)
     }
     return response.json()
   }
   ```

4. **Implement state loading on mount**
   - Call fetchFlameState on FlameProvider mount
   - Handle loading and error states
   - Transform API response to UI state

5. **Create tree computation utilities**
   ```typescript
   // utils/tree.ts
   export function buildHierarchy(
     frames: Record<string, FrameMetadata>,
     rootFrameIDs: string[]
   ): D3HierarchyNode | null

   export function getAncestors(
     frames: Record<string, FrameMetadata>,
     frameID: string
   ): FrameMetadata[]

   export function getChildren(
     frames: Record<string, FrameMetadata>,
     frameID: string
   ): FrameMetadata[]
   ```

6. **Replace mock data with live state**
   - Update FlameGraph to use live state
   - Handle empty state gracefully
   - Show "No frames" message when appropriate

#### 3.1.2 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `/Users/sl/code/flame/.opencode/plugin/flame.ts` | Modify | Add flame_get_state tool |
| `packages/opencode/src/server/server.ts` | Modify | Add /flame/state endpoint |
| `packages/app/src/components/flame/FlameProvider.tsx` | Modify | Add API integration |
| `packages/app/src/components/flame/utils/tree.ts` | Create | Tree utilities |
| `packages/app/src/components/flame/utils/api.ts` | Create | API client functions |

#### 3.1.3 Verification Criteria

- [ ] `/flame/state` endpoint returns valid JSON
- [ ] FlameProvider fetches state on mount
- [ ] Live frame tree renders in UI
- [ ] Empty state shows appropriate message
- [ ] Error states display error message
- [ ] Loading state shows spinner
- [ ] Hierarchy computation produces correct tree structure

#### 3.1.4 Dependencies

- Phase 2.0 complete
- Phase 1 plugin accessible

---

### Phase 2.2: Visualization Core
**Duration**: Weeks 3-4
**Goal**: Full flame graph rendering with navigation, zoom, and status styling

#### 3.2.1 Tasks (Week 3)

1. **Implement D3 partition layout**
   ```typescript
   // FlameGraph.tsx
   const partition = d3.partition<FrameNode>()
     .size([innerWidth, innerHeight])
     .padding(2)

   const root = d3.hierarchy(treeData, d => d.children)
     .sum(d => 1) // Equal width for siblings

   partition(root)
   ```

2. **Create Frame component for each rectangle**
   ```typescript
   interface FrameRectProps {
     node: d3.HierarchyRectangularNode<FrameNode>
     isActive: boolean
     isSelected: boolean
     onSelect: (id: string) => void
     onDoubleClick: (id: string) => void
   }
   ```

3. **Implement status-based styling**
   - Background color from STATUS_COLORS
   - Border style for active frame (pulsing)
   - Border style for selected frame (bold)
   - Opacity for invalidated frames
   - Dashed border for planned frames

4. **Add frame labels with truncation**
   - Calculate available width
   - Truncate goal text with ellipsis
   - Hide label if width < 40px

5. **Create connection lines between frames**
   - Parent-child vertical lines
   - Sibling horizontal spacing
   - Different line styles for planned vs active

#### 3.2.2 Tasks (Week 4)

6. **Implement pan and zoom**
   ```typescript
   const zoom = d3.zoom<SVGSVGElement, unknown>()
     .scaleExtent([0.5, 4])
     .on("zoom", (event) => {
       g.attr("transform", event.transform)
     })

   svg.call(zoom)
   ```

7. **Add zoom controls**
   - Zoom in button (+)
   - Zoom out button (-)
   - Reset view button
   - Current zoom level indicator

8. **Implement responsive layout**
   - ResizeObserver for container
   - Recalculate layout on resize
   - Debounce resize handler

9. **Add visual transitions**
   - Frame status change transitions
   - Zoom/pan smooth transitions
   - Layout change transitions

10. **Create legend component**
    - Status color legend
    - Keyboard shortcuts hint
    - Toggle visibility

#### 3.2.3 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `packages/app/src/components/flame/FlameGraph.tsx` | Modify | Core visualization |
| `packages/app/src/components/flame/FrameRect.tsx` | Create | Individual frame component |
| `packages/app/src/components/flame/Connection.tsx` | Create | Connection lines |
| `packages/app/src/components/flame/ZoomControls.tsx` | Create | Zoom UI controls |
| `packages/app/src/components/flame/Legend.tsx` | Create | Status legend |
| `packages/app/src/components/flame/hooks/useZoom.ts` | Create | Zoom behavior hook |
| `packages/app/src/components/flame/hooks/useLayout.ts` | Create | Layout computation hook |
| `packages/app/src/components/flame/styles.css` | Create | Component styles |

#### 3.2.4 Verification Criteria

- [ ] Flame graph renders with correct layout
- [ ] All frame statuses display correct colors
- [ ] Active frame has visible pulsing border
- [ ] Pan and zoom work smoothly (60fps)
- [ ] Zoom controls function correctly
- [ ] Reset view returns to default state
- [ ] Layout updates on container resize
- [ ] Transitions are smooth (300ms)
- [ ] Legend displays all statuses

#### 3.2.5 Dependencies

- Phase 2.1 complete

---

### Phase 2.3: Interactions & Details
**Duration**: Weeks 5-6
**Goal**: Frame selection, details panel, tooltips, and keyboard navigation

#### 3.3.1 Tasks (Week 5)

1. **Implement frame selection**
   ```typescript
   const [selectedFrameID, setSelectedFrameID] = createSignal<string | null>(null)

   function handleFrameClick(frameID: string) {
     setSelectedFrameID(frameID)
   }
   ```

2. **Create hover tooltip**
   ```typescript
   interface TooltipContent {
     goal: string
     status: FrameStatus
     duration: string
     artifactCount: number
     decisionCount: number
   }
   ```

3. **Create FrameDetails panel**
   - Goal display with edit button
   - Status badge with change dropdown
   - Created/updated timestamps
   - Duration display

4. **Add Artifacts section**
   - List existing artifacts
   - "Add artifact" button
   - Remove artifact (x) button

5. **Add Decisions section**
   - List existing decisions
   - "Add decision" button
   - Remove decision (x) button

6. **Add Summary section**
   - Show compactionSummary if exists
   - "Generate summary" button
   - Collapsible for long summaries

#### 3.3.2 Tasks (Week 6)

7. **Implement keyboard navigation**
   ```typescript
   // Register keyboard shortcuts
   command.register(() => [
     {
       id: "flame.toggle",
       title: "Toggle Flame Graph",
       keybind: "mod+shift+f",
       slash: "flame",
       onSelect: () => layout.flame.toggle(),
     },
     {
       id: "flame.push",
       title: "Push new frame",
       keybind: "mod+enter",
       onSelect: () => openPushDialog(),
     },
     {
       id: "flame.pop",
       title: "Complete current frame",
       keybind: "mod+backspace",
       onSelect: () => openPopDialog(),
     },
   ])
   ```

8. **Implement arrow key navigation**
   - Up/Down: Navigate parent/child
   - Left/Right: Navigate siblings
   - Enter: Select frame
   - Escape: Deselect

9. **Create context menu**
   - Push child frame
   - Plan child frame
   - Edit goal
   - Add artifact
   - Add decision
   - Complete frame
   - Invalidate frame
   - Copy frame ID
   - View session

10. **Integrate with OpenCode layout**
    ```typescript
    // Add to layout context
    flame: {
      opened: createMemo(() => store.flame?.opened ?? false),
      width: createMemo(() => store.flame?.width ?? 320),
      toggle() { setStore("flame", "opened", x => !x) },
      open() { setStore("flame", "opened", true) },
      close() { setStore("flame", "opened", false) },
      resize(width: number) { setStore("flame", "width", width) },
    }
    ```

#### 3.3.3 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `packages/app/src/components/flame/FrameDetails.tsx` | Create | Details panel |
| `packages/app/src/components/flame/FrameDetails/Header.tsx` | Create | Panel header |
| `packages/app/src/components/flame/FrameDetails/Artifacts.tsx` | Create | Artifacts section |
| `packages/app/src/components/flame/FrameDetails/Decisions.tsx` | Create | Decisions section |
| `packages/app/src/components/flame/FrameDetails/Summary.tsx` | Create | Summary section |
| `packages/app/src/components/flame/Tooltip.tsx` | Create | Hover tooltip |
| `packages/app/src/components/flame/ContextMenu.tsx` | Create | Right-click menu |
| `packages/app/src/components/flame/hooks/useKeyboard.ts` | Create | Keyboard navigation |
| `packages/app/src/context/layout.tsx` | Modify | Add flame panel state |
| `packages/app/src/pages/session.tsx` | Modify | Integrate flame panel |

#### 3.3.4 Verification Criteria

- [ ] Clicking frame selects it and opens details
- [ ] Hover shows tooltip with frame info
- [ ] Details panel shows all frame metadata
- [ ] Artifacts list displays and is editable
- [ ] Decisions list displays and is editable
- [ ] Summary displays when available
- [ ] Cmd+Shift+F toggles panel visibility
- [ ] Arrow keys navigate between frames
- [ ] Context menu appears on right-click
- [ ] All context menu actions work
- [ ] Panel resizes with drag handle

#### 3.3.5 Dependencies

- Phase 2.2 complete

---

### Phase 2.4: Frame Operations
**Duration**: Week 7
**Goal**: Push, pop, plan, activate, invalidate through UI

#### 3.4.1 Tasks

1. **Add direct tool invocation endpoint**
   ```typescript
   // Add to server.ts
   .post(
     "/flame/tool",
     describeRoute({
       summary: "Execute flame tool directly",
       operationId: "flame.tool",
       responses: { 200: { ... } },
     }),
     validator("json", z.object({
       tool: z.string(),
       args: z.record(z.any()),
     })),
     async (c) => {
       const { tool, args } = c.req.valid("json")
       // Load plugin and execute tool
       const result = await Plugin.executeTool(`flame_${tool}`, args)
       return c.json(result)
     }
   )
   ```

2. **Create PushFrame dialog**
   ```typescript
   interface PushFrameDialogProps {
     parentFrame?: FrameMetadata
     onClose: () => void
     onSubmit: (goal: string) => Promise<void>
   }
   ```
   - Goal text input
   - Parent frame display
   - "Start immediately" checkbox vs "Plan for later"
   - Cancel/Create buttons

3. **Create PopFrame dialog**
   ```typescript
   interface PopFrameDialogProps {
     frame: FrameMetadata
     onClose: () => void
     onSubmit: (status: FrameStatus, summary?: string) => Promise<void>
   }
   ```
   - Status radio buttons (completed, failed, blocked)
   - Summary text area (optional)
   - "Generate AI summary" checkbox
   - Cancel/Complete buttons

4. **Create PlanChildren dialog**
   - List of goal inputs
   - Add/remove child goals
   - Bulk create planned frames

5. **Implement optimistic updates**
   ```typescript
   async function pushFrame(goal: string) {
     // Optimistic: Add temp frame
     const tempID = `temp_${Date.now()}`
     setFlameState(produce(s => {
       s.frames[tempID] = {
         sessionID: tempID,
         status: "in_progress",
         goal,
         // ...
       }
     }))

     try {
       await executeFlameAction("push", { goal })
       await refresh() // Sync with server
     } catch (error) {
       // Rollback
       setFlameState(produce(s => {
         delete s.frames[tempID]
       }))
       throw error
     }
   }
   ```

6. **Wire up all operations**
   - Push: Creates child of active/selected frame
   - Pop: Completes active frame
   - Plan: Creates planned frame
   - Activate: Starts planned frame
   - Invalidate: Shows reason input, cascades

7. **Add inline goal editing**
   - Double-click goal to edit
   - Escape to cancel, Enter to save
   - Auto-save on blur

#### 3.4.2 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `packages/opencode/src/server/server.ts` | Modify | Add /flame/tool endpoint |
| `packages/app/src/components/flame/dialogs/PushFrame.tsx` | Create | Push dialog |
| `packages/app/src/components/flame/dialogs/PopFrame.tsx` | Create | Pop dialog |
| `packages/app/src/components/flame/dialogs/PlanChildren.tsx` | Create | Plan children dialog |
| `packages/app/src/components/flame/dialogs/InvalidateFrame.tsx` | Create | Invalidate dialog |
| `packages/app/src/components/flame/dialogs/EditGoal.tsx` | Create | Inline goal editor |
| `packages/app/src/components/flame/FlameProvider.tsx` | Modify | Add action implementations |
| `packages/app/src/components/flame/utils/api.ts` | Modify | Add tool execution |

#### 3.4.3 Verification Criteria

- [ ] /flame/tool endpoint executes tools correctly
- [ ] Push dialog creates new frame
- [ ] New frame appears in visualization immediately (optimistic)
- [ ] Pop dialog completes frame with selected status
- [ ] Plan dialog creates planned children
- [ ] Activate converts planned to in_progress
- [ ] Invalidate cascades to descendants
- [ ] Inline goal editing saves changes
- [ ] Optimistic updates rollback on error
- [ ] All operations show success/error notifications

#### 3.4.4 Dependencies

- Phase 2.3 complete

---

### Phase 2.5: Real-time Updates
**Duration**: Week 8
**Goal**: SSE subscription, live updates, event handling

#### 3.5.1 Tasks

1. **Add flame events to Phase 1 plugin**
   ```typescript
   // Add to flame.ts
   import { Bus } from "@opencode-ai/plugin"

   const FlameEvents = {
     FrameCreated: "flame.frame.created",
     FrameUpdated: "flame.frame.updated",
     FrameCompleted: "flame.frame.completed",
     FrameActivated: "flame.frame.activated",
     FrameInvalidated: "flame.frame.invalidated",
     StateChanged: "flame.state.changed",
   }

   // In createFrame method:
   Bus.publish(FlameEvents.FrameCreated, { frame, parentID })

   // In completeFrame method:
   Bus.publish(FlameEvents.FrameCompleted, { frame, status })
   ```

2. **Subscribe to SSE events in FlameProvider**
   ```typescript
   createEffect(() => {
     const cleanup = sdk.event.on("flame.frame.created", (event) => {
       refresh()
     })

     sdk.event.on("flame.frame.updated", (event) => {
       refresh()
     })

     // ... other events

     onCleanup(cleanup)
   })
   ```

3. **Implement connection status indicator**
   - Connected: Green dot
   - Reconnecting: Yellow dot with spinner
   - Disconnected: Red dot with retry button

4. **Handle reconnection logic**
   ```typescript
   function handleDisconnect() {
     setConnectionStatus("reconnecting")
     scheduleReconnect()
   }

   async function scheduleReconnect() {
     const delay = Math.min(1000 * Math.pow(2, attempts), 30000)
     await sleep(delay)
     await reconnect()
   }
   ```

5. **Implement state reconciliation**
   - On reconnect, fetch full state
   - Diff with local state
   - Apply minimal updates
   - Notify user of conflicts

6. **Add update animations**
   - Frame creation: Fade in + scale
   - Status change: Color transition
   - Completion: Shrink effect
   - Invalidation: Cascade ripple

7. **Implement debounced refresh**
   - Batch rapid events
   - Single refresh per animation frame
   - Prevent UI flicker

#### 3.5.2 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `/Users/sl/code/flame/.opencode/plugin/flame.ts` | Modify | Add event emission |
| `packages/app/src/components/flame/FlameProvider.tsx` | Modify | Add SSE subscription |
| `packages/app/src/components/flame/ConnectionStatus.tsx` | Create | Connection indicator |
| `packages/app/src/components/flame/hooks/useFlameEvents.ts` | Create | Event handling hook |
| `packages/app/src/components/flame/hooks/useAnimation.ts` | Create | Animation utilities |

#### 3.5.3 Verification Criteria

- [ ] Plugin emits events on state changes
- [ ] UI receives events via SSE
- [ ] Frames update in real-time (<100ms)
- [ ] Connection status displays correctly
- [ ] Reconnection works after network loss
- [ ] No duplicate updates on reconnect
- [ ] Animations play smoothly
- [ ] No UI flicker on rapid updates

#### 3.5.4 Dependencies

- Phase 2.4 complete

---

### Phase 2.6: Polish & Integration
**Duration**: Weeks 9-10
**Goal**: Error handling, accessibility, performance, documentation

#### 3.6.1 Tasks (Week 9)

1. **Implement error boundaries**
   ```typescript
   function FlameErrorBoundary(props: { children: JSX.Element }) {
     return (
       <ErrorBoundary
         fallback={(error) => (
           <FlameErrorFallback error={error} onRetry={refresh} />
         )}
       >
         {props.children}
       </ErrorBoundary>
     )
   }
   ```

2. **Add loading states**
   - Skeleton loader for initial load
   - Inline spinner for operations
   - Progress indicator for bulk operations

3. **Implement accessibility**
   - ARIA labels for all interactive elements
   - Focus management for dialogs
   - Screen reader announcements
   - High contrast mode support

4. **Performance optimization**
   - Memoize computed values
   - Virtualize large trees (>100 frames)
   - Lazy load deep subtrees
   - Debounce resize handlers

5. **Add search and filter**
   - Search by goal text
   - Filter by status
   - Filter by date range
   - Highlight matches

#### 3.6.2 Tasks (Week 10)

6. **Integration testing**
   - Test with OpenCode TUI
   - Test with real sessions
   - Test edge cases (deep trees, many siblings)
   - Test error scenarios

7. **Create user documentation**
   - Getting started guide
   - Keyboard shortcuts reference
   - Troubleshooting guide

8. **Performance profiling**
   - Measure initial load time
   - Measure update latency
   - Identify and fix bottlenecks
   - Document performance baseline

9. **Final polish**
   - Review all UI strings
   - Ensure consistent styling
   - Fix visual glitches
   - Test on multiple browsers

10. **Deployment preparation**
    - Update package versions
    - Create changelog
    - Prepare release notes

#### 3.6.3 Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `packages/app/src/components/flame/ErrorBoundary.tsx` | Create | Error handling |
| `packages/app/src/components/flame/LoadingStates.tsx` | Create | Loading UI |
| `packages/app/src/components/flame/SearchBar.tsx` | Create | Search input |
| `packages/app/src/components/flame/FilterDropdown.tsx` | Create | Status filter |
| `packages/app/src/components/flame/tests/*.test.ts` | Create | Unit tests |
| `phase2/docs/user-guide.md` | Create | User documentation |
| `phase2/docs/api-reference.md` | Create | API documentation |

#### 3.6.4 Verification Criteria

- [ ] Error boundary catches and displays errors gracefully
- [ ] All loading states display correctly
- [ ] Keyboard navigation works throughout
- [ ] Screen reader announces actions
- [ ] Performance meets targets (<2s load, <100ms updates)
- [ ] Search finds frames by goal
- [ ] Filters show correct subsets
- [ ] All tests pass
- [ ] Documentation is complete
- [ ] Works in Chrome, Firefox, Safari

#### 3.6.5 Dependencies

- Phase 2.5 complete

---

## 4. Technical Specifications

### 4.1 Project Structure

```
flame/
  phase2/
    IMPLEMENTATION-PLAN.md          # This document
    docs/
      user-guide.md                 # User documentation
      api-reference.md              # API documentation

opencode/
  packages/
    app/
      src/
        components/
          flame/
            index.tsx               # Module exports
            types.ts                # TypeScript interfaces
            constants.ts            # Colors, dimensions
            styles.css              # Component styles

            FlamePanel.tsx          # Main panel container
            FlameProvider.tsx       # State management context
            FlameGraph.tsx          # D3 visualization
            FrameRect.tsx           # Individual frame
            Connection.tsx          # Parent-child lines

            FrameDetails/
              index.tsx             # Details panel
              Header.tsx            # Panel header
              Artifacts.tsx         # Artifacts section
              Decisions.tsx         # Decisions section
              Summary.tsx           # Summary section

            dialogs/
              PushFrame.tsx         # Create frame dialog
              PopFrame.tsx          # Complete frame dialog
              PlanChildren.tsx      # Plan children dialog
              InvalidateFrame.tsx   # Invalidate dialog
              EditGoal.tsx          # Inline goal editor

            Tooltip.tsx             # Hover tooltip
            ContextMenu.tsx         # Right-click menu
            ZoomControls.tsx        # Zoom buttons
            Legend.tsx              # Status legend
            SearchBar.tsx           # Search input
            FilterDropdown.tsx      # Status filter
            ConnectionStatus.tsx    # SSE status indicator
            ErrorBoundary.tsx       # Error handling
            LoadingStates.tsx       # Loading UI

            hooks/
              useFlameState.ts      # Access flame store
              useFlameEvents.ts     # SSE subscription
              useZoom.ts            # Pan/zoom behavior
              useLayout.ts          # Layout computation
              useKeyboard.ts        # Keyboard shortcuts
              useAnimation.ts       # Transition utilities

            utils/
              tree.ts               # Tree manipulation
              api.ts                # API client
              format.ts             # Formatting helpers

            tests/
              FlameGraph.test.ts    # Visualization tests
              FlameProvider.test.ts # State tests
              tree.test.ts          # Utility tests

        context/
          layout.tsx                # Modified: add flame panel state

        pages/
          session.tsx               # Modified: integrate flame panel

    opencode/
      src/
        server/
          server.ts                 # Modified: add /flame/* endpoints

flame/
  .opencode/
    plugin/
      flame.ts                      # Modified: add flame_get_state, events
```

### 4.2 Key Interfaces

#### 4.2.1 FlameState (matches Phase 1 plugin)

```typescript
interface FlameState {
  version: number
  frames: Record<string, FrameMetadata>
  activeFrameID?: string
  rootFrameIDs: string[]
  updatedAt: number
}

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

type FrameStatus =
  | "planned"
  | "in_progress"
  | "completed"
  | "failed"
  | "blocked"
  | "invalidated"
```

#### 4.2.2 FlameContext

```typescript
interface FlameContextValue {
  // State
  state: FlameState
  loading: Accessor<boolean>
  error: Accessor<Error | null>
  selectedFrameID: Accessor<string | null>
  connectionStatus: Accessor<"connected" | "reconnecting" | "disconnected">

  // Computed
  activeFrame: Accessor<FrameMetadata | null>
  selectedFrame: Accessor<FrameMetadata | null>
  treeData: Accessor<D3HierarchyNode | null>
  flatFrames: Accessor<FrameMetadata[]>

  // Actions
  refresh: () => Promise<void>
  selectFrame: (id: string | null) => void
  pushFrame: (goal: string, parentID?: string) => Promise<void>
  popFrame: (status: FrameStatus, summary?: string) => Promise<void>
  planFrame: (goal: string, parentID?: string) => Promise<void>
  planChildren: (parentID: string, goals: string[]) => Promise<void>
  activateFrame: (id: string) => Promise<void>
  invalidateFrame: (id: string, reason: string) => Promise<void>
  setGoal: (id: string, goal: string) => Promise<void>
  addArtifact: (id: string, artifact: string) => Promise<void>
  addDecision: (id: string, decision: string) => Promise<void>
  navigateToFrame: (id: string) => void
}
```

#### 4.2.3 D3 Hierarchy Node

```typescript
interface D3HierarchyNode {
  id: string
  data: FrameMetadata
  children: D3HierarchyNode[]
  parent: D3HierarchyNode | null
  depth: number
  height: number
  x0?: number
  y0?: number
  x1?: number
  y1?: number
}
```

### 4.3 API Contracts

#### 4.3.1 GET /flame/state

**Response**: `FlameState`

```json
{
  "version": 1,
  "frames": {
    "ses_xxx": {
      "sessionID": "ses_xxx",
      "parentSessionID": "ses_yyy",
      "status": "in_progress",
      "goal": "Implement feature",
      "createdAt": 1735055400000,
      "updatedAt": 1735055500000,
      "artifacts": ["src/feature.ts"],
      "decisions": ["Use factory pattern"]
    }
  },
  "activeFrameID": "ses_xxx",
  "rootFrameIDs": ["ses_yyy"],
  "updatedAt": 1735055500000
}
```

#### 4.3.2 POST /flame/tool

**Request**:
```json
{
  "tool": "push",
  "args": {
    "goal": "New subtask"
  }
}
```

**Response**:
```json
{
  "success": true,
  "frame": {
    "sessionID": "ses_new",
    "status": "in_progress",
    "goal": "New subtask"
  }
}
```

### 4.4 Event Schemas

```typescript
const FlameEvents = {
  FrameCreated: {
    type: "flame.frame.created",
    properties: {
      frame: FrameMetadata,
      parentID: string | undefined,
    }
  },

  FrameUpdated: {
    type: "flame.frame.updated",
    properties: {
      frame: FrameMetadata,
      changes: string[], // ["goal", "status", etc.]
    }
  },

  FrameCompleted: {
    type: "flame.frame.completed",
    properties: {
      frame: FrameMetadata,
      status: "completed" | "failed" | "blocked",
    }
  },

  FrameActivated: {
    type: "flame.frame.activated",
    properties: {
      frame: FrameMetadata,
      previousActiveID: string | undefined,
    }
  },

  FrameInvalidated: {
    type: "flame.frame.invalidated",
    properties: {
      frame: FrameMetadata,
      cascadedFrames: FrameMetadata[],
      reason: string,
    }
  },

  StateChanged: {
    type: "flame.state.changed",
    properties: {
      activeFrameID: string | undefined,
      frameCount: number,
      updatedAt: number,
    }
  },
}
```

---

## 5. Testing Strategy

### 5.1 Unit Tests

**Focus**: Individual components and utilities

**Framework**: Vitest + @solidjs/testing-library

**Coverage Target**: 80% for core components

```typescript
// Example: tree.test.ts
import { describe, it, expect } from 'vitest'
import { buildHierarchy, getAncestors, getChildren } from './tree'

describe('buildHierarchy', () => {
  it('builds correct tree from flat frames', () => {
    const frames = {
      'root': { sessionID: 'root', goal: 'Root', status: 'in_progress' },
      'child1': { sessionID: 'child1', parentSessionID: 'root', goal: 'Child 1' },
      'child2': { sessionID: 'child2', parentSessionID: 'root', goal: 'Child 2' },
    }

    const tree = buildHierarchy(frames, ['root'])

    expect(tree.id).toBe('root')
    expect(tree.children).toHaveLength(2)
  })

  it('handles empty frames', () => {
    const tree = buildHierarchy({}, [])
    expect(tree).toBeNull()
  })
})
```

### 5.2 Integration Tests

**Focus**: API integration, state management

**Framework**: Vitest with MSW (Mock Service Worker)

```typescript
// Example: FlameProvider.integration.test.ts
import { describe, it, expect, beforeEach } from 'vitest'
import { render, waitFor } from '@solidjs/testing-library'
import { FlameProvider, useFlame } from './FlameProvider'

describe('FlameProvider', () => {
  it('fetches state on mount', async () => {
    const TestComponent = () => {
      const flame = useFlame()
      return <div data-testid="count">{flame.flatFrames().length}</div>
    }

    const { getByTestId } = render(() => (
      <FlameProvider>
        <TestComponent />
      </FlameProvider>
    ))

    await waitFor(() => {
      expect(getByTestId('count').textContent).toBe('3')
    })
  })

  it('handles push operation', async () => {
    const { flame } = setupFlameTest()

    await flame.pushFrame('New task')

    expect(flame.flatFrames()).toContainEqual(
      expect.objectContaining({ goal: 'New task' })
    )
  })
})
```

### 5.3 E2E Tests

**Focus**: Full user workflows

**Framework**: Playwright

```typescript
// Example: flame-graph.spec.ts
import { test, expect } from '@playwright/test'

test.describe('Flame Graph', () => {
  test('displays frame tree', async ({ page }) => {
    await page.goto('/project/session/ses_xxx')

    // Toggle flame panel
    await page.keyboard.press('Meta+Shift+F')

    // Wait for graph to load
    await page.waitForSelector('[data-testid="flame-graph"]')

    // Verify frames are visible
    const frames = await page.locator('[data-testid="frame-rect"]').count()
    expect(frames).toBeGreaterThan(0)
  })

  test('creates new frame', async ({ page }) => {
    await page.goto('/project/session/ses_xxx')
    await page.keyboard.press('Meta+Shift+F')

    // Push new frame
    await page.keyboard.press('Meta+Enter')

    // Fill goal
    await page.fill('[data-testid="goal-input"]', 'Test frame')
    await page.click('[data-testid="create-button"]')

    // Verify frame appears
    await expect(page.locator('text=Test frame')).toBeVisible()
  })
})
```

### 5.4 Manual Verification Checklist

#### Phase 2.0: Foundation
- [ ] FlamePanel mounts without console errors
- [ ] Mock data renders as colored rectangles
- [ ] Frame labels are readable
- [ ] Colors match specification

#### Phase 2.1: Data Integration
- [ ] `/flame/state` returns valid JSON
- [ ] Empty state shows "No frames" message
- [ ] Live frames render correctly
- [ ] Error state shows error message

#### Phase 2.2: Visualization Core
- [ ] Pan by clicking and dragging
- [ ] Zoom with scroll wheel
- [ ] Zoom controls work
- [ ] Reset view works
- [ ] Responsive to window resize

#### Phase 2.3: Interactions
- [ ] Click selects frame
- [ ] Hover shows tooltip
- [ ] Details panel displays all info
- [ ] Keyboard shortcuts work
- [ ] Context menu has all options

#### Phase 2.4: Frame Operations
- [ ] Push creates new frame
- [ ] Pop completes frame
- [ ] Plan creates planned frame
- [ ] Activate starts planned frame
- [ ] Invalidate cascades correctly

#### Phase 2.5: Real-time Updates
- [ ] Changes appear immediately
- [ ] Reconnection works
- [ ] No duplicate updates
- [ ] Animations are smooth

#### Phase 2.6: Polish
- [ ] Errors show friendly messages
- [ ] Loading states display
- [ ] Search works
- [ ] Filters work
- [ ] Accessibility audit passes

---

## 6. Risk Assessment

### 6.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| D3 + SolidJS integration complexity | Medium | High | Start simple, add reactivity incrementally |
| Large tree performance | Medium | Medium | Implement virtualization for >100 frames |
| SSE connection reliability | Low | Medium | Robust reconnection logic with exponential backoff |
| Plugin event emission | Low | High | Feature flag to enable/disable events |
| State synchronization conflicts | Medium | Medium | Server state wins, show conflict notification |

### 6.2 Integration Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| OpenCode API changes | Low | High | Version-lock SDK, integration tests |
| Plugin compatibility | Low | Medium | Feature detection, graceful degradation |
| Layout conflicts | Medium | Medium | Configurable panel position |

### 6.3 UX Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Visualization confusion | Medium | High | User testing, clear legend, tooltips |
| Feature discoverability | High | Medium | Keyboard shortcuts help, onboarding |
| Panel space competition | Medium | Medium | Smart defaults, collapsible panel |

### 6.4 Mitigation Actions

1. **Weekly integration testing**: Test with real OpenCode sessions weekly
2. **Performance monitoring**: Track render times, set alerts for >2s loads
3. **User feedback loop**: Gather feedback after Phase 2.3 to adjust UX
4. **Rollback plan**: Feature flag to disable flame panel if issues arise
5. **Documentation**: Complete docs before Phase 2.6 ends

---

## 7. Timeline Summary

| Phase | Duration | Dates (10-week schedule) | Key Deliverables |
|-------|----------|--------------------------|------------------|
| 2.0 | Week 1 | Week 1 | Project setup, static rendering |
| 2.1 | Week 2 | Week 2 | Live data integration |
| 2.2 | Weeks 3-4 | Weeks 3-4 | Full visualization, zoom/pan |
| 2.3 | Weeks 5-6 | Weeks 5-6 | Interactions, details panel |
| 2.4 | Week 7 | Week 7 | Frame operations, dialogs |
| 2.5 | Week 8 | Week 8 | Real-time updates, SSE |
| 2.6 | Weeks 9-10 | Weeks 9-10 | Polish, testing, docs |

---

## 8. Next Steps

1. **Immediate**: Begin Phase 2.0 project setup
2. **Week 1**: Complete foundation, verify static rendering
3. **Week 2**: Integrate with live plugin state
4. **Ongoing**: Weekly check-ins, verification at each phase

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-24 | Phase 2 Planning | Initial comprehensive plan |

---

*This document serves as the definitive implementation guide for Phase 2 of the Flame Graph Context Management system.*
