# Reviewer-result recovery

Read this when a reviewer child returns an empty, missing, or structurally incomplete result. Selected reviewers (including Pi `delegate` children) remain parallel, read-only children; each delegation names its canonical `skill`, and on Pi sets `context: "fresh"`, and captures the child's final result. Only a non-empty result with all four canonical headings (`### Action Required`, `### Recommended`, `### Minor`, `### Summary`) is complete.

On an incomplete result, first check the harness transcript for the final captured result. When continuation is supported, message or resume that same reviewer child to emit the missing canonical four-heading output. If unsupported or still incomplete, retry once in a fresh child with the same canonical skill (on Pi, `context: "fresh"`). If that retry is incomplete, stop the phase, report the failed delegation, and print the run ledger. Only a complete result with all four headings may enter refereeing.
