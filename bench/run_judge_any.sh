#!/usr/bin/env bash
# run_judge_any.sh — the DISCERNMENT stage, but with a swappable judge model (for the "swap the judge" axis).
#
# The shipped skills/fusion/scripts/run_judge.sh is codex-only. This harness variant uses the SAME rubric
# (bench_judge_prompt in lib.sh) and dispatches to any judge model so GPT-5.5 vs Opus vs Sonnet judging is
# apples-to-apples. Validates the required section headers and exits non-zero on failure so the caller can
# fall back to an Opus judge — same contract as the shipped script.
#
# Usage: run_judge_any.sh <judge_model> <task_file> <answers_dir> <out_file> [effort]
#   judge_model : gpt5.5 | opus | sonnet | haiku
# Exit: 0 ok | 2 required CLI missing | 1 ran but failed/empty/off-task

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

judge_model="${1:?usage: run_judge_any.sh <judge_model> <task_file> <answers_dir> <out_file> [effort]}"
task_file="${2:?task_file}"
answers_dir="${3:?answers_dir}"
out_file="${4:?out_file}"
effort="${5:-high}"

shopt -s nullglob
answers=("$answers_dir"/panelist_*.md)
[ ${#answers[@]} -ge 1 ] || { echo "[run_judge_any] no panelist_*.md in $answers_dir" >&2; exit 1; }

scratch="$(mktemp -d "${TMPDIR:-/tmp}/bench-judge.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
prompt_file="$scratch/judge_prompt.txt"
bench_judge_prompt "$task_file" "$answers_dir" > "$prompt_file"

case "$judge_model" in
  gpt5.5)
    command -v codex >/dev/null 2>&1 || { echo "[run_judge_any] codex not installed" >&2; exit 2; }
    export CODEX_HOME="$(fusion_codex_home)"
    fusion_run_timeout "$(fusion_default_timeout)" codex exec \
      --skip-git-repo-check --ignore-user-config --cd "$scratch" \
      -s workspace-write -c tools.web_search=true \
      -c "model_reasoning_effort=$effort" -m "${JUDGE_MODEL:-gpt-5.5}" \
      -o "$out_file" - < "$prompt_file" > "$scratch/log" 2>&1
    ;;
  opus|sonnet|haiku)
    command -v claude >/dev/null 2>&1 || { echo "[run_judge_any] claude not installed" >&2; exit 2; }
    fusion_run_timeout "$(fusion_default_timeout)" claude \
      --print --dangerously-skip-permissions --model "$judge_model" \
      "$(cat "$prompt_file")" > "$out_file" 2> "$scratch/log"
    ;;
  *) echo "[run_judge_any] unknown judge model: $judge_model" >&2; exit 2 ;;
esac

status=$?
if [ $status -eq 124 ]; then echo "[run_judge_any] judge timed out" >&2; exit 1; fi
if [ $status -ne 0 ] || [ ! -s "$out_file" ]; then
  echo "[run_judge_any] judge exited $status; tail:" >&2; tail -20 "$scratch/log" >&2; exit 1
fi

missing=""
for h in "Per-panelist assessment" "Consensus" "Contradictions" "Discernment verdict"; do
  grep -qiF "$h" "$out_file" || missing="$missing \"$h\""
done
[ -z "$missing" ] || { echo "[run_judge_any] judge missing sections:${missing}" >&2; exit 1; }
echo "[run_judge_any] ok -> $out_file (judge=$judge_model, effort=$effort, panelists=${#answers[@]})"
