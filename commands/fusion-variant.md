---
description: Fusion with a named harness preset from skills/fusion/variants (e.g. opus4.8-era)
argument-hint: <variant-name> <your question>
---
Invoke the **fusion** skill on the task below using a NAMED HARNESS VARIANT. This is an EXPLICIT
invocation, so the skill's trigger gate is satisfied — but its Step 0 model gate still applies: the driving
session must be Claude Fable 5.

The first word of the arguments is the **variant name** — a preset file at
`<skill_dir>/variants/<name>.env` capturing one harness (panel composition, judge, model strings). The rest
of the arguments are the task. If the name doesn't match a preset file, list the available variants
(`ls <skill_dir>/variants/*.env`) and stop so the user can pick one.

Then follow the skill's SKILL.md exactly (gate → detect → fan out → anonymize → judge → synthesize →
present), with one addition: prefix **every** script invocation in the run — `detect_panel.sh` and all
runners — with `FUSION_VARIANT=<name>` so the preset applies end-to-end. The scripts load the preset
themselves via `_lib.sh`; use whatever PANEL/JUDGE/SYNTH the detector then prints. Name the variant in the
final output's audit trail (it's part of the SLUG).

Arguments: $ARGUMENTS
