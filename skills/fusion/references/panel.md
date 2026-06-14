# The panel

Fusion's power comes from **independent answers, synthesized** — not from a clever prompt or assigned
personas. You dispatch the same question to several models at once, each works the problem cold with no
knowledge of the others, a judge does discernment over their answers, and Opus synthesizes a final answer
from that discernment. Independent agreement is high-confidence; independent disagreement is exactly the
signal worth surfacing.

## No lenses, no personas

Do not assign panelists "roles" or "stances" (skeptic, optimizer, first-principles, etc.). That biases
*how* each one reasons artificially and corrupts the very independence that makes the panel work. Pass
every panelist the user's task **verbatim** and let each answer it straight.

The diversity is already there for free. Running the same prompt independently produces different reasoning
paths, different tool calls, and different source selections — even when it's the *same model answering
twice*. (Two independent Opus 4.8 runs synthesized beat a single Opus 4.8 run by a wide margin precisely
because of this.) You don't manufacture diversity; you harvest it from independence. That's also why the
default panel is two Opus runs plus GPT-5.5 rather than reaching for a third model family: same-model
reruns already add real diversity, with no extra CLI or auth to babysit.

## Independence is the rule

Panelists must never see each other's work. Don't show one panelist another's answer, and don't let the
orchestrator pre-digest or summarize the task before handing it over. The judge is the only place the
answers meet. Cross-pollination before the judge defeats the entire mechanism.

## Three roles: panelist, judge, synthesizer

This fork separates the two halves of the old single-judge step, giving each to the model that's better at
it:

- **Panelists** answer the task blind and in parallel.
- **Judge (discernment)** — **GPT-5.5 via codex**, stronger at discrimination. It scores the answers,
  finds consensus and adjudicates contradictions, and decides what's load-bearing vs weak. It does **not**
  write the final answer. If codex is unavailable, Opus does the discernment instead.
- **Synthesizer (final answer)** — **always Opus 4.8**, the orchestrator, better at creative synthesis. It
  writes the final answer grounded in the judge's discernment.

Opus always drives and writes the final answer — the pipeline can't be reversed, since the panelist models
can't call back out to spawn Opus.

## How the Opus panelists run

By default the two Opus 4.8 panelists run as headless `claude` CLI subprocesses
(`scripts/run_claude.sh`) under the **Claude Fable 5 system prompt**, with `--dangerously-skip-permissions`
so each researches autonomously with web + bash — the same autonomy the codex panelist has. They run Opus
4.8 (the accessible model) loaded with the Fable 5 prompt, which is the panel's "Fable-tier" intent. Each
runs in a throwaway scratch dir so its file writes never touch your repo. (Spawning two `Agent` subagents
instead is a supported alternative — same independence, just without the Fable 5 system prompt.)

## Default panel composition

- Panelists: **two independent Opus 4.8 runs** (claude CLI under the Fable 5 prompt) **+ GPT-5.5** (codex),
  all answering in parallel and blind. If codex is absent, the panel is the two Opus runs alone.
- Gemini is **off by default** — set `FUSION_USE_GEMINI=1` to add it as an optional extra panelist when its
  CLI is present and authenticated.
- Judge: **GPT-5.5** (or Opus on fallback). Synthesizer: **Opus 4.8**.

## Anonymize before judging

Because GPT-5.5 is both a panelist and the judge, the judge could otherwise favor its own answer
(self-preference bias). Neutralize it: write the panelist answers out under **shuffled** labels — Panelist
A, B, C — and hand the judge only those. The judge never learns which model wrote which. Keep the
label→model map yourself and restore real attribution only when you (Opus) write the final answer.

## Prompt each panelist gets

Each panelist receives the user's task **verbatim**, plus a short instruction: *research with web search
and bash, then return a complete, self-contained answer; you are one of several independent experts and
will not see the others' work.* Nothing more — no lens, no framing that nudges the conclusion.
