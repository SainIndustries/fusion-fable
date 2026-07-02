---
description: Fusion — auto-detect the richest panel, GPT-5.5 judges, Fable 5 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below using the auto-detected pipeline. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5. Run `scripts/detect_panel.sh` first and use whatever it recommends:

- panelists answer the SAME prompt IN PARALLEL, blind, with web + bash (default: 2× Fable 5 + GPT-5.5),
- answers are anonymized (shuffled Panelist A/B/C),
- **GPT-5.5 judges** them into a structured discernment (falls back to Fable judging if codex is
  unavailable),
- **Fable 5 synthesizes** the final answer grounded in that discernment, with attribution restored.

Follow the skill's SKILL.md exactly (gate → detect → fan out → anonymize → judge → synthesize → present).
Pass the task verbatim to every panelist; no "lenses". Name the SLUG, the panelists, the judge, and the
synthesizer in the output, and note any fallback or dropped panelist.

Task: $ARGUMENTS
