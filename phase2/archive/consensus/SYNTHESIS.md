# Phase 2 Implementation Plan: Synthesis Document

**Date**: 2025-12-24
**Status**: Awaiting User Input on Divergences

---

## Executive Summary

This document synthesizes three independent Phase 2 proposals (A, B, and C) for building a web-based Flame Graph visualization UI. All three proposals share fundamental alignment on the core vision, technology stack, and architectural approach. However, they differ in implementation specifics, timeline estimates, and certain architectural decisions that require user resolution.

---

## 1. Areas of Agreement

All three proposals align on the following decisions:

### 1.1 Core Technology Stack

| Component | Agreed Choice | Rationale |
|-----------|---------------|-----------|
| **Framework** | SolidJS | Consistency with existing OpenCode app |
| **Visualization** | D3.js (custom implementation) | Maximum control, well-suited for flame graphs |
| **State Management** | SolidJS Stores | Native reactivity, sufficient for use case |
| **Build System** | Vite | Fast, modern, SolidJS support |
| **Styling** | Tailwind CSS | Rapid development, consistency with OpenCode |
| **Real-time Updates** | Server-Sent Events (SSE) | Leverages existing OpenCode infrastructure |

### 1.2 Visualization Design

All proposals agree on:

- **Layout**: Icicle/flame graph style with root at top, children below (not traditional bottom-up flame graphs)
- **Color Coding**: Status-based colors:
  - `in_progress`: Blue (#3B82F6)
  - `completed`: Green (#22C55E)
  - `planned`: Yellow/Gray (#FBBF24 / #9CA3AF)
  - `failed`: Red (#EF4444)
  - `blocked`: Orange/Amber (#F59E0B)
  - `invalidated`: Gray (#6B7280) with visual distinction (strikethrough/opacity)
- **Interactive Elements**: Hover tooltips, click-to-select, double-click to navigate
- **Visual Hierarchy**: Parent-child relationships clearly shown with nested layout

### 1.3 Data Flow Architecture

All proposals agree on:

```
Web UI <--> OpenCode Server <--> Flame Plugin
              (HTTP + SSE)        (state.json)
```

- UI fetches initial state via REST/tool execution
- Real-time updates via SSE event stream
- Plugin emits events on state changes (requires Phase 1 enhancement)

### 1.4 Plugin Enhancements Required

All proposals identify the need to extend the Phase 1 plugin:

1. **Event Emission**: Plugin must emit bus events when frame state changes
2. **State Export**: Need a way to get complete frame state for UI rendering
3. **Event Types**: `flame.frame.created`, `flame.frame.updated`, `flame.frame.completed`, `flame.frame.activated`, `flame.frame.invalidated`

### 1.5 Core UI Components

All proposals include:

- Main Flame Graph visualization panel
- Frame details panel (slide-out or sidebar)
- Control panel for push/pop/plan operations
- Tooltips for frame hover preview
- Search and filter functionality

### 1.6 Frame Operations to Support

All 28 Phase 1 tools should be accessible via UI, with these operations prioritized:

- `flame_push` - Create new child frame
- `flame_pop` - Complete current frame
- `flame_set_goal` - Update frame goal
- `flame_add_artifact` - Record artifact
- `flame_add_decision` - Record decision
- `flame_plan` / `flame_plan_children` - Create planned frames
- `flame_activate` - Start planned frame
- `flame_invalidate` - Invalidate frame tree

---

## 2. Areas of Divergence

The following areas require user decision:

### 2.1 Deployment Strategy

| Proposal | Approach | Description |
|----------|----------|-------------|
| **A** | Standalone first | Start with standalone web app (Option B), integrate later |
| **B** | Integrated first | Embed as panel within existing OpenCode web UI (Option A) |
| **C** | Integrated first | Embed as panel, same as B |

**Tradeoffs**:
- *Standalone*: Faster iteration, independent deployment, but requires CORS config and separate hosting
- *Integrated*: Single deployment, shared auth/context, but coupled to OpenCode release cycle

### 2.2 API Strategy: REST Endpoints vs Tool Execution

| Proposal | Primary Approach | Fallback |
|----------|------------------|----------|
| **A** | New dedicated `/flame/*` REST endpoints | Tool execution for mutations |
| **B** | Tool execution via SDK | New `/flame/state` endpoint for reads |
| **C** | Tool execution via SDK | Direct state file reading as fallback |

**Tradeoffs**:
- *REST Endpoints*: Clean API, proper abstraction, but requires OpenCode server modifications
- *Tool Execution*: Works with current infrastructure, but slower (may involve LLM round-trip)
- *Direct File Access*: Simplest, but bypasses plugin logic, no validation

### 2.3 Visualization Library

| Proposal | Library Choice |
|----------|---------------|
| **A** | Custom SVG + D3 layout utilities |
| **B** | D3.js + custom implementation (no d3-flame-graph) |
| **C** | D3.js + d3-flame-graph package |

**Tradeoffs**:
- *Custom SVG*: Maximum control, no external dependencies
- *d3-flame-graph*: Battle-tested implementation, but designed for traditional profiling flame graphs (may not fit frame semantics)

### 2.4 Panel Position/Layout

| Proposal | Default Position |
|----------|-----------------|
| **A** | Full application layout with sidebar + main visualization |
| **B** | Right sidebar panel, toggleable |
| **C** | Right sidebar panel, with options for bottom/modal |

**Tradeoffs**:
- *Full layout*: More space for visualization, but may feel separate from chat
- *Right sidebar*: Persistent visibility alongside chat, but limited width
- *Configurable*: Flexibility, but more implementation complexity

### 2.5 Timeline Estimates

| Proposal | Total Duration | Phase Breakdown |
|----------|---------------|-----------------|
| **A** | 12 weeks | 6 phases of 2 weeks each |
| **B** | 8 weeks | 4 phases of 2 weeks each |
| **C** | 8 weeks | 7 phases, varying lengths (1-2 weeks each) |

**Tradeoffs**:
- Proposal A is most comprehensive but longest timeline
- Proposals B and C are more aggressive but may require scope reduction

### 2.6 State Synchronization Strategy

| Proposal | Primary Strategy | Optimization |
|----------|-----------------|--------------|
| **A** | Full state refresh + optimistic updates | State reconciliation on reconnect |
| **B** | Full state refresh on events | Optimistic updates |
| **C** | Full state refresh | Explicit mention of delta updates as future optimization |

All proposals start with full refresh but differ on when/how to optimize.

### 2.7 New Plugin Tool: `flame_get_state` vs `flame_status`

| Proposal | Approach |
|----------|----------|
| **A** | New `flame_api_state` and `flame_api_frame` tools designed for UI |
| **B** | Use existing `flame_status` tool |
| **C** | New `flame_get_state` tool returning structured JSON |

**Tradeoffs**:
- *New tools*: Cleaner separation, optimized for UI consumption
- *Existing tools*: No plugin changes, but output format may not be ideal for UI parsing

### 2.8 Minimap Feature

| Proposal | Includes Minimap |
|----------|-----------------|
| **A** | Yes, explicitly included in wireframes |
| **B** | No |
| **C** | No |

**Tradeoffs**:
- *Minimap*: Better navigation for large graphs, but additional implementation effort

### 2.9 Keyboard Shortcuts

All proposals include keyboard shortcuts but with different defaults:

| Action | Proposal A | Proposal B | Proposal C |
|--------|-----------|-----------|-----------|
| Toggle panel | - | Cmd+Shift+F | - |
| New frame | N | Cmd+Enter | - |
| Complete frame | C | Cmd+Backspace | - |
| Navigation | Arrow keys | Arrow keys | Tab/Arrow |

### 2.10 Frame Width Calculation

| Proposal | Width Calculation |
|----------|------------------|
| **A** | Equal width or proportional to duration/complexity |
| **B** | Proportional to descendants OR token usage |
| **C** | Based on value (descendant count, or custom weight) |

**Tradeoffs**:
- *Equal width*: Simpler, predictable layout
- *Proportional*: More informative, but requires additional data (tokens, time)

---

## 3. Recommended Unified Plan

Based on areas of agreement and pragmatic assessment of divergences, here is the recommended implementation plan:

### 3.1 Phase Structure (10 weeks)

A compromise between the timelines:

| Phase | Duration | Goals |
|-------|----------|-------|
| **2.0** | Week 1 | Foundation: Project setup, D3 integration, static rendering |
| **2.1** | Week 2 | Data Integration: Connect to plugin state, FlameProvider context |
| **2.2** | Week 3-4 | Visualization Core: Full flame graph rendering, navigation, status colors |
| **2.3** | Week 5-6 | Interactions: Details panel, tooltips, frame selection |
| **2.4** | Week 7 | Frame Operations: Push/pop dialogs, basic editing |
| **2.5** | Week 8 | Real-time: SSE subscription, event handling |
| **2.6** | Week 9-10 | Polish & Integration: Animations, error handling, accessibility |

### 3.2 Recommended Decisions (Pending User Input)

For each divergence, here is the recommended default:

1. **Deployment**: Start integrated (within OpenCode app) - easier user adoption
2. **API Strategy**: Use tool execution with a new `/flame/state` read endpoint
3. **Visualization**: Custom D3 implementation (not d3-flame-graph)
4. **Panel Position**: Right sidebar, resizable, with toggle shortcut
5. **State Sync**: Full refresh initially, optimize later
6. **New Tool**: Add `flame_get_state` tool for UI-optimized state retrieval
7. **Minimap**: Defer to Phase 3 unless user requests
8. **Keyboard Shortcuts**: Follow Proposal B's conventions (Cmd+Shift+F, etc.)
9. **Frame Width**: Start with equal width, make proportional optional

### 3.3 Project Structure (Unified)

```
flame/
  phase2/
    web/                          # Web UI application
      public/
        index.html
      src/
        index.tsx
        App.tsx

        api/                      # API client layer
          client.ts
          types.ts
          events.ts

        store/                    # State management
          flame.ts
          ui.ts
          actions.ts

        components/
          FlameGraph/
            index.tsx
            Frame.tsx
            Connection.tsx
            useLayout.ts
            useZoom.ts

          DetailsPanel/
            index.tsx
            FrameInfo.tsx
            Artifacts.tsx
            Decisions.tsx

          Dialogs/
            PushFrame.tsx
            PopFrame.tsx
            PlanChildren.tsx

          Toolbar/
            index.tsx
            SearchBar.tsx
            FilterDropdown.tsx
            ZoomControls.tsx

          ContextMenu/
            index.tsx

        hooks/
          useFlameState.ts
          useFlameEvents.ts
          useKeyboard.ts

        utils/
          tree.ts
          layout.ts
          format.ts

        types/
          flame.ts
          api.ts

      tests/
        unit/
        integration/
        e2e/

      package.json
      vite.config.ts
      tsconfig.json
      tailwind.config.js

    server/                       # Server-side additions
      routes/
        flame.ts                  # /flame/state endpoint
      events/
        flame-events.ts

    docs/
      user-guide.md
      api-reference.md
```

---

## 4. Questions for User

The following questions require user input to finalize the implementation plan:

### Q1: Deployment Strategy
**Options**:
- **(A)** Standalone web application that connects to OpenCode server (faster iteration, separate deployment)
- **(B)** Integrated panel within existing OpenCode web UI (single deployment, shared context) [RECOMMENDED]

Which deployment strategy do you prefer?

### Q2: API Strategy for Frame Operations
**Options**:
- **(A)** Create new dedicated `/flame/*` REST endpoints (cleaner API, requires server changes)
- **(B)** Use existing tool execution via SDK (works now, potentially slower) [RECOMMENDED]
- **(C)** Hybrid: REST for reads, tool execution for mutations

Which API strategy should we use?

### Q3: Should we use the `d3-flame-graph` package or build custom D3 visualization?
**Options**:
- **(A)** Use `d3-flame-graph` package (faster development, but may not fit our semantics)
- **(B)** Build custom D3 implementation (more work, maximum control) [RECOMMENDED]

Which visualization approach do you prefer?

### Q4: Default Panel Position
**Options**:
- **(A)** Full-width application view (more visualization space)
- **(B)** Right sidebar panel, resizable (persistent alongside chat) [RECOMMENDED]
- **(C)** Bottom panel, collapsible (similar to terminal)
- **(D)** Configurable (user can choose position)

Which panel position should be the default?

### Q5: Timeline and Scope
**Options**:
- **(A)** 12 weeks - Comprehensive (includes minimap, all polish)
- **(B)** 10 weeks - Balanced (core features + polish) [RECOMMENDED]
- **(C)** 8 weeks - Aggressive (core features only, minimal polish)

Which timeline best fits your needs?

### Q6: Should we add new plugin tools for UI optimization?
**Options**:
- **(A)** Add new `flame_get_state` tool optimized for UI consumption [RECOMMENDED]
- **(B)** Use existing `flame_status` tool and parse its output
- **(C)** Read state.json directly (bypass plugin)

Which approach do you prefer?

### Q7: Frame Width Calculation
**Options**:
- **(A)** Equal width for all sibling frames (simple, predictable) [RECOMMENDED]
- **(B)** Proportional to descendant count (shows hierarchy size)
- **(C)** Proportional to token usage (shows context weight, requires additional tracking)
- **(D)** Configurable (let user choose)

How should frame widths be calculated?

### Q8: Minimap Feature
**Options**:
- **(A)** Include minimap in Phase 2 (better navigation for large graphs)
- **(B)** Defer minimap to Phase 3 (keep Phase 2 scope smaller) [RECOMMENDED]

Should the minimap be included in Phase 2?

### Q9: Keyboard Shortcuts Convention
**Options**:
- **(A)** Follow Proposal A (N=push, C=complete, simple keys)
- **(B)** Follow Proposal B (Cmd+Enter=push, Cmd+Backspace=pop, modifier keys) [RECOMMENDED]
- **(C)** Follow web app conventions (no standard, define as needed)

Which keyboard shortcut convention do you prefer?

### Q10: Direct Tool Invocation
Currently, the UI would need to invoke flame tools through session prompts, which may trigger LLM processing. Should we:
**Options**:
- **(A)** Add a direct tool invocation endpoint to OpenCode server (cleaner, faster) [RECOMMENDED]
- **(B)** Use existing session.prompt with `noReply` flag (works now, may be slower)
- **(C)** Manipulate state.json directly from UI (bypasses all plugin logic)

Which approach should we use for tool execution from the UI?

---

## Appendix A: Proposal Comparison Matrix

| Feature/Decision | Proposal A | Proposal B | Proposal C |
|-----------------|-----------|-----------|-----------|
| Timeline | 12 weeks | 8 weeks | 8 weeks |
| Deployment | Standalone first | Integrated | Integrated |
| D3 Library | Custom + helpers | Custom | d3-flame-graph |
| API Strategy | REST primary | Tools via SDK | Tools via SDK |
| Panel Position | Full layout | Right sidebar | Configurable |
| New Tools | Yes (api-specific) | Maybe | Yes (flame_get_state) |
| Minimap | Yes | No | No |
| State Sync | Refresh + reconcile | Refresh + optimistic | Refresh |
| Detail Level | Very comprehensive | Detailed | Detailed |
| Testing | Unit + Integration + E2E + Visual | Unit + Integration + E2E | Unit + Integration + E2E + Visual |

## Appendix B: Shared Type Definitions

All proposals agree on core type definitions:

```typescript
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

## Appendix C: Event Types (Agreed)

```typescript
const FlameEvents = {
  FrameCreated: "flame.frame.created"
  FrameUpdated: "flame.frame.updated"
  FrameCompleted: "flame.frame.completed"
  FrameActivated: "flame.frame.activated"
  FrameInvalidated: "flame.frame.invalidated"
  StateChanged: "flame.state.changed"
}
```

---

*This synthesis document was generated by analyzing proposals A, B, and C. User input on the questions above will finalize the Phase 2 implementation plan.*
