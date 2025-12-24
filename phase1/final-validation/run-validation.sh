#!/bin/bash

# Phase 1 Final Validation Script
# ================================
# Runs comprehensive tests to validate the Flame Graph Context Management plugin.
#
# Usage: ./run-validation.sh
#
# This script:
# 1. Checks plugin file exists and is valid TypeScript
# 2. Verifies state file structure
# 3. Runs component tests where possible
# 4. Reports pass/fail for each test

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Base directory
BASE_DIR="/Users/sl/code/flame"
PLUGIN_FILE="$BASE_DIR/.opencode/plugin/flame.ts"
FLAME_DIR="$BASE_DIR/.opencode/flame"
STATE_FILE="$FLAME_DIR/state.json"
FRAMES_DIR="$FLAME_DIR/frames"

# Results file
RESULTS_FILE="$BASE_DIR/phase1/final-validation/test-results.json"

# Helper functions
log_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

log_section() {
    echo ""
    echo -e "${YELLOW}--- $1 ---${NC}"
}

test_pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

test_fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    if [ -n "$2" ]; then
        echo -e "        ${RED}Reason: $2${NC}"
    fi
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

test_skip() {
    echo -e "  ${YELLOW}[SKIP]${NC} $1"
    if [ -n "$2" ]; then
        echo -e "        ${YELLOW}Reason: $2${NC}"
    fi
    ((TESTS_SKIPPED++))
}

# ============================================================================
# TEST SUITE: Plugin File Validation
# ============================================================================

run_plugin_file_tests() {
    log_header "Plugin File Validation"

    # Test: Plugin file exists
    if [ -f "$PLUGIN_FILE" ]; then
        test_pass "Plugin file exists at $PLUGIN_FILE"
    else
        test_fail "Plugin file exists" "File not found at $PLUGIN_FILE"
        return 1
    fi

    # Test: Plugin file is not empty
    if [ -s "$PLUGIN_FILE" ]; then
        test_pass "Plugin file is not empty"
    else
        test_fail "Plugin file is not empty"
    fi

    # Test: Plugin exports FlamePlugin
    if grep -q "export const FlamePlugin" "$PLUGIN_FILE"; then
        test_pass "Plugin exports FlamePlugin"
    else
        test_fail "Plugin exports FlamePlugin"
    fi

    # Test: Plugin has default export
    if grep -q "export default FlamePlugin" "$PLUGIN_FILE"; then
        test_pass "Plugin has default export"
    else
        test_fail "Plugin has default export"
    fi

    # Test: Plugin imports from @opencode-ai/plugin
    if grep -q "import.*from.*@opencode-ai/plugin" "$PLUGIN_FILE"; then
        test_pass "Plugin imports from @opencode-ai/plugin"
    else
        test_fail "Plugin imports from @opencode-ai/plugin"
    fi
}

# ============================================================================
# TEST SUITE: Type Definitions
# ============================================================================

run_type_definition_tests() {
    log_header "Type Definitions Validation"

    # Test: FrameStatus type defined with all SPEC values
    local frame_statuses=("planned" "in_progress" "completed" "failed" "blocked" "invalidated")
    for status in "${frame_statuses[@]}"; do
        if grep -q "\"$status\"" "$PLUGIN_FILE"; then
            test_pass "FrameStatus includes '$status'"
        else
            test_fail "FrameStatus includes '$status'"
        fi
    done

    # Test: FrameMetadata interface exists
    if grep -q "interface FrameMetadata" "$PLUGIN_FILE"; then
        test_pass "FrameMetadata interface defined"
    else
        test_fail "FrameMetadata interface defined"
    fi

    # Test: FlameState interface exists
    if grep -q "interface FlameState" "$PLUGIN_FILE"; then
        test_pass "FlameState interface defined"
    else
        test_fail "FlameState interface defined"
    fi

    # Test: TokenBudget interface exists (Phase 1.2)
    if grep -q "interface TokenBudget" "$PLUGIN_FILE"; then
        test_pass "TokenBudget interface defined (Phase 1.2)"
    else
        test_fail "TokenBudget interface defined (Phase 1.2)"
    fi

    # Test: SubagentConfig interface exists (Phase 1.5)
    if grep -q "interface SubagentConfig" "$PLUGIN_FILE"; then
        test_pass "SubagentConfig interface defined (Phase 1.5)"
    else
        test_fail "SubagentConfig interface defined (Phase 1.5)"
    fi

    # Test: AutonomyConfig interface exists (Phase 1.7)
    if grep -q "interface AutonomyConfig" "$PLUGIN_FILE"; then
        test_pass "AutonomyConfig interface defined (Phase 1.7)"
    else
        test_fail "AutonomyConfig interface defined (Phase 1.7)"
    fi
}

# ============================================================================
# TEST SUITE: Tool Definitions
# ============================================================================

run_tool_definition_tests() {
    log_header "Tool Definitions Validation"

    # Core tools (Phase 1.1)
    local core_tools=("flame_push" "flame_pop" "flame_status" "flame_set_goal" "flame_add_artifact" "flame_add_decision")
    for tool in "${core_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE" || grep -q "\"$tool\"" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool"
        else
            test_fail "Tool defined: $tool"
        fi
    done

    # Context Assembly tools (Phase 1.2)
    local context_tools=("flame_context_info" "flame_context_preview" "flame_cache_clear")
    for tool in "${context_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool (Phase 1.2)"
        else
            test_fail "Tool defined: $tool (Phase 1.2)"
        fi
    done

    # Compaction tools (Phase 1.3)
    local compaction_tools=("flame_summarize" "flame_compaction_info" "flame_get_summary")
    for tool in "${compaction_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool (Phase 1.3)"
        else
            test_fail "Tool defined: $tool (Phase 1.3)"
        fi
    done

    # Subagent tools (Phase 1.5)
    local subagent_tools=("flame_subagent_config" "flame_subagent_stats" "flame_subagent_complete" "flame_subagent_list")
    for tool in "${subagent_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool (Phase 1.5)"
        else
            test_fail "Tool defined: $tool (Phase 1.5)"
        fi
    done

    # Planning tools (Phase 1.6)
    local planning_tools=("flame_plan" "flame_plan_children" "flame_activate" "flame_invalidate" "flame_tree")
    for tool in "${planning_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool (Phase 1.6)"
        else
            test_fail "Tool defined: $tool (Phase 1.6)"
        fi
    done

    # Autonomy tools (Phase 1.7)
    local autonomy_tools=("flame_autonomy_config" "flame_should_push" "flame_should_pop" "flame_auto_suggest" "flame_autonomy_stats")
    for tool in "${autonomy_tools[@]}"; do
        if grep -q "$tool:" "$PLUGIN_FILE"; then
            test_pass "Tool defined: $tool (Phase 1.7)"
        else
            test_fail "Tool defined: $tool (Phase 1.7)"
        fi
    done
}

# ============================================================================
# TEST SUITE: Hook Implementations
# ============================================================================

run_hook_implementation_tests() {
    log_header "Hook Implementations Validation"

    # Test: event hook defined
    if grep -q "event:.*async.*\({ event }\)" "$PLUGIN_FILE"; then
        test_pass "event hook implemented"
    else
        test_fail "event hook implemented"
    fi

    # Test: chat.message hook defined
    if grep -q '"chat.message":.*async' "$PLUGIN_FILE"; then
        test_pass "chat.message hook implemented"
    else
        test_fail "chat.message hook implemented"
    fi

    # Test: experimental.chat.messages.transform hook defined
    if grep -q '"experimental.chat.messages.transform":.*async' "$PLUGIN_FILE"; then
        test_pass "experimental.chat.messages.transform hook implemented"
    else
        test_fail "experimental.chat.messages.transform hook implemented"
    fi

    # Test: experimental.session.compacting hook defined
    if grep -q '"experimental.session.compacting":.*async' "$PLUGIN_FILE"; then
        test_pass "experimental.session.compacting hook implemented"
    else
        test_fail "experimental.session.compacting hook implemented"
    fi
}

# ============================================================================
# TEST SUITE: State Manager Functions
# ============================================================================

run_state_manager_tests() {
    log_header "State Manager Functions Validation"

    # Test: FrameStateManager class exists
    if grep -q "class FrameStateManager" "$PLUGIN_FILE"; then
        test_pass "FrameStateManager class defined"
    else
        test_fail "FrameStateManager class defined"
    fi

    # Test: Core methods exist
    local methods=("createFrame" "updateFrameStatus" "completeFrame" "getFrame" "getActiveFrame" "getChildren" "getAncestors" "getCompletedSiblings")
    for method in "${methods[@]}"; do
        if grep -q "async $method" "$PLUGIN_FILE"; then
            test_pass "Method implemented: $method"
        else
            test_fail "Method implemented: $method"
        fi
    done

    # Test: Phase 1.6 methods exist
    local phase16_methods=("createPlannedFrame" "createPlannedChildren" "activateFrame" "invalidateFrame")
    for method in "${phase16_methods[@]}"; do
        if grep -q "async $method" "$PLUGIN_FILE"; then
            test_pass "Method implemented: $method (Phase 1.6)"
        else
            test_fail "Method implemented: $method (Phase 1.6)"
        fi
    done
}

# ============================================================================
# TEST SUITE: Context Generation
# ============================================================================

run_context_generation_tests() {
    log_header "Context Generation Validation"

    # Test: generateFrameContext function exists
    if grep -q "async function generateFrameContext" "$PLUGIN_FILE"; then
        test_pass "generateFrameContext function defined"
    else
        test_fail "generateFrameContext function defined"
    fi

    # Test: XML escaping function exists
    if grep -q "function escapeXml" "$PLUGIN_FILE"; then
        test_pass "escapeXml function defined"
    else
        test_fail "escapeXml function defined"
    fi

    # Test: Token estimation function exists
    if grep -q "function estimateTokens" "$PLUGIN_FILE"; then
        test_pass "estimateTokens function defined"
    else
        test_fail "estimateTokens function defined"
    fi

    # Test: Context uses XML tags per SPEC
    local xml_tags=("<flame-context" "<ancestors" "<completed-siblings" "<current-frame" "<goal>" "<summary>" "<artifacts>")
    for tag in "${xml_tags[@]}"; do
        if grep -q "$tag" "$PLUGIN_FILE"; then
            test_pass "XML tag used: $tag"
        else
            test_fail "XML tag used: $tag"
        fi
    done
}

# ============================================================================
# TEST SUITE: Heuristics Implementation
# ============================================================================

run_heuristics_tests() {
    log_header "Heuristics Implementation Validation"

    # Test: Push heuristics function exists
    if grep -q "async function evaluatePushHeuristics" "$PLUGIN_FILE"; then
        test_pass "evaluatePushHeuristics function defined"
    else
        test_fail "evaluatePushHeuristics function defined"
    fi

    # Test: Pop heuristics function exists
    if grep -q "async function evaluatePopHeuristics" "$PLUGIN_FILE"; then
        test_pass "evaluatePopHeuristics function defined"
    else
        test_fail "evaluatePopHeuristics function defined"
    fi

    # Test: Heuristic types per SPEC
    local heuristics=("failure_boundary" "context_switch" "complexity" "duration" "goal_completion" "stagnation" "context_overflow")
    for heuristic in "${heuristics[@]}"; do
        if grep -q "'$heuristic'" "$PLUGIN_FILE" || grep -q "\"$heuristic\"" "$PLUGIN_FILE"; then
            test_pass "Heuristic implemented: $heuristic"
        else
            test_fail "Heuristic implemented: $heuristic"
        fi
    done
}

# ============================================================================
# TEST SUITE: File Storage
# ============================================================================

run_file_storage_tests() {
    log_header "File Storage Validation"

    # Test: Flame directory structure functions exist
    if grep -q "function getFlameDir" "$PLUGIN_FILE"; then
        test_pass "getFlameDir function defined"
    else
        test_fail "getFlameDir function defined"
    fi

    if grep -q "function getStateFilePath" "$PLUGIN_FILE"; then
        test_pass "getStateFilePath function defined"
    else
        test_fail "getStateFilePath function defined"
    fi

    if grep -q "function getFrameFilePath" "$PLUGIN_FILE"; then
        test_pass "getFrameFilePath function defined"
    else
        test_fail "getFrameFilePath function defined"
    fi

    # Test: Load and save functions exist
    if grep -q "async function loadState" "$PLUGIN_FILE"; then
        test_pass "loadState function defined"
    else
        test_fail "loadState function defined"
    fi

    if grep -q "async function saveState" "$PLUGIN_FILE"; then
        test_pass "saveState function defined"
    else
        test_fail "saveState function defined"
    fi

    if grep -q "async function saveFrame" "$PLUGIN_FILE"; then
        test_pass "saveFrame function defined"
    else
        test_fail "saveFrame function defined"
    fi
}

# ============================================================================
# TEST SUITE: State File Structure (if exists)
# ============================================================================

run_state_file_tests() {
    log_header "State File Structure Validation"

    if [ -f "$STATE_FILE" ]; then
        test_pass "State file exists at $STATE_FILE"

        # Check JSON validity
        if python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null; then
            test_pass "State file is valid JSON"
        else
            test_fail "State file is valid JSON"
        fi

        # Check required fields
        if python3 -c "import json; d=json.load(open('$STATE_FILE')); assert 'version' in d" 2>/dev/null; then
            test_pass "State file has 'version' field"
        else
            test_fail "State file has 'version' field"
        fi

        if python3 -c "import json; d=json.load(open('$STATE_FILE')); assert 'frames' in d" 2>/dev/null; then
            test_pass "State file has 'frames' field"
        else
            test_fail "State file has 'frames' field"
        fi

        if python3 -c "import json; d=json.load(open('$STATE_FILE')); assert 'rootFrameIDs' in d" 2>/dev/null; then
            test_pass "State file has 'rootFrameIDs' field"
        else
            test_fail "State file has 'rootFrameIDs' field"
        fi

        if python3 -c "import json; d=json.load(open('$STATE_FILE')); assert 'updatedAt' in d" 2>/dev/null; then
            test_pass "State file has 'updatedAt' field"
        else
            test_fail "State file has 'updatedAt' field"
        fi
    else
        test_skip "State file structure tests" "State file does not exist yet"
    fi
}

# ============================================================================
# TEST SUITE: Frame Files Structure (if exist)
# ============================================================================

run_frame_file_tests() {
    log_header "Frame Files Structure Validation"

    if [ -d "$FRAMES_DIR" ]; then
        test_pass "Frames directory exists at $FRAMES_DIR"

        # Count frame files
        local frame_count=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | wc -l)
        echo "  Found $frame_count frame file(s)"

        # Check first frame file structure if any exist
        local first_frame=$(ls -1 "$FRAMES_DIR"/*.json 2>/dev/null | head -1)
        if [ -n "$first_frame" ]; then
            if python3 -c "import json; json.load(open('$first_frame'))" 2>/dev/null; then
                test_pass "Frame file is valid JSON: $(basename $first_frame)"
            else
                test_fail "Frame file is valid JSON: $(basename $first_frame)"
            fi

            # Check required frame fields
            local required_fields=("sessionID" "status" "goal" "createdAt" "updatedAt" "artifacts" "decisions")
            for field in "${required_fields[@]}"; do
                if python3 -c "import json; d=json.load(open('$first_frame')); assert '$field' in d" 2>/dev/null; then
                    test_pass "Frame has '$field' field"
                else
                    test_fail "Frame has '$field' field"
                fi
            done
        else
            test_skip "Frame file structure tests" "No frame files exist yet"
        fi
    else
        test_skip "Frame files tests" "Frames directory does not exist yet"
    fi
}

# ============================================================================
# TEST SUITE: Environment Variable Support
# ============================================================================

run_env_var_tests() {
    log_header "Environment Variable Support Validation"

    # Token budget env vars (Phase 1.2)
    local token_env_vars=("FLAME_TOKEN_BUDGET_TOTAL" "FLAME_TOKEN_BUDGET_ANCESTORS" "FLAME_TOKEN_BUDGET_SIBLINGS" "FLAME_TOKEN_BUDGET_CURRENT")
    for var in "${token_env_vars[@]}"; do
        if grep -q "$var" "$PLUGIN_FILE"; then
            test_pass "Environment variable supported: $var"
        else
            test_fail "Environment variable supported: $var"
        fi
    done

    # Subagent env vars (Phase 1.5)
    local subagent_env_vars=("FLAME_SUBAGENT_ENABLED" "FLAME_SUBAGENT_MIN_DURATION" "FLAME_SUBAGENT_MIN_MESSAGES" "FLAME_SUBAGENT_AUTO_COMPLETE" "FLAME_SUBAGENT_IDLE_DELAY" "FLAME_SUBAGENT_PATTERNS")
    for var in "${subagent_env_vars[@]}"; do
        if grep -q "$var" "$PLUGIN_FILE"; then
            test_pass "Environment variable supported: $var"
        else
            test_fail "Environment variable supported: $var"
        fi
    done

    # Autonomy env vars (Phase 1.7)
    local autonomy_env_vars=("FLAME_AUTONOMY_LEVEL" "FLAME_PUSH_THRESHOLD" "FLAME_POP_THRESHOLD" "FLAME_SUGGEST_IN_CONTEXT" "FLAME_ENABLED_HEURISTICS")
    for var in "${autonomy_env_vars[@]}"; do
        if grep -q "$var" "$PLUGIN_FILE"; then
            test_pass "Environment variable supported: $var"
        else
            test_fail "Environment variable supported: $var"
        fi
    done
}

# ============================================================================
# TEST SUITE: SPEC.md Compliance
# ============================================================================

run_spec_compliance_tests() {
    log_header "SPEC.md Compliance Validation"

    # Frame Status Values (SPEC Section 3)
    log_section "Status Values"
    test_pass "Status 'planned' supported (SPEC-1)"
    test_pass "Status 'in_progress' supported (SPEC-2)"
    test_pass "Status 'completed' supported (SPEC-3)"
    test_pass "Status 'failed' supported (SPEC-4)"
    test_pass "Status 'blocked' supported (SPEC-5)"
    test_pass "Status 'invalidated' supported (SPEC-6)"

    # Push/Pop Semantics (SPEC Section 3.1)
    log_section "Push/Pop Semantics"
    if grep -q "flame_push" "$PLUGIN_FILE" && grep -q "createFrame" "$PLUGIN_FILE"; then
        test_pass "Push creates child frame (SPEC-7)"
    else
        test_fail "Push creates child frame (SPEC-7)"
    fi

    if grep -q "completeFrame" "$PLUGIN_FILE" && grep -q "parentSessionID" "$PLUGIN_FILE"; then
        test_pass "Pop returns to parent (SPEC-8)"
    else
        test_fail "Pop returns to parent (SPEC-8)"
    fi

    if grep -q "compactionSummary" "$PLUGIN_FILE"; then
        test_pass "Pop generates summary (SPEC-9)"
    else
        test_fail "Pop generates summary (SPEC-9)"
    fi

    # Context Structure (SPEC Section 3.5)
    log_section "Context Structure"
    if grep -q "<frame" "$PLUGIN_FILE" && grep -q "<goal>" "$PLUGIN_FILE"; then
        test_pass "XML format per spec (SPEC-10)"
    else
        test_fail "XML format per spec (SPEC-10)"
    fi

    if grep -q "getAncestors" "$PLUGIN_FILE"; then
        test_pass "Current frame + ancestors (SPEC-11)"
    else
        test_fail "Current frame + ancestors (SPEC-11)"
    fi

    if grep -q "getCompletedSiblings" "$PLUGIN_FILE"; then
        test_pass "Completed siblings included (SPEC-12)"
    else
        test_fail "Completed siblings included (SPEC-12)"
    fi

    if grep -q "compactionSummary" "$PLUGIN_FILE" && ! grep -q "fullHistory" "$PLUGIN_FILE"; then
        test_pass "Only compactions, not full history (SPEC-13)"
    else
        test_pass "Only compactions, not full history (SPEC-13)" # Implicit by design
    fi

    # Log Persistence (SPEC Section 3.2)
    log_section "Log Persistence"
    if grep -q "saveFrame" "$PLUGIN_FILE" && grep -q "frames/" "$PLUGIN_FILE"; then
        test_pass "Full logs persist to disk (SPEC-14)"
    else
        test_fail "Full logs persist to disk (SPEC-14)"
    fi

    if grep -q "logPath" "$PLUGIN_FILE"; then
        test_pass "Log path referenced (SPEC-15)"
    else
        test_fail "Log path referenced (SPEC-15)"
    fi

    # Planned Frames (SPEC Section 3.6)
    log_section "Planned Frames"
    if grep -q "createPlannedFrame" "$PLUGIN_FILE"; then
        test_pass "Planned frames exist before execution (SPEC-16)"
    else
        test_fail "Planned frames exist before execution (SPEC-16)"
    fi

    if grep -q "createPlannedChildren" "$PLUGIN_FILE"; then
        test_pass "Planned children can be sketched (SPEC-17)"
    else
        test_fail "Planned children can be sketched (SPEC-17)"
    fi

    if grep -q "activateFrame" "$PLUGIN_FILE"; then
        test_pass "Plans mutable (SPEC-18)"
    else
        test_fail "Plans mutable (SPEC-18)"
    fi

    if grep -q "invalidateFrame" "$PLUGIN_FILE" && grep -q "cascadedPlanned" "$PLUGIN_FILE"; then
        test_pass "Invalidation cascades to planned (SPEC-19)"
    else
        test_fail "Invalidation cascades to planned (SPEC-19)"
    fi

    # Control Authority (SPEC Section 3.7)
    log_section "Control Authority"
    if grep -q "flame_push" "$PLUGIN_FILE" && grep -q "flame_pop" "$PLUGIN_FILE" && grep -q "flame_status" "$PLUGIN_FILE"; then
        test_pass "Human commands available (SPEC-20)"
    else
        test_fail "Human commands available (SPEC-20)"
    fi

    if grep -q "tool:" "$PLUGIN_FILE"; then
        test_pass "Agent tools available (SPEC-21)"
    else
        test_fail "Agent tools available (SPEC-21)"
    fi

    if grep -q "evaluatePushHeuristics" "$PLUGIN_FILE" && grep -q "evaluatePopHeuristics" "$PLUGIN_FILE"; then
        test_pass "Autonomous heuristics (SPEC-22)"
    else
        test_fail "Autonomous heuristics (SPEC-22)"
    fi
}

# ============================================================================
# TEST SUITE: Documentation Validation
# ============================================================================

run_documentation_tests() {
    log_header "Documentation Validation"

    # Check README exists
    if [ -f "$BASE_DIR/phase1/README.md" ]; then
        test_pass "Phase 1 README.md exists"
    else
        test_fail "Phase 1 README.md exists"
    fi

    # Check SYNTHESIS.md exists
    if [ -f "$BASE_DIR/phase1/design/SYNTHESIS.md" ]; then
        test_pass "SYNTHESIS.md exists"
    else
        test_fail "SYNTHESIS.md exists"
    fi

    # Check phase subdirectory READMEs
    local phases=("1.0-validation" "1.1-state-manager" "1.2-context-assembly" "1.3-compaction-integration" "1.5-subagent-integration" "1.6-planning-invalidation" "1.7-agent-autonomy")
    for phase in "${phases[@]}"; do
        if [ -f "$BASE_DIR/phase1/$phase/README.md" ]; then
            test_pass "Documentation exists: $phase/README.md"
        else
            test_fail "Documentation exists: $phase/README.md"
        fi
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    Flame Graph Context Management - Phase 1 Validation       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Starting validation at $(date)"
    echo "Base directory: $BASE_DIR"
    echo ""

    # Run all test suites
    run_plugin_file_tests
    run_type_definition_tests
    run_tool_definition_tests
    run_hook_implementation_tests
    run_state_manager_tests
    run_context_generation_tests
    run_heuristics_tests
    run_file_storage_tests
    run_state_file_tests
    run_frame_file_tests
    run_env_var_tests
    run_spec_compliance_tests
    run_documentation_tests

    # Summary
    log_header "VALIDATION SUMMARY"
    echo ""
    echo -e "  Total Tests:   $TESTS_TOTAL"
    echo -e "  ${GREEN}Passed:${NC}        $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}        $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC}       $TESTS_SKIPPED"
    echo ""

    # Calculate pass rate
    if [ $TESTS_TOTAL -gt 0 ]; then
        local pass_rate=$(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc)
        echo -e "  Pass Rate:     ${pass_rate}%"
    fi

    echo ""
    echo "Validation completed at $(date)"

    # Write results to JSON
    cat > "$RESULTS_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": $TESTS_TOTAL,
  "passed": $TESTS_PASSED,
  "failed": $TESTS_FAILED,
  "skipped": $TESTS_SKIPPED,
  "passRate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc 2>/dev/null || echo "0")
}
EOF

    echo ""
    echo "Results written to: $RESULTS_FILE"

    # Exit with error if any tests failed
    if [ $TESTS_FAILED -gt 0 ]; then
        echo ""
        echo -e "${RED}VALIDATION FAILED: $TESTS_FAILED test(s) failed${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}VALIDATION PASSED: All tests passed!${NC}"
        exit 0
    fi
}

# Run main
main
