---
description: Fusion flagship — 2 Opus 4.8 + GPT-5.5 panel, GPT-5.5 judges, Opus 4.8 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the flagship pipeline:
two independent Opus 4.8 panelists (headless `claude` CLI under the Claude Fable 5 system prompt, via
`scripts/run_claude.sh`) and one GPT-5.5 panelist (via `codex exec`) answer the
SAME prompt IN PARALLEL, each independently with web + bash and none seeing the others' work → answers are
anonymized (shuffled Panelist A/B/C) → **GPT-5.5 judges** them into a structured discernment (per-panelist
assessment, consensus, contradictions, partial coverage, unique insights, blind spots, verdict) → **Opus
4.8 synthesizes** the final answer grounded in that discernment, with real attribution restored.

Follow the skill's SKILL.md exactly (fan out → anonymize → GPT-5.5 judge → Opus synthesize → present). Use
exactly three panelists: two Opus 4.8 runs and one GPT-5.5 — do not add a Gemini panelist. Pass the task
verbatim to all; no "lenses". If the `codex` CLI is unavailable, the judge falls back to Opus 4.8 doing the
discernment (say so in the output) rather than failing.

Task: $ARGUMENTS
