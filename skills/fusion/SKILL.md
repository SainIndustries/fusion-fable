---
name: fusion
description: >-
  Answer a hard question by fanning it out to a cross-model PANEL running in parallel — one Claude Fable 5,
  one Claude Opus 4.8, and one GPT-5.5 (codex), each answering independently with web search and bash, none
  seeing the others' work — then having a FRESH blind Claude Fable 5 subprocess JUDGE the anonymized
  answers into a structured discernment (per-panelist assessment, consensus, contradictions, partial
  coverage, unique insights, blind spots, verdict) and the Fable 5 session SYNTHESIZE the final answer
  grounded in it. GPT-5.5 can judge instead when explicitly requested (FUSION_JUDGE=gpt5.5 or
  /fusion-gpt5.5). Fable 5 always writes the final answer — the pipeline can't be reversed. ONLY invoke
  this skill when the user EXPLICITLY asks for it: they say "fusion", use a /fusion command, or explicitly
  ask for a multi-model / panel / ensemble / cross-model answer. Do NOT auto-trigger it for merely hard
  questions — Fable 5 is the frontier model and a single direct Fable 5 answer is the default; Fusion is
  reserved for when the user wants cross-model diversity or a challenge beyond what one Fable run should
  carry alone. This skill must be DRIVEN BY a Claude Fable 5 session (see Step 0's model gate). For long
  ITERATIVE work (not a one-shot question), use a persistent codex domain expert instead — see
  references/persistent_experts.md.
---

# Fusion

Fusion turns one prompt into a panel. The question goes to several models **at the same time**, each
answering independently — with web search and bash, and with no knowledge of the others. The default panel
is deliberately **cross-model**: three different models (two Claude tiers + GPT-5.5), maximum diversity per
panelist. Then the pipeline splits the old single "judge" step into two stages:

```
            ┌─ Fable 5 panelist ───┐
prompt ─fan─┼─ Opus 4.8 panelist ──┼─→ Fable 5 JUDGE ───→ Fable 5 SYNTHESIZE ─→ final answer
       out  └─ GPT-5.5 panelist ───┘   (fresh blind          (creative answer,
                                        subprocess:            grounded in the
                                        scores, consensus,     discernment,
                                        contradictions,        written by your
                                        verdict — no answer)   session)
```

The whole mechanism is **independence, then discernment, then synthesis**. The diversity that makes a panel
beat a single model is harvested, not manufactured: three different models given the same prompt take
different reasoning paths, tool calls, and sources. So there are no assigned "lenses" or personas; every
panelist gets the task verbatim and answers it straight. (See `references/panel.md`.)

**Why the split even with one model judging and synthesizing:** the judge runs as a **fresh, blind Fable 5
subprocess** over anonymized answers — a cold context that never saw the fan-out and can't be anchored by
it — while the synthesizer is your warm session, which writes the final answer grounded in the judge's
discernment. Discernment stays skeptical and blind; synthesis stays creative and accountable. To hand
discernment to GPT-5.5 instead (cross-model judging), set `FUSION_JUDGE=gpt5.5` or use `/fusion-gpt5.5`.

**One hard rule: Fable 5 always writes the final answer — the pipeline can't be reversed.** The panelist
models can't call back out to spawn Fable, so Fable is always the driver and the synthesizer. The judge is
an intermediate stage Fable invokes and stays in control of.

## Step 0 — Gate, then detect the pipeline

**Model gate — Fable 5 drives, or nobody does.** Check what model YOUR session is running (your system
prompt names it). If you are **not** Claude Fable 5 (e.g. the session is on Opus or Sonnet), do NOT run the
pipeline: tell the user this skill is pinned to a Fable 5 driver — the synthesizer IS the session model, so
running it from a lesser session silently downgrades the "Fable-tier" result — and ask them to switch the
session to Fable 5 (`/model fable`) and re-invoke. Only proceed from a non-Fable session if the user
explicitly says to anyway.

**Worth a panel at all?** Even from a Fable 5 session, Fusion is not the default answer path. If the user
didn't explicitly invoke it, answer directly instead. If they did, but the question is quick or low-stakes,
say a single Fable 5 answer would serve them just as well for ~1/4 the cost — then respect their call.

Then detect:

```bash
bash <skill_dir>/scripts/detect_panel.sh
```

It prints a machine-parseable block — grep these:

- `PANEL=` the panelists that will answer blind (default `fable5,opus4.8,gpt5.5`).
- `JUDGE=` the discernment model (default `fable5`; `gpt5.5` when `FUSION_JUDGE=gpt5.5` and codex present).
- `SYNTH=` the synthesizer — always `fable5`.
- `SLUG=` the human-readable label for what you ran.
- `RUN_DIR=` a **fresh private directory for this run**. Use it for *every* intermediate file below
  (`$RUN_DIR/...`). Never use a shared `/tmp/fusion_*` constant — that clobbers concurrent runs in other
  sessions/projects. Set `RUN_DIR` from this value and reuse it through all steps.

| Condition | Panel | Judge | Synth |
| --- | --- | --- | --- |
| default (claude + codex present) | Fable 5 + Opus 4.8 + GPT-5.5 | Fable 5 (fresh blind subprocess) | Fable 5 |
| codex absent | Fable 5 + Opus 4.8 | Fable 5 | Fable 5 |
| `FUSION_JUDGE=gpt5.5` (or `/fusion-gpt5.5`) | Fable 5 + Opus 4.8 + GPT-5.5 | GPT-5.5 | Fable 5 |
| `FUSION_USE_GEMINI=1` + gemini present | + Gemini 3.1 Pro as an extra panelist | (unchanged) | Fable 5 |

If the user named a panel or judge, honor it — but if a required CLI is missing, say so and fall back
rather than failing. Otherwise use the detector's recommendation.

**Variants — swapping whole harnesses.** `<skill_dir>/variants/*.env` are named presets of the same knobs
(panel composition, judge, model strings) — one file per harness era or combination (e.g.
`fable5-crossmodel`, `opus4.8-era`). If the user named one (or invoked `/fusion-variant`), prefix **every**
script call in this run — `detect_panel.sh` and all runners — with `FUSION_VARIANT=<name>`; the scripts
load the preset themselves via `_lib.sh`, and explicitly exported env vars still override it. The detector
lists available variants and folds the active one into the `SLUG`.

**Is this even a panel task?** If the user wants long *iterative* work (debug this over many turns, drive
this migration), that's not a one-shot panel — read `references/persistent_experts.md` and use
`scripts/codex_expert.sh` instead.

## Step 1 — Fan out, in parallel and blind

Read `references/panel.md`. Build each panelist's prompt as the user's task **verbatim** plus the short
instruction to research with web + bash and return a complete, self-contained answer as one of several
independent experts who won't see the others' work. Do not assign lenses; do not pre-digest the task.

Launch **all panelists in a single turn** so they run concurrently:

- **Claude panelists (default)** → headless `claude` CLI subprocesses, with permissions skipped so each
  researches autonomously (web + bash). Write each panelist's prompt to a temp file and run one **Fable 5**
  and one **Opus 4.8** in the background with the *same* prompt:
  ```bash
  bash <skill_dir>/scripts/run_claude.sh "$RUN_DIR/fable_prompt.txt" "$RUN_DIR/fable_out.md"        # claude-fable-5
  bash <skill_dir>/scripts/run_claude.sh "$RUN_DIR/opus_prompt.txt"  "$RUN_DIR/opus_out.md"  opus   # Opus 4.8
  ```
  It uses `--dangerously-skip-permissions` so the panelist uses tools without prompts — deliberate for an
  isolated panelist, contained to a scratch dir. Each run is wall-clock bounded by `FUSION_TIMEOUT`
  (default 900s). Override the models with `FUSION_CLAUDE_MODEL` (Fable) / `FUSION_OPUS_MODEL` (Opus).
  *(Alternative: if you don't want headless CLI subprocesses, spawn two `Agent` subagents
  `subagent_type: general-purpose` — one with `model: fable`, one with `model: opus` — same effect.)*
- **GPT-5.5 panelist** → write its prompt to a temp file and run in the background:
  ```bash
  bash <skill_dir>/scripts/run_codex.sh "$RUN_DIR/codex_prompt.txt" "$RUN_DIR/codex_out.md" medium
  ```
- **Gemini panelist (only if `FUSION_USE_GEMINI=1`)** →
  `bash <skill_dir>/scripts/run_gemini.sh "$RUN_DIR/gemini_prompt.txt" "$RUN_DIR/gemini_out.md"`.

Map each `PANEL=` token to its runner: `fable5` → `run_claude.sh` (default model), `opus4.8` →
`run_claude.sh … opus`, `gpt5.5` → `run_codex.sh`, `gemini3.1pro` → `run_gemini.sh`. **Duplicate tokens are
independent cold runs** of the same runner (e.g. a variant panel `opus4.8,opus4.8,gpt5.5` launches
`run_claude.sh` twice with separate prompt/output files).

Keep panelists isolated: never paste one panelist's output into another's prompt. A panelist that fails or
is dropped is **absent**, never silent agreement.

## Step 2 — Anonymize for the judge

Anonymize with the script (don't shuffle by hand — that's neither reliably random nor reliably remembered).
It shuffles the returned answers into blind Panelist A/B/C labels with a real RNG and writes a durable
`map.json`, skipping any empty/dropped panelist:

```bash
bash <skill_dir>/scripts/anonymize.sh "$RUN_DIR/answers" \
  "$RUN_DIR/fable_out.md" "$RUN_DIR/opus_out.md" "$RUN_DIR/codex_out.md"
```

The label→source map lives at `$RUN_DIR/answers/map.json` (not in your head) — read it back at synthesis to
restore real attribution. Also write the user's task verbatim to `$RUN_DIR/task.txt`.

## Step 3 — Judge (discernment)

Run the judge over the anonymized answers — by default a **fresh blind Fable 5 subprocess**:

```bash
bash <skill_dir>/scripts/run_judge.sh "$RUN_DIR/task.txt" "$RUN_DIR/answers" "$RUN_DIR/judge.md" high
# GPT-5.5 judging instead (only when the user asked for it / /fusion-gpt5.5):
# bash <skill_dir>/scripts/run_judge.sh "$RUN_DIR/task.txt" "$RUN_DIR/answers" "$RUN_DIR/judge.md" high gpt5.5
```

Read `references/judge_rubric.md`. The judge **classifies the deliverable first** (Track A: code/artifact →
run & merge; Track B: research → five-section synthesis) and produces a structured discernment doc — it does
**not** write the final answer.

**Fallback (judge CLI unavailable, timed out, or off-task):** `run_judge.sh` exits non-zero (2 = judge CLI
missing, 1 = judge failed / timed out / returned output missing the required sections). When it does, **you
(the orchestrating Fable session) do the discernment yourself, inline** using
`references/judge_rubric.md` — read all answers and produce the same structured analysis. Note in the final
output that the judge fell back to inline discernment.

## Step 4 — Synthesize (your Fable session writes the final answer)

You (Fable 5) read the judge's discernment doc plus the raw answers and write the final deliverable
grounded in it. De-anonymize here using `$RUN_DIR/answers/map.json`: restore real panelist attribution
(A/B/C → the actual source files/models) so the user can trace each decision.

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
fell back to inline discernment or a panelist was dropped, say so and how to enable the fuller pipeline.

## Step 6 — (optional) Anchor the run's provenance

Off by default. The markdown audit trail from Step 5 is always the record of truth; this step is purely
additive and must never change or block the answer you already presented. Only run it if `FUSION_ANCHOR=1`.

If enabled, write the artifacts the emitter hashes into the run dir, then call it:

```bash
echo "$SLUG" > "$RUN_DIR/slug.txt"        # the SLUG from detect_panel.sh
# save the final answer you just presented so it can be hashed:
#   $RUN_DIR/synthesis.md   (judge.md, task.txt, answers/ + map.json already live in $RUN_DIR)
FUSION_ANCHOR=1 SLUG="$SLUG" JUDGE="$JUDGE" SYNTH="$SYNTH" \
  bash <skill_dir>/scripts/anchor_emit.sh "$RUN_DIR" "$SLUG" || true
```

It always writes a local **signed** `attestation.json` (hashes only — panel composition, per-answer
sha256, judge & synthesis hashes, model ids, timestamps, the SLUG). If Anchor'd is reachable
(`ANCHOR_API_URL`/`ANCHOR_API_TOKEN` set, `GET /api/health` ok) it also anchors `sha256(manifest)` via
`POST /api/anchor` and prints `ANCHOR_RESULT=anchored (...)`. It degrades to `local-only` on any failure and
**always exits 0** — never let it affect the run. Raw prompts/answers/judge/synthesis text are never
transmitted unless `FUSION_ANCHOR_INCLUDE_CONTENT=1`. On `ANCHOR_RESULT=anchored`, append one line to the
audit trail you presented: the `anchorId`, `manifest sha256`, and verification URL. See
`references/provenance.md`.

## Cost & latency note

A panel costs roughly N× a single answer in tokens, and the judge stage adds one serial subprocess call
after the parallel fan-out. That's the deliberate trade: you spend more — and split judging from writing —
to stop being confidently wrong where that's expensive. Now that Fable 5 itself is the frontier model, a
single direct Fable answer is the right call for most questions; reserve the panel for when the user wants
cross-model diversity or the stakes justify N× scrutiny. For long iterative work, a persistent codex expert
(`references/persistent_experts.md`) beats both.
