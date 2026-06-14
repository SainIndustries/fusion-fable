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

## What changed from upstream

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

Several ways, all equivalent under the hood:

- **Natural language** — just ask. The skill auto-triggers and picks the richest pipeline:
  > "Run this through Fusion: is it safe to `ALTER TABLE … ADD COLUMN` on a 200M-row Postgres table in prod?"
- **Slash commands:**
  ```
  /fusion           <prompt>   # auto-detect the richest pipeline
  /fusion-gpt5.5    <prompt>   # flagship: 2× Opus 4.8 + GPT-5.5, GPT-5.5 judges, Opus synthesizes
  /fusion-opus4.8   <prompt>   # zero-setup: 2× Opus 4.8, Opus judges + synthesizes (no codex)
  ```
- **Persistent codex expert** — for long *iterative* work, not a one-shot question:
  ```
  /codex-expert payments-debugger  find where retries can double-charge in src/payments/
  /codex-expert payments-debugger  now propose a fix with a test   # same expert, remembers the last turn
  ```

Every panel run returns the same structure: a **Final answer** up top, then the audit trail — the judge's
discernment (**Per-panelist assessment / Consensus / Contradictions / Partial coverage / Unique insights /
Blind spots / Verdict**) — with each point attributed to the panelist that raised it (real attribution
restored after anonymized judging), so you can see how the answer was assembled.

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
    detect_panel.sh         picks panel + judge + synthesizer; prints PANEL/JUDGE/SYNTH/SLUG
    run_claude.sh           runs an Opus 4.8 panelist via the claude CLI under the Fable 5 system prompt
    run_codex.sh            runs a GPT-5.5 panelist (web + bash), captures its answer
    run_judge.sh            the discernment stage — GPT-5.5 judges the anonymized answers
    codex_expert.sh         persistent codex domain experts (create/resume named sessions)
    run_gemini.sh           optional Gemini panelist (off unless FUSION_USE_GEMINI=1)
  references/
    panel.md                why independent parallel runs (no lenses) — the panel mechanism
    judge_rubric.md         discernment (the judge) → synthesis (Opus); Track A code / Track B research
    persistent_experts.md   when and how to use persistent codex domain experts
commands/
  fusion.md                 /fusion          (auto-detect)
  fusion-gpt5.5.md          /fusion-gpt5.5   (flagship)
  fusion-opus4.8.md         /fusion-opus4.8  (zero-setup pure-Opus)
  codex-expert.md           /codex-expert    (persistent domain expert)
install.sh                  copies the above into ~/.claude
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
