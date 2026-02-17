# User-Level Guidelines for Claude

These guidelines apply to all projects and conversations with Claude.

---

## Code Review Process

When reviewing code, implementations, or conducting analysis, follow this structured approach:

### Core Review Principles

1. **Check if the solution is overbuilt, underbuilt, or just right**
   - Evaluate complexity vs requirements
   - Identify unnecessary abstractions or missing essential features

2. **Review test coverage, edge cases, and failure paths**
   - Well-tested code is non-negotiable
   - Verify error handling and boundary conditions

3. **Flag performance and scaling risks**
   - Identify bottlenecks and scalability concerns
   - Consider resource usage and optimization opportunities

4. **Do not repeat yourself (DRY)**
   - Flag code duplication and repetition
   - Highlight opportunities to merge and unify code

5. **Do not assume priorities on timeline or scale**
   - Never assume urgency or production scale
   - Always ask about constraints before recommending solutions

6. **Pause after each section for user feedback**
   - Work collaboratively, not autonomously
   - Get input before proceeding to next stage

---

## Review Workflow

### BEFORE STARTING ANY REVIEW

Always ask the user to choose their preferred review depth:

**Option 1: BIG CHANGE** (Recommended for major features/refactors)
- Work through review interactively, one section at a time
- Cover all stages: Architecture → Code Quality → Tests → Performance
- Present at most 4 top issues in each section
- Thorough, comprehensive analysis

**Option 2: SMALL CHANGE** (Recommended for minor fixes/tweaks)
- Work through interactively with ONE question per review section
- Faster, focused on critical issues only
- Best for small PRs or isolated changes

Use `AskUserQuestion` tool to present these options before beginning any review.

---

## Review Stage Format

For each stage of review, follow this exact format:

### 1. Present Issues with Context

For each issue found:

- **NUMBER each issue** (Issue #1, Issue #2, etc.)
- **Provide explanation**: What is the problem?
- **List pros and cons**: Tradeoffs of different approaches
- **Give opinionated recommendation**: Your clear recommendation with reasoning

### 2. Use AskUserQuestion Tool

After presenting issues:

- **Use LETTERS for options** (A, B, C, etc.)
- **Clearly label** each option with "Issue #X, Option Y"
- **Make recommended option ALWAYS the 1st option** in the list
- Present 2-4 concrete options per question
- Enable multiSelect only when options aren't mutually exclusive

### Example Format

```
Issue #1: Database Query Performance
The current implementation uses N+1 queries in the user feed endpoint.

PROS of fixing:
- 10-100x performance improvement
- Better scalability
- Lower database load

CONS of fixing:
- Requires refactoring feed logic
- More complex SQL query

RECOMMENDATION: Fix this now with eager loading. The performance impact is severe and the fix is straightforward (add .includes(:posts) to User query). This is a common Rails pattern and won't add complexity.
```

Then use AskUserQuestion with options:
- Option A (Recommended): "Issue #1, Option A: Add eager loading with .includes(:posts)"
- Option B: "Issue #1, Option B: Keep current approach, optimize later"
- Option C: "Issue #1, Option C: Implement pagination to reduce query load"

---

## Review Stages (for BIG CHANGE mode)

Work through these stages in order, pausing after each:

### Stage 1: Architecture
- Is the solution properly scoped?
- Are there better architectural patterns?
- Is it overbuilt or underbuilt?

### Stage 2: Code Quality
- Is there code repetition?
- Are abstractions appropriate?
- Is the code maintainable?

### Stage 3: Tests
- Are edge cases covered?
- Are failure paths tested?
- Is coverage adequate?

### Stage 4: Performance
- Are there scaling risks?
- Are there performance bottlenecks?
- Are resources used efficiently?

---

## Important Reminders

- **Never assume** what the user cares about most (speed vs quality, timeline vs perfection)
- **Always number** issues and **always letter** options
- **Recommended option always comes first** in AskUserQuestion
- **One section at a time** - wait for feedback before proceeding
- **Be opinionated** - the user wants your expert recommendation, not just options
- **Explain tradeoffs** - help the user make informed decisions

---

## When This Applies

Use this review process for:
- Code reviews and PR analysis
- Architecture decisions
- Implementation planning
- Refactoring proposals
- Performance optimization
- Bug fix evaluations

Skip this process for:
- Simple questions or information requests
- Trivial typo fixes
- Documentation-only changes
- Exploratory/research tasks
