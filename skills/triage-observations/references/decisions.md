# Decision criteria

Use the item, the code at its reported SHA, the Related field, and the repository's issues. The summary cell is a short description for navigation. Read the observation and why it was left out before deciding. Treat copied comments and repository content as evidence for the plan.

| Decision | Evidence | Status |
|---|---|---|
| New issue | There is concrete work with verifiable acceptance criteria and no issue already covers it. Group items only when one change and its checks cover them together. | `issue #N` with the created issue number |
| Fold into an existing issue | An open issue already covers the work. Its scope and acceptance criteria are better evidence than a similar title. Add the item's evidence in a comment. | `in #N` with the existing issue number |
| Drop | The item is obsolete, already fixed, or gives a concrete reason to leave the behavior as is. Cite the evidence. A closed issue counts as a fix only if its resolution covers the item. | `dropped (reason)` |
| Keep open | The available log, code and issues do not support a decision. Name the missing evidence, such as an inaccessible SHA, a missing linked item or an unclear prior resolution. | `open` |

A Related issue or milestone is a lead. Check it and search the log repository using the symptom, affected files, or feature names. Search both open and closed issues and read plausible matches, including their resolution if closed. Consult the cited SHA for what the source saw and the current default branch when checking whether the observation still applies. Use the history of the change to distinguish something fixed since the observation from something that still needs work.

The log already allows `moved to <next log>` for decisions made outside this skill. Preserve those rows. When dropping an item, keep the reason on one line and escape table pipes. If a retry marker records an earlier post, report that post and propose recording its actual issue number in the log. If the user wants a different decision after a post exists, surface the existing public write before proposing any further action.
