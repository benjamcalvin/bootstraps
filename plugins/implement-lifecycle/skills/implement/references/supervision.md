# Supervising children

A hung test or a child that ends its turn with a process still running costs far more wall clock than a check-in. Waiting blind and tight polling are both wrong: supervise with sparse, cheap check-ins that adapt to what you observe.

**Expectations come from observation, not fixed numbers.** Inference speed varies by provider and time of day, and suites vary by repository. Judge a child against this run's own evidence: how long comparable children (same role, same repository) took, how long the command it is running took earlier in the run, and whether it is still producing activity. Before you have observations, start with a modest interval (minutes, not seconds). Lengthen it while children keep making progress; shorten it once something looks slow.

**A check-in is one cheap look.** Use the adapter's wait-with-timeout or timer so that either a child finishing or the interval elapsing wakes you. Look only at the child's last-activity time and the elapsed time of processes it started in its worktree. Do not read code, tail whole logs, or run bursts of monitoring commands. If the child is still active, wait again.

**A child is stalled** when it has run clearly longer than comparable observations and shows no new activity since your last check-in. Escalate one step at a time:

1. Ask the child for a one-line status through a continuation.
2. If a process it started is hung (no output, well past its earlier duration), stop only that process and tell the child to continue, bounding or investigating the command.
3. If the child is unresponsive or lost, spawn a fresh child for the same role with the current PR state.
4. If the fresh child stalls the same way, stop and escalate with the evidence.

Record each intervention (time, child, action, outcome) for the run ledger's stalls line.
