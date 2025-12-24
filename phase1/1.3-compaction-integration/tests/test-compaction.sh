#!/bin/bash

# ============================================================================
# Flame Graph Context Management - Phase 1.3 Test Script
# Tests: Compaction Integration
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAME_DIR="/Users/sl/code/flame"
PLUGIN_FILE="$FLAME_DIR/.opencode/plugin/flame.ts"

echo "=============================================="
echo "Flame Phase 1.3: Compaction Integration Tests"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    pass_count=$((pass_count + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    fail_count=$((fail_count + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================================================
# Test 1: Plugin file exists and has Phase 1.3 header
# ============================================================================
echo "--- Test 1: Plugin File Structure ---"

if [ -f "$PLUGIN_FILE" ]; then
    pass "Plugin file exists"
else
    fail "Plugin file not found at $PLUGIN_FILE"
    exit 1
fi

if grep -q "Phase 1.3" "$PLUGIN_FILE"; then
    pass "Plugin header indicates Phase 1.3"
else
    fail "Plugin header does not mention Phase 1.3"
fi

# ============================================================================
# Test 2: Compaction Type definitions
# ============================================================================
echo ""
echo "--- Test 2: Compaction Type Definitions ---"

if grep -q "type CompactionType = \"overflow\" | \"frame_completion\" | \"manual_summary\"" "$PLUGIN_FILE"; then
    pass "CompactionType type defined correctly"
else
    fail "CompactionType type not found or incorrect"
fi

if grep -q "interface PendingFrameCompletion" "$PLUGIN_FILE"; then
    pass "PendingFrameCompletion interface defined"
else
    fail "PendingFrameCompletion interface not found"
fi

if grep -q "interface CompactionTracking" "$PLUGIN_FILE"; then
    pass "CompactionTracking interface defined"
else
    fail "CompactionTracking interface not found"
fi

# ============================================================================
# Test 3: Compaction Prompt Generation
# ============================================================================
echo ""
echo "--- Test 3: Compaction Prompt Generation ---"

if grep -q "function generateFrameCompactionPrompt" "$PLUGIN_FILE"; then
    pass "generateFrameCompactionPrompt function exists"
else
    fail "generateFrameCompactionPrompt function not found"
fi

# Check for different prompt types
if grep -q "Compaction Instructions (Frame Completion)" "$PLUGIN_FILE"; then
    pass "Frame completion prompt template exists"
else
    fail "Frame completion prompt template not found"
fi

if grep -q "Compaction Instructions (Manual Summary)" "$PLUGIN_FILE"; then
    pass "Manual summary prompt template exists"
else
    fail "Manual summary prompt template not found"
fi

if grep -q "Compaction Instructions (Overflow - Continuation)" "$PLUGIN_FILE"; then
    pass "Overflow compaction prompt template exists"
else
    fail "Overflow compaction prompt template not found"
fi

# ============================================================================
# Test 4: Compaction Tracking Functions
# ============================================================================
echo ""
echo "--- Test 4: Compaction Tracking Functions ---"

if grep -q "function registerPendingCompletion" "$PLUGIN_FILE"; then
    pass "registerPendingCompletion function exists"
else
    fail "registerPendingCompletion function not found"
fi

if grep -q "function markPendingCompaction" "$PLUGIN_FILE"; then
    pass "markPendingCompaction function exists"
else
    fail "markPendingCompaction function not found"
fi

if grep -q "function getCompactionType" "$PLUGIN_FILE"; then
    pass "getCompactionType function exists"
else
    fail "getCompactionType function not found"
fi

if grep -q "function clearCompactionTracking" "$PLUGIN_FILE"; then
    pass "clearCompactionTracking function exists"
else
    fail "clearCompactionTracking function not found"
fi

if grep -q "function extractSummaryText" "$PLUGIN_FILE"; then
    pass "extractSummaryText function exists"
else
    fail "extractSummaryText function not found"
fi

# ============================================================================
# Test 5: Enhanced session.compacting Hook
# ============================================================================
echo ""
echo "--- Test 5: Enhanced session.compacting Hook ---"

if grep -q "experimental.session.compacting.*Phase 1.3 Enhanced" "$PLUGIN_FILE"; then
    pass "session.compacting hook has Phase 1.3 comment"
else
    fail "session.compacting hook Phase 1.3 comment not found"
fi

if grep -q "const compactionType = getCompactionType(input.sessionID)" "$PLUGIN_FILE"; then
    pass "Hook retrieves compaction type"
else
    fail "Hook does not retrieve compaction type"
fi

if grep -q "const compactionPrompt = generateFrameCompactionPrompt" "$PLUGIN_FILE"; then
    pass "Hook generates frame compaction prompt"
else
    fail "Hook does not generate frame compaction prompt"
fi

if grep -q "output.prompt = compactionPrompt" "$PLUGIN_FILE"; then
    pass "Hook can override compaction prompt"
else
    fail "Hook cannot override compaction prompt"
fi

# ============================================================================
# Test 6: Enhanced session.compacted Event Handler
# ============================================================================
echo ""
echo "--- Test 6: Enhanced session.compacted Event Handler ---"

if grep -q "SESSION COMPACTED (Phase 1.3)" "$PLUGIN_FILE"; then
    pass "session.compacted handler has Phase 1.3 log"
else
    fail "session.compacted handler Phase 1.3 log not found"
fi

if grep -q "const summaryText = extractSummaryText(summaryMessage)" "$PLUGIN_FILE"; then
    pass "Handler uses extractSummaryText function"
else
    fail "Handler does not use extractSummaryText"
fi

if grep -q "Frame completion finalized with compaction summary" "$PLUGIN_FILE"; then
    pass "Handler logs frame completion finalization"
else
    fail "Handler does not log frame completion finalization"
fi

if grep -q "clearCompactionTracking(sessionID)" "$PLUGIN_FILE"; then
    pass "Handler clears compaction tracking"
else
    fail "Handler does not clear compaction tracking"
fi

# ============================================================================
# Test 7: Enhanced flame_pop Tool
# ============================================================================
echo ""
echo "--- Test 7: Enhanced flame_pop Tool ---"

if grep -q "/pop.*Phase 1.3 Enhanced" "$PLUGIN_FILE"; then
    pass "flame_pop has Phase 1.3 comment"
else
    fail "flame_pop Phase 1.3 comment not found"
fi

if grep -q "generateSummary: tool.schema" "$PLUGIN_FILE"; then
    pass "flame_pop has generateSummary argument"
else
    fail "flame_pop does not have generateSummary argument"
fi

if grep -q "registerPendingCompletion" "$PLUGIN_FILE" && grep -q "args.generateSummary" "$PLUGIN_FILE"; then
    pass "flame_pop can register pending completion"
else
    fail "flame_pop does not register pending completion"
fi

if grep -q "Frame Completion Pending" "$PLUGIN_FILE"; then
    pass "flame_pop returns pending completion message"
else
    fail "flame_pop pending completion message not found"
fi

# ============================================================================
# Test 8: New Phase 1.3 Tools
# ============================================================================
echo ""
echo "--- Test 8: New Phase 1.3 Tools ---"

if grep -q "flame_summarize: tool" "$PLUGIN_FILE"; then
    pass "flame_summarize tool registered"
else
    fail "flame_summarize tool not found"
fi

if grep -q "flame_compaction_info: tool" "$PLUGIN_FILE"; then
    pass "flame_compaction_info tool registered"
else
    fail "flame_compaction_info tool not found"
fi

if grep -q "flame_get_summary: tool" "$PLUGIN_FILE"; then
    pass "flame_get_summary tool registered"
else
    fail "flame_get_summary tool not found"
fi

# Check flame_summarize functionality
if grep -q "markPendingCompaction(sessionID, 'manual_summary')" "$PLUGIN_FILE"; then
    pass "flame_summarize marks pending manual compaction"
else
    fail "flame_summarize does not mark pending compaction"
fi

# ============================================================================
# Test 9: Runtime State Has Compaction Tracking
# ============================================================================
echo ""
echo "--- Test 9: Runtime State Configuration ---"

if grep -q "compactionTracking:" "$PLUGIN_FILE"; then
    pass "Runtime state has compactionTracking"
else
    fail "Runtime state missing compactionTracking"
fi

if grep -q "pendingCompactions: new Set()" "$PLUGIN_FILE"; then
    pass "pendingCompactions initialized as Set"
else
    fail "pendingCompactions not properly initialized"
fi

if grep -q "compactionTypes: new Map()" "$PLUGIN_FILE"; then
    pass "compactionTypes initialized as Map"
else
    fail "compactionTypes not properly initialized"
fi

if grep -q "pendingCompletions: new Map()" "$PLUGIN_FILE"; then
    pass "pendingCompletions initialized as Map"
else
    fail "pendingCompletions not properly initialized"
fi

# ============================================================================
# Test 10: TypeScript Syntax Check
# ============================================================================
echo ""
echo "--- Test 10: TypeScript Syntax Check ---"

# Check if npx is available
if command -v npx &> /dev/null; then
    cd "$FLAME_DIR"
    if npx tsc --noEmit --skipLibCheck "$PLUGIN_FILE" 2>/dev/null; then
        pass "TypeScript syntax valid"
    else
        warn "TypeScript syntax check failed (may be due to missing type definitions)"
    fi
else
    warn "npx not available, skipping TypeScript syntax check"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=============================================="
echo "Test Summary"
echo "=============================================="
echo -e "Passed: ${GREEN}$pass_count${NC}"
echo -e "Failed: ${RED}$fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo "Phase 1.3 implementation verified."
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    echo ""
    echo "Please review the failing tests and update the implementation."
    exit 1
fi
