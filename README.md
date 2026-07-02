# Fusion-Fable (Sain Industries fork)

**Fuse a cross-model panel of frontier models into one Fable-tier answer — judged blind, synthesized by
Fable 5.**

Fusion-Fable is a [Claude Code](https://claude.com/claude-code) skill that runs a hard question through a
**panel → judge → synthesize** pipeline. The same prompt is dispatched to a deliberately **cross-model
panel** *in parallel* — one Claude Fable 5, one Claude Opus 4.8, one GPT-5.5 (via the `codex` CLI) — each
answering independently with web search and bash, none seeing the others' work. Then a **fresh, blind
Claude Fable 5 subprocess judges** the anonymized answers into a structured discernment (consensus,
contradictions, partial coverage, unique insights, blind spots, verdict), and **your Fable 5 session
synthesizes** the final answer grounded in that discernment.

Now that **Fable 5 is generally available**, the Claude panelists run the *real* models — the old
workaround (Opus 4.8 loaded with a Fable 5 persona prompt) is retired to a legacy fallback.

The mechanism is **independence, then discernment, then synthesis**. The diversity that makes a panel beat
a single model is harvested, not manufactured: three different models given the same prompt take three
genuinely different reasoning paths, tool calls, and source selections. So there are no contrived "lenses"
or personas; every panelist gets the task verbatim and answers it straight.

```
            ┌─ Fable 5 panelist ───┐
prompt ─fan─┼─ Opus 4.8 panelist ──┼─→ Fable 5 JUDGE ───→ Fable 5 SYNTHESIZE ─→ final answer
       out  └─ GPT-5.5 panelist ───┘   (fresh blind          (creative answer,
   (web + bash, independent, blind)     subprocess:            grounded in the
                                        scores, consensus,     discernment)
                                        contradictions,
                                        verdict — no answer)
```

**Why the judge is a separate, cold context.** Discernment and synthesis are different jobs even when one
model does both: the judge runs as a fresh headless Fable 5 subprocess that sees *only* the anonymized
answers — it never watched the fan-out, so it can't be anchored by it — while the synthesizer is your warm
session, accountable for the final answer. Prefer cross-model judging? `FUSION_JUDGE=gpt5.5` (or
`/fusion-gpt5.5`) hands discernment to GPT-5.5 instead. The judge never authors the final answer.

**The invariant still holds:** Fable 5 always writes the final answer and always drives — the pipeline
can't be reversed, because the panelist models can't call back out to spawn Fable. The judge is an
intermediate discernment stage that Fable invokes and stays in control of. If the judge subprocess is
unavailable or fails, your session does the discernment inline, so a missing judge degrades the run rather
than breaking it.

## When Fusion runs (and when it doesn't)

Fable 5 is the frontier model — for most questions, **a single direct Fable 5 answer is the default** and
Fusion should stay out of the way. The skill is therefore gated two ways:

- **Explicit invocation only.** The skill triggers when you ask for it — you say "fusion", use a `/fusion`
  command, or explicitly request a multi-model / panel / ensemble answer. It no longer auto-triggers just
  because a question looks hard.
- **Fable 5 drives, or nobody does.** The synthesizer is your session model, so running Fusion from an
  Opus or Sonnet session would silently downgrade the result. The skill checks the session model first and
  refuses to run from a non-Fable session (switch with `/model fable`) unless you explicitly override.

Reach for Fusion when you want **cross-model diversity** (GPT-5.5's and Opus 4.8's independent takes,
adjudicated against a cold Fable run) or when the stakes justify N× scrutiny on something **harder than one
Fable run should carry alone** — a risky migration, a design call you can't cheaply undo, a debugging
conclusion that would be expensive to get confidently wrong.

## What's different about this fork

Upstream Fusion has one Claude model both judge the panel and write the final answer, in one context. This
fork keeps **discernment and synthesis in separate contexts** — a blind cold judge that only sees
anonymized answers, and a warm synthesizer accountable for the final deliverable. Around that split sit a
few operational changes:

- **Cross-model panel.** One Fable 5 + one Opus 4.8 + one GPT-5.5 — three different models, two families,
  maximum diversity per panelist. Gemini stays opt-in (`FUSION_USE_GEMINI=1`).
- **Split judge / synthesizer.** A fresh blind Fable 5 subprocess does discernment; your Fable 5 session
  does synthesis. GPT-5.5 judging is one flag away (`FUSION_JUDGE=gpt5.5` / `/fusion-gpt5.5`).
- **Real Claude panelists** run as headless `claude --model claude-fable-5` / `--model opus` CLI
  subprocesses (with `--dangerously-skip-permissions`), instead of in-process Agent subagents — see the
  note below.
- **Anonymized judging** — panelist answers reach the judge as shuffled Panelist A/B/C, so a judge can't
  favor its own model family's answer (Fable judge vs the Fable panelist, GPT-5.5 judge vs the codex one).
- **Persistent codex domain experts** — `/codex-expert` and `scripts/codex_expert.sh` keep a long-lived
  codex session for iterative, context-heavy work, as an alternative to throwaway subagents.
- **Graceful judge fallback** — if the judge subprocess fails, your session does the discernment inline.
- **Explicit-only triggering + a Fable-session gate** — see "When Fusion runs" above.

## The pipelines

| Condition | Panelists | Judge | Synthesizer | Requires |
| --- | --- | --- | --- | --- |
| **flagship** (default) | Fable 5 + Opus 4.8 + GPT-5.5 | **Fable 5** (fresh blind subprocess) | Fable 5 | `claude` + `codex` CLIs |
| **fallback** (no codex) | Fable 5 + Opus 4.8 | Fable 5 | Fable 5 | just the `claude` CLI |
| **GPT-5.5-judged** (`FUSION_JUDGE=gpt5.5` / `/fusion-gpt5.5`) | Fable 5 + Opus 4.8 + GPT-5.5 | **GPT-5.5** | Fable 5 | `claude` + `codex` CLIs |
| **+ gemini** (`FUSION_USE_GEMINI=1`) | + Gemini 3.1 Pro | (unchanged) | Fable 5 | + the `gemini` CLI |

`scripts/detect_panel.sh` auto-detects which CLIs are installed and prints the richest pipeline available,
falling back gracefully when one is missing.

## Harness variants — models will keep changing

Models come and go; the pipeline doesn't. Everything that distinguishes one Fusion harness from another —
panel composition, judge, model strings — is an env knob, so **each harness is a named preset file** in
`skills/fusion/variants/*.env`, selectable per run:

```bash
FUSION_VARIANT=opus4.8-era   # …then invoke /fusion as usual, or:
/fusion-variant opus4.8-era  <prompt>   # first word = variant, rest = task
```

Shipped presets:

| Variant | Panel | Judge | Notes |
| --- | --- | --- | --- |
| `fable5-crossmodel` | Fable 5 + Opus 4.8 + GPT-5.5 | Fable 5 | the default, given a name |
| `fable5-gpt5.5-judged` | Fable 5 + Opus 4.8 + GPT-5.5 | GPT-5.5 | cross-family judging (`/fusion-gpt5.5`) |
| `fable5-duo` | Fable 5 + Opus 4.8 | Fable 5 | claude-CLI only (`/fusion-fable5`) |
| `opus4.8-era` | 2× Opus 4.8 (Fable persona) + GPT-5.5 | GPT-5.5 | the original pre-Fable-GA harness |

Presets set *defaults* — anything you export explicitly still wins — and may compose (`FUSION_VARIANT=…`
plus `FUSION_USE_GEMINI=1`, a different `FUSION_TIMEOUT`, etc.). **When the next model era arrives** (a new
Claude tier, a new GPT, a new CLI), the play is: copy the closest preset, point its model strings at the
new thing, commit it on `main` — one file, no branches. If a new model needs a genuinely new *runner*
(different CLI), add a `run_<cli>.sh` and reference its panel token from the preset.

Repo conventions around this:

- **`main`** always holds the current-best default harness *plus every preset* — old harnesses stay
  runnable from main via `FUSION_VARIANT`, sharing all script fixes.
- **`era/*` tags** freeze each milestone immutably (`era/opus4.8` = the pre-Fable harness,
  `era/fable5-crossmodel` = this one) — check one out to reproduce a full repo state exactly.
- **`dev`** trails at the previous era's tip as a working branch for archaeology and back-porting; it is
  not where new work lands.

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

Run your Claude Code session on **Fable 5** (`/model fable`) — the skill's gate requires it, and the
synthesizer is your session model. Then invoke it explicitly — three equivalent ways:

- **Natural language** — ask for it by name:
  > "Run this through Fusion: is it safe to `ALTER TABLE … ADD COLUMN` on a 200M-row Postgres table in prod?"
- **Slash commands:**
  ```
  /fusion           <prompt>   # cross-model panel, Fable judges + synthesizes (recommended default)
  /fusion-gpt5.5    <prompt>   # same panel, but GPT-5.5 judges instead of Fable
  /fusion-fable5    <prompt>   # zero-setup: Fable 5 + Opus 4.8 via claude CLI only (no codex)
  /fusion-variant   <name> <prompt>   # any named harness preset from skills/fusion/variants/
  ```
- **Persistent codex expert** — for long *iterative* work, not a one-shot question:
  ```
  /codex-expert payments-debugger  find where retries can double-charge in src/payments/
  /codex-expert payments-debugger  now propose a fix with a test   # same expert, remembers the last turn
  ```

### Which one do I reach for?

- **Most questions — even hard ones** → no Fusion at all. A single direct Fable 5 answer is cheaper,
  faster, and usually just as good. This is the default.
- **One high-stakes question** where being confidently wrong is expensive, or where you want GPT-5.5's and
  Opus 4.8's independent takes cross-checked against Fable — a design call, a risky migration, a subtle
  debugging conclusion → `/fusion`. One shot, maximum scrutiny.
- **You want the adjudicator to be a different model family than the synthesizer** → `/fusion-gpt5.5`
  (same panel, GPT-5.5 judges).
- **codex offline / capped, or you want an all-Claude run** → `/fusion-fable5`.
- **A long thread on one domain** where context should accumulate across many turns → `/codex-expert`.

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

## Panelist execution

The Fable 5 and Opus 4.8 panelists — and the blind Fable 5 judge — run as headless `claude` CLI
subprocesses pinned to the real models, via `scripts/run_claude.sh` and `scripts/run_judge.sh`:

```bash
claude --print --dangerously-skip-permissions --model claude-fable-5 "<task>"   # Fable panelist / judge
claude --print --dangerously-skip-permissions --model opus            "<task>"  # Opus panelist
```

`--dangerously-skip-permissions` lets each panelist research autonomously with web + bash without
permission prompts, the same autonomy the codex panelist has.

> ⚠️ **`--dangerously-skip-permissions` bypasses *all* permission checks for that subprocess.** That's
> deliberate here — a panelist needs to run tools unattended — and each run is contained to a throwaway
> scratch directory so its file writes can't touch your repo. Still, only use this fork on tasks and in
> repos where you're comfortable with panelists executing tools unattended. Override the models with
> `FUSION_CLAUDE_MODEL` (Fable panelist + judge) and `FUSION_OPUS_MODEL` (Opus panelist). If you'd rather
> not run headless CLI subprocesses at all, the skill can spawn in-process Agent subagents with
> `model: fable` / `model: opus` instead.

**Legacy fallback (no Fable 5 access):** set `FUSION_CLAUDE_MODEL=opus` and
`FUSION_FABLE5_PROMPT=skills/fusion/CLAUDE-FABLE-5.md` to reproduce the pre-GA behavior — Opus 4.8 loaded
with the Fable 5 persona prompt. By default the persona file is unused; the real model brings its own
system prompt.

## Requirements

- **Claude Code** with the `claude` CLI on your PATH and an account with **Fable 5 access**. The Claude
  panelists and the blind judge are launched as `claude --model claude-fable-5` / `--model opus`
  subprocesses; the synthesizer is your session, so run it on **Fable 5** (`/model fable`) — the skill's
  gate enforces this.
- For the GPT-5.5 panelist (and the optional GPT-5.5 judge) plus persistent experts: the
  [`codex` CLI](https://github.com/openai/codex) installed and logged in to an account with GPT-5.5 access.
  The runners use `codex exec` (tested against `codex-cli` 0.139).
- Optional Gemini panelist (`FUSION_USE_GEMINI=1`): a `gemini` CLI installed and authenticated. Adjust the
  model in `skills/fusion/scripts/run_gemini.sh` to one your account can access (the default is
  `gemini-2.5-pro`, overridable via `GEMINI_MODEL`).

Only the **fallback** (Fable 5 + Opus 4.8) pipeline is truly zero-setup; the GPT-5.5 panelist, optional
GPT-5.5 judge, and persistent experts light up once `codex` is installed and authenticated.

## What's in here

```
skills/fusion/
  SKILL.md                  gate → fan out → anonymize → blind Fable judge → Fable synthesize → present
  CLAUDE-FABLE-5.md         LEGACY: the Fable 5 persona prompt (only used via FUSION_FABLE5_PROMPT)
  scripts/
    detect_panel.sh         picks panel + judge + synthesizer; prints PANEL/JUDGE/SYNTH/SLUG/RUN_DIR
    run_claude.sh           runs a Claude panelist via the claude CLI (Fable 5 default; opus for Opus 4.8)
    run_codex.sh            runs a GPT-5.5 panelist (model-pinned, timeout-bounded), captures its answer
    run_judge.sh            the discernment stage — blind Fable 5 judge (gpt5.5 optional); validates output
    anonymize.sh            shuffles answers into blind A/B/C labels with a real RNG + durable map.json
    anchor_emit.sh          optional tamper-evident provenance attestation (Anchor'd; opt-in)
    codex_expert.sh         persistent codex domain experts (per-name lock + atomic id write)
    run_gemini.sh           optional Gemini panelist (off unless FUSION_USE_GEMINI=1)
    _lib.sh                 shared helpers (portable timeout shim)
  variants/
    fable5-crossmodel.env   the default harness, as a named preset
    fable5-gpt5.5-judged.env  cross-family judging (GPT-5.5 adjudicates)
    fable5-duo.env          claude-CLI-only panel
    opus4.8-era.env         the original pre-Fable-GA harness, preserved
  references/
    panel.md                why independent parallel runs (no lenses) — the panel mechanism
    judge_rubric.md         discernment (the judge) → synthesis (Fable); Track A code / Track B research
    persistent_experts.md   when and how to use persistent codex domain experts
    provenance.md           optional Anchor'd provenance emitter — data model, config, verify
commands/
  fusion.md                 /fusion          (cross-model panel, Fable judges — default)
  fusion-gpt5.5.md          /fusion-gpt5.5   (same panel, GPT-5.5 judges)
  fusion-fable5.md          /fusion-fable5   (zero-setup all-Claude: Fable 5 + Opus 4.8)
  fusion-variant.md         /fusion-variant  (run any named harness preset)
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
Fusion-Fable implements that independence-then-synthesis pipeline locally in Claude Code — leaning into the
architecture-mixing half too, with a three-model panel — and this fork adds a dedicated discernment stage
in front of synthesis: "decide what's right" happens in a blind cold context, "write the answer" in the
accountable warm one.

## Cost & latency

A panel costs roughly N× a single answer in tokens, runs as slow as its slowest panelist, and the judge
stage adds one serial subprocess call after the parallel fan-out. That's the deliberate trade: spend more to
stop being confidently wrong where that's expensive. Now that Fable 5 is the frontier model, a single
direct answer is the right call for most questions — even hard ones; for long iterative work a persistent
codex expert beats both.

## License

MIT — see [LICENSE](LICENSE).
