# Flame Graph Context Management - User Guide

A visual system for managing and navigating hierarchical AI agent execution contexts within OpenCode.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Understanding the Interface](#understanding-the-interface)
3. [Navigation](#navigation)
4. [Frame Operations](#frame-operations)
5. [Keyboard Shortcuts](#keyboard-shortcuts)
6. [Search and Filter](#search-and-filter)
7. [Troubleshooting](#troubleshooting)

---

## Getting Started

### Opening the Flame Graph Panel

The Flame Graph panel displays the hierarchical structure of your AI agent's execution contexts (frames). Each frame represents a distinct goal or task that the agent is working on.

To toggle the Flame Graph panel:
- Use the keyboard shortcut: `Cmd/Ctrl + Shift + F`
- Or use the command palette and search for "Toggle Flame Graph"

### What is a Frame?

A **frame** represents a unit of work with:
- A **goal**: What the frame is trying to accomplish
- A **status**: Current state (planned, in progress, completed, failed, blocked, invalidated)
- **Artifacts**: Files or outputs created
- **Decisions**: Key choices made during execution
- **Children**: Sub-tasks spawned from this frame

---

## Understanding the Interface

### Frame Status Colors

| Status | Color | Description |
|--------|-------|-------------|
| Planned | Gray | Scheduled for future execution |
| In Progress | Blue | Currently active and executing |
| Completed | Green | Successfully finished |
| Failed | Red | Encountered an error |
| Blocked | Amber/Yellow | Waiting on external dependency |
| Invalidated | Faded Gray | Marked as no longer relevant |

### Frame Indicators

- **Solid border**: Normal frame
- **Pulsing border**: Currently active frame
- **Dashed border**: Planned frame
- **Faded appearance**: Invalidated frame

### Connection Lines

Lines between frames show the parent-child relationship. The color of the line matches the child frame's status.

---

## Navigation

### Mouse Navigation

- **Click** on a frame to select it and view details
- **Click again** on the selected frame to deselect
- **Right-click** on a frame to open the context menu
- **Scroll** to zoom in/out (when zoom controls are enabled)
- **Drag** to pan the view (when pan is enabled)

### Keyboard Navigation

When the Flame Graph panel is focused:

| Key | Action |
|-----|--------|
| Arrow Up | Navigate to parent frame |
| Arrow Down | Navigate to first child frame |
| Arrow Left | Navigate to previous sibling |
| Arrow Right | Navigate to next sibling |
| Enter | Select the focused frame |
| Space | Select the focused frame (alternative) |
| Escape | Deselect current frame and clear focus |

### Zoom Controls

Use the zoom controls in the bottom-right corner:
- **+** to zoom in
- **-** to zoom out
- **Reset** to return to default zoom level

---

## Frame Operations

### Creating Frames

#### Push a New Frame
Creates a new child frame and immediately activates it:
1. Right-click on a parent frame
2. Select "Push Child Frame"
3. Enter the goal for the new frame
4. The new frame becomes active

#### Plan a Frame
Creates a child frame for later execution:
1. Right-click on a parent frame
2. Select "Plan Child Frame"
3. Enter the goal
4. Frame is created with "planned" status

#### Plan Multiple Children
Batch create multiple child frames:
1. Right-click on a parent frame
2. Select "Plan Children"
3. Enter multiple goals (one per line)
4. All frames are created with "planned" status

### Managing Frames

#### Complete a Frame
Mark an active frame as completed:
1. Right-click on the frame
2. Select "Complete Frame"
3. Optionally add a summary
4. Frame status changes to "completed"

#### Invalidate a Frame
Mark a frame and its children as invalid:
1. Right-click on the frame
2. Select "Invalidate"
3. Enter a reason for invalidation
4. Frame and all descendants are invalidated

#### Edit Frame Goal
Update a frame's goal text:
1. Select the frame
2. In the details panel, click "Edit Goal"
3. Modify the text
4. Save changes

### Frame Details Panel

When a frame is selected, the details panel shows:
- **Header**: Status, goal, and timing information
- **Artifacts**: Files and outputs created
- **Decisions**: Key decisions made
- **Summary**: Compaction summary (for completed frames)

---

## Keyboard Shortcuts

### Global Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + Shift + F` | Toggle Flame Graph panel |
| `Cmd/Ctrl + Enter` | Push new frame (when panel is open) |
| `Cmd/Ctrl + Backspace` | Complete current frame (when panel is open) |

### Panel Navigation

| Shortcut | Action |
|----------|--------|
| `Arrow Up` | Navigate to parent |
| `Arrow Down` | Navigate to child |
| `Arrow Left` | Navigate to previous sibling |
| `Arrow Right` | Navigate to next sibling |
| `Enter` or `Space` | Select focused frame |
| `Escape` | Deselect / close menu |

---

## Search and Filter

### Searching Frames

Use the search bar to find frames by goal text:
1. Type in the search box
2. Matching frames appear in the dropdown
3. Click a result to select that frame
4. Use arrow keys to navigate results

### Filtering by Status

Use the filter dropdown to show only frames with specific statuses:
1. Click the filter button
2. Select one or more status types
3. The graph updates to highlight matching frames

---

## Troubleshooting

### Common Issues

#### Flame Graph Not Loading
- Check your network connection
- Look for error messages in the panel
- Click "Retry" to attempt reload
- If problems persist, reload the page

#### Connection Status Issues

| Status | Meaning | Action |
|--------|---------|--------|
| Green dot | Connected | Working normally |
| Yellow pulsing dot | Reconnecting | Wait for reconnection |
| Red dot | Disconnected | Check network, refresh if needed |

#### Frames Not Updating

The Flame Graph uses real-time updates (SSE). If updates stop:
1. Check the connection indicator
2. Click the refresh button
3. If needed, reload the page

#### Performance with Large Trees

For trees with many frames (100+):
- Use search to find specific frames
- Use filters to reduce visible frames
- Consider collapsing completed subtrees

### Error Messages

#### "Failed to load flame graph"
The API request failed. Check:
- Network connectivity
- Server status
- Console for detailed error

#### "useFlame must be used within a FlameProvider"
The component is not properly wrapped. Ensure `FlameProvider` is in the component tree.

### Getting Help

If you encounter issues not covered here:
1. Check the browser console for errors
2. Look for the error boundary fallback UI
3. Use the "Show details" option to view stack traces
4. Report issues with the error details

---

## Accessibility

### Screen Reader Support

- All interactive elements have ARIA labels
- Status changes are announced
- Keyboard navigation is fully supported

### High Contrast Mode

The flame graph adapts to high contrast preferences:
- Increased border widths
- Enhanced color contrast
- Alternative highlight colors

### Reduced Motion

If you have "reduce motion" preferences enabled:
- Animations are disabled
- Transitions are instant
- Pulsing indicators are static

---

## Tips and Best Practices

1. **Use meaningful goals**: Write clear, actionable goals for each frame
2. **Complete frames promptly**: Mark frames as completed when done to keep the graph clean
3. **Plan ahead**: Use "Plan Children" to outline subtasks before starting
4. **Review decisions**: Document key decisions for future reference
5. **Invalidate thoughtfully**: Invalidation cascades to children, so use judiciously
