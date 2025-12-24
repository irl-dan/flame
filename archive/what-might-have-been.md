# What Might Have Been

I spent two days trying to build something that turned out to be impossible. Not impossible in the sense of "we don't have the technology yet" — impossible in the sense of "the architecture actively prevents this."

The idea was simple enough. Anyone who's spent time working with AI coding assistants knows the problem: context windows fill up. When they fill up, the system compacts your conversation history into a summary, and you lose detail. The AI forgets the nuances of what you tried, what failed, why you made certain decisions. Worse, when you're working on Task B, you're still carrying around all the exploration and debugging from Task A, even though none of that matters anymore.

What if, instead of treating conversation history as a flat list of messages, we treated it like a call stack? Push a frame when you start a subtask. Pop it when you're done. When you pop, generate a summary — what was accomplished, what files were touched, what decisions were made. Store the full log to disk (nothing truly lost), but only keep the summary in active context.

This is how programmers think about work anyway. You don't hold the entire codebase in your head when you're debugging a specific function. You zoom in, fix the thing, zoom out. Flame graphs visualize this beautifully — nested rectangles showing where time is spent, parent-child relationships clear at a glance.

So I tried to build this for Claude Code.

---

## What I found in ~/.claude

Before getting into what doesn't work, I should explain what does. Because Claude Code actually does something clever with subagents that I hadn't fully appreciated until I went digging through the actual files on disk.

When Claude spawns a subagent — one of those Task tool invocations you see when it delegates work — that subagent gets its own transcript file. Not a section of the main transcript. Its own file.

```
~/.claude/projects/-Users-sl-code-flame/
├── df78735e-ac15-48b0-aa59-45ebd9f19ada.jsonl   # Main session: 6.3MB
├── agent-aca56da.jsonl                           # Subagent: 320KB
├── agent-a14843c.jsonl                           # Another subagent
└── ...
```

When I cracked open one of these agent files, the first thing I noticed was `isSidechain: true`. The subagent knows it's a sidechain. It has its own `agentId`. It references the parent's `sessionId` but maintains its own message history.

And here's the part that matters: when the subagent finishes, what goes back to the parent isn't the full transcript. It's a `tool_result` containing whatever the subagent decided to return — typically a summary. The parent session recorded this:

```json
{
  "type": "tool_result",
  "toolUseResult": {
    "prompt": "Original prompt to subagent",
    "agentId": "aca56da",
    "totalTokens": 65414,
    "totalToolUseCount": 12,
    "content": [{"type": "text", "text": "Summary of what agent did..."}]
  }
}
```

65,000 tokens of work, compressed down to a summary. The full history exists in the agent's file if you ever need to look at it, but the parent context only gets the digest.

This is, in miniature, exactly what I wanted for flame graph context management. A frame (the subagent) with isolated context, doing focused work, returning a compacted summary to its parent.

So why can't we just... do that?

---

## The depth problem

Subagents can't spawn subagents. The documentation says this explicitly: "This prevents infinite nesting of agents."

Which means the frame tree is limited to one level. Root plus children. No grandchildren.

```
Root -> [Child1, Child2, Child3]     // This works

Root -> Child -> Grandchild          // This doesn't
```

For many tasks, one level is enough. You could structure work as: main session orchestrates, subagents do focused work, summaries come back. But the moment you need recursive decomposition — and complex tasks often do — you hit a wall.

The workaround in the proposal I was analyzing suggested "virtual frames" inside subagents, where the subagent would log markers like `=== VIRTUAL FRAME START ===` and pretend to have nested context. But that's just bookkeeping theater. The context isn't actually isolated. The subagent's window still fills up the same way.

---

## The bigger problem: you can only add, never subtract

Here's where the architecture really bites.

Claude Code constructs context by concatenating things together:

```
System Prompt + CLAUDE.md + Linear Message History + Tool Results
```

Extensions — hooks, plugins, MCP servers — can inject additional context. The `SessionStart` hook can add an `additionalContext` string. The `UserPromptSubmit` hook can prepend information to each user message. The `PreCompact` hook fires before compaction and can inject instructions about what to prioritize.

What extensions cannot do: remove anything from the message history. Restructure how context is assembled. Replace linear concatenation with tree-based assembly.

The hook documentation is clear on this. Looking at the `SessionStart` output format:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Your injected context here"
  }
}
```

That's additive. You're putting more stuff in, not taking stuff out.

So even if I built an elaborate frame management system — even if I tracked a perfect tree of frames with compactions and parent-child relationships in an MCP server — I could inject that tree into context as a big XML blob or whatever, and Claude would see it, but Claude would *also* still see the entire linear history of every sibling frame's detailed work.

The spec I was trying to implement says: when working in Frame B1, context should include:
- B1's own working history
- Compaction of parent B
- Compaction of grandparent Root
- Compaction of uncle A (sibling branch)
- **NOT** the full linear history of A1, A2

That "NOT" is the killer. There's no API for "NOT."

---

## What the transcripts actually show

I spent time looking at recent sessions to verify this. The main session transcript in `df78735e...jsonl` is 6.3MB. It contains the full conversation history including every tool call, every result, every message.

When a subagent ran (agent-aca56da), yes, its work happened in isolation. Its transcript is separate. But the parent session's transcript still grew because it recorded:
- The tool call that spawned the subagent (with the full prompt)
- The tool result that came back (with the summary)

And if you spawn ten subagents? You get ten summaries in the parent's linear history. Better than ten full transcripts, sure. But still linear. Still accumulating.

The compaction system doesn't know about frames. When context pressure forces a compaction, it summarizes the whole linear history, not "keep current frame, compact siblings." You can inject instructions via the `PreCompact` hook telling it to prioritize certain things, but that's advisory. The model tries to follow your instructions; it doesn't always succeed.

---

## The shape of the missing piece

What would need to exist for this to work?

A context assembly hook. Something that fires before the final context is sent to the model, receiving the raw materials — system prompt, CLAUDE.md contents, message history, tool results — and returning a modified version.

Not `additionalContext`. Full replacement capability. The ability to say: here's what I want you to send instead.

```javascript
// Hypothetical API that doesn't exist
hooks.onContextAssembly((materials) => {
  const { systemPrompt, claudeMd, messages, toolResults } = materials;

  // Filter messages to only include current frame
  const frameMessages = messages.filter(m => m.frameId === currentFrameId);

  // Build context from frame tree instead
  const frameContext = buildFrameContext(currentFrameId);

  return {
    systemPrompt,
    claudeMd,
    messages: frameMessages,
    additionalContext: frameContext
  };
});
```

This doesn't exist. Extensions live downstream of context construction, not inside it.

---

## Why this probably won't get built

I don't say this to be cynical. I say it because the current architecture isn't an accident.

Linear history is simple. It's predictable. Every message goes in, gets stored, feeds forward. You can reason about what the model has seen because it's just... everything, in order.

The moment you add filtering — the moment context depends on some external frame state that might be corrupted, might have bugs, might do something unexpected — you introduce a class of problems that's hard to debug. "Why did Claude forget about X?" becomes a question with non-obvious answers.

There's also the problem of trust. If extensions could modify context arbitrarily, a malicious plugin could remove safety-relevant messages, hide previous instructions, gaslight the model about what the user said. The additive-only design is conservative for reasons.

And honestly? For most use cases, subagents-as-frames works well enough. One level of depth handles a lot of scenarios. The people who need deeper decomposition can build external orchestrators — spawn separate Claude sessions entirely, manage the tree outside Claude Code, inject summaries manually.

That's what the proposal ultimately concluded. Build the plugin anyway, use it for one-level frames, accept the limitation. Or go external.

---

## What we lost

The thing I keep coming back to is how close the existing machinery gets.

Subagents have isolated context. That's real isolation, verified in the transcript files.

Subagents can be resumed. The `agentId` persists, the transcript persists, you can pick up where you left off.

Subagent completion has a natural hook point. `SubagentStop` fires, you can process the output, you could run compaction logic.

MCP servers can maintain state. You could absolutely build a frame tree manager that tracks everything.

Slash commands work. `/push`, `/pop`, `/status` could control the system.

All the pieces are there except the one that matters: the ability to make linear history not linear.

It's like having every component of a car except the engine. The wheels turn freely. The steering works. The seats are comfortable. But you're not going anywhere.

---

## Coda

I wrote this partly to explain why the approach failed, but also because I think the underlying idea is sound. The linear history model has real costs. Anyone who's hit a compaction boundary in the middle of complex work knows the feeling — watching the model lose track of something you'd carefully established, having to re-explain context that was clear five minutes ago.

Tree-structured context isn't just a nice-to-have. It's how human cognition actually works. We don't hold everything in working memory; we hold what's relevant to the current task plus compressed summaries of related context. We push and pop focus all the time, naturally, without thinking about it.

The current generation of AI assistants forces us to work against that grain. Everything is flat. Everything accumulates. The only release valve is lossy compaction of the whole history at once.

Maybe that's fine for now. Maybe the context windows will keep growing and we'll hit some point where it doesn't matter. Maybe the compaction algorithms will get smart enough to effectively learn frame boundaries on their own.

Or maybe someone will add a context assembly hook and this whole thing becomes buildable in an afternoon.

I'd bet on the latter. The demand is there. The design is understood. It's just a matter of whether the Claude Code team decides it's worth the complexity.

Until then, I've got a directory full of transcripts showing what might have been.
