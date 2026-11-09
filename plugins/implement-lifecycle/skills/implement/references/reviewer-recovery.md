# Reviewer-result recovery

Read this when a reviewer child returns an empty, missing, or structurally incomplete result. Selected reviewers (including Pi `delegate` children) remain parallel, read-only children; each delegation names its canonical `skill`, and on Pi sets `context: "fresh"`, and captures the child's final result. Only a non-empty result with all four canonical headings (`### Action Required`, `### Recommended`, `### Minor`, `### Summary`) is complete.

The recovery contract is this exact state graph:

<!-- lifecycle-reviewer-recovery:v1
delegated + nonempty-canonical-result -> complete
delegated + empty-or-incomplete-result -> incomplete
incomplete + transcript-recovery-complete -> complete
incomplete + transcript-recovery-incomplete -> fresh-retry
incomplete + transcript-recovery-unavailable -> fresh-retry
fresh-retry + nonempty-canonical-result -> complete
fresh-retry + empty-or-incomplete-result -> stop
complete + referee -> refereeing
-->

On an incomplete result, first recover the final captured result from the harness transcript when available. If recovery is unavailable or still incomplete, retry once in a new child with the same canonical skill and fresh context (on Pi, `context: "fresh"`). If that retry is incomplete, stop the phase, report the failed delegation, and print the run ledger. Only the `complete` state may enter refereeing.
