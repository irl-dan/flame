# Phase 1.6: Planning & Invalidation - Implementation

## Overview

Phase 1.6 completes the core frame management functionality by adding support for:
- **Planned frames** - Frames that exist before execution begins
- **Invalidation cascade** - Automatic invalidation of planned children when a parent is invalidated
- **Frame tree visualization** - ASCII tree display of all frames with status indicators

## Features Implemented

### 1. Planned Frame Support

#### New Tool: `flame_plan`
Creates a planned frame for future work. Planned frames appear in the frame tree but are not started yet.

**Arguments:**
- `goal` (required): The goal/purpose of this planned frame
- `parentSessionID` (optional): Parent frame session ID (uses current frame if not provided)

**Example:**
```
flame_plan({ goal: "Implement user authentication" })
```

#### New Tool: `flame_plan_children`
Creates multiple planned child frames at once. Useful for sketching out the structure of subtasks before starting work.

**Arguments:**
- `parentSessionID` (optional): Parent frame session ID (uses current frame if not provided)
- `children` (required): Array of goals for the planned child frames

**Example:**
```
flame_plan_children({
  children: [
    "Implement login endpoint",
    "Implement logout endpoint",
    "Add JWT token generation"
  ]
})
```

This creates B -> B1, B2, B3 before starting B, as specified in SPEC.md.

#### New Tool: `flame_activate`
Starts working on a planned frame by changing its status from 'planned' to 'in_progress'.

**Arguments:**
- `sessionID` (required): The session ID of the planned frame to activate

**Example:**
```
flame_activate({ sessionID: "plan-12345678" })
```

### 2. Invalidation Cascade

#### New Tool: `flame_invalidate`
Invalidates a frame and cascades to its planned children.

**Cascade Rules (per SPEC.md):**
- All `planned` children are automatically set to `invalidated`
- `in_progress` children are warned/flagged but **not** auto-invalidated
- `completed` children remain completed

**Arguments:**
- `sessionID` (optional): The session ID of the frame to invalidate (uses current frame if not provided)
- `reason` (required): The reason for invalidation (stored in frame metadata)

**Example:**
```
flame_invalidate({
  reason: "Requirements changed - using third-party auth instead"
})
```

### 3. Frame Tree Visualization

#### New Tool: `flame_tree`
Shows a visual ASCII tree of all frames with status indicators.

**Status Icons:**
| Status | Icon |
|--------|------|
| completed | ✓ |
| in_progress | → |
| planned | ○ |
| invalidated | ✗ |
| blocked | ! |
| failed | ⚠ |

**Arguments:**
- `showFull` (optional): Show full tree including all branches (default: true)
- `rootID` (optional): Root frame ID to start from (shows subtree only)
- `showDetails` (optional): Show additional details like timestamps and summaries (default: false)

**Example Output:**
```
# Flame Frame Tree

**Legend:** ✓ completed, → in_progress, ○ planned, ✗ invalidated, ! blocked, ⚠ failed
**Active Frame:** abc12345

```
    → Build Application (root1234) <<<ACTIVE
    ├── ✓ Implement Auth (child123)
    ├── → Build API (child456)
    │   └── ○ Add Endpoints (grandch1)
    └── ○ Create UI (child789)
```

**Stats:** 5 total | 1 ✓ | 2 → | 2 ○ | 0 ✗ | 0 ! | 0 ⚠
```

## Frame Metadata Updates

Added new fields to `FrameMetadata` interface:

```typescript
interface FrameMetadata {
  // ... existing fields

  // Phase 1.6: Planning and Invalidation fields
  /** Reason for invalidation (if status is 'invalidated') */
  invalidationReason?: string
  /** When the frame was invalidated */
  invalidatedAt?: number
  /** IDs of planned child frames (for planning ahead) */
  plannedChildren?: string[]
}
```

## FrameStateManager Updates

New methods added to `FrameStateManager`:

### `createPlannedFrame(sessionID, goal, parentSessionID?)`
Creates a new planned frame (not yet started).

### `createPlannedChildren(parentSessionID, children[])`
Creates multiple planned children at once.

### `activateFrame(sessionID)`
Activates a planned frame (changes status from 'planned' to 'in_progress').

### `invalidateFrame(sessionID, reason)`
Invalidates a frame and cascades to planned children. Returns:
- `invalidated`: The invalidated frame
- `cascadedPlanned`: Array of planned children that were auto-invalidated
- `warningInProgress`: Array of in-progress children that were NOT auto-invalidated

### `getAllSiblings(sessionID)`
Gets all siblings (not just completed) of a frame.

### `getAllChildren(sessionID)`
Gets all children of a frame (any status).

### `getFramesByStatus(status)`
Gets all frames with a specific status.

## Testing

Run the test script:
```bash
cd /Users/sl/code/flame
./phase1/1.6-planning-invalidation/tests/test-planning.sh
```

### Test Cases

1. **test_planned_frame_creation** - Verifies planned frames can be created with 'planned' status
2. **test_planned_children_creation** - Verifies multiple planned children can be created at once
3. **test_frame_activation** - Verifies activation changes status from 'planned' to 'in_progress'
4. **test_invalidation_cascade** - Verifies invalidation cascades to planned children
5. **test_in_progress_not_auto_invalidated** - Verifies in-progress children are NOT auto-invalidated
6. **test_tree_visualization_structure** - Verifies tree has correct structure and relationships
7. **test_invalidation_reason_tracked** - Verifies invalidation reason is stored in metadata
8. **test_nested_planned_cascade** - Verifies nested planned children are cascaded

## Usage Examples

### Example 1: Planning a Feature

```typescript
// Start with a feature goal
flame_push({ goal: "Implement user management" })

// Plan out the subtasks before starting
flame_plan_children({
  children: [
    "Create User model",
    "Add user CRUD endpoints",
    "Implement user permissions",
    "Add user tests"
  ]
})

// View the plan
flame_tree()

// Start work on first subtask
flame_activate({ sessionID: "plan-..." })
```

### Example 2: Handling Invalidation

```typescript
// After working on a feature, requirements change
flame_invalidate({
  reason: "Switching to OAuth instead of custom auth"
})

// This automatically invalidates all planned children
// but leaves in-progress children with a warning
```

### Example 3: Viewing Frame Status

```typescript
// Quick overview
flame_tree()

// Detailed view with summaries
flame_tree({ showDetails: true })

// View specific subtree
flame_tree({ rootID: "abc12345" })
```

## Integration with Existing Features

### Context Injection
Planned frames are included in the context XML with status "planned":
```xml
<child id="plan123" status="planned">
  <goal>Implement feature X</goal>
</child>
```

### Compaction
Planned frames don't accumulate conversation history until activated. When activated, they function like any other in-progress frame.

### Subagent Integration
Subagent sessions can have planned children, allowing agents to sketch out work before delegation.

## Files Modified

- `/Users/sl/code/flame/.opencode/plugin/flame.ts` - Main plugin with Phase 1.6 additions

## Files Created

- `/Users/sl/code/flame/phase1/1.6-planning-invalidation/IMPLEMENTATION.md` - This document
- `/Users/sl/code/flame/phase1/1.6-planning-invalidation/tests/test-planning.sh` - Test script

## Summary

Phase 1.6 completes the core frame management functionality as specified in SYNTHESIS.md and SPEC.md. The implementation provides:

1. **Planned frames** for sketching work before execution
2. **Invalidation cascade** for automatic cleanup when plans change
3. **Frame tree visualization** for understanding the current state

This enables more structured planning and flexible handling of changing requirements during AI agent work.
