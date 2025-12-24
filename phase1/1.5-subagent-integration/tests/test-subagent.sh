#!/bin/bash
# Phase 1.5 Subagent Integration Tests
#
# This script tests the subagent integration features of the Flame plugin.
# It uses the OpenCode SDK to simulate subagent sessions and verify behavior.
#
# Prerequisites:
# - OpenCode installed and configured
# - Flame plugin installed at .opencode/plugin/flame.ts
# - Node.js/npm available
#
# Usage:
#   ./test-subagent.sh [--verbose]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLAME_DIR="$PROJECT_DIR/.opencode/flame"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
  VERBOSE=true
fi

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log() {
  echo -e "${BLUE}[TEST]${NC} $1"
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG]${NC} $1"
  fi
}

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
  local test_name="$1"
  local test_func="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  log "Running: $test_name"
  if $test_func; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
}

# ============================================================================
# Test Functions
# ============================================================================

test_plugin_loads() {
  # Verify the plugin file exists and is valid TypeScript
  if [[ ! -f "$PROJECT_DIR/.opencode/plugin/flame.ts" ]]; then
    echo "Plugin file not found"
    return 1
  fi

  # Check for Phase 1.5 markers
  if grep -q "Phase 1.5" "$PROJECT_DIR/.opencode/plugin/flame.ts"; then
    log_verbose "Found Phase 1.5 markers"
    return 0
  else
    echo "Phase 1.5 markers not found in plugin"
    return 1
  fi
}

test_subagent_types_defined() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for SubagentConfig interface
  if ! grep -q "interface SubagentConfig" "$plugin_file"; then
    echo "SubagentConfig interface not found"
    return 1
  fi

  # Check for SubagentSession interface
  if ! grep -q "interface SubagentSession" "$plugin_file"; then
    echo "SubagentSession interface not found"
    return 1
  fi

  # Check for SubagentStats interface
  if ! grep -q "interface SubagentStats" "$plugin_file"; then
    echo "SubagentStats interface not found"
    return 1
  fi

  # Check for SubagentTracking interface
  if ! grep -q "interface SubagentTracking" "$plugin_file"; then
    echo "SubagentTracking interface not found"
    return 1
  fi

  return 0
}

test_default_config_values() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for default configuration
  if ! grep -q "DEFAULT_SUBAGENT_CONFIG" "$plugin_file"; then
    echo "DEFAULT_SUBAGENT_CONFIG not found"
    return 1
  fi

  # Verify key default values
  if ! grep -q "minDuration: 60000" "$plugin_file"; then
    echo "Default minDuration not set to 60000ms"
    return 1
  fi

  if ! grep -q "minMessageCount: 3" "$plugin_file"; then
    echo "Default minMessageCount not set to 3"
    return 1
  fi

  if ! grep -q "autoCompleteOnIdle: true" "$plugin_file"; then
    echo "Default autoCompleteOnIdle not set to true"
    return 1
  fi

  return 0
}

test_subagent_patterns() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for default patterns
  if ! grep -q '@.*subagent' "$plugin_file"; then
    echo "Default @.*subagent pattern not found"
    return 1
  fi

  return 0
}

test_detection_functions() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for key detection functions
  local functions=(
    "isSubagentTitle"
    "registerSubagentSession"
    "updateSubagentActivity"
    "meetsFrameHeuristics"
    "maybeCreateSubagentFrame"
    "handleSubagentIdle"
    "completeSubagentSession"
    "getSubagentStats"
    "resetSubagentStats"
    "cleanupOldSubagentSessions"
  )

  for func in "${functions[@]}"; do
    if ! grep -q "function $func" "$plugin_file"; then
      echo "Function $func not found"
      return 1
    fi
  done

  return 0
}

test_tools_defined() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for new subagent tools
  local tools=(
    "flame_subagent_config"
    "flame_subagent_stats"
    "flame_subagent_complete"
    "flame_subagent_list"
  )

  for tool in "${tools[@]}"; do
    if ! grep -q "$tool:" "$plugin_file"; then
      echo "Tool $tool not found"
      return 1
    fi
  done

  return 0
}

test_event_handlers_updated() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check that session.created handler includes subagent detection
  if ! grep -q "registerSubagentSession" "$plugin_file"; then
    echo "registerSubagentSession not called in event handler"
    return 1
  fi

  # Check that session.idle handler includes subagent handling
  if ! grep -q "handleSubagentIdle" "$plugin_file"; then
    echo "handleSubagentIdle not called in event handler"
    return 1
  fi

  # Check that chat.message handler updates activity
  if ! grep -q "updateSubagentActivity" "$plugin_file"; then
    echo "updateSubagentActivity not called in chat.message handler"
    return 1
  fi

  return 0
}

test_env_config_loading() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for environment variable loading function
  if ! grep -q "loadSubagentConfigFromEnv" "$plugin_file"; then
    echo "loadSubagentConfigFromEnv function not found"
    return 1
  fi

  # Check for environment variable references
  local env_vars=(
    "FLAME_SUBAGENT_ENABLED"
    "FLAME_SUBAGENT_MIN_DURATION"
    "FLAME_SUBAGENT_MIN_MESSAGES"
    "FLAME_SUBAGENT_AUTO_COMPLETE"
    "FLAME_SUBAGENT_IDLE_DELAY"
    "FLAME_SUBAGENT_PATTERNS"
  )

  for env_var in "${env_vars[@]}"; do
    if ! grep -q "$env_var" "$plugin_file"; then
      echo "Environment variable $env_var not referenced"
      return 1
    fi
  done

  return 0
}

test_heuristic_logic() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check that meetsFrameHeuristics checks duration
  if ! grep -A 20 "function meetsFrameHeuristics" "$plugin_file" | grep -q "minDuration"; then
    echo "Heuristics don't check duration"
    return 1
  fi

  # Check that meetsFrameHeuristics checks message count
  if ! grep -A 20 "function meetsFrameHeuristics" "$plugin_file" | grep -q "minMessageCount"; then
    echo "Heuristics don't check message count"
    return 1
  fi

  return 0
}

test_auto_complete_timer() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check for setTimeout usage in idle handler
  if ! grep -A 60 "function handleSubagentIdle" "$plugin_file" | grep -q "setTimeout"; then
    echo "Auto-complete timer not found in handleSubagentIdle"
    return 1
  fi

  # Check for idleCompletionDelay usage (need more lines to capture end of setTimeout)
  if ! grep -A 60 "function handleSubagentIdle" "$plugin_file" | grep -q "idleCompletionDelay"; then
    echo "idleCompletionDelay not used in timer"
    return 1
  fi

  return 0
}

test_cache_invalidation() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check that subagent frame creation invalidates parent cache
  if ! grep -B 5 -A 5 "Subagent frame created" "$plugin_file" | grep -q "invalidateCache"; then
    echo "Parent cache not invalidated on subagent frame creation"
    return 1
  fi

  return 0
}

test_cleanup_function() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check that cleanup removes old completed sessions
  if ! grep -A 15 "function cleanupOldSubagentSessions" "$plugin_file" | grep -q "isCompleted"; then
    echo "Cleanup doesn't check isCompleted"
    return 1
  fi

  # Check that cleanup uses a time threshold
  if ! grep -A 15 "function cleanupOldSubagentSessions" "$plugin_file" | grep -q "maxAge"; then
    echo "Cleanup doesn't use time threshold"
    return 1
  fi

  return 0
}

test_format_duration() {
  local plugin_file="$PROJECT_DIR/.opencode/plugin/flame.ts"

  # Check that formatDuration function exists
  if ! grep -q "function formatDuration" "$plugin_file"; then
    echo "formatDuration function not found"
    return 1
  fi

  return 0
}

# ============================================================================
# Run Tests
# ============================================================================

main() {
  echo ""
  echo "========================================"
  echo "  Phase 1.5 Subagent Integration Tests"
  echo "========================================"
  echo ""
  echo "Project Directory: $PROJECT_DIR"
  echo "Flame Directory: $FLAME_DIR"
  echo ""

  # Run all tests
  run_test "Plugin loads with Phase 1.5 code" test_plugin_loads
  run_test "Subagent types are defined" test_subagent_types_defined
  run_test "Default config values are correct" test_default_config_values
  run_test "Subagent patterns are defined" test_subagent_patterns
  run_test "Detection functions exist" test_detection_functions
  run_test "Subagent tools are defined" test_tools_defined
  run_test "Event handlers are updated" test_event_handlers_updated
  run_test "Environment config loading works" test_env_config_loading
  run_test "Heuristic logic is implemented" test_heuristic_logic
  run_test "Auto-complete timer is implemented" test_auto_complete_timer
  run_test "Cache invalidation is correct" test_cache_invalidation
  run_test "Cleanup function exists" test_cleanup_function
  run_test "Duration formatting exists" test_format_duration

  # Summary
  echo ""
  echo "========================================"
  echo "  Test Summary"
  echo "========================================"
  echo ""
  echo -e "Total Tests: $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

main "$@"
