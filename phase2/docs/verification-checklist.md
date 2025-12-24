# Flame Graph Component Verification Checklist

This document provides comprehensive manual verification procedures for the Flame Graph components implemented in Phase 2.4, 2.5, and 2.6.

## Table of Contents

1. [Pre-Verification Setup](#pre-verification-setup)
2. [Phase 2.4: Frame Operations](#phase-24-frame-operations)
3. [Phase 2.5: Real-time Updates](#phase-25-real-time-updates)
4. [Phase 2.6: Polish and Integration](#phase-26-polish-and-integration)
5. [Visual Verification](#visual-verification)
6. [Accessibility Verification](#accessibility-verification)
7. [Performance Verification](#performance-verification)
8. [Cross-Browser Testing](#cross-browser-testing)

---

## Pre-Verification Setup

### Environment Preparation

- [ ] OpenCode server is running (`npm run dev` or equivalent)
- [ ] Flame plugin is properly configured in the backend
- [ ] Browser DevTools are open for console monitoring
- [ ] Network tab is visible for SSE connection monitoring
- [ ] At least one test project with flame state is available

### Initial State Verification

- [ ] Navigate to the flame graph view
- [ ] Verify flame graph panel loads without errors
- [ ] Verify no console errors on initial load
- [ ] Verify loading skeleton appears during data fetch
- [ ] Verify frames render after data loads

---

## Phase 2.4: Frame Operations

### 2.4.1 PushFrame Dialog

#### Opening the Dialog

- [ ] Right-click on a frame to open context menu
- [ ] Click "Push Frame" or "Add Child" option
- [ ] Verify dialog opens centered on screen
- [ ] Verify backdrop overlay is visible (50% opacity black)
- [ ] Verify parent frame information is displayed in header
- [ ] Verify goal textarea is focused automatically

#### Form Interaction

- [ ] Type in goal textarea
- [ ] Verify character input is reflected immediately
- [ ] Toggle "Start immediately" checkbox
- [ ] Verify title changes between "Push New Frame" and "Plan New Frame"
- [ ] Verify button text changes between "Push Frame" and "Plan Frame"

#### Keyboard Navigation

- [ ] Press `Escape` - dialog should close
- [ ] Press `Cmd/Ctrl + Enter` - form should submit (if goal is valid)
- [ ] Press `Tab` - should cycle through focusable elements

#### Validation

- [ ] Try to submit with empty goal
- [ ] Verify error message "Goal is required" appears
- [ ] Verify submit button is disabled when goal is empty
- [ ] Enter valid goal
- [ ] Verify error message clears
- [ ] Verify submit button becomes enabled

#### Submission

- [ ] Click submit button with valid goal
- [ ] Verify loading state appears (button shows "Creating...")
- [ ] Verify buttons are disabled during loading
- [ ] Verify dialog closes on success
- [ ] Verify new frame appears in flame graph
- [ ] Verify form state is reset for next use

#### Error Handling

- [ ] Simulate network error (disable network)
- [ ] Submit form
- [ ] Verify error message displays
- [ ] Verify form remains open
- [ ] Verify user can retry

#### Backdrop Behavior

- [ ] Click on backdrop (outside dialog)
- [ ] Verify dialog closes
- [ ] Click inside dialog
- [ ] Verify dialog stays open

---

### 2.4.2 PopFrame Dialog

#### Opening the Dialog

- [ ] Right-click on active frame
- [ ] Click "Complete Frame" or "Pop Frame"
- [ ] Verify dialog opens
- [ ] Verify frame goal is displayed in header

#### Status Selection

- [ ] Verify "Completed" is selected by default
- [ ] Click "Failed" status button
- [ ] Verify visual selection changes
- [ ] Verify submit button color changes to match status
- [ ] Click "Blocked" status button
- [ ] Verify selection updates

#### Summary Input

- [ ] Leave summary empty (optional field)
- [ ] Enter summary text
- [ ] Verify helper text mentions auto-generation

#### Keyboard Navigation

- [ ] Press `Escape` - dialog closes
- [ ] Press `Cmd/Ctrl + Enter` - form submits

#### Submission

- [ ] Submit with "Completed" status
- [ ] Verify loading state
- [ ] Verify dialog closes on success
- [ ] Verify frame status updates in graph
- [ ] Verify frame color changes to green (completed)

---

### 2.4.3 PlanChildren Dialog

#### Opening the Dialog

- [ ] Right-click on a frame
- [ ] Click "Plan Children"
- [ ] Verify dialog opens with 3 empty goal inputs

#### Adding Goals

- [ ] Enter goal in first input
- [ ] Enter goal in second input
- [ ] Leave third input empty
- [ ] Click "+ Add another goal" button
- [ ] Verify fourth input appears
- [ ] Verify footer shows correct count (2 frames to create)

#### Removing Goals

- [ ] Click X button on a goal row
- [ ] Verify row is removed
- [ ] Verify count updates
- [ ] Verify cannot remove last remaining goal input

#### Validation

- [ ] Try to submit with all goals empty
- [ ] Verify error "At least one goal is required"
- [ ] Enter at least one valid goal
- [ ] Verify error clears

#### Submission

- [ ] Submit with 2 valid goals
- [ ] Verify loading state
- [ ] Verify dialog closes
- [ ] Verify 2 new frames appear as children
- [ ] Verify new frames have "planned" status (gray color)

---

### 2.4.4 InvalidateFrame Dialog

#### Opening the Dialog

- [ ] Right-click on a frame with children
- [ ] Click "Invalidate"
- [ ] Verify dialog opens with red header
- [ ] Verify cascade warning shows child count

#### Cascade Warning

- [ ] Verify warning icon (triangle with exclamation)
- [ ] Verify warning text mentions number of child frames
- [ ] For frame without children, verify no warning appears

#### Reason Input

- [ ] Verify reason field is required (red asterisk)
- [ ] Verify placeholder text
- [ ] Type invalidation reason

#### Validation

- [ ] Try to submit with empty reason
- [ ] Verify error message appears
- [ ] Enter reason
- [ ] Verify submit button enables

#### Submission

- [ ] Submit invalidation
- [ ] Verify loading state
- [ ] Verify dialog closes
- [ ] Verify frame status changes to "invalidated"
- [ ] Verify frame opacity decreases (dimmed)
- [ ] Verify child frames are also invalidated (cascade)

---

### 2.4.5 EditGoal Component

#### Activation

- [ ] Double-click on frame goal text
- [ ] OR click edit button if available
- [ ] Verify inline editor appears
- [ ] Verify current goal text is pre-filled
- [ ] Verify text is selected

#### Editing

- [ ] Modify goal text
- [ ] Press `Enter` to save
- [ ] Verify new goal is displayed
- [ ] Edit again, press `Escape`
- [ ] Verify original goal is restored

#### Validation

- [ ] Edit goal to empty string
- [ ] Try to save
- [ ] Verify error "Goal cannot be empty"
- [ ] Enter valid goal
- [ ] Verify error clears

#### Cancel Behavior

- [ ] Start editing
- [ ] Click Cancel button
- [ ] Verify edit mode exits
- [ ] Verify original goal remains

---

### 2.4.6 API Integration

#### Network Requests

- [ ] Open Network tab in DevTools
- [ ] Perform a push action
- [ ] Verify POST request to `/flame/tool`
- [ ] Verify request body contains `{ tool: "push", args: { goal: "..." } }`
- [ ] Verify response contains `{ success: true }`

#### Optimistic Updates

- [ ] Perform an action (e.g., activate frame)
- [ ] Observe immediate UI update before server response
- [ ] If action fails, observe rollback to previous state

---

## Phase 2.5: Real-time Updates

### 2.5.1 SSE Connection

#### Initial Connection

- [ ] Open Network tab, filter by "EventSource" or "fetch"
- [ ] Load flame graph
- [ ] Verify SSE connection is established
- [ ] Verify `connected` status indicator appears

#### Connection Status Indicator

- [ ] Verify green dot for "connected" state
- [ ] Verify label shows "Connected"
- [ ] Simulate network disconnect (DevTools > Network > Offline)
- [ ] Verify status changes to "disconnected" (red)
- [ ] Re-enable network
- [ ] Verify status changes to "reconnecting" (yellow/spinning)
- [ ] Verify status returns to "connected" (green)

#### Retry Button

- [ ] While disconnected, verify "Retry" button appears
- [ ] Click Retry button
- [ ] Verify reconnection attempt

---

### 2.5.2 Event Handling

#### Debounced Updates

- [ ] Make rapid changes in another window
- [ ] Verify flame graph updates smoothly (not flickering)
- [ ] Verify updates are batched

#### Event Types

- [ ] Create a new session (should trigger update)
- [ ] Update a session (should trigger update)
- [ ] Verify frame state refreshes after relevant events

---

### 2.5.3 Animation System

#### Frame Creation Animation

- [ ] Push a new frame
- [ ] Observe creation animation (fade in / scale up)
- [ ] Verify animation duration is ~300ms

#### Status Change Animations

- [ ] Complete a frame
- [ ] Observe completion animation (green glow/flash)
- [ ] Activate a planned frame
- [ ] Observe activation animation
- [ ] Invalidate a frame
- [ ] Observe invalidation animation (may include cascade effect)

#### Active Frame Pulse

- [ ] Verify active frame has subtle pulse animation
- [ ] Verify pulse doesn't interfere with readability

#### Reduced Motion

- [ ] Enable "Reduce motion" in OS accessibility settings
- [ ] Verify animations are disabled or minimized
- [ ] Verify functionality still works

---

## Phase 2.6: Polish and Integration

### 2.6.1 ErrorBoundary

#### Error Display

- [ ] Simulate component error (if test mode available)
- [ ] Verify error fallback UI displays
- [ ] Verify error icon appears
- [ ] Verify "Something went wrong" message
- [ ] Verify "The flame graph encountered an error" description

#### Error Details

- [ ] Click "Show details" button
- [ ] Verify error message and stack trace appear
- [ ] Click "Hide details"
- [ ] Verify details collapse

#### Recovery Actions

- [ ] Click "Try again" button
- [ ] Verify component attempts to re-render
- [ ] Click "Reload page" button
- [ ] Verify page reloads

---

### 2.6.2 LoadingStates

#### SkeletonLoader

- [ ] Reload flame graph with slow network (DevTools throttle)
- [ ] Verify skeleton loader appears
- [ ] Verify 4 skeleton rows with indentation
- [ ] Verify pulse animation on skeleton
- [ ] Verify accessible loading announcement (`role="status"`)

#### InlineSpinner

- [ ] Trigger a loading state (e.g., form submission)
- [ ] Verify spinner appears at correct size
- [ ] Verify spinner animates
- [ ] Verify accessible label

#### ProgressIndicator

- [ ] If bulk operation available, trigger it
- [ ] Verify progress bar appears
- [ ] Verify progress updates smoothly
- [ ] Verify percentage display (if enabled)

#### OperationOverlay

- [ ] Trigger long-running operation
- [ ] Verify overlay appears over content
- [ ] Verify message is displayed
- [ ] If cancel available, verify cancel button works

---

### 2.6.3 SearchBar

#### Basic Search

- [ ] Click search input
- [ ] Verify focus ring appears
- [ ] Type search query
- [ ] Verify results dropdown appears
- [ ] Verify matching text is highlighted
- [ ] Verify status badge on each result

#### Keyboard Navigation

- [ ] Press `Arrow Down` - move to next result
- [ ] Press `Arrow Up` - move to previous result
- [ ] Verify selected result is visually indicated
- [ ] Press `Enter` - select highlighted result
- [ ] Verify frame is selected in graph
- [ ] Press `Escape` - close results and clear search

#### Clear Button

- [ ] Enter search text
- [ ] Verify X clear button appears
- [ ] Click clear button
- [ ] Verify input clears
- [ ] Verify results close

#### No Results

- [ ] Search for non-existent term
- [ ] Verify "No frames found matching..." message

#### Accessibility

- [ ] Verify `role="combobox"` on input
- [ ] Verify `aria-expanded` updates
- [ ] Verify `role="listbox"` on results
- [ ] Verify `role="option"` on each result
- [ ] Verify `aria-selected` on selected result

---

### 2.6.4 FilterDropdown

#### Opening Dropdown

- [ ] Click filter button
- [ ] Verify dropdown opens
- [ ] Verify all status options listed
- [ ] Verify count for each status

#### Single Selection Mode

- [ ] Click a status option
- [ ] Verify dropdown closes
- [ ] Verify button label updates
- [ ] Verify frames are filtered in graph

#### Multiple Selection Mode (if enabled)

- [ ] Click multiple options
- [ ] Verify checkboxes appear
- [ ] Verify multiple selections maintained
- [ ] Verify button shows count

#### Closing Dropdown

- [ ] Click outside dropdown
- [ ] Verify dropdown closes
- [ ] Press `Escape`
- [ ] Verify dropdown closes

#### Accessibility

- [ ] Verify `aria-haspopup="listbox"` on button
- [ ] Verify `aria-expanded` updates
- [ ] Verify `role="listbox"` on dropdown
- [ ] Verify `role="option"` on each option
- [ ] Verify `aria-selected` on selected options

---

## Visual Verification

### Color Accuracy

- [ ] Planned frames: Gray (#9CA3AF)
- [ ] In Progress frames: Blue (#3B82F6)
- [ ] Completed frames: Green (#22C55E)
- [ ] Failed frames: Red (#EF4444)
- [ ] Blocked frames: Amber (#F59E0B)
- [ ] Invalidated frames: Gray (#6B7280) with 50% opacity

### Typography

- [ ] Frame labels are readable at default zoom
- [ ] Long goals are truncated with ellipsis
- [ ] Tooltips show full goal on hover

### Spacing

- [ ] Consistent padding inside frames
- [ ] Gap between sibling frames
- [ ] Border radius on all frames

### Dark Mode (if applicable)

- [ ] Toggle dark mode
- [ ] Verify colors adjust appropriately
- [ ] Verify sufficient contrast
- [ ] Verify no color inversion issues

---

## Accessibility Verification

### Screen Reader Testing

- [ ] Navigate flame graph with screen reader
- [ ] Verify frame labels are announced
- [ ] Verify status is announced
- [ ] Verify dialog content is read

### Keyboard Navigation

- [ ] Navigate between frames with arrow keys
- [ ] Select frame with Enter
- [ ] Open context menu with keyboard
- [ ] Navigate dialogs with Tab
- [ ] Verify focus trap in dialogs
- [ ] Verify focus returns after dialog close

### Focus Indicators

- [ ] Verify visible focus ring on all interactive elements
- [ ] Verify focus ring has sufficient contrast

### ARIA Attributes

- [ ] Run axe DevTools or similar
- [ ] Verify no critical accessibility issues
- [ ] Check all custom components have proper roles

---

## Performance Verification

### Initial Load

- [ ] Measure time to first meaningful paint
- [ ] Verify skeleton appears within 100ms
- [ ] Verify data loads within reasonable time

### Large Data Sets

- [ ] Load flame graph with 50+ frames
- [ ] Verify smooth rendering
- [ ] Verify no lag during scroll/zoom

### Interaction Responsiveness

- [ ] Click frame - response should be instant
- [ ] Open dialog - should appear within 100ms
- [ ] Submit form - loading state should appear immediately

### Memory Usage

- [ ] Monitor memory in DevTools Performance tab
- [ ] After extended use, verify no memory leaks
- [ ] Verify cleanup on component unmount

---

## Cross-Browser Testing

### Chrome (latest)

- [ ] All functionality works
- [ ] Animations smooth
- [ ] SSE connection stable

### Firefox (latest)

- [ ] All functionality works
- [ ] Animations smooth
- [ ] SSE connection stable

### Safari (latest, if macOS)

- [ ] All functionality works
- [ ] Animations smooth
- [ ] SSE connection stable

### Edge (latest)

- [ ] All functionality works
- [ ] Animations smooth
- [ ] SSE connection stable

---

## Sign-off

| Phase | Verified By | Date | Notes |
|-------|-------------|------|-------|
| 2.4 Frame Operations | | | |
| 2.5 Real-time Updates | | | |
| 2.6 Polish & Integration | | | |

### Overall Status

- [ ] All critical features verified
- [ ] All accessibility requirements met
- [ ] Performance within acceptable limits
- [ ] Ready for production

---

## Appendix: Test Data Setup

### Creating Test Frames

```bash
# Create root frame
curl -X POST "http://localhost:3000/flame/tool?directory=/path/to/project" \
  -H "Content-Type: application/json" \
  -d '{"tool": "push", "args": {"goal": "Root task"}}'

# Create child frame
curl -X POST "http://localhost:3000/flame/tool?directory=/path/to/project" \
  -H "Content-Type: application/json" \
  -d '{"tool": "push", "args": {"goal": "Child task", "parentSessionID": "<parent-id>"}}'

# Complete a frame
curl -X POST "http://localhost:3000/flame/tool?directory=/path/to/project" \
  -H "Content-Type: application/json" \
  -d '{"tool": "pop", "args": {"status": "completed"}}'
```

### Simulating Network Issues

1. Open DevTools > Network
2. Select "Offline" from throttling dropdown
3. Perform verification steps
4. Re-enable network
5. Verify recovery behavior

### Enabling Debug Mode

If available, set `DEBUG=flame:*` environment variable to see detailed logs.

---

*Last updated: Phase 2.4-2.6 implementation*
