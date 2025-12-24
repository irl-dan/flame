# Phase 1 Final Validation Test Plan

## Overview

This document defines comprehensive tests to validate the entire Phase 1 implementation of the Flame Graph Context Management plugin against SPEC.md and SYNTHESIS.md requirements.

**Test Categories:**
1. Component Tests - Verify individual features work in isolation
2. End-to-End Tests - Verify complete workflows
3. SPEC.md Compliance Tests - Verify specification adherence

---

## 1. Component Tests

### 1.1 State Manager Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| SM-1 | Create root frame with `flame_push` | Frame created with status `in_progress`, goal set, added to rootFrameIDs | High |
| SM-2 | Create child frame with `flame_push` | Frame created with parentSessionID set, not in rootFrameIDs | High |
| SM-3 | Frame persistence to disk | `state.json` and frame JSON files exist in `.opencode/flame/` | High |
| SM-4 | Load state after restart | State correctly loaded from JSON files | High |
| SM-5 | Update frame goal with `flame_set_goal` | Goal updated, updatedAt changed | Medium |
| SM-6 | Add artifact with `flame_add_artifact` | Artifact added to array | Medium |
| SM-7 | Add decision with `flame_add_decision` | Decision added to array | Medium |
| SM-8 | Get frame ancestors | Returns chain from parent to root | High |
| SM-9 | Get completed siblings | Returns siblings with status `completed` only | High |
| SM-10 | Get all children | Returns all children regardless of status | Medium |

### 1.2 Context Assembly Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| CA-1 | Generate XML context for frame | Valid XML with `<flame-context>` root | High |
| CA-2 | Token budget applied | Context respects FLAME_TOKEN_BUDGET_* limits | High |
| CA-3 | Ancestor selection with priority | Parent always included, deep ancestors pruned if over budget | High |
| CA-4 | Sibling relevance filtering | Low-relevance siblings filtered, high-relevance included | Medium |
| CA-5 | Context caching | Same request returns cached result within TTL | Medium |
| CA-6 | Cache invalidation on state change | Cache invalidated when frame updated | Medium |
| CA-7 | Truncation indicators | XML includes `truncated="true"` when content truncated | Low |
| CA-8 | `flame_context_info` output | Shows token usage, selection stats, cache info | Medium |
| CA-9 | `flame_context_preview` output | Shows actual XML that would be injected | Medium |
| CA-10 | `flame_cache_clear` clears cache | Cache entries removed | Low |

### 1.3 Compaction Integration Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| CI-1 | Frame completion compaction prompt | Custom prompt used when `flame_pop` with `generateSummary:true` | High |
| CI-2 | Overflow compaction prompt | Different prompt for auto-compaction vs frame completion | High |
| CI-3 | Manual summary with `flame_summarize` | Marks session for manual_summary compaction type | Medium |
| CI-4 | Summary extraction from compaction | Summary stored in frame.compactionSummary | High |
| CI-5 | Pending completion handling | Frame completed after compaction fires with summary | High |
| CI-6 | `flame_compaction_info` output | Shows pending compactions, types, completions | Medium |
| CI-7 | `flame_get_summary` retrieval | Returns stored summary for frame | Medium |

### 1.4 Subagent Integration Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| SA-1 | Subagent session detection | Sessions with parentID and matching title patterns detected | High |
| SA-2 | Pattern-matched subagent gets immediate frame | Frame created on session.created for pattern matches | High |
| SA-3 | Heuristic-based frame creation | Frame created after minDuration and minMessageCount met | Medium |
| SA-4 | Auto-complete on idle | Frame completed after idleCompletionDelay | High |
| SA-5 | Manual completion with `flame_subagent_complete` | Frame completed with specified status | Medium |
| SA-6 | `flame_subagent_config` modifications | Settings updated and persisted | Medium |
| SA-7 | `flame_subagent_stats` reporting | Correct counts for detected, created, completed | Medium |
| SA-8 | `flame_subagent_list` filtering | Filters work (active, completed, with-frame, etc.) | Low |
| SA-9 | Parent context injection | Parent frame context included in subagent frame | High |
| SA-10 | Summary propagation to parent | Completed subagent summary visible in parent's sibling context | High |

### 1.5 Planning Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| PL-1 | Create planned frame with `flame_plan` | Frame created with status `planned` | High |
| PL-2 | Create multiple children with `flame_plan_children` | All children created with status `planned` | High |
| PL-3 | Activate planned frame with `flame_activate` | Status changes to `in_progress`, becomes active | High |
| PL-4 | Cannot activate non-planned frame | Error returned | Medium |
| PL-5 | Planned frame in tree visualization | Shows with `[P]` or `planned` indicator | Medium |

### 1.6 Invalidation Cascade Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| IC-1 | Invalidate frame with `flame_invalidate` | Status becomes `invalidated`, reason stored | High |
| IC-2 | Cascade to planned children | All planned descendants auto-invalidated | High |
| IC-3 | In-progress children warned not invalidated | Warning returned, children unchanged | High |
| IC-4 | Completed children unchanged | Completed children remain completed | High |
| IC-5 | Invalidation reason stored | `invalidationReason` and `invalidatedAt` set | Medium |

### 1.7 Agent Autonomy Tests

| ID | Test | Expected Result | Priority |
|----|------|-----------------|----------|
| AU-1 | Push heuristics evaluation | `flame_should_push` returns confidence and scores | High |
| AU-2 | Pop heuristics evaluation | `flame_should_pop` returns confidence and status | High |
| AU-3 | Failure boundary heuristic | Error count increases push score | Medium |
| AU-4 | Context switch heuristic | Different goal keywords increase score | Medium |
| AU-5 | Complexity heuristic | Many messages/files increase score | Medium |
| AU-6 | Goal completion heuristic | Success signals increase pop score | Medium |
| AU-7 | Stagnation heuristic | No progress increases pop score | Medium |
| AU-8 | Context overflow heuristic | High token usage increases pop score | Medium |
| AU-9 | Suggestion creation in suggest mode | Suggestions added to queue | High |
| AU-10 | Suggestions in context when enabled | XML includes suggestion comments | Medium |
| AU-11 | `flame_autonomy_config` modifications | Settings updated | Medium |
| AU-12 | `flame_auto_suggest` toggle | suggestInContext toggled | Medium |
| AU-13 | `flame_autonomy_stats` reporting | Correct statistics shown | Low |

---

## 2. End-to-End Tests

### E2E-1: Create Frame Tree and Pop with Summaries

**Scenario:** Create a multi-level frame tree, complete child frames, verify summaries propagate.

**Steps:**
1. Start in root session
2. `flame_push` to create child A with goal "Implement auth"
3. `flame_push` to create grandchild A1 with goal "JWT tokens"
4. `flame_add_artifact` to record "src/auth/jwt.ts"
5. `flame_pop` A1 with status `completed` and summary
6. `flame_push` to create A2 with goal "Login routes"
7. `flame_pop` A2 with status `completed`
8. `flame_pop` A with status `completed`
9. `flame_status` to verify tree structure

**Expected:**
- Three frames completed with summaries
- Parent A has A1 and A2 as completed siblings in its context
- Root shows A as completed child

### E2E-2: Subagent Spawns Child, Completes, Parent Sees Context

**Scenario:** Simulate subagent creating child session, verify context sharing.

**Steps:**
1. Create root frame
2. Simulate session.created event with parentID and "(@agent subagent)" title
3. Verify frame auto-created for subagent
4. Simulate activity (chat.message events)
5. Simulate session.idle event
6. Verify auto-completion after delay
7. Check parent frame sees subagent summary in sibling context

**Expected:**
- Subagent session detected and tracked
- Frame created due to pattern match
- Auto-completed on idle
- Parent context includes completed subagent summary

### E2E-3: Plan Frames, Activate One, Invalidate Parent, Verify Cascade

**Scenario:** Test planned frame workflow with invalidation cascade.

**Steps:**
1. Create root frame "Build app"
2. `flame_plan_children` with ["Auth", "API", "UI"]
3. `flame_activate` the "Auth" planned frame
4. `flame_push` under Auth to create "JWT" child
5. `flame_invalidate` Auth with reason "Switching to OAuth"
6. Verify "JWT" child is warned (in_progress)
7. Verify "API" and "UI" planned siblings are NOT invalidated (they're siblings, not children)
8. `flame_tree` to see structure

**Expected:**
- Three planned children created
- Auth activated, JWT child created
- Auth invalidated with reason
- JWT warned but not auto-invalidated
- API and UI remain planned (they are siblings of Auth, not its children)

### E2E-4: Fill Context, Trigger Compaction, Verify Frame-Aware Summary

**Scenario:** Test compaction integration under context pressure.

**Steps:**
1. Create frame with goal "Long running task"
2. Add many artifacts and decisions
3. Trigger compaction (simulate session.compacting event)
4. Verify custom compaction prompt includes frame context
5. Simulate session.compacted event with summary message
6. Verify summary stored in frame

**Expected:**
- Compacting hook receives frame context in prompt
- Summary extracted and stored
- Frame remains in_progress with updated summary

### E2E-5: Agent Autonomy Suggests Push Based on Context Switch

**Scenario:** Test autonomy suggestion system.

**Steps:**
1. Set autonomy level to "suggest"
2. Create frame with goal "Backend work"
3. Call `flame_should_push` with potentialGoal "Frontend UI", recentFileChanges: ["src/ui/App.tsx"]
4. Verify high context_switch score
5. Verify suggestion created
6. Verify suggestion in context (formatSuggestionsForContext)
7. Call `flame_push` with suggested goal
8. Verify suggestion marked as acted upon

**Expected:**
- Context switch detected due to different goal keywords
- Suggestion created with confidence above threshold
- Suggestion formatted in context
- Statistics updated after action

---

## 3. SPEC.md Compliance Tests

### 3.1 Frame Status Values

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-1 | Status: planned | Frame can have status `planned` | Pass |
| SPEC-2 | Status: in_progress | Frame can have status `in_progress` | Pass |
| SPEC-3 | Status: completed | Frame can have status `completed` | Pass |
| SPEC-4 | Status: failed | Frame can have status `failed` | Pass |
| SPEC-5 | Status: blocked | Frame can have status `blocked` | Pass |
| SPEC-6 | Status: invalidated | Frame can have status `invalidated` | Pass |

### 3.2 Push/Pop Semantics

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-7 | Push creates child frame | `flame_push` creates new child session | TBD |
| SPEC-8 | Pop returns to parent | `flame_pop` sets activeFrameID to parent | TBD |
| SPEC-9 | Pop generates summary | Summary stored on completion | TBD |

### 3.3 Context Structure

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-10 | XML format per spec | Context uses `<frame>`, `<goal>`, `<summary>`, `<artifacts>` | TBD |
| SPEC-11 | Current frame + ancestors | Context includes ancestor chain | TBD |
| SPEC-12 | Completed siblings included | Context includes completed sibling summaries | TBD |
| SPEC-13 | Full history not included | Only compactions, not full linear history | TBD |

### 3.4 Log Persistence

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-14 | Full logs persist to disk | Frame JSON files exist in .opencode/flame/frames/ | TBD |
| SPEC-15 | Log path referenced | logPath field available in metadata | TBD |

### 3.5 Planned Frames

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-16 | Planned frames exist before execution | Can create with status `planned` | TBD |
| SPEC-17 | Planned children can be sketched | `flame_plan_children` works | TBD |
| SPEC-18 | Plans mutable | Can add/modify planned frames | TBD |
| SPEC-19 | Invalidation cascades to planned | `flame_invalidate` cascades | TBD |

### 3.6 Control Authority

| ID | Requirement | Test | Status |
|----|-------------|------|--------|
| SPEC-20 | Human commands | /push, /pop, /status work | TBD |
| SPEC-21 | Agent tools | flame_push, flame_pop tools available | TBD |
| SPEC-22 | Autonomous heuristics | Autonomy system provides suggestions | TBD |

---

## 4. Test Execution Checklist

### Prerequisites
- [ ] OpenCode installed and accessible
- [ ] Flame plugin loaded (`.opencode/plugin/flame.ts` exists)
- [ ] No existing state (clean `.opencode/flame/` directory)

### Component Tests
- [ ] SM-1 through SM-10 executed
- [ ] CA-1 through CA-10 executed
- [ ] CI-1 through CI-7 executed
- [ ] SA-1 through SA-10 executed
- [ ] PL-1 through PL-5 executed
- [ ] IC-1 through IC-5 executed
- [ ] AU-1 through AU-13 executed

### End-to-End Tests
- [ ] E2E-1: Frame tree with summaries
- [ ] E2E-2: Subagent integration
- [ ] E2E-3: Planning and invalidation
- [ ] E2E-4: Compaction integration
- [ ] E2E-5: Autonomy suggestions

### SPEC.md Compliance
- [ ] All SPEC tests verified

---

## 5. Success Criteria

Phase 1 is considered **COMPLETE** if:

1. **Component Tests:** 80%+ pass rate on High priority tests
2. **End-to-End Tests:** All E2E tests pass or have documented acceptable failures
3. **SPEC.md Compliance:** All SPEC tests pass
4. **No Critical Bugs:** No data loss, crashes, or security issues
5. **Documentation:** All features documented in phase1/README.md

---

## 6. Test Data

### Sample Frame Goals
- "Build the application"
- "Implement authentication"
- "Create JWT tokens"
- "Build API routes"
- "Add database models"

### Sample Artifacts
- "src/auth/jwt.ts"
- "src/models/User.ts"
- "src/routes/api.ts"

### Sample Decisions
- "Use JWT for auth tokens instead of sessions"
- "PostgreSQL over MongoDB for relational data"

### Sample Subagent Titles
- "Analyze code structure (@build subagent)"
- "[Task] Review authentication implementation"
- "Quick helper task"
