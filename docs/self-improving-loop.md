# The self-improving loop

A goal-driven loop that works the Fusion improvement roadmap (`improve/roadmap.json`, seeded from
[fusion-self-review.md](fusion-self-review.md)) autonomously: each iteration picks the next item, designs
the fix with Fusion when non-trivial, implements it, runs the regression gate, and commits atomically or
reverts — until a stop condition fires.

This design was produced by running Fusion on Fusion (two Opus 4.8 panelists, Opus synthesis; the codex
stages were skipped this round per Finding #0). Both panelists independently converged on the same core
principle, which is the load-bearing idea:

**The deterministic driver owns state and safety; Claude only proposes how to implement.** A bash driver
(`improve/run_iteration.sh`) is the single source of truth for the roadmap, the budget, and every stop
condition. The model can write code, but it cannot mark its own broken work "done" or talk the loop past a
guardrail — every state transition goes through the driver, which gates on a real test before it commits.

## How to run it

```
/fusion-improve            # the wrapped /loop prompt (recommended)
```

or directly under `/loop` with the prompt in [commands/fusion-improve.md](../commands/fusion-improve.md).
The driver subcommands (the model calls these; you can too, to inspect):

```bash
bash improve/run_iteration.sh init     # capture a green baseline (refuses if the tree is already red)
bash improve/run_iteration.sh status   # backlog + budget
bash improve/run_iteration.sh next     # enforce stops, pick the next item, mark it in-progress
bash improve/run_iteration.sh commit <id>   # run check.sh; commit if green, else revert + attempts++
bash improve/run_iteration.sh gate  <id>    # write a human-approval proposal for a risky item
bash improve/run_iteration.sh abort <id> "reason"
```

## Files

`improve/roadmap.json` is the backlog (one object per item: `order`, `priority`, `risk`, `trivial`,
`design`, `requires_approval`, `status`, `attempts`, `depends_on`, `files`, `acceptance`). `improve/state.json`
holds the counters and budget. `improve/progress.md` is the append-only narrative. `improve/check.sh` is the
regression gate. `improve/designs/<id>.md` caches Fusion design syntheses; `improve/proposals/<id>.md` holds
human-approval requests. All are git-tracked, so the loop reconstructs itself after a context reset from
three files.

## The guardrails (and why each exists)

- **Cost is bounded by what bash can actually count.** Claude Code can't read its own dollar spend from a
  shell, so the hard caps are `max_iterations`, `max_fusions` (each Fusion run is the ~N× cost multiplier),
  and a wall-clock `deadline_epoch`. `usd_*` fields are an honest derived *estimate*, logged, not a meter.
- **Test-before-commit + no-regression.** `commit` runs `check.sh` and only commits on green; `next` refuses
  to start unless the baseline is already green and the tree is clean. So the worst a wrong iteration can do
  is fail its gate and get reverted — the tree is always the last green commit.
- **Human-approval gate.** `risk:"high"` items (e.g. `F0-codex-hermetic`, which rewrites how codex is
  invoked, and `P3-install-backup`, which touches user files) are never auto-implemented — the driver routes
  them to `gate`, which writes a proposal and waits for a human to set `"approved": true`.
- **Anti-thrash / anti-infinite-loop.** Per-item `attempts` cap → `blocked` after repeated failure (removed
  from selection forever); a global `consecutive_no_progress` cap halts the whole loop; `next` sorts by
  `order` and only returns dependency-satisfied items, so it converges instead of oscillating; an
  `improve/STOP` sentinel file forces a clean stop.
- **Atomic everything.** State writes are `jq | mv -f`; each iteration is one commit or a full
  `git checkout`/`clean` revert (improve/ bookkeeping excluded), so no half-finished change survives.

## Using Fusion inside the loop

Items flagged `design:"fusion"` are designed by calling the Fusion skill first (synthesis cached to
`improve/designs/<id>.md`); trivial items are implemented directly to conserve the Fusion budget. Until the
codex-hermeticity item lands, the loop should use the pure-Opus pipeline (`/fusion-opus4.8`) for design
runs, since the codex stages can be contaminated by other local projects (Finding #0).

> Safety summary: the single most important property is that state transitions are script-owned with atomic
> writes and a clean-tree + green-baseline precondition. A confidently-wrong iteration costs one attempt and
> a revert, never a corrupted roadmap or a broken commit.
