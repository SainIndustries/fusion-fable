---
name: fusion
description: >-
  Run an explicitly requested subscription-backed cross-model panel: Claude Fable 5.1 and GPT-6 Astra
  answer independently, a fresh blind Fable 5.1 judge evaluates anonymized answers, and Fable 5.1
  synthesizes the result. Use only when the user says fusion, panel, ensemble, or cross-model. Do not
  auto-trigger for ordinary hard questions. Use the persistent-expert workflow for long iterative work
  rather than a repeated one-shot panel. GPT-6 Astra may judge when explicitly requested with
  FUSION_JUDGE=astra.
---

# Fusion

Fusion turns one prompt into a panel. The question goes to several models **at the same time**, each
answering independently — with web search and bash, and with no knowledge of the others. The default panel
is deliberately **cross-model**: two different model families (Claude Fable 5.1 + GPT-6 Astra), maximum diversity
per panelist. Opus 4.8 is the automatic fallback second panelist, used when codex/GPT-6 Astra isn't available.
Then the pipeline splits the old single "judge" step into two stages:

```
            ┌─ Fable 5.1 panelist ─┐
prompt ─fan─┤                      ├─→ Fable 5.1 JUDGE ─→ Fable 5.1 SYNTHESIZE ─→ final answer
       out  └─ GPT-6 Astra panelist┘   (fresh blind          (creative answer,
              (Opus 4.8 if no codex)    subprocess:            grounded in the
                                        scores, consensus,     discernment,
                                        contradictions,        written by your
                                        verdict — no answer)   session)
```

The whole mechanism is **independence, then discernment, then synthesis**. The diversity that makes a panel
beat a single model is harvested, not manufactured: two different models given the same prompt take
different reasoning paths, tool calls, and sources. So there are no assigned "lenses" or personas; every
panelist gets the task verbatim and answers it straight. (See `references/panel.md`.)

**Why the split even with one model judging and synthesizing:** the judge runs as a **fresh, blind Fable 5.1
subprocess** over anonymized answers — a cold context that never saw the fan-out and can't be anchored by
it — while the synthesizer is your warm session, which writes the final answer grounded in the judge's
discernment. Discernment stays skeptical and blind; synthesis stays creative and accountable. To hand
discernment to GPT-6 Astra instead (cross-model judging), set `FUSION_JUDGE=astra` or use `/fusion-astra`.

**One hard rule: Fable 5.1 always writes the final answer — the pipeline can't be reversed.** The panelist
models can't call back out to spawn Fable, so Fable is always the driver and the synthesizer. The judge is
an intermediate stage Fable invokes and stays in control of.

## Step 0 — Gate, then detect the pipeline

**Model gate — Fable 5.1 drives, or nobody does.** Check what model YOUR session is running (your system
prompt names it). If you are **not** Claude Fable 5.1 (e.g. the session is on Opus or Sonnet), do NOT run the
pipeline: tell the user this skill is pinned to a Fable 5.1 driver — the synthesizer IS the session model, so
running it from a lesser session silently downgrades the "Fable-tier" result — and ask them to switch the
session to Fable 5.1 (`/model fable`) and re-invoke. Only proceed from a non-Fable session if the user
explicitly says to anyway.

**Worth a panel at all?** Even from a Fable 5.1 session, Fusion is not the default answer path. If the user
didn't explicitly invoke it, answer directly instead. If they did, but the question is quick or low-stakes,
say a single Fable 5.1 answer would serve them just as well for ~1/4 the cost — then respect their call.

Then detect:

```bash
bash <skill_dir>/scripts/detect_panel.sh
```

It prints a machine-parseable block — grep these:

- `PANEL=` the panelists that will answer blind (default `fable5,astra`; `fable5,opus4.8` when codex is absent).
- `JUDGE=` the discernment model (default `fable5`; `astra` when `FUSION_JUDGE=astra` and codex present).
- `SYNTH=` the synthesizer — always `fable5`.
- `SLUG=` the human-readable label for what you ran.
- `RUN_DIR=` a **fresh private directory for this run**. Use it for *every* intermediate file below
  (`$RUN_DIR/...`). Never use a shared `/tmp/fusion_*` constant — that clobbers concurrent runs in other
  sessions/projects. Set `RUN_DIR` from this value and reuse it through all steps.

| Condition | Panel | Judge | Synth |
| --- | --- | --- | --- |
| default (claude + codex present) | Fable 5.1 + GPT-6 Astra | Fable 5.1 (fresh blind subprocess) | Fable 5.1 |
| codex absent (Opus 4.8 fallback) | Fable 5.1 + Opus 4.8 | Fable 5.1 | Fable 5.1 |
| `FUSION_JUDGE=astra` (or `/fusion-astra`) | Fable 5.1 + GPT-6 Astra | GPT-6 Astra | Fable 5.1 |
| `FUSION_USE_GEMINI=1` + gemini present | + Gemini 3.1 Pro as an extra panelist | (unchanged) | Fable 5.1 |

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

Launch **the panelists named by `PANEL=`, all in a single turn** so they run concurrently. The default
panel is `fable5,astra`; when codex is absent the detector substitutes `fable5,opus4.8`.

- **Fable 5.1 panelist (always present)** → headless `claude` CLI subprocess, permissions skipped so it
  researches autonomously (web + bash). Write its prompt to a temp file and run in the background:
  ```bash
  bash <skill_dir>/scripts/run_claude.sh "$RUN_DIR/fable_prompt.txt" "$RUN_DIR/fable_out.md"        # claude-fable-5-1
  ```
  It uses `--dangerously-skip-permissions` so the panelist uses tools without prompts — deliberate for an
  isolated panelist, contained to a scratch dir. Each run is wall-clock bounded by `FUSION_TIMEOUT`
  (default 900s). Override the model with `FUSION_CLAUDE_MODEL`.
  *(Alternative: if you don't want headless CLI subprocesses, spawn an `Agent` subagent
  `subagent_type: general-purpose` with `model: fable` — same effect.)*
  **If `run_claude.sh` exits non-zero, do not drop the Fable panelist — rerun it as that `Agent`
  subagent.** The usual cause is a revoked/expired CLI login (the script prints "the claude CLI is not
  logged in"); subagents use the session's own auth, so they still work. Give the subagent the same
  verbatim prompt and have it write its answer to `$RUN_DIR/fable_out.md`. A failed run never leaves
  error text behind as an "answer": the runners move a failed output to `<file>.failed`.
- **GPT-6 Astra panelist (default second panelist)** → write its prompt to a temp file and run in the background:
  ```bash
  bash <skill_dir>/scripts/run_codex.sh "$RUN_DIR/codex_prompt.txt" "$RUN_DIR/codex_out.md" medium
  ```
- **Opus 4.8 panelist (fallback only)** → run this *instead of* GPT-6 Astra when `PANEL=` names `opus4.8`
  (codex absent, or the `fable5-duo` / `/fusion-fable5` harness). Same runner as Fable, `opus` model arg:
  ```bash
  bash <skill_dir>/scripts/run_claude.sh "$RUN_DIR/opus_prompt.txt"  "$RUN_DIR/opus_out.md"  opus   # Opus 4.8
  ```
  Override with `FUSION_OPUS_MODEL`. *(Agent alternative: `model: opus`.)*
- **Gemini panelist (only if `FUSION_USE_GEMINI=1`)** →
  `bash <skill_dir>/scripts/run_gemini.sh "$RUN_DIR/gemini_prompt.txt" "$RUN_DIR/gemini_out.md"`.

`run_codex.sh` exit codes: `3` = the installed codex CLI is too old for the pinned model (GPT-6 Astra needs
codex ≥ 0.153.1 — relay the upgrade command the script prints), `1` = ran but failed (the script names
usage-limit and login causes), `127` = not installed. On any of them the GPT panelist is **absent**: run the
Opus 4.8 fallback panelist in its place and say so. Never substitute a different GPT model silently.

Map each `PANEL=` token to its runner: `fable5` → `run_claude.sh` (default model), `opus4.8` →
`run_claude.sh … opus`, `astra` (or the legacy tokens `gpt5.6` / `gpt5.5`, used by the preserved presets) → `run_codex.sh`, `gemini3.1pro` → `run_gemini.sh`.
**Duplicate tokens are independent cold runs** of the same runner (e.g. a variant panel
`opus4.8,opus4.8,gpt5.5` launches `run_claude.sh` twice with separate prompt/output files).

Keep panelists isolated: never paste one panelist's output into another's prompt. A panelist that fails or
is dropped is **absent**, never silent agreement.

## Step 2 — Anonymize for the judge

Anonymize with the script (don't shuffle by hand — that's neither reliably random nor reliably remembered).
It shuffles the returned answers into blind Panelist A/B/C labels with a real RNG and writes a durable
`map.json`, skipping any empty/dropped panelist:

```bash
# Pass whichever panelist outputs this run actually produced; anonymize.sh skips missing/empty sources.
# Default panel → fable_out + codex_out. Opus-fallback / duo run → fable_out + opus_out.
bash <skill_dir>/scripts/anonymize.sh "$RUN_DIR/answers" \
  "$RUN_DIR/fable_out.md" "$RUN_DIR/codex_out.md" "$RUN_DIR/opus_out.md"
```

The label→source map lives at `$RUN_DIR/answers/map.json` (not in your head) — read it back at synthesis to
restore real attribution. Also write the user's task verbatim to `$RUN_DIR/task.txt`.

## Step 3 — Judge (discernment)

Run the judge over the anonymized answers — by default a **fresh blind Fable 5.1 subprocess**:

```bash
bash <skill_dir>/scripts/run_judge.sh "$RUN_DIR/task.txt" "$RUN_DIR/answers" "$RUN_DIR/judge.md" high
# GPT-6 Astra judging instead (only when the user asked for it / /fusion-astra):
# bash <skill_dir>/scripts/run_judge.sh "$RUN_DIR/task.txt" "$RUN_DIR/answers" "$RUN_DIR/judge.md" high astra
```

Read `references/judge_rubric.md`. The judge **classifies the deliverable first** (Track A: code/artifact →
run & merge; Track B: research → five-section synthesis) and produces a structured discernment doc — it does
**not** write the final answer.

**Fallback (judge CLI unavailable, timed out, or off-task):** `run_judge.sh` exits non-zero (2 = judge CLI
missing or too old for the pinned model, 1 = judge failed / not logged in / timed out / returned output
missing the required sections). Fall back in this order, and say which one you used in the final output:

1. **A fresh blind `Agent` subagent** (`subagent_type: general-purpose`, `model: fable`). Give it only the
   rubric path, `$RUN_DIR/task.txt`, and the anonymized `$RUN_DIR/answers/panelist_*.md` (tell it not to
   open `map.json`), ask it to verify contested factual claims itself, and have it write
   `$RUN_DIR/judge.md`. This keeps what the judge stage exists for — a cold context that never saw the
   fan-out — and works when the `claude` CLI login is revoked.
2. **Inline discernment** by you, the orchestrating session, using `references/judge_rubric.md`, only when
   subagents are unavailable too.

## Step 4 — Synthesize (your Fable session writes the final answer)

You (Fable 5.1) read the judge's discernment doc plus the raw answers and write the final deliverable
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
to stop being confidently wrong where that's expensive. Now that Fable 5.1 itself is the frontier model, a
single direct Fable answer is the right call for most questions; reserve the panel for when the user wants
cross-model diversity or the stakes justify N× scrutiny. For long iterative work, a persistent codex expert
(`references/persistent_experts.md`) beats both.
