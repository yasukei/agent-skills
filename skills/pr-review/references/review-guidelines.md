# Review criteria and how to set priorities

## Stance

- The goal is to find what would cause problems after the merge, not to nitpick.
- There is no target number of findings. If there is no problem, "no findings" is fine.
- When not sure, ask a Question instead of asserting, because you may have misunderstood an assumption.
- The repository's conventions (`CLAUDE.md`, `CONTRIBUTING.md`, etc.) take precedence over general practice.
- Do not point out what linters, formatters or type checkers catch.

## What to look at

Roughly in descending order of importance. The priority, however, comes from the impact, not from the category (see below).

### Correctness
- Does it work as the spec and the PR description say?
- Boundary values, empty input, null, large input, error paths
- Concurrency, race conditions, transaction scope
- Does it break existing callers or invariants? (Look beyond the diff too.)

### Security
- Input validation, injection (SQL, command, path)
- Missing authentication or authorization
- Hard-coded or logged secrets (tokens, passwords, keys)
- New dependencies and whether they are justified

### Error handling
- Swallowed exceptions, ignored errors
- State on failure (partial writes, leaked resources)
- Can users and operators trace the cause?

### Data and compatibility
- Safety of DB migrations (rollback, existing data, lock duration)
- Backward compatibility of APIs, configuration and file formats
- Are breaking changes stated in the PR description?

### Tests
- Are the main cases and the important edge cases of the change tested?
- Do the tests depend too much on implementation details, or are they flaky?

### Performance
- Obvious complexity problems, N+1 queries, needless I/O in loops
- Does it work with data at a scale that actually matters? (Do not raise findings that assume an unrealistic scale.)

### Maintainability and readability
- Is the intent readable? Duplication, separation of responsibilities
- Consistency with the existing code base

### PR description
- Does the description match the implementation? (With a squash merge it becomes the commit message.)

## Setting the priority

Decide by **what happens if it is left as is**, not by the category.

| Priority | Rule of thumb | Examples |
|---|---|---|
| P0 (Critical) | Merging causes serious harm right away | Missing authorization check, a bug that deletes data, the build fails, a committed secret |
| P1 (High) | Misbehaves under realistic conditions, or does not meet the spec | An exception on certain input, a wrong boundary, no tests for the main path |
| P2 (Medium) | Works now, but likely to cause trouble with future changes or in operation | Duplicated logic, insufficient error messages, obvious inefficiency |
| P3 (Low) | Nice to improve, no harm if not | Naming, a small refactoring, adding a comment |
| Question | Not enough information to judge | "Is this branch intended?" |

When unsure, pick the lower one. A priority set too high wastes the author's time and dilutes the weight of the findings that really matter.

## Writing a finding

- One finding, one problem.
- Write what, why (under which conditions what happens), and how to fix it.
- When guessing, say that it is a guess.
- Write it as a suggestion, not a command.
