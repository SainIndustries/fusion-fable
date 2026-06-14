---
name: fusion
description: >-
  Answer a hard question by fanning it out to a PANEL of models running in parallel — each answering
  independently with web search and bash, none seeing the others' work — then having GPT-5.5 (codex) JUDGE
  the answers into a structured discernment (per-panelist assessment, consensus, contradictions, partial
  coverage, unique insights, blind spots, verdict) and Opus 4.8 SYNTHESIZE the final answer grounded in it.
  The default panel is two independent Opus 4.8 runs + GPT-5.5; GPT-5.5 judges (discrimination), Opus
  writes (synthesis). If codex is unavailable, Opus both judges and writes. Opus always writes the final
  answer — the pipeline can't be reversed. Use this whenever the user asks to "run it through Fusion", wants
  a multi-model / panel / ensemble answer, wants a question cross-checked across models, or wants a
  higher-confidence answer with consensus and blind spots surfaced — even if they don't say "fusion". Best
  for high-stakes research, design calls, and debugging where being confidently wrong is expensive. For
  long ITERATIVE work (not a one-shot question), use a persistent codex domain expert instead — see
  references/persistent_experts.md.
---

# Fusion

Fusion turns one prompt into a panel. The question goes to several models **at the same time**, each
answering independently — with web search and bash, and with no knowledge of the others. Then the pipeline
splits the old single "judge" step into two stages, each given to the model that's better at it:

```
            ┌─ Opus 4.8 panelist 1 ─┐
prompt ─fan─┼─ Opus 4.8 panelist 2 ─┼─→ GPT-5.5 JUDGE ──→ Opus 4.8 SYNTHESIZE ─→ final answer
       out  └─ GPT-5.5 panelist ────┘   (discernment:        (creative answer,
                                         scores, consensus,    grounded in the
                                         contradictions,       discernment)
                                         verdict — no answer)
```

The whole mechanism is **independence, then discernment, then synthesis**. The diversity that makes a panel
beat a single model is harvested, not manufactured: running the same prompt independently yields different
reasoning paths, tool calls, and sources — even two cold runs of the *same* model diverge enough that
synthesizing them beats running it once. So there are no assigned "lenses" or personas; every panelist gets
the task verbatim and answers it straight. (See `references/panel.md`.)

**Why the split:** GPT-5.5 is stronger at *discrimination* — deciding which claims are actually correct and
well-supported — so it judges. Opus 4.8 is stronger at *creative synthesis* — writing the grounded final
answer — so it writes. The judge does not author the final answer.

**One hard rule: Opus 4.8 always writes the final answer — the pipeline can't be reversed.** The panelist
models can't call back out to spawn Opus, so Opus is always the driver and the synthesizer. The judge is an
intermediate stage Opus invokes and stays in control of.

## Step 0 — Detect the pipeline

```bash
bash <skill_dir>/scripts/detect_panel.sh
```

It prints a machine-parseable block — grep these:

- `PANEL=` the panelists that will answer blind (default `opus4.8,opus4.8,gpt5.5`).
- `JUDGE=` the discernment model (`gpt5.5` when codex is present, else `opus4.8`).
- `SYNTH=` the synthesizer — always `opus4.8`.
- `SLUG=` the human-readable label for what you ran.

| Condition | Panel | Judge | Synth |
| --- | --- | --- | --- |
| codex present (default) | 2× Opus 4.8 + GPT-5.5 | GPT-5.5 | Opus 4.8 |
| codex absent | 2× Opus 4.8 | Opus 4.8 | Opus 4.8 |
| `FUSION_USE_GEMINI=1` + gemini present | + Gemini 3.1 Pro as an extra panelist | (unchanged) | Opus 4.8 |

If the user named a panel or judge, honor it — but if a required CLI is missing, say so and fall back
rather than failing. Otherwise use the detector's recommendation.

**Is this even a panel task?** If the user wants long *iterative* work (debug this over many turns, drive
this migration), that's not a one-shot panel — read `references/persistent_experts.md` and use
`scripts/codex_expert.sh` instead.

## Step 1 — Fan out, in parallel and blind

Read `references/panel.md`. Build each panelist's prompt as the user's task **verbatim** plus the short
instruction to research with web + bash and return a complete, self-contained answer as one of several
independent experts who won't see the others' work. Do not assign lenses; do not pre-digest the task.

Launch **all panelists in a single turn** so they run concurrently:

- **Opus 4.8 panelists (default)** → headless `claude` CLI subprocesses under the **Claude Fable 5 system
  prompt**, with permissions skipped so each researches autonomously (web + bash). Write each panelist's
  prompt to a temp file and run **two** of them in the background with the *same* prompt — two cold runs:
  ```bash
  bash <skill_dir>/scripts/run_claude.sh /tmp/fusion_claude1_prompt.txt /tmp/fusion_claude1_out.md opus
  bash <skill_dir>/scripts/run_claude.sh /tmp/fusion_claude2_prompt.txt /tmp/fusion_claude2_out.md opus
  ```
  This runs Opus 4.8 but loads the Fable 5 system prompt (the "Fable-tier" intent). It uses
  `--dangerously-skip-permissions` so the panelist uses tools without prompts — deliberate for an isolated
  panelist, contained to a scratch dir. *(Alternative: if you don't want headless CLI subprocesses, spawn
  two `Agent` subagents `subagent_type: general-purpose` with the same prompt instead — same effect, no
  Fable 5 prompt.)*
- **GPT-5.5 panelist** → write its prompt to a temp file and run in the background:
  ```bash
  bash <skill_dir>/scripts/run_codex.sh /tmp/fusion_codex_prompt.txt /tmp/fusion_codex_out.md medium
  ```
- **Gemini panelist (only if `FUSION_USE_GEMINI=1`)** →
  `bash <skill_dir>/scripts/run_gemini.sh /tmp/fusion_gemini_prompt.txt /tmp/fusion_gemini_out.md`.

Keep panelists isolated: never paste one panelist's output into another's prompt. A panelist that fails or
is dropped is **absent**, never silent agreement.

## Step 2 — Anonymize for the judge

Collect every returned answer and write each to an answers directory under **shuffled** labels so the judge
can't tell which model wrote which (this is what stops a GPT-5.5 judge from favoring the GPT-5.5 panelist's
own answer):

```bash
mkdir -p /tmp/fusion_answers && rm -f /tmp/fusion_answers/panelist_*.md
# Write each answer to panelist_A.md, panelist_B.md, panelist_C.md in a RANDOM order.
```

**Keep the label→model map yourself** (e.g. A=Opus-run-2, B=GPT-5.5, C=Opus-run-1). You restore real
attribution only at synthesis. Also write the user's task verbatim to `/tmp/fusion_task.txt`.

## Step 3 — Judge (discernment)

Run the GPT-5.5 judge over the anonymized answers:

```bash
bash <skill_dir>/scripts/run_judge.sh /tmp/fusion_task.txt /tmp/fusion_answers /tmp/fusion_judge.md high
```

Read `references/judge_rubric.md`. The judge **classifies the deliverable first** (Track A: code/artifact →
run & merge; Track B: research → five-section synthesis) and produces a structured discernment doc — it does
**not** write the final answer.

**Fallback (codex unavailable or capped):** `run_judge.sh` exits non-zero (2 = no codex, 1 = codex failed).
When it does, **you (Opus) do the discernment yourself** using `references/judge_rubric.md` — read all
answers and produce the same structured analysis. Note in the final output that the judge fell back to Opus.

## Step 4 — Synthesize (Opus writes the final answer)

You (Opus) read the judge's discernment doc plus the raw answers and write the final deliverable grounded
in it. De-anonymize here: restore real panelist attribution (A/B/C → the actual models) so the user can
trace each decision.

- **Track A (code/artifact):** emit the complete, merged artifact — every file, ready to run as-is. Per
  `judge_rubric.md` you got here by running both candidates and keeping what worked; **run the merged
  result and fix until it passes** before presenting. Follow with a tight merge rationale.
- **Track B (research):** write the answer grounded in the discernment — lead with high-confidence
  consensus, fold in unique insights, flag what stays uncertain. It must follow *from* the discernment, not
  be one panelist's answer lightly edited.

## Step 5 — Present

Lead with the **final deliverable** — the merged working artifact (Track A) or the grounded answer
(Track B) — then the audit trail beneath it: the judge's discernment (per-panelist assessment, consensus,
contradictions, partial coverage, unique insights, blind spots, verdict), with real attribution restored.
Name what you ran: the `SLUG`, which panelists participated, who judged, and who synthesized. If the judge
fell back to Opus (codex missing/capped) or a panelist was dropped, say so and how to enable the fuller
pipeline.

## Cost & latency note

A panel costs roughly N× a single answer in tokens, and the new judge stage adds one serial codex call
after the parallel fan-out. That's the deliberate trade: you spend more — and split judging from writing —
to stop being confidently wrong where that's expensive. For quick or low-stakes questions, a single direct
answer is the right call. For long iterative work, a persistent codex expert
(`references/persistent_experts.md`) beats both.
