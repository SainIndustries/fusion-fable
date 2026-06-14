---
description: Fusion — auto-detect the richest panel, GPT-5.5 judges, Opus 4.8 synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below using the auto-detected pipeline. Run
`scripts/detect_panel.sh` first and use whatever it recommends:

- panelists answer the SAME prompt IN PARALLEL, blind, with web + bash (default: 2× Opus 4.8 + GPT-5.5),
- answers are anonymized (shuffled Panelist A/B/C),
- **GPT-5.5 judges** them into a structured discernment (falls back to Opus judging if codex is
  unavailable),
- **Opus 4.8 synthesizes** the final answer grounded in that discernment, with attribution restored.

Follow the skill's SKILL.md exactly (detect → fan out → anonymize → judge → synthesize → present). Pass the
task verbatim to every panelist; no "lenses". Name the SLUG, the panelists, the judge, and the synthesizer
in the output, and note any fallback or dropped panelist.

Task: $ARGUMENTS
