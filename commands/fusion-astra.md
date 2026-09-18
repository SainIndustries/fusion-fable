---
description: Fusion, Astra-judged — Fable 5.1 + GPT-6 Astra panel, GPT-6 Astra judges, Fable 5.1 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below, forcing the Astra-judged variant. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5.1. The pipeline:
one Claude Fable 5.1 panelist (headless `claude` CLI subprocess via `scripts/run_claude.sh`) and one GPT-6 Astra
panelist (via `codex exec`, `scripts/run_codex.sh`) answer the SAME prompt IN PARALLEL, each independently
with web + bash and neither seeing the other's work → answers are anonymized (shuffled Panelist A/B) →
**GPT-6 Astra judges** them into a structured discernment (per-panelist assessment, consensus, contradictions,
partial coverage, unique insights, blind spots, verdict) — pass `astra` as the judge arg to
`scripts/run_judge.sh` → **Fable 5.1 synthesizes** the final answer grounded in that discernment, with real
attribution restored.

Use this variant when you want cross-model judging: the model that adjudicates is from a different family
than the synthesizer. Follow the skill's SKILL.md exactly (gate → fan out → anonymize → GPT-6 Astra judge →
Fable synthesize → present). Use exactly two panelists: Fable 5.1 + GPT-6 Astra — do not add a Gemini panelist.
Pass the task verbatim to both; no "lenses". If the `codex` CLI is unavailable, fall back to the default
Fable 5.1 judge over the Opus 4.8 fallback panel (say so in the output) rather than failing.

Task: $ARGUMENTS
