#!/usr/bin/env bash
# run_bench.sh — top-level driver. Runs <arms> x <items> x <repeats>, grades each, appends one line per run
# to results/graded.jsonl. Resumable: skips a (arm,item,repeat) whose graded line already exists.
#
# Usage:
#   run_bench.sh --tasks bench/tasks/smoke.jsonl [--arms "single-opus,fusion-default"] [--repeats 3] [--out results/run1]
#
# Defaults: all arms in arms.jsonl, repeats=3, out=bench/results/<tasks-basename>.
#
# Cost/latency warning: a fusion arm is ~3-4 model calls; arms x items x repeats multiplies fast. Start with
# the PILOT (single-opus, single-gpt5.5, fusion-default on a 20-item slice, repeats=3) before the full matrix.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
arms_file="${ARMS_FILE:-$HERE/arms.jsonl}"
tasks=""; arms_csv=""; repeats=3; out=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tasks)   tasks="$2"; shift 2 ;;
    --arms)    arms_csv="$2"; shift 2 ;;
    --repeats) repeats="$2"; shift 2 ;;
    --out)     out="$2"; shift 2 ;;
    *) echo "[run_bench] unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$tasks" ] && [ -s "$tasks" ] || { echo "[run_bench] --tasks <file.jsonl> required" >&2; exit 64; }
[ -n "$out" ] || out="$HERE/results/$(basename "$tasks" .jsonl)"
mkdir -p "$out"
graded="$out/graded.jsonl"; touch "$graded"

# arms to run (built with a while-read loop so it works on macOS's stock bash 3.2 — no mapfile)
arms=()
if [ -n "$arms_csv" ]; then
  IFS=',' read -ra arms <<< "$arms_csv"
else
  while IFS= read -r l; do [ -n "$l" ] && arms+=("$l"); done < <(jq -r '.id' "$arms_file")
fi
[ ${#arms[@]} -ge 1 ] || { echo "[run_bench] no arms resolved" >&2; exit 64; }

total=0; done_n=0
while IFS= read -r item; do
  [ -n "$item" ] || continue
  item_id="$(echo "$item" | jq -r '.id')"
  item_file="$out/items/$item_id.json"; mkdir -p "$out/items"; echo "$item" > "$item_file"
  for arm in "${arms[@]}"; do
    for r in $(seq 1 "$repeats"); do
      total=$((total+1))
      key="$arm|$item_id|$r"
      if grep -qF "\"key\":\"$key\"" "$graded" 2>/dev/null; then
        echo "[run_bench] skip (done): $key"; done_n=$((done_n+1)); continue
      fi
      rdir="$out/runs/$arm/$item_id/r$r"; mkdir -p "$rdir"
      echo "[run_bench] === $key ==="
      ARMS_FILE="$arms_file" bash "$HERE/run_arm.sh" "$arm" "$item_file" "$rdir" || true
      if [ -s "$rdir/result.json" ]; then
        bash "$HERE/grade.sh" "$rdir/result.json" "$item_file" "$rdir/verdict.json" || true
        # merge result + verdict + key into one graded line
        jq -c -n --slurpfile res "$rdir/result.json" --slurpfile ver "$rdir/verdict.json" \
          --arg key "$key" --argjson repeat "$r" \
          '$res[0] + {verdict:$ver[0].verdict, grade_reason:$ver[0].reason, grader:$ver[0].grader, repeat:$repeat, key:$key}' \
          >> "$graded"
        done_n=$((done_n+1))
      else
        echo "[run_bench] no result.json for $key (arm failed)" >&2
      fi
    done
  done
done < "$tasks"

echo "[run_bench] complete: $done_n/$total runs in $graded"
echo "[run_bench] score with: python3 $HERE/score.py $graded"
