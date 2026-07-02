---
description: Fusion flagship — 2 Fable 5 + GPT-5.5 panel, GPT-5.5 judges, Fable 5 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the flagship pipeline. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5. The pipeline:
two independent Claude Fable 5 panelists (headless `claude --model claude-fable-5` CLI subprocesses, via
`scripts/run_claude.sh`) and one GPT-5.5 panelist (via `codex exec`) answer the
SAME prompt IN PARALLEL, each independently with web + bash and none seeing the others' work → answers are
anonymized (shuffled Panelist A/B/C) → **GPT-5.5 judges** them into a structured discernment (per-panelist
assessment, consensus, contradictions, partial coverage, unique insights, blind spots, verdict) → **Fable 5
synthesizes** the final answer grounded in that discernment, with real attribution restored.

Follow the skill's SKILL.md exactly (gate → fan out → anonymize → GPT-5.5 judge → Fable synthesize →
present). Use exactly three panelists: two Fable 5 runs and one GPT-5.5 — do not add a Gemini panelist.
Pass the task verbatim to all; no "lenses". If the `codex` CLI is unavailable, the judge falls back to
Fable 5 doing the discernment (say so in the output) rather than failing.

Task: $ARGUMENTS
