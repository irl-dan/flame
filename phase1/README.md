# Phase 1: Core Plugin Implementation

This directory contains the design, validation results, and implementation for Phase 1 of Flame Graph Context Management.

---

## Phase Progression

| Phase | Name | Status | Description |
|-------|------|--------|-------------|
| 1.0 | [Validation](./1.0-validation/) | Complete | Validated OpenCode plugin API assumptions |
| 1.1 | [State Manager](./1.1-state-manager/) | Complete | File-based frame state management |
| 1.2 | [Context Assembly](./1.2-context-assembly/) | Complete | Enhanced context injection with token budgets |
| 1.3 | [Compaction Integration](./1.3-compaction-integration/) | Complete | Custom compaction prompts and summary capture |
| 1.4 | Log Persistence | Skipped | OpenCode handles logging natively (see [research](./research/opencode-logging.md)) |
| 1.5 | [Subagent Integration](./1.5-subagent-integration/) | Complete | TaskTool session detection, heuristic framing, auto-completion |
| 1.6 | [Planning & Invalidation](./1.6-planning-invalidation/) | Complete | Planned frame support, invalidation cascade, frame tree visualization |
| 1.7 | [Agent Autonomy](./1.7-agent-autonomy/) | Complete | Autonomy levels, push/pop heuristics, suggestion system |

**Phase 1 is now complete.**

---

## Overview

Phase 1 focuses on building the core OpenCode plugin that enables frame-based context management. The goal is to validate that tree-structured context (frames) can improve AI agent effectiveness by reducing irrelevant context in the active window.

## Completed Work

### Phase 1.0: Validation

Validated five critical assumptions about the OpenCode plugin API:

- **File Storage:** Plugins can write to `.opencode/flame/`
- **Session ID Tracking:** Track via `chat.message` hook for use in transform hooks
- **Hook Timing:** Predictable order - events -> chat.message -> transforms -> LLM
- **Message Prepend:** Synthetic messages via transform hooks reach the LLM
- **Compaction Capture:** Hooks are ready (not yet fully tested)

See [1.0-validation/results.md](./1.0-validation/results.md) for full details.

### Phase 1.1: State Manager

Implemented the core Frame State Manager with:

- **File-based persistence** in `.opencode/flame/`
- **Frame metadata tracking** (sessionID, status, goal, artifacts, decisions)
- **Custom tools:** `flame_push`, `flame_pop`, `flame_status`, `flame_set_goal`, `flame_add_artifact`, `flame_add_decision`
- **Session event tracking** for lifecycle management
- **Context injection** via message transform hook

All 10 automated tests pass. See [1.1-state-manager/tests/VERIFICATION-REPORT.md](./1.1-state-manager/tests/VERIFICATION-REPORT.md).

### Phase 1.2: Context Assembly

Implemented enhanced context injection with:

- **Token budget management** with configurable limits
- **Intelligent ancestor selection** with priority-based pruning
- **Sibling relevance filtering** based on goal similarity
- **Context caching** for performance optimization

All acceptance criteria verified. See [1.2-context-assembly/README.md](./1.2-context-assembly/README.md).

### Phase 1.3: Compaction Integration

Implemented:
- Custom compaction prompts for frame completion
- Better summary extraction from compaction events
- Automatic summary storage in frame metadata
- `flame_summarize` tool for manual summary generation

### Phase 1.5: Subagent Integration

Implemented:
- TaskTool/subagent session detection via `session.created` events with `parentID`
- Heuristic-based frame creation (duration, title patterns, message count)
- Automatic frame completion on `session.idle`
- Cross-frame context sharing between parent and child frames
- Runtime configuration via `flame_subagent_config` tool

See [1.5-subagent-integration/README.md](./1.5-subagent-integration/README.md) for details.

### Phase 1.6: Planning & Invalidation

Implemented:
- Planned frame support (`flame_plan`, `flame_plan_children`, `flame_activate`)
- Invalidation cascade (`flame_invalidate`)
- Frame tree visualization (`flame_tree`)
- Track invalidation reason and timestamp in frame metadata

See [1.6-planning-invalidation/README.md](./1.6-planning-invalidation/README.md) for details.

### Phase 1.7: Agent Autonomy (Final Phase)

Implemented:
- Autonomy configuration (manual/suggest/auto modes)
- Push heuristics (failure boundary, context switch, complexity, duration)
- Pop heuristics (goal completion, stagnation, context overflow)
- Auto-suggestion system with context injection
- `flame_autonomy_config`, `flame_should_push`, `flame_should_pop`, `flame_auto_suggest`, `flame_autonomy_stats` tools

See [1.7-agent-autonomy/README.md](./1.7-agent-autonomy/README.md) for details.

---

## Key Documents

| Document | Description |
|----------|-------------|
| [design/SYNTHESIS.md](./design/SYNTHESIS.md) | Consolidated implementation plan from three proposals |
| [design/proposals/](./design/proposals/) | Original implementation proposals (A, B, C) |

## Architecture Decisions

Based on synthesis of three implementation proposals:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Context Injection | Message prepend | Fresh per-call, visible for debugging, doesn't disrupt system prompt caching |
| Compaction Trigger | Both overflow and explicit pop | Handles long frames gracefully, gives user control |
| State Storage | File-based in `.opencode/flame/` | Portable, doesn't depend on internal APIs |
| Subagent Integration | Heuristic-based | Captures meaningful work without noise |
| Context Depth | All ancestors + completed siblings | Matches SPEC, can tune later |
| Autonomy Default | Suggest mode | Provides value without automatic actions |

## Directory Structure

```
phase1/
├── README.md                    # This file
├── design/                      # Design documents
│   ├── SYNTHESIS.md             # Implementation plan
│   └── proposals/               # Original proposals
│       ├── proposal-A.md
│       ├── proposal-B.md
│       └── proposal-C.md
├── 1.0-validation/              # Phase 1.0: Validation (complete)
│   ├── README.md
│   ├── flame-validation.ts
│   ├── test-plan.md
│   └── results.md
├── 1.1-state-manager/           # Phase 1.1: State Manager (complete)
│   ├── README.md
│   ├── IMPLEMENTATION.md
│   └── tests/
│       ├── test-state-manager.sh
│       ├── test-flame.sh
│       └── VERIFICATION-REPORT.md
├── 1.2-context-assembly/        # Phase 1.2: Context Assembly (complete)
│   ├── README.md
│   ├── IMPLEMENTATION.md
│   └── tests/
├── 1.3-compaction-integration/  # Phase 1.3: Compaction Integration (complete)
│   ├── README.md
│   └── IMPLEMENTATION.md
├── research/                    # Research documents
│   └── opencode-logging.md      # Why Phase 1.4 was skipped
├── 1.5-subagent-integration/    # Phase 1.5: Subagent Integration (complete)
│   ├── README.md
│   ├── IMPLEMENTATION.md
│   └── tests/
│       └── test-subagent.sh
├── 1.6-planning-invalidation/   # Phase 1.6: Planning & Invalidation (complete)
│   ├── README.md
│   └── IMPLEMENTATION.md
└── 1.7-agent-autonomy/          # Phase 1.7: Agent Autonomy (complete)
    ├── README.md
    ├── IMPLEMENTATION.md
    └── tests/
        └── test-autonomy.sh
```

## Plugin Location

The actual plugin implementation is at:
```
/Users/sl/code/flame/.opencode/plugin/flame.ts
```

## Running the Plugin

```bash
cd /Users/sl/code/flame
opencode
```

The plugin loads automatically and provides:
- Frame state management via custom tools
- Context injection via message transform
- Session event tracking for lifecycle management
- Autonomy suggestions for frame lifecycle

## Running Tests

```bash
# State Manager tests
/Users/sl/code/flame/phase1/1.1-state-manager/tests/test-state-manager.sh

# Agent Autonomy tests
/Users/sl/code/flame/phase1/1.7-agent-autonomy/tests/test-autonomy.sh
```

## Complete Tool Reference

### Core Frame Management
- `flame_push` - Create a new child frame
- `flame_pop` - Complete current frame and return to parent
- `flame_status` - Show current frame tree

### Frame Metadata
- `flame_set_goal` - Update frame goal
- `flame_add_artifact` - Record artifact produced
- `flame_add_decision` - Record key decision

### Context Assembly (Phase 1.2)
- `flame_context_info` - Show context generation metadata
- `flame_context_preview` - Preview injected XML context
- `flame_cache_clear` - Clear context cache

### Compaction (Phase 1.3)
- `flame_summarize` - Manual summary generation
- `flame_compaction_info` - Show compaction tracking state
- `flame_get_summary` - Get frame summary

### Subagent Integration (Phase 1.5)
- `flame_subagent_config` - View/modify subagent settings
- `flame_subagent_stats` - Show subagent statistics
- `flame_subagent_complete` - Manually complete subagent session
- `flame_subagent_list` - List tracked subagent sessions

### Planning & Invalidation (Phase 1.6)
- `flame_plan` - Create a planned frame
- `flame_plan_children` - Create multiple planned children
- `flame_activate` - Start working on a planned frame
- `flame_invalidate` - Invalidate frame with cascade
- `flame_tree` - Visual ASCII tree of all frames

### Agent Autonomy (Phase 1.7)
- `flame_autonomy_config` - View/modify autonomy settings
- `flame_should_push` - Evaluate push heuristics
- `flame_should_pop` - Evaluate pop heuristics
- `flame_auto_suggest` - Toggle auto-suggestions
- `flame_autonomy_stats` - View autonomy statistics

## Environment Variables

### Token Budget (Phase 1.2)
- `FLAME_TOKEN_BUDGET_TOTAL` - Total token budget for context
- `FLAME_TOKEN_BUDGET_ANCESTORS` - Budget for ancestor contexts
- `FLAME_TOKEN_BUDGET_SIBLINGS` - Budget for sibling contexts
- `FLAME_TOKEN_BUDGET_CURRENT` - Budget for current frame

### Subagent Integration (Phase 1.5)
- `FLAME_SUBAGENT_ENABLED` - Enable/disable subagent integration
- `FLAME_SUBAGENT_MIN_DURATION` - Minimum duration for frame creation
- `FLAME_SUBAGENT_MIN_MESSAGES` - Minimum message count
- `FLAME_SUBAGENT_AUTO_COMPLETE` - Auto-complete on idle
- `FLAME_SUBAGENT_IDLE_DELAY` - Delay before auto-complete
- `FLAME_SUBAGENT_PATTERNS` - Subagent detection patterns

### Agent Autonomy (Phase 1.7)
- `FLAME_AUTONOMY_LEVEL` - Autonomy level (manual/suggest/auto)
- `FLAME_PUSH_THRESHOLD` - Confidence threshold for push (0-100)
- `FLAME_POP_THRESHOLD` - Confidence threshold for pop (0-100)
- `FLAME_SUGGEST_IN_CONTEXT` - Include suggestions in context
- `FLAME_ENABLED_HEURISTICS` - Comma-separated list of heuristics

## Next Steps

With Phase 1 complete, potential future work includes:

### Phase 2 Possibilities
- Visual UI for frame tree navigation
- Integration with external project management tools
- Machine learning for heuristic improvement
- Multi-agent coordination across frames
- Performance optimization for deep trees
