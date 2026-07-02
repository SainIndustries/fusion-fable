---
description: Fusion, GPT-5.5-judged — Fable 5 + Opus 4.8 + GPT-5.5 panel, GPT-5.5 judges, Fable 5 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the GPT-5.5-judged variant. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5. The pipeline:
one Claude Fable 5 panelist and one Claude Opus 4.8 panelist (headless `claude` CLI subprocesses via
`scripts/run_claude.sh`) and one GPT-5.5 panelist (via `codex exec`) answer the SAME prompt IN PARALLEL,
each independently with web + bash and none seeing the others' work → answers are anonymized (shuffled
Panelist A/B/C) → **GPT-5.5 judges** them into a structured discernment (per-panelist assessment,
consensus, contradictions, partial coverage, unique insights, blind spots, verdict) — pass `gpt5.5` as the
judge arg to `scripts/run_judge.sh` → **Fable 5 synthesizes** the final answer grounded in that
discernment, with real attribution restored.

Use this variant when you want cross-model judging: the model that adjudicates is from a different family
than the synthesizer. Follow the skill's SKILL.md exactly (gate → fan out → anonymize → GPT-5.5 judge →
Fable synthesize → present). Use exactly three panelists: Fable 5, Opus 4.8, GPT-5.5 — do not add a Gemini
panelist. Pass the task verbatim to all; no "lenses". If the `codex` CLI is unavailable, fall back to the
default Fable 5 judge (say so in the output) rather than failing.

Task: $ARGUMENTS
