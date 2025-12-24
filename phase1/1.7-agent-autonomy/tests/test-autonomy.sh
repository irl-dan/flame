#!/bin/bash
#
# Phase 1.7: Agent Autonomy Test Script
#
# Tests the autonomy configuration, push/pop heuristics, and suggestion system.
#
# Usage: ./test-autonomy.sh
#
# Prerequisites:
# - OpenCode must be installed and in PATH
# - flame plugin must be loaded
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLAME_DIR="$PROJECT_DIR/.opencode/flame"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

log_pass() {
    echo -e "${GREEN}PASS:${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

run_test() {
    local name="$1"
    local command="$2"
    local expected="$3"

    ((TESTS_RUN++))
    log_test "$name"

    if eval "$command"; then
        log_pass "$name"
        return 0
    else
        log_fail "$name"
        return 1
    fi
}

# ==============================================================================
# Test 1: Autonomy Configuration Types
# ==============================================================================

test_autonomy_config_types() {
    log_test "Verifying AutonomyConfig type exists in plugin"

    if grep -q "interface AutonomyConfig" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "AutonomyConfig interface found"
    else
        log_fail "AutonomyConfig interface not found"
        return 1
    fi

    # Check for autonomy levels
    if grep -q "type AutonomyLevel = \"manual\" | \"suggest\" | \"auto\"" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "AutonomyLevel type found"
    else
        log_fail "AutonomyLevel type not found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 2: Environment Variable Loading
# ==============================================================================

test_env_variable_loading() {
    log_test "Verifying environment variable loading function"

    if grep -q "loadAutonomyConfigFromEnv" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "loadAutonomyConfigFromEnv function found"
    else
        log_fail "loadAutonomyConfigFromEnv function not found"
        return 1
    fi

    # Check for specific env variables
    local env_vars=("FLAME_AUTONOMY_LEVEL" "FLAME_PUSH_THRESHOLD" "FLAME_POP_THRESHOLD")
    for var in "${env_vars[@]}"; do
        if grep -q "$var" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
            log_pass "Environment variable $var handling found"
        else
            log_fail "Environment variable $var handling not found"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# Test 3: Push Heuristics Implementation
# ==============================================================================

test_push_heuristics() {
    log_test "Verifying push heuristics implementation"

    if grep -q "evaluatePushHeuristics" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "evaluatePushHeuristics function found"
    else
        log_fail "evaluatePushHeuristics function not found"
        return 1
    fi

    # Check for specific heuristics
    local heuristics=("failure_boundary" "context_switch" "complexity" "duration")
    for h in "${heuristics[@]}"; do
        if grep -q "'$h'" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
            log_pass "Heuristic '$h' found"
        else
            log_fail "Heuristic '$h' not found"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# Test 4: Pop Heuristics Implementation
# ==============================================================================

test_pop_heuristics() {
    log_test "Verifying pop heuristics implementation"

    if grep -q "evaluatePopHeuristics" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "evaluatePopHeuristics function found"
    else
        log_fail "evaluatePopHeuristics function not found"
        return 1
    fi

    # Check for specific heuristics
    local heuristics=("goal_completion" "stagnation" "context_overflow")
    for h in "${heuristics[@]}"; do
        if grep -q "'$h'" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
            log_pass "Heuristic '$h' found"
        else
            log_fail "Heuristic '$h' not found"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# Test 5: Tool Registration
# ==============================================================================

test_tool_registration() {
    log_test "Verifying Phase 1.7 tools are registered"

    local tools=("flame_autonomy_config" "flame_should_push" "flame_should_pop" "flame_auto_suggest" "flame_autonomy_stats")
    for tool in "${tools[@]}"; do
        if grep -q "$tool: tool({" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
            log_pass "Tool '$tool' registered"
        else
            log_fail "Tool '$tool' not registered"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# Test 6: Suggestion System
# ==============================================================================

test_suggestion_system() {
    log_test "Verifying suggestion system implementation"

    if grep -q "createSuggestion" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "createSuggestion function found"
    else
        log_fail "createSuggestion function not found"
        return 1
    fi

    if grep -q "addSuggestion" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "addSuggestion function found"
    else
        log_fail "addSuggestion function not found"
        return 1
    fi

    if grep -q "formatSuggestionsForContext" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "formatSuggestionsForContext function found"
    else
        log_fail "formatSuggestionsForContext function not found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 7: Context Injection
# ==============================================================================

test_context_injection() {
    log_test "Verifying suggestion context injection"

    if grep -q "autonomySuggestions = formatSuggestionsForContext()" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "Suggestion injection in message transform found"
    else
        log_fail "Suggestion injection in message transform not found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 8: Default Configuration
# ==============================================================================

test_default_configuration() {
    log_test "Verifying default configuration values"

    if grep -q "DEFAULT_AUTONOMY_CONFIG" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "DEFAULT_AUTONOMY_CONFIG constant found"
    else
        log_fail "DEFAULT_AUTONOMY_CONFIG constant not found"
        return 1
    fi

    # Check default values
    if grep -q "level: \"suggest\"" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "Default level is 'suggest'"
    else
        log_fail "Default level is not 'suggest'"
        return 1
    fi

    if grep -q "pushThreshold: 70" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "Default pushThreshold is 70"
    else
        log_fail "Default pushThreshold is not 70"
        return 1
    fi

    if grep -q "popThreshold: 80" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "Default popThreshold is 80"
    else
        log_fail "Default popThreshold is not 80"
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 9: Runtime State Initialization
# ==============================================================================

test_runtime_initialization() {
    log_test "Verifying runtime state initialization"

    if grep -q "autonomyTracking: AutonomyTracking" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "autonomyTracking in RuntimeState found"
    else
        log_fail "autonomyTracking in RuntimeState not found"
        return 1
    fi

    if grep -q "autonomyTracking: {" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "autonomyTracking initialization found"
    else
        log_fail "autonomyTracking initialization not found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 10: Manual Mode Behavior
# ==============================================================================

test_manual_mode() {
    log_test "Verifying manual mode blocks suggestions"

    if grep -q "if (config.level === 'manual') return ''" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
        log_pass "Manual mode blocks formatSuggestionsForContext"
    else
        log_fail "Manual mode does not block formatSuggestionsForContext"
        return 1
    fi

    return 0
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

main() {
    echo "=============================================="
    echo " Phase 1.7: Agent Autonomy Tests"
    echo "=============================================="
    echo ""
    echo "Project Directory: $PROJECT_DIR"
    echo "Plugin Location: $PROJECT_DIR/.opencode/plugin/flame.ts"
    echo ""

    # Run all tests
    test_autonomy_config_types || true
    test_env_variable_loading || true
    test_push_heuristics || true
    test_pop_heuristics || true
    test_tool_registration || true
    test_suggestion_system || true
    test_context_injection || true
    test_default_configuration || true
    test_runtime_initialization || true
    test_manual_mode || true

    # Print summary
    echo ""
    echo "=============================================="
    echo " Test Summary"
    echo "=============================================="
    echo "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
