──────────────────────────────────────────────────────────────────────────────────────────
Interviewer:
──────────────────────────────────────────────────────────────────────────────────────────

Interview: Flame Graph Context Management

Question 1: Stack Frame Lifecycle

When a task is "popped off the stack," what happens to its context?

- A: Full summary (compressed into structured outcome)
- B: Selective preservation (artifacts + decisions, not exploration steps)
- C: Result-only (deliverable + pointers)
- D: Something else?

Question 2: What Triggers a New Stack Frame?

When should the agent "push" a new frame?

- User-initiated (explicit "subtask: do X")?
- Agent-initiated (complexity heuristics)?
- Context length approaching limits?
- Some combination?

Question 3: Cross-Talk Between Stacks

You mentioned cross-talk is desirable. Concrete example: if Stack A is building auth and Stack B is building API routes, what information flows between them, and when?

Question 4: The "Base Stack" Concept

You mentioned "compaction of results into the base stack before working up the next stack."

- Is there always a single base stack that accumulates knowledge?
- Or more like a tree where siblings don't know about each other until merging at a common parent?

---

Please answer whichever feel most important to clarify first. Your answers will help us define the Key Theoretical Goal before evaluating implementation approaches.

──────────────────────────────────────────────────────────────────────────────────────────
CEO:
──────────────────────────────────────────────────────────────────────────────────────────

> Question 1: Stack Frame Lifecycle

When a task is "popped off the stack," what happens to its context?

- there should presumably be an ongoing log of every branch across every stack, so we
  won't "lose context"
- but there should be a compaction step which introduces the now-complete (or
  dangling, whatever the outcome) branch back into the context of whatever layer of the
  tree we're about to pick up again from. this helps preserve context of what happened
  in the other branch.
- presumably, there should be some real clear notation for this, such that the agent
  can keep track of the other branch and not be "distracted" by it. Presumably this
  compaction should also point to the log file of the branch that was complete, just in
  case the agent wants to browse it again.

Question 2: What Triggers a New Stack Frame?

When should the agent "push" a new frame?

- I have many thoughts on this. Presumably, sometimes we'll want to project some sort
  of schedule "ie non-linear TODO list" into the future. This is akin to the current
  TODO list, which is already a structure in Claude Code. However, it should allow the
  agent or the human to sketch out a planned path
- notably, this planned path may change at any point, as discoveries may be made along
  the way that cause new frames to be pushed onto the present stack or another planned
  stack.
- the key question becomes: how granular is a frame? We don't want it trivially
  granular (ie per message) as then a substantial component of the attention will be
  eaten by managing frames. On the other hand, if it's too broad it won't be useful.
  This in part will come down to a judgement call, and so I'd be curious if you have any
  ideas for heuristics we could apply to help the agent/human decide the right size
  task for a frame.

Question 3: Cross-Talk Between Stacks

You mentioned cross-talk is desirable. Concrete example: if Stack A is building auth
and Stack B is building API routes, what information flows between them, and when?

The most obvious path here is something I already mentioned: once we've completed the
task for Stack A and are stepping down back out of it to the base where Stack B
branches from, we should run a compaction step which captures the meaningful/relevant
results of what happened in Stack A and attach them into the context before stepping
into Stack B.

There may be other ways of adding cross-talk, though let's start with that one.

Needless to say, this is sort of recursive, as their may be a Stack C that derives
from a deeper shared frame and that frame will eventually receive the compaction of
both Stack A and Stack B results, a sort of summary of summaries.

I use the word "summary" there but we should be careful, it should include key
details.

Question 4: The "Base Stack" Concept

You mentioned "compaction of results into the base stack before working up the next
stack."

- Is there always a single base stack that accumulates knowledge?
- Or more like a tree where siblings don't know about each other until merging at a
  common parent?

Hopefully my above answers have made this clear. This whole concept is a tree, a
general call stack. All of what we're saying applies at any level. When I used the
word "base" in the above tweet, it was probably a mistake. I just meant "parent" (ie
the shared base of any two branches, not the "root" base).

---

These are good questions, though not exhaustive. I'm sure my answers will leave more
questions. Perhaps ask more clarifying questions to continue to wrap your arms around what I'm
after. Hopefully this process leaves us with a shared mental model of what I'm trying
to do here.

──────────────────────────────────────────────────────────────────────────────────────────
Interviewer:
──────────────────────────────────────────────────────────────────────────────────────────

Synthesized Mental Model

                      [Root Frame: "Build App"]
                             |
           +-----------------+-----------------+
           |                                   |
     [Frame A: Auth]                    [Frame B: API Routes]
     (completed)                        (pending)
           |                                   |
      +----+----+                        +-----+-----+
      |         |                        |           |

[A1] [A2] [B1] [B2]
(done) (done) (planned) (planned)

Key Mechanics:

1. Full Logs Persist: Every frame's history saved to disk - nothing truly lost
2. Compaction for Context: When Frame A completes, compaction injected into Root before Frame B begins
3. Recursive Summaries: B2's context includes: compaction of A (from root) + compaction of B1 (from B)
4. Planned vs Executed: Non-linear TODO sketches future frames, mutable as discoveries occur

---

Follow-Up Questions: Round 2

Q5: Frame Granularity Heuristics (you asked for ideas)

- A: "Summarizable Unit" - Can you summarize in 2-3 sentences without losing critical info?
- B: "Context Switch" - Push when work requires different files/concepts/goals
- C: "Failure Boundary" - Frame = something that could fail and be retried as a unit
- D: Token Budget Proxy - Target ~X tokens before considering subdivision

Which resonates? Agent-decided, human-decided, or negotiated?

Q6: Compaction Format

- A: Structured metadata block (status, artifacts, decisions, log pointer)
- B: Prose summary with key details
- C: Hybrid (both)

Agent-generated or templated?

Q7: Non-Linear TODO / Planned Path

- Separate planning doc, or same tree with planned/pending frames?
- Can planned frames have planned children? (sketch B→B1,B2,B3 before starting B)
- When a planned frame is invalidated, what happens to its planned children?

Q8: Dangling/Failed Frames

How to handle:

- Incomplete (user says "stop, switch")
- Failed (couldn't complete)
- Blocked (waiting on external input)

Compacted differently? Stay "open"?

Q9: Control Authority

- Human only (explicit /push, /pop)
- Agent proposes, human approves
- Agent autonomous with guardrails
- Negotiated per-session

──────────────────────────────────────────────────────────────────────────────────────────
CEO:
──────────────────────────────────────────────────────────────────────────────────────────

>  Q5: Frame Granularity Heuristics (you asked for ideas)

Of the ones you listed, the one the "Failure Boundary" and "Context Switch" are the
two that come closest. I think we should mostly leave it up the agent as a judgement
call (unless of course the user explicitly specifies) but we should give them these
heuristics as a starting point.

Q6: Compaction Format

I think it needs to be a prose summary with key details, but the overall stack/frame
structure should be presented as XML, because this is the best way to outline
nested/tree structure.

In other words, somewhere in the current context of the call to the agent when we're
working through, say Frame B, should be an XML of the direct parents of (and probably
uncles/cousins, but not much deeper than that of the other layers to add context).
These of course are all compactions and not the full work logs.

All of this will of course have to be agent-generated.

Q7: Non-Linear TODO / Planned Path

    - Separate planning doc, or same tree with planned/pending frames?

I don't know how TODO lists work in Claude Code we should investigate how those are
stored.

    - Can planned frames have planned children? (sketch B→B1,B2,B3 before starting B)

Yes, definitely.

    - When a planned frame is invalidated, what happens to its planned children?

We should not proceed down the children and they should all be invalidated/compacted
into whatever the invalidated frame is being compacted into.

Q8: Dangling/Failed Frames

    How to handle:
    - Incomplete (user says "stop, switch")
    - Failed (couldn't complete)
    - Blocked (waiting on external input)

Yes those are all good recommendations, but this is getting into details we can cover
later now.

Q9: Control Authority

Human should be able to control with slash commands (or whatever is sensible) and the
Agent should be able to control on its own accord too. I think this has to be a
"Controller Agent" or a "Meta Agent" because the agent doing the work may not have
this ability, TBD.
──────────────────────────────────────────────────────────────────────────────────────────
