# Fusion-Fable (Sain Industries fork)

**Fuse a panel of frontier models into one Fable-tier answer — judged by the model best at discernment,
written by the model best at synthesis.**

Fusion-Fable is a [Claude Code](https://claude.com/claude-code) skill that runs a hard question through a
**panel → judge → synthesize** pipeline. The same prompt is dispatched to several models *in parallel* —
each answering independently with web search and bash, none seeing the others' work. Then the two halves of
"judging" are split and handed to the model that's better at each: **GPT-5.5 (via the `codex` CLI) judges**
the answers into a structured discernment (consensus, contradictions, partial coverage, unique insights,
blind spots, verdict), and **Opus 4.8 synthesizes** the final answer grounded in that discernment.

The mechanism is **independence, then discernment, then synthesis**. The diversity that makes a panel beat
a single model is harvested, not manufactured: running the same prompt independently yields different
reasoning paths, tool calls, and sources — even two cold runs of the *same* model diverge enough that
synthesizing them beats running it once. So there are no contrived "lenses" or personas; every panelist
gets the task verbatim and answers it straight.

```
            ┌─ Opus 4.8 panelist 1 ─┐
prompt ─fan─┼─ Opus 4.8 panelist 2 ─┼─→ GPT-5.5 JUDGE ──→ Opus 4.8 SYNTHESIZE ─→ final answer
       out  └─ GPT-5.5 panelist ────┘   (discernment:        (creative answer,
   (web + bash, independent, blind)      scores, consensus,    grounded in the
                                         contradictions,       discernment)
                                         verdict — no answer)
```

**Why this fork splits the judge.** GPT-5.5 is stronger at *discrimination* — deciding which claims are
actually correct and well-supported — so it judges. Opus 4.8 is stronger at *creative synthesis* — writing
the grounded final answer — so it writes. The judge never authors the final answer.

**The invariant still holds:** Opus 4.8 always writes the final answer and always drives — the pipeline
can't be reversed, because the panelist models can't call back out to spawn Opus. The GPT-5.5 judge is an
intermediate discernment stage that Opus invokes and stays in control of. If `codex` is unavailable or
capped, Opus does the discernment itself, so a missing judge degrades the run rather than breaking it.

## What's different about this fork

Upstream Fusion-Fable has Opus 4.8 both judge the panel and write the final answer. This fork's core bet is
that **discernment and synthesis are different skills** — picking what's actually correct rewards a
discriminating judge, while writing the grounded answer rewards a creative synthesizer — so it hands each
job to the model better at it. Around that split sit a few operational changes:

- **Split judge / synthesizer.** GPT-5.5 does discernment; Opus 4.8 does synthesis (upstream had Opus do
  both).
- **Opus panelists run as `claude` CLI subprocesses under the Claude Fable 5 system prompt** (with
  `--dangerously-skip-permissions`), instead of in-process Agent subagents — see the note below.
- **Default panel is 2× Opus 4.8 + GPT-5.5** — Gemini is dropped from the default (opt back in with
  `FUSION_USE_GEMINI=1`). A second Opus run adds real within-model diversity with no extra CLI/auth.
- **Anonymized judging** — panelist answers reach the judge as shuffled Panelist A/B/C, so a GPT-5.5 judge
  can't favor the GPT-5.5 panelist's own answer.
- **Persistent codex domain experts** — `/codex-expert` and `scripts/codex_expert.sh` keep a long-lived
  codex session for iterative, context-heavy work, as an alternative to throwaway subagents.
- **Graceful judge fallback** — if `codex` is missing or capped, Opus judges and synthesizes.

## The pipelines

| Condition | Panelists | Judge | Synthesizer | Requires |
| --- | --- | --- | --- | --- |
| **flagship** (default) | 2× Opus 4.8 + GPT-5.5 | **GPT-5.5** | Opus 4.8 | the `codex` CLI |
| **fallback** (no codex) | 2× Opus 4.8 | Opus 4.8 | Opus 4.8 | nothing — works everywhere |
| **+ gemini** (`FUSION_USE_GEMINI=1`) | + Gemini 3.1 Pro | GPT-5.5 | Opus 4.8 | `codex` + `gemini` CLIs |

`scripts/detect_panel.sh` auto-detects which CLIs are installed and prints the richest pipeline available,
falling back gracefully when one is missing.

## Install

```bash
git clone https://github.com/SainIndustries/fusion-fable.git
cd fusion-fable
./install.sh
```

This copies the skill to `~/.claude/skills/fusion` and the slash commands to `~/.claude/commands`, then
prints what your machine can run. Restart Claude Code (or run `/reload-skills`) afterward.

> Override the target with `CLAUDE_CONFIG_DIR=/path/to/.claude ./install.sh`.

## Use it

Nothing to configure session to session: `install.sh` placed the skill in `~/.claude`, and every Claude
Code session auto-loads it. Just invoke it — three equivalent ways:

- **Natural language** — just ask. The skill auto-triggers and picks the richest pipeline:
  > "Run this through Fusion: is it safe to `ALTER TABLE … ADD COLUMN` on a 200M-row Postgres table in prod?"
- **Slash commands:**
  ```
  /fusion           <prompt>   # auto-detect the richest pipeline (recommended default)
  /fusion-gpt5.5    <prompt>   # flagship: 2× Opus 4.8 + GPT-5.5, GPT-5.5 judges, Opus synthesizes
  /fusion-opus4.8   <prompt>   # zero-setup: 2× Opus 4.8, Opus judges + synthesizes (no codex)
  ```
- **Persistent codex expert** — for long *iterative* work, not a one-shot question:
  ```
  /codex-expert payments-debugger  find where retries can double-charge in src/payments/
  /codex-expert payments-debugger  now propose a fix with a test   # same expert, remembers the last turn
  ```

For a *literal* Fable-tier run, keep your Claude Code session on **Opus 4.8**: the panelists are pinned to
Opus 4.8 no matter what, but the synthesizer is your session.

### Which one do I reach for?

- **One high-stakes question** where being confidently wrong is expensive — a design call, a risky
  migration, a subtle debugging conclusion → `/fusion` (or `/fusion-gpt5.5`). One shot, maximum scrutiny.
- **codex offline / capped, or you want a pure-Opus run** → `/fusion-opus4.8`.
- **A long thread on one domain** where context should accumulate across many turns → `/codex-expert`.
- **Quick or low-stakes** → don't use Fusion at all; a single direct answer is cheaper and just as good.

Every panel run returns the same structure: a **Final answer** up top, then the audit trail — the judge's
discernment (**Per-panelist assessment / Consensus / Contradictions / Partial coverage / Unique insights /
Blind spots / Verdict**) — with each point attributed to the panelist that raised it (real attribution
restored after anonymized judging), so you can see how the answer was assembled.

## Goal-driven autonomous loops

Fusion answers one question per run, but you can put it inside a goal-driven loop with the `/loop` Claude
Code skill, which keeps working toward a stated goal — self-paced, or on a fixed interval — and calls a
`/fusion` command at each decision point. The two compose directly:

```
# Self-paced: no interval — Claude decides when to iterate until the goal's stop condition is met.
/loop Harden our JWT refresh-rotation design. Each round, run the most important open question through
      /fusion-gpt5.5, apply the synthesis, and move to the next-riskiest unknown. Stop when a fusion
      run surfaces no high-severity blind spots.

# Fixed interval: re-run on a cadence.
/loop 30m /fusion has anything in the incident postmortem changed our root-cause conclusion?
```

To get good results from a goal-loop, put three things in the loop prompt: the **goal**, an explicit
**stop condition**, and the instruction to **act on the synthesis** at each step (not on any single
panelist). The loop holds the goal across iterations; Fusion supplies the high-confidence answer for each
step.

> ⚠️ **Cost compounds in a loop.** Every Fusion run is ~N× a single answer (three panelists + a judge +
> synthesis), so a loop that fuses on every iteration spends quickly. Reserve panel-grade scrutiny for the
> hard decision points — have the loop fuse there and answer cheaper steps directly — and always give it a
> concrete stop condition so it terminates.

## Self-improving loop

The repo can improve *itself*: `/fusion-improve` runs a goal-driven loop that works the backlog in
`improve/roadmap.json` (seeded from `docs/fusion-self-review.md`) — each iteration picks the next item,
designs the fix with Fusion when it's non-trivial, implements it, runs a regression gate, and commits
atomically or reverts. A deterministic driver (`improve/run_iteration.sh`) owns all state, budget, and stop
conditions, so the model proposes the *how* but can't loop forever, commit a regression, or auto-apply a
risky change (those route to a human-approval gate). See [docs/self-improving-loop.md](docs/self-improving-loop.md).

## Provenance (optional, Anchor'd)

Every run produces an audit trail; with `FUSION_ANCHOR=1` you can make it **tamper-evident** by attesting it
to [Anchor'd](https://github.com/SainIndustries) — a hashes-only manifest (panel composition, per-answer
sha256, judge & synthesis hashes, model ids, the SLUG) anchored via `POST /api/anchor`, with raw prompts and
answers never leaving the machine. It's opt-in and purely additive: the local markdown trail stays the record
of truth, and the emitter always exits 0. See [provenance.md](skills/fusion/references/provenance.md).

## Panelist execution & the Claude Fable 5 system prompt

By default this fork runs the two Opus 4.8 panelists as headless `claude` CLI subprocesses loaded with the
Claude Fable 5 system prompt (`skills/fusion/CLAUDE-FABLE-5.md`), via `scripts/run_claude.sh`:

```bash
claude --print --dangerously-skip-permissions --model opus --system-prompt-file CLAUDE-FABLE-5.md "<task>"
```

`--model opus` runs Opus 4.8 (the accessible model) while the system-prompt file gives it the Fable 5
persona — the panel's "Fable-tier" intent. `--dangerously-skip-permissions` lets each panelist research
autonomously with web + bash without permission prompts, the same autonomy the codex panelist has.

> ⚠️ **`--dangerously-skip-permissions` bypasses *all* permission checks for that subprocess.** That's
> deliberate here — a panelist needs to run tools unattended — and each run is contained to a throwaway
> scratch directory so its file writes can't touch your repo. Still, only use this fork on tasks and in
> repos where you're comfortable with panelists executing tools unattended. Override the model with
> `FUSION_CLAUDE_MODEL`, or the prompt file with `FUSION_FABLE5_PROMPT`. If you'd rather not run headless
> CLI subprocesses at all, the skill can spawn in-process Agent subagents instead (no Fable 5 prompt).

## Requirements

- **Claude Code** with the `claude` CLI on your PATH. The Opus panelists are launched as
  `claude --model opus` subprocesses (so they're literally Opus 4.8 regardless of your session model); the
  synthesizer is your session, so run it on **Opus 4.8** for a literal Fable-tier result.
- For the flagship pipeline and persistent experts: the [`codex` CLI](https://github.com/openai/codex)
  installed and logged in to an account with GPT-5.5 access. The runners use `codex exec` (tested against
  `codex-cli` 0.139).
- Optional Gemini panelist (`FUSION_USE_GEMINI=1`): a `gemini` CLI installed and authenticated. Adjust the
  model in `skills/fusion/scripts/run_gemini.sh` to one your account can access (the default is
  `gemini-2.5-pro`, overridable via `GEMINI_MODEL`).

Only the **fallback** (2× Opus 4.8) pipeline is truly zero-setup; the GPT-5.5 judge/panelist and persistent
experts light up once `codex` is installed and authenticated.

## What's in here

```
skills/fusion/
  SKILL.md                  fan out → anonymize → GPT-5.5 judge → Opus synthesize → present
  CLAUDE-FABLE-5.md         the Claude Fable 5 system prompt the Opus panelists load
  scripts/
    detect_panel.sh         picks panel + judge + synthesizer; prints PANEL/JUDGE/SYNTH/SLUG/RUN_DIR
    run_claude.sh           runs an Opus 4.8 panelist via the claude CLI under the Fable 5 system prompt
    run_codex.sh            runs a GPT-5.5 panelist (model-pinned, timeout-bounded), captures its answer
    run_judge.sh            the discernment stage — GPT-5.5 judges; validates output or falls back to Opus
    anonymize.sh            shuffles answers into blind A/B/C labels with a real RNG + durable map.json
    anchor_emit.sh          optional tamper-evident provenance attestation (Anchor'd; opt-in)
    codex_expert.sh         persistent codex domain experts (per-name lock + atomic id write)
    run_gemini.sh           optional Gemini panelist (off unless FUSION_USE_GEMINI=1)
    _lib.sh                 shared helpers (portable timeout shim)
  references/
    panel.md                why independent parallel runs (no lenses) — the panel mechanism
    judge_rubric.md         discernment (the judge) → synthesis (Opus); Track A code / Track B research
    persistent_experts.md   when and how to use persistent codex domain experts
    provenance.md           optional Anchor'd provenance emitter — data model, config, verify
commands/
  fusion.md                 /fusion          (auto-detect)
  fusion-gpt5.5.md          /fusion-gpt5.5   (flagship)
  fusion-opus4.8.md         /fusion-opus4.8  (zero-setup pure-Opus)
  codex-expert.md           /codex-expert    (persistent domain expert)
  fusion-improve.md         /fusion-improve  (self-improving loop)
improve/                    the self-improvement loop: roadmap.json, state.json, run_iteration.sh, check.sh
docs/                       self-review, self-improving-loop design
install.sh                  copies the skill + commands into ~/.claude
```

## Why a panel beats one model

On the DRACO deep-research benchmark, OpenRouter found that fusing model answers consistently beats the
individual models — and that a meaningful chunk of the lift comes from the *synthesis step itself*, not just
from mixing architectures: two independent runs of one model, synthesized, beat that model run once.
Fusion-Fable implements that independence-then-synthesis pipeline locally in Claude Code, and this fork
adds a dedicated discernment stage in front of synthesis — splitting "decide what's right" (GPT-5.5) from
"write the answer" (Opus) so each is done by the model better suited to it.

## Cost & latency

A panel costs roughly N× a single answer in tokens, runs as slow as its slowest panelist, and the judge
stage adds one serial codex call after the parallel fan-out. That's the deliberate trade: spend more to
stop being confidently wrong where that's expensive. For quick or low-stakes questions a single direct
answer is the right call; for long iterative work a persistent codex expert beats both.

## License

MIT — see [LICENSE](LICENSE).
