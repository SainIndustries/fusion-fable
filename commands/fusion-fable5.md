---
description: Fusion zero-setup — two independent Fable 5 runs, Fable judges + synthesizes (no codex)
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the pure-Fable pipeline. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5. The pipeline:
run the same prompt twice as TWO independent Claude Fable 5 panelists (headless
`claude --model claude-fable-5` CLI subprocesses via `scripts/run_claude.sh`, in parallel, neither seeing
the other's work) → **Fable 5 does the discernment** (per-panelist assessment, consensus, contradictions,
partial coverage, unique insights, blind spots, verdict) → **Fable 5 synthesizes** the final answer
grounded in it.

This pipeline needs no external CLI — use it when codex is unavailable, capped, or you deliberately want a
pure-Fable run. Follow the skill's SKILL.md exactly. Do NOT add a GPT-5.5 or Gemini panelist, and do NOT
route the judging to GPT-5.5, even if codex is installed — this command is pinned to Fable judging and
synthesizing. Do not assign the two runs any "lenses" — pass the task verbatim to both.

Task: $ARGUMENTS
