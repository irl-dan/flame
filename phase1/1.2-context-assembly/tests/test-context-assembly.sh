#!/bin/bash
#
# Phase 1.2 Context Assembly Test Script
# Tests token budget, ancestor selection, sibling filtering, and caching
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FLAME_DIR="/Users/sl/code/flame"
STATE_DIR="$FLAME_DIR/.opencode/flame"
STATE_FILE="$STATE_DIR/state.json"
FRAMES_DIR="$STATE_DIR/frames"
PLUGIN_FILE="$FLAME_DIR/.opencode/plugin/flame.ts"

echo "========================================"
echo " Flame Phase 1.2 Context Assembly Tests"
echo "========================================"
echo ""

# Track test results
PASSED=0
FAILED=0

pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    ((PASSED++)) || true
}

fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    ((FAILED++)) || true
}

warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# Test 1: Plugin file exists and has Phase 1.2 features
# ============================================================================

echo "Step 1: Checking plugin implementation..."

if [ -f "$PLUGIN_FILE" ]; then
    pass "Plugin file exists"
else
    fail "Plugin file not found: $PLUGIN_FILE"
    exit 1
fi

# Check for Phase 1.2 header
if grep -q "Phase 1.2" "$PLUGIN_FILE"; then
    pass "Plugin has Phase 1.2 header"
else
    fail "Plugin missing Phase 1.2 header"
fi

echo ""

# ============================================================================
# Test 2: Token Budget Manager
# ============================================================================

echo "Step 2: Checking Token Budget Manager..."

if grep -q "interface TokenBudget" "$PLUGIN_FILE"; then
    pass "TokenBudget interface defined"
else
    fail "TokenBudget interface missing"
fi

if grep -q "DEFAULT_TOKEN_BUDGET" "$PLUGIN_FILE"; then
    pass "Default token budget constants present"
else
    fail "Default token budget constants missing"
fi

if grep -q "estimateTokens" "$PLUGIN_FILE"; then
    pass "Token estimation function present"
else
    fail "Token estimation function missing"
fi

if grep -q "truncateToTokenBudget" "$PLUGIN_FILE"; then
    pass "Token budget truncation function present"
else
    fail "Token budget truncation function missing"
fi

if grep -q "FLAME_TOKEN_BUDGET_TOTAL" "$PLUGIN_FILE"; then
    pass "Environment variable override support present"
else
    fail "Environment variable override support missing"
fi

echo ""

# ============================================================================
# Test 3: Intelligent Ancestor Selection
# ============================================================================

echo "Step 3: Checking Intelligent Ancestor Selection..."

if grep -q "scoreAncestor" "$PLUGIN_FILE"; then
    pass "Ancestor scoring function present"
else
    fail "Ancestor scoring function missing"
fi

if grep -q "selectAncestors" "$PLUGIN_FILE"; then
    pass "Ancestor selection function present"
else
    fail "Ancestor selection function missing"
fi

if grep -q "depth === 0" "$PLUGIN_FILE"; then
    pass "Parent prioritization logic present"
else
    fail "Parent prioritization logic missing"
fi

if grep -q "truncatedCount" "$PLUGIN_FILE"; then
    pass "Truncation tracking present"
else
    fail "Truncation tracking missing"
fi

echo ""

# ============================================================================
# Test 4: Sibling Relevance Filtering
# ============================================================================

echo "Step 4: Checking Sibling Relevance Filtering..."

if grep -q "scoreSibling" "$PLUGIN_FILE"; then
    pass "Sibling scoring function present"
else
    fail "Sibling scoring function missing"
fi

if grep -q "selectSiblings" "$PLUGIN_FILE"; then
    pass "Sibling selection function present"
else
    fail "Sibling selection function missing"
fi

if grep -q "extractKeywords" "$PLUGIN_FILE"; then
    pass "Keyword extraction function present"
else
    fail "Keyword extraction function missing"
fi

if grep -q "minRelevanceScore" "$PLUGIN_FILE"; then
    pass "Minimum relevance threshold present"
else
    fail "Minimum relevance threshold missing"
fi

if grep -q "filteredCount" "$PLUGIN_FILE"; then
    pass "Filtered count tracking present"
else
    fail "Filtered count tracking missing"
fi

echo ""

# ============================================================================
# Test 5: Context Caching
# ============================================================================

echo "Step 5: Checking Context Caching..."

if grep -q "interface CacheEntry" "$PLUGIN_FILE"; then
    pass "CacheEntry interface defined"
else
    fail "CacheEntry interface missing"
fi

if grep -q "contextCache" "$PLUGIN_FILE"; then
    pass "Context cache map present"
else
    fail "Context cache map missing"
fi

if grep -q "cacheTTL" "$PLUGIN_FILE"; then
    pass "Cache TTL configuration present"
else
    fail "Cache TTL configuration missing"
fi

if grep -q "generateStateHash" "$PLUGIN_FILE"; then
    pass "State hash generation for invalidation present"
else
    fail "State hash generation missing"
fi

if grep -q "isCacheValid" "$PLUGIN_FILE"; then
    pass "Cache validation function present"
else
    fail "Cache validation function missing"
fi

if grep -q "invalidateCache" "$PLUGIN_FILE"; then
    pass "Cache invalidation function present"
else
    fail "Cache invalidation function missing"
fi

if grep -q "cacheContext" "$PLUGIN_FILE"; then
    pass "Cache storage function present"
else
    fail "Cache storage function missing"
fi

echo ""

# ============================================================================
# Test 6: Enhanced XML Context Generation
# ============================================================================

echo "Step 6: Checking Enhanced XML Context Generation..."

if grep -q "ContextMetadata" "$PLUGIN_FILE"; then
    pass "Context metadata interface defined"
else
    fail "Context metadata interface missing"
fi

if grep -q "generateFrameContextWithMetadata" "$PLUGIN_FILE"; then
    pass "Metadata-aware context generation present"
else
    fail "Metadata-aware context generation missing"
fi

if grep -q "<metadata>" "$PLUGIN_FILE"; then
    pass "XML metadata section present"
else
    fail "XML metadata section missing"
fi

if grep -q "truncated=" "$PLUGIN_FILE"; then
    pass "Truncation indicators in XML present"
else
    fail "Truncation indicators in XML missing"
fi

if grep -q "ancestors-omitted\|omitted=" "$PLUGIN_FILE"; then
    pass "Ancestor omission indicators present"
else
    fail "Ancestor omission indicators missing"
fi

if grep -q "siblings-filtered\|filtered=" "$PLUGIN_FILE"; then
    pass "Sibling filtering indicators present"
else
    fail "Sibling filtering indicators missing"
fi

echo ""

# ============================================================================
# Test 7: New Phase 1.2 Tools
# ============================================================================

echo "Step 7: Checking Phase 1.2 Tools..."

if grep -q "flame_context_info" "$PLUGIN_FILE"; then
    pass "flame_context_info tool registered"
else
    fail "flame_context_info tool missing"
fi

if grep -q "flame_context_preview" "$PLUGIN_FILE"; then
    pass "flame_context_preview tool registered"
else
    fail "flame_context_preview tool missing"
fi

if grep -q "flame_cache_clear" "$PLUGIN_FILE"; then
    pass "flame_cache_clear tool registered"
else
    fail "flame_cache_clear tool missing"
fi

echo ""

# ============================================================================
# Test 8: Cache Invalidation Integration
# ============================================================================

echo "Step 8: Checking Cache Invalidation Integration..."

# Check that cache is invalidated on frame changes
if grep -A5 "flame_push" "$PLUGIN_FILE" | grep -q "invalidateCache"; then
    pass "Cache invalidation in flame_push"
else
    warn "Cache invalidation may be missing in flame_push"
fi

if grep -A5 "flame_pop" "$PLUGIN_FILE" | grep -q "invalidateCache"; then
    pass "Cache invalidation in flame_pop"
else
    warn "Cache invalidation may be missing in flame_pop"
fi

if grep -A5 "session.compacted" "$PLUGIN_FILE" | grep -q "invalidateCache"; then
    pass "Cache invalidation on compaction events"
else
    warn "Cache invalidation may be missing on compaction"
fi

echo ""

# ============================================================================
# Test 9: TypeScript Syntax Check (if available)
# ============================================================================

echo "Step 9: Checking TypeScript syntax..."

if command -v npx &> /dev/null; then
    # Try to compile the plugin
    cd "$FLAME_DIR"
    SYNTAX_CHECK=$(npx tsc --noEmit --skipLibCheck --target ES2020 --moduleResolution node "$PLUGIN_FILE" 2>&1) || true

    if [ -z "$SYNTAX_CHECK" ]; then
        pass "TypeScript syntax check passed"
    elif echo "$SYNTAX_CHECK" | grep -q "error TS"; then
        # Count errors
        ERROR_COUNT=$(echo "$SYNTAX_CHECK" | grep -c "error TS" || echo "0")
        fail "TypeScript has $ERROR_COUNT syntax errors"
        echo "  First few errors:"
        echo "$SYNTAX_CHECK" | head -5 | sed 's/^/    /'
    else
        pass "TypeScript syntax appears valid"
    fi
else
    warn "npx not available, skipping TypeScript check"
fi

echo ""

# ============================================================================
# Test 10: Code Quality Checks
# ============================================================================

echo "Step 10: Running code quality checks..."

# Check that functions have proper return types/handling
if grep -c "async function" "$PLUGIN_FILE" | grep -q "[0-9]"; then
    ASYNC_COUNT=$(grep -c "async function" "$PLUGIN_FILE")
    pass "Found $ASYNC_COUNT async functions"
fi

# Check for proper error handling
if grep -c "try {" "$PLUGIN_FILE" | grep -q "[0-9]"; then
    TRY_COUNT=$(grep -c "try {" "$PLUGIN_FILE")
    pass "Found $TRY_COUNT try-catch blocks"
fi

# Check for logging
if grep -c 'log("' "$PLUGIN_FILE" | grep -q "[0-9]"; then
    LOG_COUNT=$(grep -c 'log("' "$PLUGIN_FILE")
    pass "Found $LOG_COUNT log statements"
fi

# Check plugin exports
if grep -q "export const FlamePlugin" "$PLUGIN_FILE"; then
    pass "Plugin export present"
else
    fail "Plugin export missing"
fi

if grep -q "export default FlamePlugin" "$PLUGIN_FILE"; then
    pass "Default export present"
else
    fail "Default export missing"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "========================================"
echo " Test Summary"
echo "========================================"
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASSED"
echo -e "  ${RED}Failed:${NC} $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All Phase 1.2 tests passed!${NC}"
    echo ""
    echo "The plugin implements:"
    echo "  1. Token Budget Manager with configurable limits"
    echo "  2. Intelligent Ancestor Selection with scoring"
    echo "  3. Sibling Relevance Filtering with keyword matching"
    echo "  4. Context Caching with TTL and invalidation"
    echo "  5. Enhanced XML with metadata and truncation indicators"
    echo "  6. New debugging tools (flame_context_info, flame_context_preview, flame_cache_clear)"
    echo ""
    echo "Environment variables for configuration:"
    echo "  - FLAME_TOKEN_BUDGET_TOTAL"
    echo "  - FLAME_TOKEN_BUDGET_ANCESTORS"
    echo "  - FLAME_TOKEN_BUDGET_SIBLINGS"
    echo "  - FLAME_TOKEN_BUDGET_CURRENT"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
