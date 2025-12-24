# Proposal: Flame Graph Context Management via Claude Agents SDK

**Date:** 2025-12-23
**Status:** Analysis Complete
**Verdict:** FULLY FEASIBLE - The most capable approach with complete control over context construction

---

## Executive Summary

This proposal analyzes implementing "Flame Graph Context Management" using the Claude Agents SDK (TypeScript/Python). Unlike the previous proposals, the Agents SDK provides **complete programmatic control** over how context is constructed, when subagents are spawned, and how conversation history is managed.

**Key Finding:** The Agents SDK is the IDEAL platform for flame graph context management because:

1. **Full Context Control**: We construct the context ourselves before each API call
2. **Session Management**: Each frame can be a separate session with explicit resume/fork
3. **Programmable Subagents**: Define subagents programmatically with custom prompts
4. **Hook System**: Intercept all tool calls, session events, and compaction
5. **Message Streaming**: Full visibility into all messages for logging and compaction

**Bottom Line:** This is a ground-up implementation that gives us exactly what we want. The tradeoff is development effort versus leveraging existing Claude Code capabilities, but the result is a purpose-built flame graph system with no compromises.

---

## Table of Contents

1. [Why the Agents SDK is Ideal](#1-why-the-agents-sdk-is-ideal)
2. [SDK Capabilities Analysis](#2-sdk-capabilities-analysis)
3. [Architecture Design](#3-architecture-design)
4. [Frame State Management](#4-frame-state-management)
5. [Custom Context Assembly](#5-custom-context-assembly)
6. [Compaction Generation](#6-compaction-generation)
7. [Push/Pop Mechanics](#7-pushpop-mechanics)
8. [Parent-Child Agent Coordination](#8-parent-child-agent-coordination)
9. [Implementation Code Examples](#9-implementation-code-examples)
10. [Comparison with Proposals 01 and 02](#10-comparison-with-proposals-01-and-02)
11. [Effort Estimate and Complexity Analysis](#11-effort-estimate-and-complexity-analysis)
12. [Recommendations](#12-recommendations)

---

## 1. Why the Agents SDK is Ideal

### The Core Problem Revisited

From SPEC.md, flame graph context management requires:
- **Active Context Construction**: Current frame + ancestor compactions + sibling compactions (NOT full linear history)
- **Frame Push/Pop**: Create child frames for subtasks, pop when complete
- **Full Logs to Disk**: Every frame's complete history saved
- **Compaction on Pop**: Generate summary when frame completes

### Why Previous Approaches Fall Short

| Approach | Critical Limitation |
|----------|---------------------|
| **Proposal 01 (Inside Claude Code)** | Cannot EXCLUDE linear history from context - hooks can only ADD |
| **Proposal 02 (Composing Claude Codes)** | Requires external orchestrator to spawn/manage processes |

### Why Agents SDK Succeeds

The Agents SDK provides the fundamental capability missing from both previous approaches:

```typescript
// We control EXACTLY what goes into context
const response = query({
  prompt: frameGoal,
  options: {
    systemPrompt: assembleFrameContext(currentFrame),  // We build this!
    resume: frameSessionId,  // Continue frame's own history
    // NO unwanted linear history - we control everything
  }
});
```

**The SDK does not impose linear history.** Each `query()` call starts fresh or resumes a specific session. We can inject ancestor compactions as system prompts, sibling summaries as context, and the frame's own working history via session resume - achieving TRUE context isolation.

---

## 2. SDK Capabilities Analysis

### 2.1 Conversation History Representation

The SDK represents conversation history through:

1. **Session IDs**: Each session has a unique identifier
2. **Transcript Files**: Full history persisted to JSONL files
3. **Message Streaming**: `SDKMessage` union type captures all message types

```typescript
// Message types we receive during query
type SDKMessage =
  | SDKAssistantMessage  // Claude's responses
  | SDKUserMessage       // User inputs
  | SDKSystemMessage     // Session init, compaction boundaries
  | SDKResultMessage     // Final results with usage/cost
  | SDKPartialAssistantMessage;  // Streaming chunks
```

**For Flame Graph**: Each frame gets its own session ID. The transcript file becomes the frame's log.

### 2.2 Context Interception/Modification

The SDK provides MULTIPLE ways to modify context:

#### System Prompt Control
```typescript
options: {
  // Complete replacement
  systemPrompt: "Custom instructions for this frame...",

  // Or append to Claude Code's default
  systemPrompt: {
    type: 'preset',
    preset: 'claude_code',
    append: "Frame-specific context here..."
  }
}
```

#### Session Resume with Context Injection
```typescript
// Resume frame's session with additional context
const response = query({
  prompt: "Continue work with this context: " + siblingCompactions,
  options: {
    resume: frameSessionId,
    // Frame's own history is loaded automatically
  }
});
```

#### Hooks for Real-time Modification
```typescript
hooks: {
  UserPromptSubmit: [{
    hooks: [async (input) => ({
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: getFrameContext(currentFrame)
      }
    })]
  }],
  PreCompact: [{
    hooks: [async (input) => ({
      systemMessage: "Preserve frame-specific context when compacting..."
    })]
  }]
}
```

### 2.3 Parent/Child Agent Hierarchies

The SDK supports subagents with custom configurations:

```typescript
options: {
  agents: {
    "frame-worker": {
      description: "Executes focused work within a frame boundary",
      prompt: "You are working on a specific subtask. Stay focused on the goal.",
      tools: ["Read", "Edit", "Bash", "Glob", "Grep"],
      model: "sonnet"
    }
  },
  allowedTools: ["Task", ...]  // Enable Task tool to spawn subagents
}
```

**For Flame Graph**: Subagents can represent child frames with isolated context.

### 2.4 Session Management Features

| Feature | SDK Support | Frame Graph Use |
|---------|-------------|-----------------|
| Create session | Automatic on `query()` | Each frame = new session |
| Resume session | `resume: sessionId` | Return to frame work |
| Fork session | `forkSession: true` | Create child frame from parent |
| Session ID access | Init message `session_id` | Track frame-to-session mapping |
| Transcript access | `transcript_path` in hooks | Full frame logs |

### 2.5 Hooks for State Management

Available hooks map well to frame lifecycle:

| Hook | Frame Graph Use |
|------|-----------------|
| `SessionStart` | Initialize frame, inject context |
| `SessionEnd` | Generate compaction, persist state |
| `PreToolUse` | Log tool usage to frame |
| `PostToolUse` | Track artifacts, detect completion |
| `SubagentStart` | Child frame creation |
| `SubagentStop` | Child frame completion, extract summary |
| `PreCompact` | Custom compaction with frame awareness |
| `Stop` | Detect frame completion signal |

---

## 3. Architecture Design

### 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Flame Graph Orchestrator                         │
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │  Frame State    │  │    Context      │  │    Compaction       │  │
│  │   Manager       │  │   Assembler     │  │    Generator        │  │
│  │                 │  │                 │  │                     │  │
│  │ • Tree storage  │  │ • Build context │  │ • LLM summarization │  │
│  │ • Session map   │  │ • Ancestor walk │  │ • Artifact extract  │  │
│  │ • Status track  │  │ • Sibling merge │  │ • Decision capture  │  │
│  └────────┬────────┘  └────────┬────────┘  └──────────┬──────────┘  │
│           │                    │                      │              │
│           └────────────────────┼──────────────────────┘              │
│                                │                                     │
│  ┌─────────────────────────────┴─────────────────────────────────┐  │
│  │                    Query Interface                             │  │
│  │                                                                │  │
│  │   • Wraps SDK query()                                          │  │
│  │   • Injects frame context via systemPrompt                     │  │
│  │   • Manages session lifecycle                                  │  │
│  │   • Streams messages to frame logs                             │  │
│  │   • Detects completion signals                                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                │                                     │
└────────────────────────────────┼─────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                    Claude Agents SDK                                │
│                                                                     │
│   query() → AsyncGenerator<SDKMessage>                              │
│                                                                     │
│   • Manages API calls                                               │
│   • Executes tools                                                  │
│   • Streams responses                                               │
│   • Handles sessions                                                │
└────────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Responsibilities

#### Frame State Manager
- Maintains tree of frames (Map<frameId, Frame>)
- Tracks frame-to-session mapping
- Persists state to disk
- Handles planned frames and invalidation

#### Context Assembler
- Builds context for each frame from:
  - Current frame's goal and instructions
  - Ancestor chain compactions
  - Completed sibling compactions
- Formats as system prompt or additional context

#### Compaction Generator
- Generates summaries when frames complete
- Uses Claude to summarize frame work
- Extracts artifacts and key decisions
- Stores compaction in frame state

#### Query Interface
- Wraps SDK `query()` function
- Injects assembled context
- Manages session resume/create
- Streams messages to frame logs
- Detects FRAME_COMPLETE signals

---

## 4. Frame State Management

### 4.1 Data Structures

```typescript
interface Frame {
  id: string;
  sessionId: string;
  parent: string | null;
  children: string[];
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked' | 'invalidated';
  goal: string;
  compaction: FrameCompaction | null;
  logPath: string;
  createdAt: string;
  completedAt: string | null;
}

interface FrameCompaction {
  summary: string;
  artifacts: string[];
  decisions: string[];
  status: 'completed' | 'failed' | 'blocked';
}

interface FlameState {
  frames: Map<string, Frame>;
  currentFrameId: string;
  rootFrameId: string;
  version: number;
}
```

### 4.2 State Persistence

```typescript
class FrameStateManager {
  private state: FlameState;
  private statePath: string;
  private logsDir: string;

  constructor(projectDir: string) {
    this.statePath = path.join(projectDir, '.flame', 'state.json');
    this.logsDir = path.join(projectDir, '.flame', 'logs');
    this.loadState();
  }

  private loadState(): void {
    if (fs.existsSync(this.statePath)) {
      const data = JSON.parse(fs.readFileSync(this.statePath, 'utf-8'));
      this.state = {
        frames: new Map(Object.entries(data.frames)),
        currentFrameId: data.currentFrameId,
        rootFrameId: data.rootFrameId,
        version: data.version
      };
    } else {
      this.initializeState();
    }
  }

  private saveState(): void {
    const data = {
      frames: Object.fromEntries(this.state.frames),
      currentFrameId: this.state.currentFrameId,
      rootFrameId: this.state.rootFrameId,
      version: this.state.version
    };
    fs.mkdirSync(path.dirname(this.statePath), { recursive: true });
    fs.writeFileSync(this.statePath, JSON.stringify(data, null, 2));
  }

  getCurrentFrame(): Frame {
    return this.state.frames.get(this.state.currentFrameId)!;
  }

  getAncestors(frameId: string): Frame[] {
    const ancestors: Frame[] = [];
    let current = this.state.frames.get(frameId);
    while (current?.parent) {
      const parent = this.state.frames.get(current.parent);
      if (parent) {
        ancestors.push(parent);
        current = parent;
      } else break;
    }
    return ancestors;
  }

  getCompletedSiblings(frameId: string): Frame[] {
    const frame = this.state.frames.get(frameId);
    if (!frame?.parent) return [];

    const parent = this.state.frames.get(frame.parent);
    if (!parent) return [];

    return parent.children
      .filter(id => id !== frameId)
      .map(id => this.state.frames.get(id)!)
      .filter(f => f.status === 'completed' && f.compaction);
  }
}
```

---

## 5. Custom Context Assembly

### 5.1 Context Assembly Algorithm

```typescript
class ContextAssembler {
  constructor(private stateManager: FrameStateManager) {}

  assembleContext(frameId: string): string {
    const frame = this.stateManager.getFrame(frameId);
    const ancestors = this.stateManager.getAncestors(frameId);
    const siblings = this.stateManager.getCompletedSiblings(frameId);

    const parts: string[] = [];

    // 1. Frame Graph Header
    parts.push(`# Flame Graph Context

You are operating within a FLAME GRAPH context management system.
Your work is organized as a tree of frames, not linear chat history.
`);

    // 2. Ancestor Chain (root to parent)
    if (ancestors.length > 0) {
      parts.push(`## Ancestor Context (Compacted)`);
      for (const ancestor of ancestors.reverse()) {
        if (ancestor.compaction) {
          parts.push(`
### ${ancestor.goal}
**Status:** ${ancestor.compaction.status}
**Summary:** ${ancestor.compaction.summary}
**Artifacts:** ${ancestor.compaction.artifacts.join(', ') || 'none'}
**Key Decisions:** ${ancestor.compaction.decisions.join('; ') || 'none'}
`);
        } else {
          parts.push(`
### ${ancestor.goal}
**Status:** in_progress
(Parent frame - currently active)
`);
        }
      }
    }

    // 3. Completed Sibling Frames
    if (siblings.length > 0) {
      parts.push(`## Sibling Frames (Completed)`);
      for (const sibling of siblings) {
        parts.push(`
### ${sibling.goal}
**Status:** ${sibling.compaction!.status}
**Summary:** ${sibling.compaction!.summary}
**Artifacts:** ${sibling.compaction!.artifacts.join(', ') || 'none'}
`);
      }
    }

    // 4. Current Frame Instructions
    parts.push(`
## Current Frame

**Frame ID:** ${frame.id}
**Goal:** ${frame.goal}
**Status:** ${frame.status}

### Instructions

1. Focus exclusively on this frame's goal
2. When you complete the goal, output: FRAME_COMPLETE: <summary>
3. If you need a distinct subtask, output: PUSH_FRAME: <subtask goal>
4. If blocked or failed, output: FRAME_BLOCKED: <reason> or FRAME_FAILED: <reason>
5. You can reference artifacts from sibling frames but don't repeat their work
6. Keep your work bounded and completable

Begin your work on: **${frame.goal}**
`);

    return parts.join('\n');
  }
}
```

### 5.2 Context Injection via System Prompt

```typescript
async function executeFrame(
  frameId: string,
  stateManager: FrameStateManager,
  contextAssembler: ContextAssembler
): Promise<void> {
  const frame = stateManager.getFrame(frameId);
  const context = contextAssembler.assembleContext(frameId);

  // Create or resume session
  const isNewFrame = !frame.sessionId;
  const sessionId = frame.sessionId || crypto.randomUUID();

  if (isNewFrame) {
    stateManager.updateFrame(frameId, { sessionId });
  }

  const options: Options = {
    systemPrompt: context,  // Inject assembled context
    allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task'],
    permissionMode: 'acceptEdits',
    hooks: createFrameHooks(frameId, stateManager),
    ...(isNewFrame ? {} : { resume: sessionId })
  };

  const prompt = isNewFrame
    ? `Begin work on: ${frame.goal}`
    : `Continue work on your current frame goal.`;

  for await (const message of query({ prompt, options })) {
    // Log to frame transcript
    logToFrame(frameId, message);

    // Check for frame signals
    if (message.type === 'assistant') {
      const text = extractText(message);

      if (text.includes('FRAME_COMPLETE:')) {
        const summary = extractAfter(text, 'FRAME_COMPLETE:');
        await completeFrame(frameId, 'completed', summary);
        return;
      }

      if (text.includes('PUSH_FRAME:')) {
        const childGoal = extractAfter(text, 'PUSH_FRAME:');
        await pushFrame(childGoal, frameId, stateManager);
        // Recursively execute child frame
        // Then resume parent when child completes
      }
    }
  }
}
```

---

## 6. Compaction Generation

### 6.1 LLM-Based Compaction

```typescript
class CompactionGenerator {
  async generateCompaction(
    frameId: string,
    status: 'completed' | 'failed' | 'blocked',
    stateManager: FrameStateManager
  ): Promise<FrameCompaction> {
    const frame = stateManager.getFrame(frameId);
    const transcript = this.loadTranscript(frame.logPath);

    // Use Claude to generate compaction
    const compactionPrompt = `
You are generating a compaction summary for a completed work frame.

## Frame Information
**Goal:** ${frame.goal}
**Status:** ${status}
**Duration:** ${this.calculateDuration(frame)}

## Transcript
${this.formatTranscript(transcript)}

## Instructions

Generate a compaction summary with:
1. **Summary**: 2-3 sentences describing what was accomplished
2. **Artifacts**: List of files/resources created or modified (paths)
3. **Decisions**: Key technical decisions made (1-2 sentences each)

Respond in JSON format:
{
  "summary": "...",
  "artifacts": ["path1", "path2"],
  "decisions": ["decision1", "decision2"]
}
`;

    // Use SDK to generate compaction (single turn, no tools)
    let compactionResult: FrameCompaction = {
      summary: '',
      artifacts: [],
      decisions: [],
      status
    };

    for await (const message of query({
      prompt: compactionPrompt,
      options: {
        maxTurns: 1,
        allowedTools: [],  // No tools needed for summarization
      }
    })) {
      if (message.type === 'result' && message.result) {
        try {
          const parsed = JSON.parse(message.result);
          compactionResult = { ...parsed, status };
        } catch {
          // Fallback to basic compaction
          compactionResult.summary = message.result;
        }
      }
    }

    return compactionResult;
  }

  private loadTranscript(logPath: string): SDKMessage[] {
    if (!fs.existsSync(logPath)) return [];
    const lines = fs.readFileSync(logPath, 'utf-8').split('\n');
    return lines.filter(l => l).map(l => JSON.parse(l));
  }

  private formatTranscript(messages: SDKMessage[]): string {
    return messages
      .filter(m => m.type === 'assistant' || m.type === 'user')
      .map(m => {
        if (m.type === 'assistant') {
          return `Assistant: ${this.extractContent(m)}`;
        } else {
          return `User: ${this.extractContent(m)}`;
        }
      })
      .join('\n\n');
  }
}
```

### 6.2 Hook-Based Compaction Trigger

```typescript
function createFrameHooks(
  frameId: string,
  stateManager: FrameStateManager
): Partial<Record<HookEvent, HookCallbackMatcher[]>> {
  return {
    // Log all tool usage
    PostToolUse: [{
      hooks: [async (input, toolUseId) => {
        const postInput = input as PostToolUseHookInput;
        logToolUse(frameId, postInput.tool_name, postInput.tool_input, postInput.tool_response);

        // Track artifacts for compaction
        if (postInput.tool_name === 'Write' || postInput.tool_name === 'Edit') {
          trackArtifact(frameId, postInput.tool_input.file_path);
        }

        return {};
      }]
    }],

    // Custom compaction handling
    PreCompact: [{
      hooks: [async (input) => {
        return {
          systemMessage: `
When compacting, preserve frame context:
- Current frame goal: ${stateManager.getCurrentFrame().goal}
- Key artifacts: ${getFrameArtifacts(frameId).join(', ')}
- Prioritize recent work over historical exploration
`
        };
      }]
    }],

    // Detect agent stop to potentially trigger frame completion
    Stop: [{
      hooks: [async (input) => {
        // Check if agent naturally finished
        // Could trigger compaction if goal appears complete
        return {};
      }]
    }],

    // Track subagent (child frame) completion
    SubagentStop: [{
      hooks: [async (input) => {
        // Subagent completion = child frame completion
        // Extract result and update frame state
        return {};
      }]
    }]
  };
}
```

---

## 7. Push/Pop Mechanics

### 7.1 Push Frame

```typescript
async function pushFrame(
  goal: string,
  parentId: string,
  stateManager: FrameStateManager
): Promise<string> {
  // Generate frame ID and session ID
  const frameId = `frame-${crypto.randomUUID().slice(0, 8)}`;
  const sessionId = crypto.randomUUID();

  // Create frame record
  const frame: Frame = {
    id: frameId,
    sessionId,
    parent: parentId,
    children: [],
    status: 'in_progress',
    goal,
    compaction: null,
    logPath: path.join(stateManager.logsDir, `${frameId}.jsonl`),
    createdAt: new Date().toISOString(),
    completedAt: null
  };

  // Update state
  stateManager.addFrame(frame);
  stateManager.addChild(parentId, frameId);
  stateManager.setCurrentFrame(frameId);

  console.log(`[PUSH] Created frame ${frameId}: ${goal}`);
  console.log(`[PUSH] Parent: ${parentId}`);

  return frameId;
}
```

### 7.2 Pop Frame

```typescript
async function popFrame(
  frameId: string,
  status: 'completed' | 'failed' | 'blocked',
  summary: string | null,
  stateManager: FrameStateManager,
  compactionGenerator: CompactionGenerator
): Promise<void> {
  const frame = stateManager.getFrame(frameId);

  // Generate compaction if not provided
  const compaction = summary
    ? { summary, artifacts: [], decisions: [], status }
    : await compactionGenerator.generateCompaction(frameId, status, stateManager);

  // Update frame
  stateManager.updateFrame(frameId, {
    status,
    compaction,
    completedAt: new Date().toISOString()
  });

  console.log(`[POP] Completed frame ${frameId}: ${status}`);
  console.log(`[POP] Summary: ${compaction.summary}`);

  // Switch to parent
  if (frame.parent) {
    stateManager.setCurrentFrame(frame.parent);
    console.log(`[POP] Returned to parent: ${frame.parent}`);

    // Inject compaction into parent context
    await notifyParentOfChildCompletion(frame.parent, compaction, stateManager);
  }
}
```

### 7.3 Notify Parent of Child Completion

```typescript
async function notifyParentOfChildCompletion(
  parentId: string,
  childCompaction: FrameCompaction,
  stateManager: FrameStateManager
): Promise<void> {
  const parent = stateManager.getFrame(parentId);

  // Resume parent session with child's compaction as context
  const message = `
Child frame completed. Here's the summary:

**Status:** ${childCompaction.status}
**Summary:** ${childCompaction.summary}
**Artifacts:** ${childCompaction.artifacts.join(', ') || 'none'}
**Key Decisions:** ${childCompaction.decisions.join('; ') || 'none'}

Continue with the parent frame's work. You can now use any artifacts created by the child frame.
`;

  for await (const msg of query({
    prompt: message,
    options: {
      resume: parent.sessionId,
      // Parent's context is restored, child's compaction injected as prompt
    }
  })) {
    logToFrame(parentId, msg);
    // Continue processing parent frame...
  }
}
```

---

## 8. Parent-Child Agent Coordination

### 8.1 Using SDK Subagents for Child Frames

```typescript
async function executeFrameWithSubagents(
  frameId: string,
  stateManager: FrameStateManager,
  contextAssembler: ContextAssembler
): Promise<void> {
  const frame = stateManager.getFrame(frameId);
  const context = contextAssembler.assembleContext(frameId);

  const options: Options = {
    systemPrompt: context,
    allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task'],

    // Define child frame worker as subagent
    agents: {
      'child-frame': {
        description: 'Execute a focused subtask within a child frame',
        prompt: `You are working on a child frame within a flame graph context.
Your work will be compacted and returned to the parent frame when complete.
Focus on your specific goal. When done, summarize your work clearly.`,
        tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'],
        model: 'sonnet'
      }
    },

    hooks: {
      SubagentStart: [{
        hooks: [async (input) => {
          const subInput = input as SubagentStartHookInput;
          console.log(`[SUBAGENT] Starting: ${subInput.agent_id}`);
          // Could create child frame here
          return {};
        }]
      }],
      SubagentStop: [{
        hooks: [async (input) => {
          const subInput = input as SubagentStopHookInput;
          console.log(`[SUBAGENT] Stopped`);
          // Extract result, generate compaction
          return {};
        }]
      }]
    }
  };

  for await (const message of query({
    prompt: `Begin work on: ${frame.goal}`,
    options
  })) {
    logToFrame(frameId, message);

    // Subagent messages have parent_tool_use_id set
    if (message.parent_tool_use_id) {
      // This is from a child frame
      handleChildFrameMessage(message, stateManager);
    }
  }
}
```

### 8.2 Explicit Session-Per-Frame Model

For maximum isolation, we can use separate sessions per frame:

```typescript
class FlameGraphOrchestrator {
  private stateManager: FrameStateManager;
  private contextAssembler: ContextAssembler;
  private compactionGenerator: CompactionGenerator;

  async executeFrame(frameId: string): Promise<void> {
    const frame = this.stateManager.getFrame(frameId);
    const context = this.contextAssembler.assembleContext(frameId);

    // Each frame gets its own session
    // If new frame, create session; if existing, resume
    const sessionOptions = frame.sessionId
      ? { resume: frame.sessionId }
      : {};

    for await (const message of query({
      prompt: frame.sessionId
        ? 'Continue your work on the current frame goal.'
        : `Begin work on: ${frame.goal}`,
      options: {
        systemPrompt: context,
        ...sessionOptions,
        allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'],
        permissionMode: 'acceptEdits',
        hooks: this.createFrameHooks(frameId)
      }
    })) {
      // Capture session ID if new
      if (message.type === 'system' && message.subtype === 'init') {
        if (!frame.sessionId) {
          this.stateManager.updateFrame(frameId, {
            sessionId: message.session_id
          });
        }
      }

      // Log message
      this.logToFrame(frameId, message);

      // Handle frame signals
      await this.handleFrameSignals(frameId, message);
    }
  }

  private async handleFrameSignals(
    frameId: string,
    message: SDKMessage
  ): Promise<void> {
    if (message.type !== 'assistant') return;

    const text = this.extractText(message);

    // Child frame push
    if (text.includes('PUSH_FRAME:')) {
      const childGoal = this.extractAfter(text, 'PUSH_FRAME:');
      const childId = await this.pushFrame(childGoal, frameId);

      // Execute child frame (recursive)
      await this.executeFrame(childId);

      // After child completes, we return here and continue parent
      // The child's compaction is now available in context
    }

    // Frame completion
    if (text.includes('FRAME_COMPLETE:')) {
      const summary = this.extractAfter(text, 'FRAME_COMPLETE:');
      await this.popFrame(frameId, 'completed', summary);
    }

    // Frame blocked/failed
    if (text.includes('FRAME_BLOCKED:')) {
      const reason = this.extractAfter(text, 'FRAME_BLOCKED:');
      await this.popFrame(frameId, 'blocked', reason);
    }

    if (text.includes('FRAME_FAILED:')) {
      const reason = this.extractAfter(text, 'FRAME_FAILED:');
      await this.popFrame(frameId, 'failed', reason);
    }
  }
}
```

---

## 9. Implementation Code Examples

### 9.1 Complete Flame Graph Orchestrator (TypeScript)

```typescript
// flame-orchestrator.ts
import { query, Options, SDKMessage, HookCallback } from '@anthropic-ai/claude-agent-sdk';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';

// Types
interface Frame {
  id: string;
  sessionId: string | null;
  parent: string | null;
  children: string[];
  status: 'planned' | 'in_progress' | 'completed' | 'failed' | 'blocked' | 'invalidated';
  goal: string;
  compaction: FrameCompaction | null;
  logPath: string;
  createdAt: string;
  completedAt: string | null;
}

interface FrameCompaction {
  summary: string;
  artifacts: string[];
  decisions: string[];
  status: 'completed' | 'failed' | 'blocked';
}

interface FlameState {
  frames: Record<string, Frame>;
  currentFrameId: string;
  rootFrameId: string;
}

// Main Orchestrator Class
export class FlameGraphOrchestrator {
  private state: FlameState;
  private flameDir: string;
  private statePath: string;
  private logsDir: string;

  constructor(projectDir: string) {
    this.flameDir = path.join(projectDir, '.flame');
    this.statePath = path.join(this.flameDir, 'state.json');
    this.logsDir = path.join(this.flameDir, 'logs');

    fs.mkdirSync(this.logsDir, { recursive: true });
    this.loadOrInitState();
  }

  private loadOrInitState(): void {
    if (fs.existsSync(this.statePath)) {
      this.state = JSON.parse(fs.readFileSync(this.statePath, 'utf-8'));
    } else {
      const rootId = `frame-${crypto.randomUUID().slice(0, 8)}`;
      this.state = {
        frames: {},
        currentFrameId: rootId,
        rootFrameId: rootId
      };
    }
  }

  private saveState(): void {
    fs.writeFileSync(this.statePath, JSON.stringify(this.state, null, 2));
  }

  // Initialize with a root goal
  async init(goal: string): Promise<string> {
    const rootId = this.state.rootFrameId;

    if (!this.state.frames[rootId]) {
      this.state.frames[rootId] = {
        id: rootId,
        sessionId: null,
        parent: null,
        children: [],
        status: 'in_progress',
        goal,
        compaction: null,
        logPath: path.join(this.logsDir, `${rootId}.jsonl`),
        createdAt: new Date().toISOString(),
        completedAt: null
      };
      this.saveState();
    }

    return rootId;
  }

  // Get current frame
  getCurrentFrame(): Frame {
    return this.state.frames[this.state.currentFrameId];
  }

  // Assemble context for a frame
  private assembleContext(frameId: string): string {
    const frame = this.state.frames[frameId];
    const ancestors = this.getAncestors(frameId);
    const siblings = this.getCompletedSiblings(frameId);

    let context = `# Flame Graph Context

You are working within a flame graph context management system.
Work is organized as a tree of frames, not linear history.

`;

    // Ancestors
    if (ancestors.length > 0) {
      context += `## Ancestor Context\n\n`;
      for (const ancestor of ancestors.reverse()) {
        if (ancestor.compaction) {
          context += `### ${ancestor.goal}\n`;
          context += `**Summary:** ${ancestor.compaction.summary}\n`;
          context += `**Artifacts:** ${ancestor.compaction.artifacts.join(', ') || 'none'}\n\n`;
        }
      }
    }

    // Siblings
    if (siblings.length > 0) {
      context += `## Completed Siblings\n\n`;
      for (const sibling of siblings) {
        context += `### ${sibling.goal}\n`;
        context += `**Summary:** ${sibling.compaction!.summary}\n`;
        context += `**Artifacts:** ${sibling.compaction!.artifacts.join(', ') || 'none'}\n\n`;
      }
    }

    // Current frame
    context += `## Current Frame

**ID:** ${frame.id}
**Goal:** ${frame.goal}

### Frame Signals
- FRAME_COMPLETE: <summary> - when goal is achieved
- PUSH_FRAME: <goal> - to create a child frame for a subtask
- FRAME_BLOCKED: <reason> - if you cannot proceed
- FRAME_FAILED: <reason> - if the task failed

Focus on: **${frame.goal}**
`;

    return context;
  }

  private getAncestors(frameId: string): Frame[] {
    const ancestors: Frame[] = [];
    let current = this.state.frames[frameId];
    while (current?.parent) {
      const parent = this.state.frames[current.parent];
      if (parent) {
        ancestors.push(parent);
        current = parent;
      } else break;
    }
    return ancestors;
  }

  private getCompletedSiblings(frameId: string): Frame[] {
    const frame = this.state.frames[frameId];
    if (!frame?.parent) return [];

    const parent = this.state.frames[frame.parent];
    if (!parent) return [];

    return parent.children
      .filter(id => id !== frameId)
      .map(id => this.state.frames[id])
      .filter(f => f && f.status === 'completed' && f.compaction);
  }

  // Push a new child frame
  async pushFrame(goal: string): Promise<string> {
    const parentId = this.state.currentFrameId;
    const frameId = `frame-${crypto.randomUUID().slice(0, 8)}`;

    this.state.frames[frameId] = {
      id: frameId,
      sessionId: null,
      parent: parentId,
      children: [],
      status: 'in_progress',
      goal,
      compaction: null,
      logPath: path.join(this.logsDir, `${frameId}.jsonl`),
      createdAt: new Date().toISOString(),
      completedAt: null
    };

    this.state.frames[parentId].children.push(frameId);
    this.state.currentFrameId = frameId;
    this.saveState();

    console.log(`[PUSH] ${frameId}: ${goal}`);
    return frameId;
  }

  // Pop current frame
  async popFrame(
    status: 'completed' | 'failed' | 'blocked',
    summary: string
  ): Promise<void> {
    const frameId = this.state.currentFrameId;
    const frame = this.state.frames[frameId];

    frame.status = status;
    frame.compaction = {
      summary,
      artifacts: this.extractArtifacts(frame.logPath),
      decisions: [],
      status
    };
    frame.completedAt = new Date().toISOString();

    console.log(`[POP] ${frameId}: ${status}`);
    console.log(`[POP] Summary: ${summary}`);

    if (frame.parent) {
      this.state.currentFrameId = frame.parent;
    }
    this.saveState();
  }

  private extractArtifacts(logPath: string): string[] {
    // Extract file paths from Write/Edit tool calls in log
    const artifacts: string[] = [];
    if (fs.existsSync(logPath)) {
      const lines = fs.readFileSync(logPath, 'utf-8').split('\n');
      for (const line of lines) {
        if (!line) continue;
        try {
          const msg = JSON.parse(line);
          if (msg.toolName === 'Write' || msg.toolName === 'Edit') {
            const filePath = msg.toolInput?.file_path;
            if (filePath && !artifacts.includes(filePath)) {
              artifacts.push(filePath);
            }
          }
        } catch {}
      }
    }
    return artifacts;
  }

  // Log message to frame
  private logToFrame(frameId: string, message: SDKMessage): void {
    const frame = this.state.frames[frameId];
    const line = JSON.stringify({
      timestamp: new Date().toISOString(),
      ...message
    });
    fs.appendFileSync(frame.logPath, line + '\n');
  }

  // Execute current frame
  async execute(): Promise<void> {
    const frame = this.getCurrentFrame();
    const context = this.assembleContext(frame.id);

    const options: Options = {
      systemPrompt: context,
      allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'],
      permissionMode: 'acceptEdits',
      ...(frame.sessionId ? { resume: frame.sessionId } : {})
    };

    const prompt = frame.sessionId
      ? 'Continue work on your current frame goal.'
      : `Begin work on: ${frame.goal}`;

    for await (const message of query({ prompt, options })) {
      // Capture session ID
      if (message.type === 'system' && message.subtype === 'init') {
        if (!frame.sessionId) {
          frame.sessionId = message.session_id;
          this.saveState();
        }
      }

      // Log message
      this.logToFrame(frame.id, message);

      // Handle frame signals
      if (message.type === 'assistant' && message.message?.content) {
        const text = message.message.content
          .filter(b => b.type === 'text')
          .map(b => (b as any).text)
          .join('');

        if (text.includes('PUSH_FRAME:')) {
          const goal = text.split('PUSH_FRAME:')[1].trim().split('\n')[0];
          await this.pushFrame(goal);
          await this.execute();  // Recurse into child
          // After child completes, continue in parent
        }

        if (text.includes('FRAME_COMPLETE:')) {
          const summary = text.split('FRAME_COMPLETE:')[1].trim();
          await this.popFrame('completed', summary);
          return;  // Exit this frame
        }

        if (text.includes('FRAME_BLOCKED:')) {
          const reason = text.split('FRAME_BLOCKED:')[1].trim();
          await this.popFrame('blocked', reason);
          return;
        }

        if (text.includes('FRAME_FAILED:')) {
          const reason = text.split('FRAME_FAILED:')[1].trim();
          await this.popFrame('failed', reason);
          return;
        }
      }
    }
  }

  // Display frame tree
  printTree(): void {
    const printFrame = (frameId: string, indent: number): void => {
      const frame = this.state.frames[frameId];
      if (!frame) return;

      const prefix = '  '.repeat(indent);
      const current = frameId === this.state.currentFrameId ? ' <-- CURRENT' : '';
      const status = frame.status;

      console.log(`${prefix}[${status}] ${frame.goal}${current}`);

      if (frame.compaction) {
        console.log(`${prefix}  Summary: ${frame.compaction.summary}`);
      }

      for (const childId of frame.children) {
        printFrame(childId, indent + 1);
      }
    };

    console.log('\n=== Flame Graph Tree ===');
    printFrame(this.state.rootFrameId, 0);
    console.log('========================\n');
  }
}

// CLI Interface
async function main() {
  const orchestrator = new FlameGraphOrchestrator(process.cwd());

  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case 'init':
      const goal = args.slice(1).join(' ') || 'Complete the project';
      await orchestrator.init(goal);
      console.log('Initialized with root goal:', goal);
      break;

    case 'run':
      await orchestrator.execute();
      break;

    case 'push':
      const pushGoal = args.slice(1).join(' ');
      if (!pushGoal) {
        console.error('Usage: flame push <goal>');
        process.exit(1);
      }
      await orchestrator.pushFrame(pushGoal);
      await orchestrator.execute();
      break;

    case 'status':
      orchestrator.printTree();
      break;

    default:
      console.log('Usage: flame <init|run|push|status> [args]');
  }
}

main().catch(console.error);
```

### 9.2 Human Control Interface

```typescript
// flame-cli.ts
import * as readline from 'readline';
import { FlameGraphOrchestrator } from './flame-orchestrator';

async function interactiveMode() {
  const orchestrator = new FlameGraphOrchestrator(process.cwd());

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const prompt = () => {
    const current = orchestrator.getCurrentFrame();
    rl.question(`[${current.id}] > `, async (input) => {
      const [cmd, ...args] = input.trim().split(' ');

      switch (cmd) {
        case '/push':
          const goal = args.join(' ');
          await orchestrator.pushFrame(goal);
          console.log(`Pushed new frame: ${goal}`);
          break;

        case '/pop':
          const status = args[0] as 'completed' | 'failed' | 'blocked' || 'completed';
          const summary = args.slice(1).join(' ') || 'Completed';
          await orchestrator.popFrame(status, summary);
          console.log('Popped frame');
          break;

        case '/status':
          orchestrator.printTree();
          break;

        case '/run':
          await orchestrator.execute();
          break;

        case '/help':
          console.log(`
Commands:
  /push <goal>     - Push new child frame
  /pop [status] [summary] - Pop current frame
  /status          - Show frame tree
  /run             - Execute current frame
  /quit            - Exit
          `);
          break;

        case '/quit':
          rl.close();
          process.exit(0);

        default:
          console.log('Unknown command. Type /help for options.');
      }

      prompt();
    });
  };

  console.log('Flame Graph Interactive Mode');
  console.log('Type /help for commands\n');
  prompt();
}

interactiveMode();
```

---

## 10. Comparison with Proposals 01 and 02

### 10.1 Feature Comparison

| Feature | Proposal 01 (Inside Claude Code) | Proposal 02 (Composing CLIs) | Proposal 03 (Agents SDK) |
|---------|----------------------------------|------------------------------|--------------------------|
| **True Context Isolation** | IMPOSSIBLE | YES (separate processes) | YES (separate sessions) |
| **Exclude Sibling History** | NO | YES | YES |
| **Custom Context Assembly** | Additive only | System prompt injection | Full control |
| **Agent-Initiated Frames** | Advisory (Skills) | Detection patterns | Native (signals/hooks) |
| **Implementation Complexity** | Medium | High | Medium-High |
| **Process Overhead** | Low | High (many processes) | Low (single process) |
| **State Management** | MCP Server | External file | Built-in/file |
| **Error Recovery** | Hooks | Manual restart | Session resume |
| **Debugging** | Limited visibility | Separate logs | Full message stream |

### 10.2 Architectural Differences

```
Proposal 01: Inside Claude Code
================================
[Claude Code] --> [Hooks/MCP] --> [Frame State]
     |
     v
[Linear History] <-- Cannot exclude!

Proposal 02: Composing CLI Instances
=====================================
[Orchestrator] --> [claude -p] --> [Session A]
     |         --> [claude -p] --> [Session B]
     |         --> [claude -p] --> [Session C]
     |
     v
[State File] -- Manages multiple processes

Proposal 03: Agents SDK
========================
[Orchestrator] --> [query()] --> [Session A]
     |                       --> [Session B]
     |                       --> [Session C]
     |
     v
[Single Process] -- Full programmatic control
```

### 10.3 Key Advantages of Agents SDK Approach

1. **Single Process**: No process spawning overhead or coordination complexity
2. **Native Streaming**: Full visibility into all messages as they stream
3. **Programmatic Hooks**: In-process callbacks, not shell scripts
4. **Session Management**: Built-in resume/fork with session IDs
5. **Type Safety**: TypeScript types for all message and configuration types
6. **Error Handling**: Try/catch, no process exit codes to parse
7. **Testability**: Easy to unit test with mocked SDK

### 10.4 Disadvantages vs Other Approaches

1. **Ground-up Implementation**: Must build entire flame graph system
2. **No Existing UI**: Claude Code's interactive TUI not available
3. **Learning Curve**: SDK API to learn (though well-documented)
4. **Dependency**: Tied to SDK version updates

---

## 11. Effort Estimate and Complexity Analysis

### 11.1 Development Phases

| Phase | Effort | Description |
|-------|--------|-------------|
| **Phase 1: Core Framework** | 2-3 days | Frame state, context assembly, basic push/pop |
| **Phase 2: Compaction** | 1-2 days | LLM-based summarization, artifact extraction |
| **Phase 3: Hooks Integration** | 1-2 days | Tool logging, subagent tracking, completion detection |
| **Phase 4: CLI Interface** | 1 day | Interactive commands, status display |
| **Phase 5: Polish** | 2-3 days | Error handling, session recovery, testing |

**Total Estimated Effort: 7-11 days**

### 11.2 Complexity Factors

| Factor | Complexity | Mitigation |
|--------|------------|------------|
| State Management | Medium | Use JSON file, simple schema |
| Context Assembly | Low | String concatenation |
| Session Coordination | Medium | SDK handles most complexity |
| Signal Detection | Medium | Clear patterns in output |
| Compaction Quality | High | Iterate on prompts |
| Error Recovery | Medium | Session resume helps |
| Concurrent Frames | High | Start sequential, add later |

### 11.3 Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| SDK API changes | Medium | Medium | Pin version, test on updates |
| Signal detection failures | Medium | Medium | Clear patterns, fallbacks |
| Compaction quality issues | Medium | Low | Human override option |
| Context window overflow | Low | High | Automatic compaction trigger |
| Session resume failures | Low | Medium | State recovery from logs |

---

## 12. Recommendations

### 12.1 Verdict: FULLY FEASIBLE

The Agents SDK approach is the **most capable and complete solution** for flame graph context management:

1. **True Context Isolation**: Achieved through separate sessions per frame
2. **Custom Context Construction**: Full control via system prompts
3. **Frame Lifecycle Management**: Native session resume/fork support
4. **Observability**: Full message streaming and hook system
5. **Production Ready**: Single process, no orchestration overhead

### 12.2 Recommended Implementation Strategy

#### Start Small
1. Build frame state manager with JSON persistence
2. Implement context assembly (ancestors + siblings)
3. Add basic push/pop with FRAME_COMPLETE detection
4. Test with simple multi-frame scenarios

#### Then Iterate
5. Add compaction generation with LLM
6. Implement planned frames
7. Add human control interface (/push, /pop, /status)
8. Add hooks for logging and artifact tracking

#### Finally Polish
9. Session recovery from interrupted runs
10. Concurrent frame execution (if needed)
11. IDE integration or web UI

### 12.3 Quick Start

```typescript
// Minimal flame graph implementation
import { query } from '@anthropic-ai/claude-agent-sdk';

const frames = new Map();
let currentFrame = 'root';

async function executeWithFlameContext(goal: string) {
  const context = buildContext(currentFrame, frames);

  for await (const msg of query({
    prompt: goal,
    options: { systemPrompt: context }
  })) {
    if (msg.type === 'assistant') {
      const text = extractText(msg);

      if (text.includes('PUSH_FRAME:')) {
        const childGoal = extractAfter(text, 'PUSH_FRAME:');
        const childId = createFrame(childGoal, currentFrame);
        currentFrame = childId;
        await executeWithFlameContext(childGoal);  // Recurse
        // Returns here when child completes
      }

      if (text.includes('FRAME_COMPLETE:')) {
        const summary = extractAfter(text, 'FRAME_COMPLETE:');
        completeFrame(currentFrame, summary);
        currentFrame = frames.get(currentFrame).parent;
        return;  // Pop back to parent
      }
    }
  }
}
```

### 12.4 Comparison Summary

| Approach | Feasibility | Effort | Context Isolation | Recommendation |
|----------|-------------|--------|-------------------|----------------|
| Proposal 01 | Partial | Low | NO | Use for PoC only |
| Proposal 02 | Full | High | YES | Viable but complex |
| **Proposal 03** | **Full** | **Medium** | **YES** | **RECOMMENDED** |

**The Agents SDK is the clear winner for a production-grade flame graph implementation.**

---

## Appendix A: SDK Message Types Reference

```typescript
// Key message types for flame graph implementation

// Session initialization - capture session ID
SDKSystemMessage {
  type: 'system';
  subtype: 'init';
  session_id: string;
}

// Assistant messages - check for frame signals
SDKAssistantMessage {
  type: 'assistant';
  message: {
    content: Array<{ type: 'text', text: string } | { type: 'tool_use', ... }>;
  };
  parent_tool_use_id: string | null;  // Set for subagent messages
}

// Completion - extract final result
SDKResultMessage {
  type: 'result';
  subtype: 'success' | 'error_*';
  result?: string;
}

// Compaction boundary - triggered on /compact or auto
SDKCompactBoundaryMessage {
  type: 'system';
  subtype: 'compact_boundary';
  compact_metadata: {
    trigger: 'manual' | 'auto';
    pre_tokens: number;
  };
}
```

## Appendix B: Hook Types for Frame Tracking

```typescript
// Hooks configuration for frame lifecycle tracking
const flameHooks = {
  // Tool usage logging
  PostToolUse: [{
    matcher: 'Write|Edit',
    hooks: [async (input) => {
      // Track artifacts created
      const filePath = (input as PostToolUseHookInput).tool_input.file_path;
      addArtifactToFrame(currentFrame, filePath);
      return {};
    }]
  }],

  // Subagent = child frame
  SubagentStart: [{
    hooks: [async (input) => {
      const { agent_id, agent_type } = input as SubagentStartHookInput;
      console.log(`[SUBAGENT] Child frame starting: ${agent_id}`);
      return {};
    }]
  }],

  SubagentStop: [{
    hooks: [async (input) => {
      console.log('[SUBAGENT] Child frame completed');
      // Could extract compaction here
      return {};
    }]
  }],

  // Context injection on each prompt
  UserPromptSubmit: [{
    hooks: [async (input) => ({
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: getFrameContext(currentFrame)
      }
    })]
  }],

  // Frame-aware compaction
  PreCompact: [{
    hooks: [async (input) => ({
      systemMessage: `Preserve frame context when compacting. Current frame: ${currentFrame.goal}`
    })]
  }]
};
```

## Appendix C: Example Frame Tree Display

```
=== Flame Graph Tree ===
[in_progress] Build REST API with authentication
  [completed] Implement JWT authentication
    Summary: Implemented JWT auth with User model, bcrypt hashing, token middleware
  [in_progress] Build API routes <-- CURRENT
    [completed] Implement CRUD endpoints
      Summary: Created REST endpoints for users, products, orders with validation
    [planned] Add pagination support
  [planned] Add caching layer
========================
```

---

**End of Proposal**
