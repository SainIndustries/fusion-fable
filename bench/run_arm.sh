#!/usr/bin/env bash
# run_arm.sh — run ONE arm (config) on ONE item. Emits result.json with the final answer + per-stage latency.
#
# Usage: run_arm.sh <arm_id> <item_file> <out_dir>
#   <item_file> : a single JSON object {"id":..., "question":..., "gold":...}
#   <out_dir>   : where this run's artifacts + result.json are written
# Env: ARMS_FILE (default bench/arms.jsonl)
#
# Arm kinds (see arms.jsonl):
#   single : run one model, its answer IS the result (no judge/synth) — the Fusion-vs-single baseline.
#   fusion : fan out the panel blind -> anonymize -> judge -> synth. Judge falls back to opus if it fails.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

arm_id="${1:?usage: run_arm.sh <arm_id> <item_file> <out_dir>}"
item_file="${2:?item_file}"
out_dir="${3:?out_dir}"
arms_file="${ARMS_FILE:-$HERE/arms.jsonl}"
mkdir -p "$out_dir"

# --- resolve arm config ---
IFS=$'\t' read -r kind panel judge synth < <(
  jq -r --arg id "$arm_id" 'select(.id==$id) | [.kind,(.panel//[]|join(",")),(.judge//""),(.synth//"")] | @tsv' "$arms_file"
)
[ -n "${kind:-}" ] || { echo "[run_arm] arm '$arm_id' not found in $arms_file" >&2; exit 3; }

item_id="$(jq -r '.id' "$item_file")"
question="$(jq -r '.question' "$item_file")"

# task.txt (verbatim) + the panelist prompt every model gets
printf '%s' "$question" > "$out_dir/task.txt"
bench_panelist_prompt "$question" > "$out_dir/panelist_prompt.txt"

t_start="$(bench_now)"
lat_panel=0; lat_judge=0; lat_synth=0
judge_fellback=false; panel_dropped=0
final_src=""

if [ "$kind" = "single" ]; then
  model="${panel%%,*}"
  ts="$(bench_now)"
  if ! bench_run_model "$model" "$out_dir/panelist_prompt.txt" "$out_dir/answer.md"; then
    echo "[run_arm] single model $model failed for $item_id" >&2
  fi
  lat_panel="$(bench_elapsed "$ts" "$(bench_now)")"
  final_src="$out_dir/answer.md"

else
  # --- fan out the panel, blind and in parallel ---
  ts="$(bench_now)"
  i=0; pids=(); outs=()
  IFS=',' read -ra members <<< "$panel"
  for m in "${members[@]}"; do
    i=$((i+1))
    o="$out_dir/panel_${i}_${m}.md"; outs+=("$o")
    bench_run_model "$m" "$out_dir/panelist_prompt.txt" "$o" >"$out_dir/panel_${i}.log" 2>&1 &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
  lat_panel="$(bench_elapsed "$ts" "$(bench_now)")"

  # count drops (empty outputs = absent panelist, never silent agreement)
  live=()
  for o in "${outs[@]}"; do [ -s "$o" ] && live+=("$o") || panel_dropped=$((panel_dropped+1)); done
  [ ${#live[@]} -ge 1 ] || { echo "[run_arm] all panelists dropped for $item_id" >&2; }

  # --- anonymize ---
  bash "$SCRIPTS_DIR/anonymize.sh" "$out_dir/answers" "${live[@]}" >/dev/null 2>&1 || true

  # --- judge (discernment), with Opus fallback exactly like the shipped pipeline ---
  ts="$(bench_now)"
  if ! bash "$HERE/run_judge_any.sh" "$judge" "$out_dir/task.txt" "$out_dir/answers" "$out_dir/judge.md" "${BENCH_JUDGE_EFFORT:-high}" >"$out_dir/judge.log" 2>&1; then
    echo "[run_arm] judge '$judge' failed/unavailable -> falling back to opus" >&2
    judge_fellback=true
    bash "$HERE/run_judge_any.sh" opus "$out_dir/task.txt" "$out_dir/answers" "$out_dir/judge.md" "${BENCH_JUDGE_EFFORT:-high}" >>"$out_dir/judge.log" 2>&1 || true
  fi
  lat_judge="$(bench_elapsed "$ts" "$(bench_now)")"

  # --- synthesize ---
  ts="$(bench_now)"
  bash "$HERE/run_synth.sh" "$synth" "$out_dir/task.txt" "$out_dir/judge.md" "$out_dir/answers" "$out_dir/answer.md" >"$out_dir/synth.log" 2>&1 || true
  lat_synth="$(bench_elapsed "$ts" "$(bench_now)")"
  final_src="$out_dir/answer.md"
fi

lat_total="$(bench_elapsed "$t_start" "$(bench_now)")"
final_answer=""; answer_chars=0
if [ -s "$final_src" ]; then
  final_answer="$(bench_extract_final "$final_src")"
  answer_chars="$(wc -c < "$final_src" | tr -d ' ')"
fi

jq -n \
  --arg arm "$arm_id" --arg kind "$kind" --arg panel "$panel" --arg judge "$judge" --arg synth "$synth" \
  --arg item "$item_id" --arg final "$final_answer" \
  --argjson lat_total "$lat_total" --argjson lat_panel "$lat_panel" \
  --argjson lat_judge "${lat_judge:-0}" --argjson lat_synth "${lat_synth:-0}" \
  --argjson answer_chars "$answer_chars" --argjson dropped "$panel_dropped" \
  --argjson fellback "$judge_fellback" \
  '{arm:$arm,kind:$kind,panel:$panel,judge:$judge,synth:$synth,item:$item,
    final_answer:$final,answer_chars:$answer_chars,panel_dropped:$dropped,judge_fellback:$fellback,
    latency:{total_s:$lat_total,panel_s:$lat_panel,judge_s:$lat_judge,synth_s:$lat_synth}}' \
  > "$out_dir/result.json"

echo "[run_arm] $arm_id / $item_id -> ${lat_total}s (panel ${lat_panel}s judge ${lat_judge}s synth ${lat_synth}s) drops=$panel_dropped"
