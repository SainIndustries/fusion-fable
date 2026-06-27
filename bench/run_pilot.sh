#!/usr/bin/env bash
# run_pilot.sh — run a set of arms in PARALLEL (separate out dirs, no append races), combine, score.
#
# Usage: run_pilot.sh [tasks_file] [repeats] [out_root] [arms_csv]
# Defaults: tasks=tasks/simpleqa.jsonl repeats=2 out=results/pilot arms="single-opus,single-gpt5.5,fusion-default"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS="${1:-$HERE/tasks/simpleqa.jsonl}"
REPEATS="${2:-2}"
root="${3:-$HERE/results/pilot}"
ARMS_CSV="${4:-single-opus,single-gpt5.5,fusion-default}"
export FUSION_TIMEOUT="${FUSION_TIMEOUT:-600}"
rm -rf "$root"; mkdir -p "$root"

IFS=',' read -ra arms <<< "$ARMS_CSV"
for arm in "${arms[@]}"; do
  ARMS_FILE="$HERE/arms.jsonl" bash "$HERE/run_bench.sh" --tasks "$TASKS" \
    --arms "$arm" --repeats "$REPEATS" --out "$root/$arm" >"$root/$arm.log" 2>&1 &
done
wait

cat "$root"/*/graded.jsonl > "$root/graded.jsonl" 2>/dev/null
echo "=== combined $(wc -l < "$root/graded.jsonl") runs ==="
python3 "$HERE/score.py" "$root/graded.jsonl" --baseline fusion-default | tee "$root/score.txt"
echo "PILOT_DONE"
