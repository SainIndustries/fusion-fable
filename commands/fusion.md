---
description: Fusion — cross-model panel (Fable 5 + Opus 4.8 + GPT-5.5), Fable 5 judges + synthesizes
argument-hint: <your question>
---
Invoke the **fusion** skill on the task below using the auto-detected pipeline. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5. Run `scripts/detect_panel.sh` first and use whatever it recommends:

- panelists answer the SAME prompt IN PARALLEL, blind, with web + bash (default cross-model panel:
  Fable 5 + Opus 4.8 + GPT-5.5),
- answers are anonymized (shuffled Panelist A/B/C),
- **Fable 5 judges** them into a structured discernment, as a FRESH blind subprocess (falls back to inline
  discernment by the session if the subprocess fails),
- **Fable 5 synthesizes** the final answer grounded in that discernment, with attribution restored.

Follow the skill's SKILL.md exactly (gate → detect → fan out → anonymize → judge → synthesize → present).
Pass the task verbatim to every panelist; no "lenses". Name the SLUG, the panelists, the judge, and the
synthesizer in the output, and note any fallback or dropped panelist.

Task: $ARGUMENTS
