# Phase 1.2: Context Assembly

**Status:** Complete
**Implementation Date:** 2025-12-24
**Prerequisites:** Phase 1.1 (State Manager) complete

---

## Goals

Phase 1.2 focuses on enhancing the context injection system to provide intelligent, context-aware frame information to the LLM. While Phase 1.1 implemented basic context injection, Phase 1.2 will add:

1. **Smart ancestor context selection** based on token budget
2. **Sibling context relevance filtering**
3. **Context caching** for performance optimization
4. **Token budget management** to prevent context overflow

## Acceptance Criteria

- [x] Context injection respects configurable token budget limits
- [x] Ancestor contexts are intelligently selected (most relevant ancestors prioritized)
- [x] Completed sibling compactions are filtered for relevance
- [x] Context generation is cached to avoid redundant computation
- [x] Deep frame trees do not cause context overflow errors
- [x] Context format remains compliant with SPEC.md XML schema

## Implementation

See [IMPLEMENTATION.md](./IMPLEMENTATION.md) for complete implementation details.

### Quick Test

```bash
./tests/test-context-assembly.sh
```

## What Needs to Be Built

### 1. Token Budget Manager

Implement a token budget system that:
- Estimates token count for context blocks
- Prioritizes which context to include when space is limited
- Falls back gracefully when budget is exceeded

```typescript
interface TokenBudget {
  total: number           // Total tokens available for frame context
  ancestors: number       // Budget for ancestor contexts
  siblings: number        // Budget for sibling contexts
  current: number         // Budget for current frame
}
```

### 2. Intelligent Ancestor Selection

Improve `getAncestors()` to:
- Prioritize immediate parent (always include)
- Include grandparents based on relevance/recency
- Truncate older ancestors when budget exceeded
- Consider ancestor completion status

### 3. Sibling Relevance Filtering

Enhance `getCompletedSiblings()` to:
- Score siblings by relevance to current frame's goal
- Filter out low-relevance siblings
- Prioritize recently completed siblings
- Consider artifact overlap with current frame

### 4. Context Caching

Add caching layer to avoid recomputing context on every LLM call:
- Cache generated XML context per session
- Invalidate cache on frame state changes
- Use TTL for staleness prevention

### 5. Enhanced XML Context Generation

Improve `generateFrameContext()` to:
- Include token usage metadata
- Add truncation indicators when content is trimmed
- Support hierarchical compaction (compact the compactions)

## Proposed Approach

### Phase 1.2.1: Token Budget Infrastructure

1. Add token estimation function (approximate based on character count)
2. Create configurable budget limits
3. Instrument current context generation with budget tracking

### Phase 1.2.2: Ancestor Selection

1. Implement ancestor scoring algorithm
2. Add budget-aware ancestor pruning
3. Test with deep frame trees (5+ levels)

### Phase 1.2.3: Sibling Filtering

1. Implement relevance scoring (keyword/goal overlap)
2. Add sibling limit configuration
3. Test with many-sibling scenarios (10+ siblings)

### Phase 1.2.4: Caching Layer

1. Add in-memory cache for context strings
2. Implement cache invalidation hooks
3. Measure performance improvement

## Test Plan

1. **Token Budget Tests**
   - Verify context stays within budget limits
   - Test graceful degradation with very small budgets
   - Verify priority order (current > parent > siblings > grandparents)

2. **Deep Tree Tests**
   - Create frame tree with 10+ levels
   - Verify context doesn't explode
   - Verify important ancestors are preserved

3. **Many Siblings Tests**
   - Create frame with 20+ completed siblings
   - Verify relevant siblings are selected
   - Verify irrelevant siblings are filtered

4. **Cache Tests**
   - Verify cache hits on sequential LLM calls
   - Verify cache invalidation on state changes
   - Measure latency improvement

## Dependencies

- Phase 1.1 State Manager (complete)
- Flame plugin at `.opencode/plugin/flame.ts`
- OpenCode `experimental.chat.messages.transform` hook

## References

- [SYNTHESIS.md](../design/SYNTHESIS.md) - Section 5.2 Phase 2
- [SPEC.md](/Users/sl/code/flame/SPEC.md) - Context format specification
- [Phase 1.1 IMPLEMENTATION.md](../1.1-state-manager/IMPLEMENTATION.md) - Current context injection

## Notes

The current Phase 1.1 implementation includes basic context injection that works for simple cases. Phase 1.2 addresses scalability concerns that will arise with:
- Long-running projects with many frames
- Deep decomposition hierarchies
- Extensive parallel work (many sibling frames)
