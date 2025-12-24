#!/bin/bash
#
# Flame Plugin - State Manager Unit Test
#
# This script directly tests the file-based state management
# by running a single opencode command and inspecting the results.
#
# Usage: ./test-state-manager.sh
#

set -e

FLAME_DIR="/Users/sl/code/flame"
FLAME_STATE_DIR="$FLAME_DIR/.opencode/flame"
FRAMES_DIR="$FLAME_STATE_DIR/frames"
STATE_FILE="$FLAME_STATE_DIR/state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Flame State Manager Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Clean previous state
echo -e "${YELLOW}Step 1: Cleaning previous state...${NC}"
rm -rf "$FLAME_STATE_DIR/state.json" 2>/dev/null || true
rm -rf "$FRAMES_DIR" 2>/dev/null || true
echo "  Done."
echo ""

# Step 2: Run opencode with a simple prompt
echo -e "${YELLOW}Step 2: Running opencode to trigger plugin...${NC}"
cd "$FLAME_DIR"

# Capture output (no timeout on macOS)
OUTPUT=$(opencode run --print-logs "Hello! Just say hi back briefly." 2>&1) || {
    echo -e "${RED}Error: opencode command failed${NC}"
    echo "Output:"
    echo "$OUTPUT" | head -50
    exit 1
}

echo "  OpenCode execution complete."
echo ""

# Step 3: Check plugin initialization
echo -e "${YELLOW}Step 3: Checking plugin initialization...${NC}"
if echo "$OUTPUT" | grep -q "FLAME PLUGIN INITIALIZED"; then
    echo -e "  ${GREEN}[PASS]${NC} Plugin initialized"
else
    echo -e "  ${RED}[FAIL]${NC} Plugin initialization not detected"
    echo "  Output preview:"
    echo "$OUTPUT" | head -30
    exit 1
fi

# Step 4: Check state directory
echo ""
echo -e "${YELLOW}Step 4: Checking state directory...${NC}"
if [ -d "$FLAME_STATE_DIR" ]; then
    echo -e "  ${GREEN}[PASS]${NC} State directory exists: $FLAME_STATE_DIR"
else
    echo -e "  ${RED}[FAIL]${NC} State directory not created"
    exit 1
fi

# Step 5: Check state file
echo ""
echo -e "${YELLOW}Step 5: Checking state file...${NC}"
if [ -f "$STATE_FILE" ]; then
    echo -e "  ${GREEN}[PASS]${NC} State file exists: $STATE_FILE"
else
    echo -e "  ${RED}[FAIL]${NC} State file not created"
    exit 1
fi

# Step 6: Validate state JSON
echo ""
echo -e "${YELLOW}Step 6: Validating state JSON...${NC}"
if jq empty "$STATE_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}[PASS]${NC} State file is valid JSON"
else
    echo -e "  ${RED}[FAIL]${NC} State file is not valid JSON"
    cat "$STATE_FILE"
    exit 1
fi

# Display state content
echo ""
echo -e "${YELLOW}State file content:${NC}"
jq '.' "$STATE_FILE"

# Step 7: Check frames directory
echo ""
echo -e "${YELLOW}Step 7: Checking frames directory...${NC}"
if [ -d "$FRAMES_DIR" ]; then
    echo -e "  ${GREEN}[PASS]${NC} Frames directory exists: $FRAMES_DIR"
else
    echo -e "  ${RED}[FAIL]${NC} Frames directory not created"
    exit 1
fi

# Step 8: Check frame files
echo ""
echo -e "${YELLOW}Step 8: Checking frame files...${NC}"
FRAME_COUNT=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$FRAME_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} Found $FRAME_COUNT frame file(s)"
else
    echo -e "  ${RED}[FAIL]${NC} No frame files found"
    exit 1
fi

# Display frame content
echo ""
echo -e "${YELLOW}Frame file content:${NC}"
for f in "$FRAMES_DIR"/*.json; do
    echo "--- $(basename "$f") ---"
    jq '.' "$f"
done

# Step 9: Verify frame structure
echo ""
echo -e "${YELLOW}Step 9: Verifying frame structure...${NC}"
FIRST_FRAME=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | head -1)
if [ -n "$FIRST_FRAME" ]; then
    HAS_SESSION=$(jq 'has("sessionID")' "$FIRST_FRAME")
    HAS_STATUS=$(jq 'has("status")' "$FIRST_FRAME")
    HAS_GOAL=$(jq 'has("goal")' "$FIRST_FRAME")
    HAS_CREATED=$(jq 'has("createdAt")' "$FIRST_FRAME")

    if [ "$HAS_SESSION" = "true" ]; then
        echo -e "  ${GREEN}[PASS]${NC} Frame has sessionID"
    else
        echo -e "  ${RED}[FAIL]${NC} Frame missing sessionID"
        exit 1
    fi

    if [ "$HAS_STATUS" = "true" ]; then
        STATUS=$(jq -r '.status' "$FIRST_FRAME")
        echo -e "  ${GREEN}[PASS]${NC} Frame has status: $STATUS"
    else
        echo -e "  ${RED}[FAIL]${NC} Frame missing status"
        exit 1
    fi

    if [ "$HAS_GOAL" = "true" ]; then
        GOAL=$(jq -r '.goal' "$FIRST_FRAME")
        echo -e "  ${GREEN}[PASS]${NC} Frame has goal: $GOAL"
    else
        echo -e "  ${RED}[FAIL]${NC} Frame missing goal"
        exit 1
    fi

    if [ "$HAS_CREATED" = "true" ]; then
        echo -e "  ${GREEN}[PASS]${NC} Frame has createdAt timestamp"
    else
        echo -e "  ${RED}[FAIL]${NC} Frame missing createdAt"
        exit 1
    fi
fi

# Step 10: Check for context injection in logs
echo ""
echo -e "${YELLOW}Step 10: Checking hook execution...${NC}"
if echo "$OUTPUT" | grep -q "CHAT.MESSAGE"; then
    echo -e "  ${GREEN}[PASS]${NC} chat.message hook executed"
else
    echo -e "  ${YELLOW}[WARN]${NC} chat.message hook not detected in logs"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}All critical tests passed!${NC}"
echo ""
echo "State Manager functionality verified:"
echo "  - Plugin loads and initializes"
echo "  - State directory created"
echo "  - State file persisted as valid JSON"
echo "  - Frame files created with correct structure"
echo ""
echo "Files created:"
echo "  - $STATE_FILE"
ls -la "$FRAMES_DIR"/*.json 2>/dev/null || true
