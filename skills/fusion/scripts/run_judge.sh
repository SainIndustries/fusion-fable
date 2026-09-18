#!/usr/bin/env bash
# run_judge.sh — the DISCERNMENT stage. Runs the judge over the panel's anonymized answers.
#
# This is the middle stage of the Sain Industries Fusion pipeline:
#     fan out (blind panelists) → [ run_judge.sh: discernment ] → Fable 5.1 synthesizes
#
# Default judge: **Claude Fable 5.1**, run as a FRESH headless `claude` subprocess. Running the judge cold —
# instead of having the orchestrator judge inline — keeps discernment blind: the subprocess sees only the
# anonymized answers, not the orchestrator's memory of which panelist ran where. Optional: GPT-6 Astra (codex)
# as the judge, via the [judge] arg or FUSION_JUDGE=astra (the legacy token gpt5.5 is also accepted).
#
# The judge does NOT write the final answer. It produces a structured discernment doc that the Fable 5.1
# synthesizer consumes: per-panelist assessment, consensus, adjudicated contradictions, partial coverage,
# unique insights, blind spots, and a verdict on what's load-bearing vs weak.
#
# Usage:
#   run_judge.sh <task_file> <answers_dir> <output_file> [reasoning_effort] [judge]
#
# - <task_file>    : the original user task, verbatim.
# - <answers_dir>  : a directory of anonymized panelist answers named panelist_A.md, panelist_B.md, ...
#                    ANONYMITY IS THE CALLER'S JOB: write the answers under shuffled A/B/C labels and keep
#                    the label→model map yourself. The judge must not be able to tell which answer came
#                    from its own model family — a Fable judge could otherwise favor the Fable panelist,
#                    and a GPT-6 Astra judge the codex panelist. That's how we neutralize self-preference bias.
# - <output_file>  : where the discernment doc is written (the judge's final message only).
# - reasoning_effort : low | medium | high (default: high). Applies to the codex judge; the claude judge
#                    reasons at its own default and ignores it.
# - judge          : fable5 (default) | astra (gpt5.5 accepted for legacy). Also settable via FUSION_JUDGE.
#
# Exit codes:
#   0   discernment written to <output_file>
#   2   judge CLI not installed             -> caller (the orchestrator) does the discernment inline
#   1   judge ran but failed/empty/off-task -> same inline fallback
#
# The caller (SKILL.md) treats any non-zero exit as "judge unavailable" and has the orchestrating Fable
# session do the discernment itself before synthesizing — a failed judge degrades the run, never breaks it.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"

task_file="${1:?usage: run_judge.sh <task_file> <answers_dir> <output_file> [reasoning_effort] [judge]}"
answers_dir="${2:?usage: run_judge.sh <task_file> <answers_dir> <output_file> [reasoning_effort] [judge]}"
output_file="${3:?usage: run_judge.sh <task_file> <answers_dir> <output_file> [reasoning_effort] [judge]}"
effort="${4:-high}"
judge="${5:-${FUSION_JUDGE:-fable5}}"

case "$judge" in
  fable5)
    if ! command -v claude >/dev/null 2>&1; then
      echo "[run_judge.sh] claude CLI not installed — caller should do the discernment inline." >&2
      exit 2
    fi
    ;;
  astra|gpt5.6|gpt5.5)
    if ! command -v codex >/dev/null 2>&1; then
      echo "[run_judge.sh] codex CLI not installed — caller should do the discernment inline (or use judge=fable5)." >&2
      exit 2
    fi
    ;;
  *)
    echo "[run_judge.sh] unknown judge '$judge' (expected fable5 or astra; legacy gpt5.6/gpt5.5 accepted)." >&2
    exit 2
    ;;
esac

shopt -s nullglob
answers=("$answers_dir"/panelist_*.md)
if [ ${#answers[@]} -eq 0 ]; then
  echo "[run_judge.sh] no panelist_*.md files in $answers_dir — nothing to judge." >&2
  exit 1
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-judge.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Copy the anonymized answers into the judge's sandbox so it can read (and, for code tasks, RUN) them.
cp "$answers_dir"/panelist_*.md "$scratch"/ 2>/dev/null || true

prompt_file="$scratch/judge_prompt.txt"
{
  cat <<'EOF'
You are the JUDGE in a panel pipeline. Several independent experts answered the SAME task below without
seeing each other's work. Your job is DISCERNMENT, not authorship: do not write the final answer — a
separate synthesizer will do that from your analysis. Be rigorous, skeptical, and decisive about what is
actually correct and well-supported versus what is plausible but weak.

The panelist answers are anonymized (Panelist A, B, ...). You do not know which model wrote which, and you
must not guess or favor any "style" — judge only on substance and evidence.

If the task is a coding/artifact task and the answers contain code, RUN it: you have a writable sandbox and
bash. Build/execute each candidate, record what passes and what breaks, and let observed behavior outrank
which one "looks" better. If it genuinely can't be executed here, say so and reason about the seams.

Produce a structured DISCERNMENT doc with exactly these sections:

## Per-panelist assessment
For each panelist (A, B, ...): its approach, what it gets right, where it's wrong/weak/unsupported, and the
quality of its evidence (ran code / cited a primary source / reasoned from memory). One tight paragraph each.

## Consensus
Claims the panelists independently agree on. Independent agreement is the highest-confidence signal — flag
it and note how many converged and whether by different routes.

## Contradictions
Direct disagreements on fact or recommendation. State the competing positions, who holds them, and
ADJUDICATE: which side has better evidence (ran the code, read the source)? If you can't resolve it, say so
and name exactly what would settle it. Never bury a real conflict.

## Partial coverage
Important sub-questions only some panelists engaged.

## Unique insights
Non-obvious, valuable points raised by exactly one panelist — preserve them even if off the majority view.

## Blind spots
What the panel as a whole missed or got wrong, including shared assumptions none questioned. Add one the
panel didn't name if you see it.

## Discernment verdict
The payload for the synthesizer: which specific claims are load-bearing AND well-supported (keep), which
are weak/contradicted (discard or hedge), and the recommended spine for the final answer. Be explicit and
prescriptive — this is what the synthesizer builds on.

=== THE TASK (verbatim) ===
EOF
  cat "$task_file"
  echo
  for f in "$scratch"/panelist_*.md; do
    label="$(basename "$f" .md | sed 's/^panelist_/Panelist /')"
    echo
    echo "=== ${label} ==="
    cat "$f"
    echo
  done
} > "$prompt_file"

if [ "$judge" = "fable5" ]; then
  # Fresh blind Fable 5.1 subprocess: cold context, anonymized answers only. Runs in the scratch dir so any
  # file writes (Track A candidate runs) never touch the repo; wall-clock bounded like every other stage.
  judge_model="${FUSION_CLAUDE_MODEL:-claude-fable-5-1}"
  ( cd "$scratch" && fusion_run_timeout "$(fusion_default_timeout)" claude \
      --print \
      --dangerously-skip-permissions \
      --model "$judge_model" \
      "$(cat "$prompt_file")" ) > "$output_file" 2> "$scratch/stream.log"
  status=$?
else
  # GPT-6 Astra judge via codex. Hermetic codex home (auth only) + ignore user config so the judge can't
  # inherit cross-project context from ~/.codex (Finding #0 — a contaminated judge once confabulated an
  # unrelated project's task).
  judge_model="${JUDGE_MODEL:-gpt-6-astra}"   # override to A/B the codex judge
  if ! fusion_codex_supports_model "$judge_model"; then
    echo "[run_judge.sh] $(fusion_codex_upgrade_hint) — caller should judge with fable5 (or a blind Agent subagent)." >&2
    exit 2
  fi
  export CODEX_HOME="$(fusion_codex_home)"
  fusion_run_timeout "$(fusion_default_timeout)" codex exec \
    --skip-git-repo-check \
    --ignore-user-config \
    --cd "$scratch" \
    -s workspace-write \
    -c tools.web_search=true \
    -c "model_reasoning_effort=$effort" \
    -m "$judge_model" \
    -o "$output_file" \
    - < "$prompt_file" \
    > "$scratch/stream.log" 2>&1
  status=$?
fi

if [ $status -eq 124 ]; then
  echo "[run_judge.sh] $judge judge timed out after $(fusion_default_timeout)s — caller should do the discernment inline." >&2
  exit 1
fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_judge.sh] $judge judge exited $status; tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  cat "$scratch/stream.log" "$output_file" > "$scratch/diag.log" 2>/dev/null
  fusion_diagnose_log "$scratch/diag.log" "run_judge.sh"
  fusion_discard_failed_output "$output_file"
  exit 1
fi

# Validate the discernment actually has the required structure. A judge can return non-empty but off-task
# output — that must trigger the inline fallback, not be synthesized over. Require the load-bearing
# section headers.
missing=""
for h in "Per-panelist assessment" "Consensus" "Contradictions" "Discernment verdict"; do
  grep -qiF "$h" "$output_file" || missing="$missing \"$h\""
done
if [ -n "$missing" ]; then
  echo "[run_judge.sh] judge output missing required sections:${missing} — treating as failed; caller should do the discernment inline." >&2
  exit 1
fi
echo "[run_judge.sh] ok -> $output_file (judge=$judge model=$judge_model, effort=$effort, panelists=${#answers[@]})"
