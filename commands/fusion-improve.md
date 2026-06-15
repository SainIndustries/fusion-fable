---
description: Self-improving loop — autonomously work the Fusion improvement roadmap, gated by a deterministic driver
argument-hint: (no args — drives improve/roadmap.json)
---
Drive the Fusion self-improvement backlog (`improve/roadmap.json`, seeded from `docs/fusion-self-review.md`)
to completion, autonomously and SAFELY. The driver `improve/run_iteration.sh` owns all state and guardrails;
you propose how to implement each item. Run from the repo root.

This is meant to be run under `/loop` (self-paced). One roadmap item per iteration, atomic commit or full
revert. STOP the moment the driver prints a `HALT=` line.

First iteration only: run `bash improve/run_iteration.sh init`. If it errors (baseline red), stop and report.

Each iteration, in order:
1. `bash improve/run_iteration.sh next`. If output starts with `HALT=`, announce that exact reason, summarize
   what landed (`git log`) and what is awaiting-human (`improve/proposals/`), and STOP THE LOOP. Otherwise
   grep `NEXTID RISK TRIVIAL DESIGN ACTION FILES ACCEPTANCE BUDGET`.
2. If `ACTION=gate`: write the concrete plan into `improve/proposals/<NEXTID>.md`, run
   `bash improve/run_iteration.sh gate <NEXTID>`, and go to step 1. Never edit code for a gated item.
3. If `DESIGN=needed`: design the fix with Fusion — invoke the `fusion` skill (prefer `/fusion-opus4.8`
   while codex hermeticity item `F0-codex-hermetic` is unresolved, since codex stages can be contaminated)
   on the item's title + the relevant slice of `docs/fusion-self-review.md` + the current `FILES`. Save the
   synthesis to `improve/designs/<NEXTID>.md`, then run `bash improve/run_iteration.sh fused <NEXTID>`. Act
   on the SYNTHESIS, not any single panelist. If `DESIGN=skip`, implement directly.
4. Implement the SMALLEST change satisfying the item's `ACCEPTANCE` checks; touch only `FILES` (+ new files
   the item needs). Add/extend a test under `tests/` when the item is testable.
5. `bash improve/run_iteration.sh commit <NEXTID>`. On `RESULT=committed`, move on. On `RESULT=reverted` or
   `RESULT=noop`, read the printed check log but do NOT retry the same item this iteration — the driver
   already bumped attempts; go to step 1.
6. If you cannot implement an item cleanly, run `bash improve/run_iteration.sh abort <NEXTID> "<reason>"`.

Hard rules: never commit with a red `check.sh`; never bypass a closed gate; one item per commit; never edit
`improve/state.json` or `improve/roadmap.json` by hand (only the driver mutates them); never weaken
`improve/check.sh` to make something pass. Respect the `BUDGET` line — the driver HALTs when caps are hit.
Create `improve/STOP` to force a clean stop. Obey a `HALT=` from the driver immediately.
