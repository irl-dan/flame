# Phase 1.6: Planning & Invalidation

This phase adds planned frame support, invalidation cascades, and frame tree visualization.

## Status: Next

## Goals

From SYNTHESIS.md Phase 6:
- **Planned frame support** - Pre-declare work structure before execution
- **Invalidation cascade** - Propagate changes when parent frames are modified
- **Frame tree visualization** - Navigate and inspect work hierarchy

## Features to Build

### 1. Planned Frames

Allow frames to be created in a `planned` state before work begins:

```typescript
// New status: 'planned' -> 'in_progress' -> 'completed'|'failed'|'blocked'
flame_plan goal="Implement user authentication" children=["Database schema", "API routes", "Frontend forms"]
```

**Requirements:**
- `flame_plan` tool to create planned frame hierarchies
- Planned frames visible in context but marked as pending
- Activation when work begins (`flame_activate`)
- Integration with existing push/pop workflow

### 2. Invalidation Cascade

When a parent frame changes significantly, child frames may need re-evaluation:

```
Parent frame modified (goal change, major artifact change)
       |
       v
  Mark dependent children as 'invalidated'
       |
       v
  Notify agent of invalidated frames
       |
       v
  Agent decides: re-execute, skip, or mark completed
```

**Requirements:**
- Track frame dependencies (parent -> children, sibling references)
- Detect significant changes that warrant invalidation
- `flame_invalidate` tool for manual invalidation
- Notification system for invalidated frames
- `flame_revalidate` tool to clear invalidation status

### 3. Frame Tree Visualization

Visual representation of frame hierarchy:

```
flame_tree

Output:
root (in_progress)
  +-- auth (completed) [summary: "JWT auth with refresh tokens"]
  +-- api (in_progress)
  |     +-- users (completed)
  |     +-- products (in_progress) <-- current
  +-- frontend (planned)
        +-- components (planned)
        +-- pages (planned)
```

**Requirements:**
- `flame_tree` tool to display hierarchy
- Status indicators (icons/colors)
- Current frame marker
- Optional: expand/collapse, filter by status

## Acceptance Criteria

### Planned Frames
- [ ] `flame_plan` creates frames with `planned` status
- [ ] Planned frames appear in context with "planned" marker
- [ ] `flame_activate` transitions planned -> in_progress
- [ ] Planned frames can be skipped or removed

### Invalidation
- [ ] Parent goal change triggers child invalidation prompt
- [ ] `flame_invalidate` manually invalidates a frame and descendants
- [ ] Invalidated frames are excluded from context assembly
- [ ] `flame_revalidate` clears invalidation status

### Visualization
- [ ] `flame_tree` displays full frame hierarchy
- [ ] Current frame is highlighted
- [ ] Status is visible for each frame
- [ ] Completed frames show summary snippet

## Test Plan

### Unit Tests
1. Planned frame creation and state transitions
2. Invalidation cascade logic (parent -> children)
3. Tree rendering with various hierarchies

### Integration Tests
1. Full workflow: plan -> activate -> complete
2. Invalidation triggered by goal change
3. Tree visualization after complex operations

### Manual Tests
1. Create multi-level planned hierarchy
2. Activate and complete frames in various orders
3. Trigger invalidation and observe cascade
4. Verify tree output is readable and accurate

## Implementation Notes

### Open Questions

1. **Planned frame storage**: Create sessions immediately or defer until activation?
   - Recommendation: Store in plugin state, create session on activation

2. **Invalidation triggers**: What changes should trigger invalidation?
   - Goal change (always)
   - Major artifact change (configurable)
   - Manual trigger (always available)

3. **Tree format**: ASCII art vs structured data?
   - Recommendation: ASCII for display, JSON option for programmatic use

## Dependencies

- Phase 1.1 (State Manager): Frame state storage
- Phase 1.2 (Context Assembly): Context injection for planned frames
- Phase 1.5 (Subagent Integration): Frame lifecycle events

## Files

| File | Description |
|------|-------------|
| `README.md` | This file |
| `IMPLEMENTATION.md` | Technical implementation details (to be created) |
| `tests/` | Test suite (to be created) |
