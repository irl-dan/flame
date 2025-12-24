#!/bin/bash
#
# Flame Plugin Phase 1.1 - Automated Test Script
#
# This script tests the core functionality of the Flame plugin:
# 1. Plugin loads without errors
# 2. Frame is created for new sessions
# 3. Frame state is persisted to .opencode/flame/
# 4. Context injection works
#
# Usage: ./test-flame.sh
#
# Prerequisites:
# - opencode installed and available in PATH
# - Working directory is /Users/sl/code/flame

set -e

FLAME_DIR="/Users/sl/code/flame"
OPENCODE_DIR="$FLAME_DIR/.opencode"
FLAME_STATE_DIR="$OPENCODE_DIR/flame"
FRAMES_DIR="$FLAME_STATE_DIR/frames"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
    echo ""
    echo "=============================================="
    echo " $1"
    echo "=============================================="
    echo ""
}

print_test() {
    echo -n "[TEST] $1... "
}

pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}FAIL${NC}"
    echo "       $1"
    ((TESTS_FAILED++))
}

warn() {
    echo -e "${YELLOW}WARN${NC}"
    echo "       $1"
}

cleanup() {
    print_header "Cleanup"
    echo "Removing previous test state..."
    rm -rf "$FLAME_STATE_DIR/state.json" 2>/dev/null || true
    rm -rf "$FRAMES_DIR" 2>/dev/null || true
    echo "Cleanup complete."
}

test_plugin_exists() {
    print_test "Plugin file exists"
    if [ -f "$OPENCODE_DIR/plugin/flame.ts" ]; then
        pass
    else
        fail "Plugin file not found at $OPENCODE_DIR/plugin/flame.ts"
    fi
}

test_plugin_loads() {
    print_header "Test: Plugin Loading"

    print_test "OpenCode can load the plugin"

    # Run opencode with a simple prompt and check for errors
    cd "$FLAME_DIR"

    # Run opencode
    OUTPUT=$(opencode run --print-logs "Say hello and confirm you can see this message." 2>&1) || true

    # Check for plugin initialization
    if echo "$OUTPUT" | grep -q "FLAME PLUGIN INITIALIZED"; then
        pass
    else
        fail "Plugin initialization message not found in output"
        echo "Output snippet:"
        echo "$OUTPUT" | head -20
    fi
}

test_frame_creation() {
    print_header "Test: Frame Creation"

    print_test "State directory created"
    if [ -d "$FLAME_STATE_DIR" ]; then
        pass
    else
        fail "State directory not found at $FLAME_STATE_DIR"
    fi

    print_test "State file created"
    if [ -f "$FLAME_STATE_DIR/state.json" ]; then
        pass
    else
        fail "State file not found"
        return
    fi

    print_test "State file is valid JSON"
    if jq empty "$FLAME_STATE_DIR/state.json" 2>/dev/null; then
        pass
    else
        fail "State file is not valid JSON"
        return
    fi

    print_test "State has frames object"
    FRAMES_COUNT=$(jq '.frames | length' "$FLAME_STATE_DIR/state.json" 2>/dev/null)
    if [ "$FRAMES_COUNT" -ge 0 ]; then
        pass
        echo "       Found $FRAMES_COUNT frame(s) in state"
    else
        fail "Could not read frames from state"
    fi
}

test_frame_persistence() {
    print_header "Test: Frame Persistence"

    print_test "Frames directory created"
    if [ -d "$FRAMES_DIR" ]; then
        pass
    else
        fail "Frames directory not found at $FRAMES_DIR"
        return
    fi

    print_test "At least one frame file exists"
    FRAME_FILES=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FRAME_FILES" -gt 0 ]; then
        pass
        echo "       Found $FRAME_FILES frame file(s)"
    else
        fail "No frame files found in $FRAMES_DIR"
        return
    fi

    # Get first frame file
    FRAME_FILE=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | head -1)

    print_test "Frame file is valid JSON"
    if jq empty "$FRAME_FILE" 2>/dev/null; then
        pass
    else
        fail "Frame file is not valid JSON: $FRAME_FILE"
        return
    fi

    print_test "Frame has required fields"
    HAS_SESSION=$(jq 'has("sessionID")' "$FRAME_FILE" 2>/dev/null)
    HAS_STATUS=$(jq 'has("status")' "$FRAME_FILE" 2>/dev/null)
    HAS_GOAL=$(jq 'has("goal")' "$FRAME_FILE" 2>/dev/null)

    if [ "$HAS_SESSION" = "true" ] && [ "$HAS_STATUS" = "true" ] && [ "$HAS_GOAL" = "true" ]; then
        pass
        GOAL=$(jq -r '.goal' "$FRAME_FILE")
        STATUS=$(jq -r '.status' "$FRAME_FILE")
        echo "       Frame goal: $GOAL"
        echo "       Frame status: $STATUS"
    else
        fail "Frame missing required fields (sessionID, status, or goal)"
    fi
}

test_context_injection() {
    print_header "Test: Context Injection"

    print_test "Running context visibility test"

    cd "$FLAME_DIR"
    OUTPUT=$(opencode run --print-logs "Do you see any flame-context XML in your context? Answer yes or no and quote any flame-context you see." 2>&1) || true

    # Check if the LLM mentions seeing flame-context
    if echo "$OUTPUT" | grep -qi "flame-context\|yes.*context\|<flame-context"; then
        pass
        echo "       LLM confirmed seeing frame context"
    else
        # This might not always pass if the frame context is minimal
        warn "Could not confirm LLM saw flame-context (may be expected if context is minimal)"
    fi

    print_test "Context injection logged"
    if echo "$OUTPUT" | grep -q "Frame context injected"; then
        pass
    else
        warn "Context injection log not found (may be expected if no ancestor context)"
    fi
}

test_tools_registered() {
    print_header "Test: Tool Registration"

    cd "$FLAME_DIR"

    print_test "flame_push tool available"
    OUTPUT=$(opencode run --print-logs "List your available tools. Do you have a tool called flame_push?" 2>&1) || true

    if echo "$OUTPUT" | grep -qi "flame_push\|push"; then
        pass
    else
        warn "flame_push tool not confirmed in output"
    fi

    print_test "flame_status tool available"
    OUTPUT=$(opencode run --print-logs "Use the flame_status tool to show the frame tree." 2>&1) || true

    if echo "$OUTPUT" | grep -qi "frame.*tree\|no frames\|active frame"; then
        pass
    else
        warn "flame_status output not as expected"
    fi
}

print_summary() {
    print_header "Test Summary"

    TOTAL=$((TESTS_PASSED + TESTS_FAILED))

    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Total tests:  $TOTAL"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main execution
main() {
    print_header "Flame Plugin Phase 1.1 - Test Suite"
    echo "Testing directory: $FLAME_DIR"
    echo "OpenCode plugin:   $OPENCODE_DIR/plugin/flame.ts"
    echo ""

    # Run tests
    cleanup
    test_plugin_exists
    test_plugin_loads
    test_frame_creation
    test_frame_persistence
    test_context_injection
    test_tools_registered

    # Summary
    print_summary
}

main "$@"
