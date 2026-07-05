#!/usr/bin/env bash
# run_dual_judge.sh — DUAL discernment: run TWO judges of different model families over the same
# anonymized answers, in parallel, blind. Diversity of judgment on top of diversity of thought.
#
#     fan out (blind panelists) → [ run_dual_judge.sh: Fable 5 judge ∥ GPT-5.5 judge ] → Fable 5 synthesizes
#
# Two independent adjudicators catch different things: a Fable judge and a GPT-5.5 judge reason from
# different priors, so consensus BETWEEN the judges is a strong signal and their disagreements flag exactly
# where the synthesizer must decide. The Fable 5 session still writes the final answer, now grounded in
# BOTH discernment docs. Neither judge is the synthesizer — that invariant is preserved.
#
# Usage:
#   run_dual_judge.sh <task_file> <answers_dir> <out_dir> [reasoning_effort] [judges_csv]
#
# - <out_dir>       : both discernments are written here as judge_fable5.md and judge_gpt5.5.md.
# - reasoning_effort: low|medium|high (default high) — passed to each judge.
# - judges_csv      : comma-separated judge list (default "fable5,gpt5.5", or $FUSION_JUDGES).
#
# Exit codes:
#   0   at least one discernment written (partial dual-judge is still useful; the missing one is absent)
#   1   BOTH judges failed/unavailable      -> caller does inline discernment per SKILL.md
#
# A judge that fails is ABSENT, never silently treated as agreement — same rule as a dropped panelist.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"

task_file="${1:?usage: run_dual_judge.sh <task_file> <answers_dir> <out_dir> [effort] [judges_csv]}"
answers_dir="${2:?usage: run_dual_judge.sh <task_file> <answers_dir> <out_dir> [effort] [judges_csv]}"
out_dir="${3:?usage: run_dual_judge.sh <task_file> <answers_dir> <out_dir> [effort] [judges_csv]}"
effort="${4:-high}"
judges_csv="${5:-${FUSION_JUDGES:-fable5,gpt5.5}}"

mkdir -p "$out_dir"
IFS=',' read -r -a judges <<< "$judges_csv"

pids=(); outs=()
for j in "${judges[@]}"; do
  j="$(echo "$j" | tr -d '[:space:]')"; [ -z "$j" ] && continue
  out="$out_dir/judge_${j}.md"
  echo "[run_dual_judge] launching $j judge -> $out" >&2
  # each judge is a fresh blind subprocess (run_judge.sh); run them concurrently
  bash "$HERE/run_judge.sh" "$task_file" "$answers_dir" "$out" "$effort" "$j" \
      > "$out_dir/judge_${j}.log" 2>&1 &
  pids+=("$!"); outs+=("$out:$j")
done

ok=0
for i in "${!pids[@]}"; do
  wait "${pids[$i]}"; rc=$?
  out="${outs[$i]%%:*}"; j="${outs[$i]##*:}"
  if [ "$rc" -eq 0 ] && [ -s "$out" ]; then
    echo "[run_dual_judge] $j judge OK ($(wc -c < "$out") bytes)" >&2
    ok=$((ok+1))
  else
    echo "[run_dual_judge] $j judge FAILED (rc=$rc) — treated as ABSENT, not agreement" >&2
    rm -f "$out"
  fi
done

if [ "$ok" -eq 0 ]; then
  echo "[run_dual_judge] both judges unavailable — caller must do inline discernment." >&2
  exit 1
fi
echo "[run_dual_judge] $ok/${#judges[@]} discernments written to $out_dir" >&2
exit 0
