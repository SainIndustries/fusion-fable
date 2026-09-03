# The panel

Fusion's power comes from **independent answers, synthesized** — not from a clever prompt or assigned
personas. You dispatch the same question to several models at once, each works the problem cold with no
knowledge of the others, a judge does discernment over their answers, and Fable 5.1 synthesizes a final
answer from that discernment. Independent agreement is high-confidence; independent disagreement is exactly
the signal worth surfacing.

## No lenses, no personas

Do not assign panelists "roles" or "stances" (skeptic, optimizer, first-principles, etc.). That biases
*how* each one reasons artificially and corrupts the very independence that makes the panel work. Pass
every panelist the user's task **verbatim** and let each answer it straight.

The diversity is real and free: the default panel is deliberately **cross-model** — one Claude Fable 5.1 and
one GPT-5.6 Sol — two different model families, so the same prompt takes genuinely different reasoning paths,
tool calls, and source selections. (Opus 4.8 is the automatic fallback second panelist when codex/GPT-5.6
isn't available.) You don't manufacture diversity with personas; you harvest it from model variety plus
independence.

## Independence is the rule

Panelists must never see each other's work. Don't show one panelist another's answer, and don't let the
orchestrator pre-digest or summarize the task before handing it over. The judge is the only place the
answers meet. Cross-pollination before the judge defeats the entire mechanism.

## Three roles: panelist, judge, synthesizer

This fork separates the two halves of the old single-judge step:

- **Panelists** answer the task blind and in parallel.
- **Judge (discernment)** — **a fresh, blind Claude Fable 5.1 subprocess** by default
  (`scripts/run_judge.sh`). It reads only the anonymized answers — a cold context that never watched the
  fan-out — scores them, finds consensus and adjudicates contradictions, and decides what's load-bearing vs
  weak. It does **not** write the final answer. Set `FUSION_JUDGE=gpt5.6` (or use `/fusion-gpt5.6`) to hand
  discernment to GPT-5.6 via codex instead — cross-model judging. If the judge subprocess fails, the
  orchestrating session does the discernment inline.
- **Synthesizer (final answer)** — **always Claude Fable 5.1**, the orchestrator. It writes the final answer
  grounded in the judge's discernment.

Fable always drives and writes the final answer — the pipeline can't be reversed, since the panelist models
can't call back out to spawn Fable.

## How the Claude panelists run

The Fable 5.1 panelist — and the Opus 4.8 fallback panelist — run as headless `claude` CLI subprocesses
(`scripts/run_claude.sh`) pinned to the real models (`claude-fable-5-1` and `opus`), with
`--dangerously-skip-permissions` so each researches autonomously with web + bash — the same autonomy the
codex panelist has. Each runs in a throwaway scratch dir so its file writes never touch your repo. (Spawning
`Agent` subagents with `model: fable` / `model: opus` instead is a supported alternative — same
independence, in-process.) Override the models with `FUSION_CLAUDE_MODEL` (Fable) and `FUSION_OPUS_MODEL`
(Opus).

## Default panel composition

- Panelists: **one Fable 5.1** (claude CLI) **+ one GPT-5.6 Sol** (codex), both answering in parallel and blind.
  If codex is absent, GPT-5.6 is replaced by an **Opus 4.8** fallback panelist so the panel stays a pair.
- Gemini is **off by default** — set `FUSION_USE_GEMINI=1` to add it as an optional extra panelist when its
  CLI is present and authenticated.
- Judge: **Fable 5.1, fresh blind subprocess** (GPT-5.6 Sol via `FUSION_JUDGE=gpt5.6`). Synthesizer: **Fable 5.1**.

## Anonymize before judging

The judge shares a model family with at least one panelist — a Fable judge with the Fable panelist, a
GPT-5.6 judge with the codex panelist — so an un-blinded judge could favor its own model's answer
(self-preference bias). Neutralize it: write the panelist answers out under **shuffled** labels — Panelist
A, B, C — and hand the judge only those. The judge never learns which model wrote which. Keep the
label→model map yourself and restore real attribution only when you (Fable) write the final answer.

## Prompt each panelist gets

Each panelist receives the user's task **verbatim**, plus a short instruction: *research with web search
and bash, then return a complete, self-contained answer; you are one of several independent experts and
will not see the others' work.* Nothing more — no lens, no framing that nudges the conclusion.
