#!/usr/bin/env bash
# run_synth.sh — the SYNTHESIS stage with a swappable synthesizer model (for the "swap the synthesizer" axis).
#
# The skill locks synthesis to Opus 4.8 ("Opus always writes the final answer"). This harness variant lets
# you A/B that invariant by running synthesis with any model, grounded in the judge's discernment.
#
# Usage: run_synth.sh <synth_model> <task_file> <judge_file> <answers_dir> <out_file>
#   synth_model : opus | sonnet | haiku | gpt5.5

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

synth_model="${1:?usage: run_synth.sh <synth_model> <task_file> <judge_file> <answers_dir> <out_file>}"
task_file="${2:?task_file}"
judge_file="${3:?judge_file}"
answers_dir="${4:?answers_dir}"
out_file="${5:?out_file}"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/bench-synth.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
prompt_file="$scratch/synth_prompt.txt"
bench_synth_prompt "$task_file" "$judge_file" "$answers_dir" > "$prompt_file"

case "$synth_model" in
  opus|sonnet|haiku)
    fusion_run_timeout "$(fusion_default_timeout)" claude \
      --print --dangerously-skip-permissions --model "$synth_model" \
      "$(cat "$prompt_file")" > "$out_file" 2> "$scratch/log"
    ;;
  gpt5.5)
    export CODEX_HOME="$(fusion_codex_home)"
    fusion_run_timeout "$(fusion_default_timeout)" codex exec \
      --skip-git-repo-check --ignore-user-config --cd "$scratch" \
      -s workspace-write -c tools.web_search=true \
      -c "model_reasoning_effort=${BENCH_CODEX_EFFORT:-medium}" -m "${CODEX_PANELIST_MODEL:-gpt-5.5}" \
      -o "$out_file" - < "$prompt_file" > "$scratch/log" 2>&1
    ;;
  *) echo "[run_synth] unknown synth model: $synth_model" >&2; exit 64 ;;
esac

status=$?
if [ $status -eq 124 ]; then echo "[run_synth] synth timed out" >&2; exit 1; fi
if [ $status -ne 0 ] || [ ! -s "$out_file" ]; then
  echo "[run_synth] synth exited $status; tail:" >&2; tail -20 "$scratch/log" >&2; exit 1
fi
echo "[run_synth] ok -> $out_file (synth=$synth_model)"
