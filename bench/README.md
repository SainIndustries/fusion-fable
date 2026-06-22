# Fusion benchmark harness (`bench/`)

Benchmarks the **shipped Fusion pipeline** against single models and against ablated configs of itself, on
public benchmarks, with a **blind LLM-as-judge** grader and **paired statistics**. It answers four questions:

1. **Fusion vs single model** — does the pipeline actually beat one Opus 4.8 (or one GPT-5.5) call, and by
   how much per dollar/second?
2. **Swap the panel** — does adding Gemini / a 3rd Opus / dropping codex change quality?
3. **Swap the judge** — GPT-5.5 vs Opus discernment.
4. **Swap the synthesizer** — does the "Opus always writes" invariant hold, or is a cheaper synth fine?

It drives the **real** skill scripts (`skills/fusion/scripts/run_claude.sh`, `run_codex.sh`, `run_gemini.sh`,
`anonymize.sh`) so you're measuring the actual pipeline, not a reimplementation. The only added stages are a
swappable judge (`run_judge_any.sh`) and synthesizer (`run_synth.sh`) — the skill normally has the
orchestrating Opus do those inline, so they have to be scripted to be A/B-able.

## Why it's built the way it is

Fusion is a **stochastic pipeline**, not a model: two "identical" runs diverge by design (that divergence is
the mechanism). The two things that wreck an ensemble benchmark are **run-to-run variance** and **benchmark
contamination**. Everything here is built to control those:

- **k repeats per (arm, item)** (default 3) → report mean, and the paired tests average correctness per item
  across repeats before comparing. One run per arm is uninformative.
- **Paired design** — every arm runs the *same* items; comparisons are paired (bootstrap CI + exact McNemar)
  so item-difficulty variance cancels.
- **Blind grader** — the grader sees only (question, gold, candidate); never the arm id, so it can't prefer
  "the fusion one". Set `GRADER_MODEL` to a model *not* in the arm, and double-grade a sample for κ.
- **Contamination tripwire** — include the closed-reasoning slice (GPQA/AIME). Any public set may be in
  training data, which inflates single-model baselines and *shrinks Fusion's apparent lift*; say so in the
  writeup.

## The metric that matters most

Fusion's value proposition isn't "+3% accuracy" — it's "**stops being confidently wrong**." So the headline
isn't only `acc`; it's **`halluc` = incorrect / attempted** (wrong when the system committed) and
**`na%`**. A pipeline that converts confident-wrong answers into "I'm not sure" wins even at equal accuracy.
That's why **SimpleQA** (which has a `not_attempted` bucket) is the primary slice.

## Task set

Recommended 3-slice set, ~45 items each (`tasks/fetch_tasks.sh`):

| Slice | Source | Role | Why |
|---|---|---|---|
| **SimpleQA** | `fetch_tasks.sh simpleqa` | calibration (PRIMARY) | short factual Q + `not_attempted` → the confidently-wrong signal |
| **FRAMES** | `fetch_tasks.sh frames` | web research (PRIMARY) | multi-hop retrieval+reasoning; rewards the tool-using panel |
| **GPQA-Diamond** | `fetch_tasks.sh gpqa` | reasoning control | no web helps; contamination tripwire |

`tasks/smoke.jsonl` is a tiny trivially-verifiable set for validating the harness end-to-end — **not** a
benchmark; expect every arm near 100%.

## Run it

```bash
# 0. smoke-test the plumbing (cheap, ~8 trivial items)
bash bench/run_bench.sh --tasks bench/tasks/smoke.jsonl \
  --arms "single-opus,fusion-default" --repeats 1
python3 bench/score.py bench/results/smoke/graded.jsonl --baseline fusion-default

# 1. PILOT — the headline question only, before spending on the full matrix
bash bench/tasks/fetch_tasks.sh simpleqa 20
bash bench/run_bench.sh --tasks bench/tasks/simpleqa.jsonl \
  --arms "single-opus,single-gpt5.5,fusion-default" --repeats 3
python3 bench/score.py bench/results/simpleqa/graded.jsonl --baseline fusion-default

# 2. FULL matrix (only if the pilot shows real lift) — omit --arms to run all 10
bash bench/tasks/fetch_tasks.sh all 45
bash bench/run_bench.sh --tasks bench/tasks/simpleqa.jsonl --repeats 5
python3 bench/score.py bench/results/simpleqa/graded.jsonl --baseline fusion-default
```

`run_bench.sh` is **resumable** — a killed run skips already-graded `(arm,item,repeat)` keys on restart.

### Inter-grader agreement (κ)

Re-grade with a second model and check the graders agree before trusting any delta:

```bash
GRADER_MODEL=opus bash bench/run_bench.sh --tasks bench/tasks/simpleqa.jsonl \
  --arms "single-opus,single-gpt5.5,fusion-default" --repeats 3 --out bench/results/simpleqa_opusgrader
python3 bench/score.py bench/results/simpleqa/graded.jsonl \
  --kappa bench/results/simpleqa_opusgrader/graded.jsonl
```

κ < 0.6 means the scores are noisy — fix the rubric in `grade.sh` before believing arm rankings.

## Reading `score.py`

- **`acc`** accuracy over all graded items · **`acc|att`** accuracy when it committed · **`na%`**
  not-attempted · **`halluc`** wrong-when-attempted (lower is better) · **`lat_s`** mean wall-clock ·
  **`chars`** answer size · **`drops`** dropped panelists · **`jfb`** judge-fell-back-to-Opus count.
- **PAIRED vs baseline** — per-item accuracy delta with a bootstrap 95% CI and exact McNemar. A `*` means
  the CI excludes 0 (significant at ~95%). **This is the only valid way to claim arm A beat arm B here.**

## Decision rule (pre-register before running)

Ship a config change only if it **beats `fusion-default` by a CI that excludes 0 on a PRIMARY slice** and
**does not regress `halluc`**. Pre-committing this stops post-hoc cherry-picking across 10 arms.

## Cost accounting (known limitation)

**Latency is measured and authoritative.** Token/$ cost is **not** yet captured — the skill scripts call the
CLIs in text mode. To get real usage, the cleanest upgrade is to run the claude panelists/synth with
`--output-format json` (answer in `.result`, tokens in `.usage`) and parse codex's usage from its stream
log, then sum per stage. Until then use `lat_s` and `chars` as the efficiency proxies, and remember a
`fusion` arm is ~3–4 model calls vs 1 for a `single` arm when reasoning about spend.

## Files

| File | Role |
|---|---|
| `arms.jsonl` | the config matrix (tier 0 baselines, tier 1 shipped, tier 2 ablations) |
| `run_bench.sh` | driver: arms × items × repeats → grade → `results/<tasks>/graded.jsonl` |
| `run_arm.sh` | one arm on one item (single, or fan-out→judge→synth) + per-stage latency |
| `run_judge_any.sh` | discernment with a swappable judge model (same rubric as the shipped judge) |
| `run_synth.sh` | synthesis with a swappable synthesizer model |
| `grade.sh` | blind LLM-judge grader → `correct`/`incorrect`/`not_attempted` |
| `score.py` | per-arm metrics + paired bootstrap + McNemar + κ (pure stdlib) |
| `lib.sh` | prompt templates, judge rubric, model dispatch, helpers |
| `tasks/fetch_tasks.sh` | pull SimpleQA / FRAMES / GPQA slices (gitignored) |
| `tasks/smoke.jsonl` | tiny plumbing-test set (not a benchmark) |
