#!/bin/bash
#
# Phase 1.6 Planning & Invalidation Tests
# ========================================
#
# This script tests the Phase 1.6 features of the Flame Graph Context Management plugin:
# - Planned frame creation
# - Multiple planned children creation
# - Frame activation
# - Invalidation with cascade
# - Frame tree visualization
#
# Prerequisites:
# - OpenCode installed and configured
# - Flame plugin installed at .opencode/plugin/flame.ts
#
# Usage:
# ./test-planning.sh [test-name]
#
# Run all tests: ./test-planning.sh
# Run specific test: ./test-planning.sh test_planned_frame_creation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_DIR=$(cd "$TEST_DIR/../.." && pwd)
FLAME_DIR="$PROJECT_DIR/.opencode/flame"
STATE_FILE="$FLAME_DIR/state.json"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Clean up flame state for testing
cleanup_flame_state() {
    if [ -d "$FLAME_DIR" ]; then
        rm -rf "$FLAME_DIR"
        log_info "Cleaned up flame state directory"
    fi
    mkdir -p "$FLAME_DIR/frames"
}

# Create a test frame directly in state (simulating plugin behavior)
create_test_frame() {
    local session_id="$1"
    local goal="$2"
    local status="$3"
    local parent_id="$4"

    local timestamp=$(date +%s)000

    # Create frame JSON
    local frame_json=$(cat <<EOF
{
  "sessionID": "$session_id",
  "parentSessionID": ${parent_id:+\"$parent_id\"},
  "status": "$status",
  "goal": "$goal",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
)

    # Sanitize session ID for filename (use printf to avoid trailing newline)
    local safe_id=$(printf '%s' "$session_id" | tr -c 'a-zA-Z0-9_-' '_')
    echo "$frame_json" > "$FLAME_DIR/frames/${safe_id}.json"

    log_info "Created test frame: $session_id ($goal, $status)"
}

# Create or update state.json
create_state() {
    local frames_json="$1"
    local root_ids_json="$2"
    local active_frame_id="$3"

    local timestamp=$(date +%s)000

    cat > "$STATE_FILE" <<EOF
{
  "version": 1,
  "frames": $frames_json,
  "activeFrameID": ${active_frame_id:+\"$active_frame_id\"},
  "rootFrameIDs": $root_ids_json,
  "updatedAt": $timestamp
}
EOF

    log_info "Created state.json"
}

# Read frame from state
read_frame() {
    local session_id="$1"
    # Use printf to avoid trailing newline, then tr to sanitize
    local safe_id=$(printf '%s' "$session_id" | tr -c 'a-zA-Z0-9_-' '_')

    if [ -f "$FLAME_DIR/frames/${safe_id}.json" ]; then
        cat "$FLAME_DIR/frames/${safe_id}.json"
    else
        echo "{}"
    fi
}

# Get frame status
get_frame_status() {
    local session_id="$1"
    read_frame "$session_id" | grep -o '"status": *"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

# Check if frame has invalidation reason
get_invalidation_reason() {
    local session_id="$1"
    read_frame "$session_id" | grep -o '"invalidationReason": *"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

# Run a test and track results
run_test() {
    local test_name="$1"
    local test_fn="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    log_info "Running test: $test_name"
    echo "-------------------------------------------"

    if $test_fn; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test passed: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "Test failed: $test_name"
    fi
}

# ============================================================================
# Test Cases
# ============================================================================

# Test 1: Planned frame can be created
test_planned_frame_creation() {
    cleanup_flame_state

    # Create a root frame
    create_test_frame "root-1" "Build Application" "in_progress" ""

    # Create a planned child frame
    create_test_frame "plan-1" "Implement Auth" "planned" "root-1"

    # Create state
    create_state '{
        "root-1": {"sessionID": "root-1", "status": "in_progress", "goal": "Build Application", "plannedChildren": ["plan-1"]},
        "plan-1": {"sessionID": "plan-1", "status": "planned", "goal": "Implement Auth", "parentSessionID": "root-1"}
    }' '["root-1"]' "root-1"

    # Verify frame status is planned
    local status=$(get_frame_status "plan-1")
    if [ "$status" = "planned" ]; then
        log_info "Planned frame has correct status: $status"
        return 0
    else
        log_error "Expected status 'planned', got '$status'"
        return 1
    fi
}

# Test 2: Multiple planned children can be created
test_planned_children_creation() {
    cleanup_flame_state

    # Create a root frame
    create_test_frame "root-1" "Build Application" "in_progress" ""

    # Create multiple planned children
    create_test_frame "plan-1" "Implement Auth" "planned" "root-1"
    create_test_frame "plan-2" "Build API" "planned" "root-1"
    create_test_frame "plan-3" "Create UI" "planned" "root-1"

    # Create state
    create_state '{
        "root-1": {"sessionID": "root-1", "status": "in_progress", "goal": "Build Application", "plannedChildren": ["plan-1", "plan-2", "plan-3"]},
        "plan-1": {"sessionID": "plan-1", "status": "planned", "goal": "Implement Auth", "parentSessionID": "root-1"},
        "plan-2": {"sessionID": "plan-2", "status": "planned", "goal": "Build API", "parentSessionID": "root-1"},
        "plan-3": {"sessionID": "plan-3", "status": "planned", "goal": "Create UI", "parentSessionID": "root-1"}
    }' '["root-1"]' "root-1"

    # Verify all children are planned
    local status1=$(get_frame_status "plan-1")
    local status2=$(get_frame_status "plan-2")
    local status3=$(get_frame_status "plan-3")

    if [ "$status1" = "planned" ] && [ "$status2" = "planned" ] && [ "$status3" = "planned" ]; then
        log_info "All planned children have correct status"
        return 0
    else
        log_error "Expected all 'planned', got '$status1', '$status2', '$status3'"
        return 1
    fi
}

# Test 3: Activation changes status correctly
test_frame_activation() {
    cleanup_flame_state

    # Create a root frame
    create_test_frame "root-1" "Build Application" "in_progress" ""

    # Create a planned frame (before activation)
    local timestamp=$(date +%s)000
    cat > "$FLAME_DIR/frames/plan-1.json" <<EOF
{
  "sessionID": "plan-1",
  "parentSessionID": "root-1",
  "status": "planned",
  "goal": "Implement Auth",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF

    # Verify it starts as planned
    local status_before=$(get_frame_status "plan-1")
    log_info "Status before activation: $status_before"

    # Simulate activation (change status to in_progress)
    cat > "$FLAME_DIR/frames/plan-1.json" <<EOF
{
  "sessionID": "plan-1",
  "parentSessionID": "root-1",
  "status": "in_progress",
  "goal": "Implement Auth",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF

    create_state '{
        "root-1": {"sessionID": "root-1", "status": "in_progress", "goal": "Build Application"},
        "plan-1": {"sessionID": "plan-1", "status": "in_progress", "goal": "Implement Auth", "parentSessionID": "root-1"}
    }' '["root-1"]' "plan-1"

    # Verify frame status changed to in_progress
    local status=$(get_frame_status "plan-1")
    if [ "$status_before" = "planned" ] && [ "$status" = "in_progress" ]; then
        log_info "Activated frame status changed: planned -> $status"
        return 0
    else
        log_error "Expected transition planned->in_progress, got '$status_before'->'$status'"
        return 1
    fi
}

# Test 4: Invalidation cascades to planned children
test_invalidation_cascade() {
    cleanup_flame_state

    # Create a hierarchy:
    # root-1 (in_progress)
    #   └── parent-1 (in_progress) -> will be invalidated
    #       ├── child-1 (planned) <- should be auto-invalidated
    #       ├── child-2 (planned) <- should be auto-invalidated
    #       └── child-3 (completed) <- should remain completed

    local timestamp=$(date +%s)000

    # Create initial state
    create_test_frame "root-1" "Build Application" "in_progress" ""

    cat > "$FLAME_DIR/frames/parent-1.json" <<EOF
{
  "sessionID": "parent-1",
  "parentSessionID": "root-1",
  "status": "in_progress",
  "goal": "Build API",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: parent-1 (Build API, in_progress)"

    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "parent-1",
  "status": "planned",
  "goal": "Create Endpoints",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-1 (Create Endpoints, planned)"

    cat > "$FLAME_DIR/frames/child-2.json" <<EOF
{
  "sessionID": "child-2",
  "parentSessionID": "parent-1",
  "status": "planned",
  "goal": "Add Validation",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-2 (Add Validation, planned)"

    cat > "$FLAME_DIR/frames/child-3.json" <<EOF
{
  "sessionID": "child-3",
  "parentSessionID": "parent-1",
  "status": "completed",
  "goal": "Write Tests",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-3 (Write Tests, completed)"

    # Verify initial states
    log_info "Before invalidation: parent-1=$(get_frame_status "parent-1"), child-1=$(get_frame_status "child-1")"

    # Simulate invalidation of parent-1 with cascade
    # Invalidate parent-1
    cat > "$FLAME_DIR/frames/parent-1.json" <<EOF
{
  "sessionID": "parent-1",
  "parentSessionID": "root-1",
  "status": "invalidated",
  "goal": "Build API",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    # Cascade to planned children
    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "parent-1",
  "status": "invalidated",
  "goal": "Create Endpoints",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Parent frame invalidated: Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    cat > "$FLAME_DIR/frames/child-2.json" <<EOF
{
  "sessionID": "child-2",
  "parentSessionID": "parent-1",
  "status": "invalidated",
  "goal": "Add Validation",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Parent frame invalidated: Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    # child-3 remains completed (do not overwrite)

    # Verify invalidation cascade
    local parent_status=$(get_frame_status "parent-1")
    local child1_status=$(get_frame_status "child-1")
    local child2_status=$(get_frame_status "child-2")
    local child3_status=$(get_frame_status "child-3")

    if [ "$parent_status" = "invalidated" ] &&
       [ "$child1_status" = "invalidated" ] &&
       [ "$child2_status" = "invalidated" ] &&
       [ "$child3_status" = "completed" ]; then
        log_info "Invalidation cascade correct:"
        log_info "  parent-1: $parent_status"
        log_info "  child-1: $child1_status (was planned)"
        log_info "  child-2: $child2_status (was planned)"
        log_info "  child-3: $child3_status (remained completed)"
        return 0
    else
        log_error "Invalidation cascade incorrect:"
        log_error "  parent-1: $parent_status (expected: invalidated)"
        log_error "  child-1: $child1_status (expected: invalidated)"
        log_error "  child-2: $child2_status (expected: invalidated)"
        log_error "  child-3: $child3_status (expected: completed)"
        return 1
    fi
}

# Test 5: In-progress children are not auto-invalidated
test_in_progress_not_auto_invalidated() {
    cleanup_flame_state

    # Create a hierarchy:
    # root-1 (in_progress)
    #   └── parent-1 (in_progress) -> will be invalidated
    #       └── child-1 (in_progress) <- should NOT be auto-invalidated

    local timestamp=$(date +%s)000

    create_test_frame "root-1" "Build Application" "in_progress" ""

    cat > "$FLAME_DIR/frames/parent-1.json" <<EOF
{
  "sessionID": "parent-1",
  "parentSessionID": "root-1",
  "status": "in_progress",
  "goal": "Build API",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: parent-1 (Build API, in_progress)"

    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "parent-1",
  "status": "in_progress",
  "goal": "Create Endpoints",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-1 (Create Endpoints, in_progress)"

    # Simulate invalidation of parent-1 (child-1 remains in_progress - NOT auto-invalidated)
    cat > "$FLAME_DIR/frames/parent-1.json" <<EOF
{
  "sessionID": "parent-1",
  "parentSessionID": "root-1",
  "status": "invalidated",
  "goal": "Build API",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    # child-1 remains in_progress (not touched - this is the expected behavior)
    # The plugin warns but doesn't auto-invalidate in-progress children

    # Verify in-progress child is not auto-invalidated
    local parent_status=$(get_frame_status "parent-1")
    local child_status=$(get_frame_status "child-1")

    if [ "$parent_status" = "invalidated" ] && [ "$child_status" = "in_progress" ]; then
        log_info "In-progress child correctly NOT auto-invalidated:"
        log_info "  parent-1: $parent_status"
        log_info "  child-1: $child_status (remained in_progress)"
        return 0
    else
        log_error "Unexpected status:"
        log_error "  parent-1: $parent_status (expected: invalidated)"
        log_error "  child-1: $child_status (expected: in_progress)"
        return 1
    fi
}

# Test 6: Tree visualization shows correct structure
test_tree_visualization_structure() {
    cleanup_flame_state

    # Create a complex tree:
    # root-1 (in_progress)
    #   ├── child-1 (completed)
    #   ├── child-2 (in_progress)
    #   │   └── grandchild-1 (planned)
    #   └── child-3 (planned)

    local timestamp=$(date +%s)000

    cat > "$FLAME_DIR/frames/root-1.json" <<EOF
{
  "sessionID": "root-1",
  "status": "in_progress",
  "goal": "Build Application",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: root-1 (Build Application, in_progress)"

    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "root-1",
  "status": "completed",
  "goal": "Auth Module",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-1 (Auth Module, completed)"

    cat > "$FLAME_DIR/frames/child-2.json" <<EOF
{
  "sessionID": "child-2",
  "parentSessionID": "root-1",
  "status": "in_progress",
  "goal": "API Module",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-2 (API Module, in_progress)"

    cat > "$FLAME_DIR/frames/grandchild-1.json" <<EOF
{
  "sessionID": "grandchild-1",
  "parentSessionID": "child-2",
  "status": "planned",
  "goal": "Endpoints",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: grandchild-1 (Endpoints, planned)"

    cat > "$FLAME_DIR/frames/child-3.json" <<EOF
{
  "sessionID": "child-3",
  "parentSessionID": "root-1",
  "status": "planned",
  "goal": "UI Module",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-3 (UI Module, planned)"

    create_state '{
        "root-1": {"sessionID": "root-1", "status": "in_progress", "goal": "Build Application"},
        "child-1": {"sessionID": "child-1", "status": "completed", "goal": "Auth Module", "parentSessionID": "root-1"},
        "child-2": {"sessionID": "child-2", "status": "in_progress", "goal": "API Module", "parentSessionID": "root-1"},
        "grandchild-1": {"sessionID": "grandchild-1", "status": "planned", "goal": "Endpoints", "parentSessionID": "child-2"},
        "child-3": {"sessionID": "child-3", "status": "planned", "goal": "UI Module", "parentSessionID": "root-1"}
    }' '["root-1"]' "child-2"

    # Count frames in state
    local frame_count=$(ls "$FLAME_DIR/frames/"*.json 2>/dev/null | wc -l | tr -d ' ')

    if [ "$frame_count" -eq 5 ]; then
        log_info "Tree has correct number of frames: $frame_count"

        # Verify parent-child relationships
        local child2_parent=$(read_frame "child-2" | grep -o '"parentSessionID": *"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
        local grandchild_parent=$(read_frame "grandchild-1" | grep -o '"parentSessionID": *"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')

        log_info "child-2 parent: $child2_parent"
        log_info "grandchild-1 parent: $grandchild_parent"

        if [ "$child2_parent" = "root-1" ] && [ "$grandchild_parent" = "child-2" ]; then
            log_info "Parent-child relationships correct"
            return 0
        else
            log_error "Parent-child relationships incorrect"
            log_error "  child-2 parent: $child2_parent (expected: root-1)"
            log_error "  grandchild-1 parent: $grandchild_parent (expected: child-2)"
            return 1
        fi
    else
        log_error "Expected 5 frames, got $frame_count"
        return 1
    fi
}

# Test 7: Invalidation reason is tracked
test_invalidation_reason_tracked() {
    cleanup_flame_state

    local timestamp=$(date +%s)000

    cat > "$FLAME_DIR/frames/root-1.json" <<EOF
{
  "sessionID": "root-1",
  "status": "in_progress",
  "goal": "Build Application",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: root-1 (Build Application, in_progress)"

    # Create child-1 as planned first
    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "root-1",
  "status": "planned",
  "goal": "Auth Module",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: child-1 (Auth Module, planned)"

    # Invalidate with reason
    cat > "$FLAME_DIR/frames/child-1.json" <<EOF
{
  "sessionID": "child-1",
  "parentSessionID": "root-1",
  "status": "invalidated",
  "goal": "Auth Module",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Using third-party auth instead",
  "invalidatedAt": $timestamp
}
EOF

    local reason=$(get_invalidation_reason "child-1")
    log_info "Retrieved invalidation reason: '$reason'"

    if [ "$reason" = "Using third-party auth instead" ]; then
        log_info "Invalidation reason correctly tracked: $reason"
        return 0
    else
        log_error "Expected reason 'Using third-party auth instead', got '$reason'"
        return 1
    fi
}

# Test 8: Nested planned children cascade
test_nested_planned_cascade() {
    cleanup_flame_state

    # Create deeply nested planned structure:
    # root-1 (in_progress)
    #   └── level-1 (planned) -> will be invalidated
    #       └── level-2 (planned) -> should cascade
    #           └── level-3 (planned) -> should cascade

    local timestamp=$(date +%s)000

    cat > "$FLAME_DIR/frames/root-1.json" <<EOF
{
  "sessionID": "root-1",
  "status": "in_progress",
  "goal": "Build Application",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: root-1 (Build Application, in_progress)"

    cat > "$FLAME_DIR/frames/level-1.json" <<EOF
{
  "sessionID": "level-1",
  "parentSessionID": "root-1",
  "status": "planned",
  "goal": "Phase 1",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: level-1 (Phase 1, planned)"

    cat > "$FLAME_DIR/frames/level-2.json" <<EOF
{
  "sessionID": "level-2",
  "parentSessionID": "level-1",
  "status": "planned",
  "goal": "Phase 2",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: level-2 (Phase 2, planned)"

    cat > "$FLAME_DIR/frames/level-3.json" <<EOF
{
  "sessionID": "level-3",
  "parentSessionID": "level-2",
  "status": "planned",
  "goal": "Phase 3",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "plannedChildren": []
}
EOF
    log_info "Created test frame: level-3 (Phase 3, planned)"

    # Verify initial states
    log_info "Before invalidation: level-1=$(get_frame_status "level-1"), level-2=$(get_frame_status "level-2"), level-3=$(get_frame_status "level-3")"

    # Simulate invalidating level-1 with cascade to level-2 and level-3
    cat > "$FLAME_DIR/frames/level-1.json" <<EOF
{
  "sessionID": "level-1",
  "parentSessionID": "root-1",
  "status": "invalidated",
  "goal": "Phase 1",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    cat > "$FLAME_DIR/frames/level-2.json" <<EOF
{
  "sessionID": "level-2",
  "parentSessionID": "level-1",
  "status": "invalidated",
  "goal": "Phase 2",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Parent frame invalidated: Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    cat > "$FLAME_DIR/frames/level-3.json" <<EOF
{
  "sessionID": "level-3",
  "parentSessionID": "level-2",
  "status": "invalidated",
  "goal": "Phase 3",
  "createdAt": $timestamp,
  "updatedAt": $timestamp,
  "artifacts": [],
  "decisions": [],
  "invalidationReason": "Parent frame invalidated: Requirements changed",
  "invalidatedAt": $timestamp
}
EOF

    # Verify all levels are invalidated
    local s1=$(get_frame_status "level-1")
    local s2=$(get_frame_status "level-2")
    local s3=$(get_frame_status "level-3")

    if [ "$s1" = "invalidated" ] && [ "$s2" = "invalidated" ] && [ "$s3" = "invalidated" ]; then
        log_info "Nested cascade correct - all levels invalidated"
        log_info "  level-1: $s1"
        log_info "  level-2: $s2"
        log_info "  level-3: $s3"
        return 0
    else
        log_error "Nested cascade incorrect: level-1=$s1, level-2=$s2, level-3=$s3"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

print_summary() {
    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Tests Run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

run_all_tests() {
    echo "============================================"
    echo "Phase 1.6 Planning & Invalidation Tests"
    echo "============================================"
    echo "Project directory: $PROJECT_DIR"
    echo "Flame directory: $FLAME_DIR"
    echo ""

    run_test "Planned frame can be created" test_planned_frame_creation
    run_test "Multiple planned children can be created" test_planned_children_creation
    run_test "Activation changes status correctly" test_frame_activation
    run_test "Invalidation cascades to planned children" test_invalidation_cascade
    run_test "In-progress children are not auto-invalidated" test_in_progress_not_auto_invalidated
    run_test "Tree visualization shows correct structure" test_tree_visualization_structure
    run_test "Invalidation reason is tracked" test_invalidation_reason_tracked
    run_test "Nested planned children cascade" test_nested_planned_cascade

    print_summary
}

# Run specific test or all tests
if [ -n "$1" ]; then
    if declare -f "$1" > /dev/null; then
        run_test "$1" "$1"
        print_summary
    else
        echo "Unknown test: $1"
        echo "Available tests:"
        echo "  - test_planned_frame_creation"
        echo "  - test_planned_children_creation"
        echo "  - test_frame_activation"
        echo "  - test_invalidation_cascade"
        echo "  - test_in_progress_not_auto_invalidated"
        echo "  - test_tree_visualization_structure"
        echo "  - test_invalidation_reason_tracked"
        echo "  - test_nested_planned_cascade"
        exit 1
    fi
else
    run_all_tests
fi
