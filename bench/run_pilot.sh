#!/usr/bin/env bash
# run_pilot.sh — headline pilot: 3 arms in parallel, combine, score. Not committed by default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS="${1:-$HERE/tasks/simpleqa.jsonl}"
REPEATS="${2:-2}"
export FUSION_TIMEOUT="${FUSION_TIMEOUT:-300}"
root="$HERE/results/pilot"
rm -rf "$root"; mkdir -p "$root"

for arm in single-opus single-gpt5.5 fusion-default; do
  ARMS_FILE="$HERE/arms.jsonl" bash "$HERE/run_bench.sh" --tasks "$TASKS" \
    --arms "$arm" --repeats "$REPEATS" --out "$root/$arm" >"$root/$arm.log" 2>&1 &
done
wait

cat "$root"/*/graded.jsonl > "$root/graded.jsonl"
echo "=== combined $(wc -l < "$root/graded.jsonl") runs ==="
python3 "$HERE/score.py" "$root/graded.jsonl" --baseline fusion-default | tee "$root/score.txt"
echo "PILOT_DONE"
