# Next Steps

Future directions for the Call Stack Context Manager.

## Telemetry and Debug Logging

**Current state**: No structured logging of plugin activity. Debugging requires reading through OpenCode's general logs or adding console statements.

**Direction**: Add JSONL append-only logs for telemetry and debugging:

```
.opencode/stack/logs/
├── events.jsonl     # Frame lifecycle events
└── telemetry.jsonl  # Token counts, timing, costs
```

Each entry timestamped with event type, frame ID, and relevant metadata. Enables post-hoc analysis of agent behavior, performance profiling, and debugging without impacting runtime state management.

## Directory-Based Frame Storage

**Current state**: All frame metadata lives in a single `state.json` file that gets rewritten on every update. Individual frame files exist but duplicate the same data.

**Direction**: Move to a directory-based structure where each frame is self-contained:

```
.opencode/stack/
├── index.json              # Minimal: just frame IDs and tree structure
└── frames/{sessionID}/
    └── metadata.json       # All frame state lives here
```

This eliminates the monolithic state file that grows with every frame. Each frame update only touches its own directory. The index becomes a lightweight pointer structure rather than a full copy of all metadata.

## Webapp Flame Chart Improvements

**Current state**: The webapp shows a tree visualization with status colors and basic metadata. No runtime metrics are displayed.

**Direction**: Transform the tree into a proper flame chart where:

- Horizontal axis represents wall-clock time
- Frame width proportional to actual duration
- Display per-frame metrics: runtime, token count, estimated cost
- Stacked view showing time spent in each status phase

This would make it immediately visible which frames consumed the most resources and where time was spent waiting vs. actively working.

## Session Interactivity

**Current state**: Frames run to completion. The webapp is read-only—you can view frame state but cannot interact with sessions.

**Direction**: Enable stepping into and out of any session directly from the webapp:

- Click a frame to open its OpenCode session in a new terminal/tab
- Pause/resume frames mid-execution
- Manual checkpoint creation for branching scenarios
- Human-in-the-loop decision points where frames can request input before proceeding

This bridges the gap between passive visualization and active control.

## Stop All

**Current state**: Each frame completes independently. No mechanism to halt multiple active sessions at once.

**Direction**: Add cascade termination capability:

- `stack_stop_all` to send interrupt signals to all `in_progress` frames
- Graceful shutdown with status transition to `blocked` (preserving work)
- Automatic invalidation of downstream `planned` frames
- Parent notification of cascade events

Essential for recovering from runaway agents or pivoting when requirements change mid-execution.

## Parallelization Across Frames

**Current state**: Frames activate sequentially. Only one frame works at a time, even when sibling frames have no dependencies on each other.

**Direction**: Enable concurrent frame execution:

- Dependency graph where frames declare what they depend on
- Scheduler that activates all frames whose dependencies are satisfied
- Resource pooling to limit concurrent sessions (API rate limits, cost control)
- Work queue with ready/blocked frame tracking

Independent subtasks (e.g., "write tests" and "write docs" after implementation completes) could run in parallel, reducing total wall-clock time.

## Inversion of Control

**Current state**: The plugin manages frame lifecycle reactively—frames are created as subagents spawn, and the plugin orchestrates internally.

**Direction**: Move orchestration to an external container with declarative dependency trees:

```typescript
{
  frames: [
    { id: "research", goal: "Research options", outputs: ["findings.md"] },
    { id: "implement", goal: "Build solution", dependsOn: ["research"] },
    { id: "test", goal: "Validate", dependsOn: ["implement"], parallel: ["docs"] },
    { id: "docs", goal: "Write documentation", dependsOn: ["research"], parallel: ["test"] }
  ]
}
```

The external orchestrator would:

- Parse and validate the dependency DAG upfront
- Trigger frame activations in topological order
- Monitor completion, collect outputs, handle retries
- Enable frame reuse and composition across projects
- Scale execution across multiple agents or machines

This separates *what work needs to happen* from *how it gets executed*, enabling more sophisticated scheduling strategies and distributed execution.
