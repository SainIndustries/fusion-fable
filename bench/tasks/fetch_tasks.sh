#!/usr/bin/env bash
# fetch_tasks.sh — pull real public benchmark slices into bench/tasks/ as {id,question,gold} JSONL.
#
# We DON'T vendor benchmark data into the repo (licensing + bulk). This fetches from official sources and
# samples a small slice (default 45 items) per benchmark. Requires network + python3 (+ `datasets` for the
# HF-hosted sets). Each downloaded file is gitignored (see bench/.gitignore).
#
# Usage: fetch_tasks.sh [simpleqa|frames|gpqa] [N]
#
# Recommended 3-slice set (see README "Task set"):
#   simpleqa  — short factual Q with gold; ships the calibration/"confidently wrong" signal. PRIMARY.
#   frames    — multi-hop retrieval+reasoning with gold; rewards the tool-using panel. PRIMARY.
#   gpqa      — graduate science MCQ, no web helps; reasoning control + contamination tripwire.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
which="${1:-all}"; N="${2:-45}"

py() { python3 "$@"; }

fetch_simpleqa() {
  # OpenAI SimpleQA — public CSV.
  echo "[fetch] SimpleQA -> $HERE/simpleqa.jsonl (N=$N)"
  py - "$N" "$HERE/simpleqa.jsonl" <<'PY'
import sys, csv, io, json, urllib.request, random
N, out = int(sys.argv[1]), sys.argv[2]
URL = "https://openaipublic.blob.core.windows.net/simple-evals/simple_qa_test_set.csv"
data = urllib.request.urlopen(URL, timeout=60).read().decode("utf-8")
rows = list(csv.DictReader(io.StringIO(data)))
random.seed(7); random.shuffle(rows)
with open(out, "w") as f:
    for i, r in enumerate(rows[:N]):
        f.write(json.dumps({"id": f"simpleqa-{i}", "question": r["problem"], "gold": r["answer"]}) + "\n")
print(f"wrote {min(N,len(rows))} items")
PY
}

fetch_frames() {
  # FRAMES via HuggingFace datasets-server REST (no `datasets` lib needed). 824 multi-hop Q with gold.
  echo "[fetch] FRAMES -> $HERE/frames.jsonl (N=$N)"
  py - "$N" "$HERE/frames.jsonl" <<'PY'
import sys, json, random, urllib.request
N, out = int(sys.argv[1]), sys.argv[2]
BASE = "https://datasets-server.huggingface.co/rows?dataset=google/frames-benchmark&config=default&split=test"
def page(off, length):
    u = f"{BASE}&offset={off}&length={length}"
    return json.load(urllib.request.urlopen(u, timeout=60))
first = page(0, 100)
total = first["num_rows_total"]
rows = list(first["rows"])
off = 100
while off < total:
    rows += page(off, 100)["rows"]; off += 100
recs = [{"Prompt": r["row"]["Prompt"], "Answer": r["row"]["Answer"]} for r in rows]
random.seed(7); random.shuffle(recs)
with open(out, "w") as f:
    for k, r in enumerate(recs[:N]):
        f.write(json.dumps({"id": f"frames-{k}", "question": r["Prompt"], "gold": r["Answer"]}) + "\n")
print(f"wrote {min(N,len(recs))} of {total} items")
PY
}

fetch_gpqa() {
  echo "[fetch] GPQA-Diamond -> $HERE/gpqa.jsonl (N=$N)  [needs: pip install datasets + HF gated access]"
  py - "$N" "$HERE/gpqa.jsonl" <<'PY'
import sys, json, random
N, out = int(sys.argv[1]), sys.argv[2]
from datasets import load_dataset
ds = load_dataset("Idavidrein/gpqa", "gpqa_diamond", split="train")
idx = list(range(len(ds))); random.seed(7); random.shuffle(idx)
with open(out, "w") as f:
    for k, i in enumerate(idx[:N]):
        r = ds[i]
        f.write(json.dumps({"id": f"gpqa-{k}", "question": r["Question"], "gold": r["Correct Answer"]}) + "\n")
print(f"wrote {min(N,len(ds))} items")
PY
}

case "$which" in
  simpleqa) fetch_simpleqa ;;
  frames)   fetch_frames ;;
  gpqa)     fetch_gpqa ;;
  all)      fetch_simpleqa; fetch_frames || true; fetch_gpqa || true ;;
  *) echo "usage: fetch_tasks.sh [simpleqa|frames|gpqa|all] [N]" >&2; exit 64 ;;
esac
