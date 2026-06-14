---
description: Fusion zero-setup — two independent Opus 4.8 runs, Opus judges + synthesizes (no codex)
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the pure-Opus pipeline:
run the same prompt twice as TWO independent Opus 4.8 panelists (headless `claude` CLI under the Claude
Fable 5 system prompt, via `scripts/run_claude.sh`, in parallel, neither seeing the other's work) →
**Opus 4.8 does the discernment** (per-panelist assessment, consensus,
contradictions, partial coverage, unique insights, blind spots, verdict) → **Opus 4.8 synthesizes** the
final answer grounded in it.

This pipeline needs no external CLI — use it when codex is unavailable, capped, or you deliberately want a
pure-Opus run. Follow the skill's SKILL.md exactly. Do NOT add a GPT-5.5 or Gemini panelist, and do NOT
route the judging to GPT-5.5, even if codex is installed — this command is pinned to Opus judging and
synthesizing. Do not assign the two runs any "lenses" — pass the task verbatim to both.

Task: $ARGUMENTS
