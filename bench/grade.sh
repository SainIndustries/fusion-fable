#!/usr/bin/env bash
# grade.sh — blind LLM-as-judge grader. Scores ONE result's final answer against the gold answer.
#
# Blindness: the grader sees only (question, gold, candidate final answer) — never which ARM produced it, so
# it cannot prefer "the fusion one". To avoid self-preference, set GRADER_MODEL to a model that is NOT in the
# arm being graded (default: gpt5.5; flip to opus when grading codex-heavy arms, or double-grade — see README).
#
# Usage: grade.sh <result_json> <item_file> <out_verdict_json>
# Verdict: {"verdict":"correct"|"incorrect"|"not_attempted","reason":"..."} (SimpleQA-style rubric)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

result_json="${1:?usage: grade.sh <result_json> <item_file> <out_verdict_json>}"
item_file="${2:?item_file}"
out="${3:?out_verdict_json}"
grader="${GRADER_MODEL:-gpt5.5}"

question="$(jq -r '.question' "$item_file")"
gold="$(jq -r '.gold' "$item_file")"
candidate="$(jq -r '.final_answer' "$result_json")"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/bench-grade.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
prompt="$scratch/grade_prompt.txt"
{
  cat <<'EOF'
You are a strict grader. Compare the CANDIDATE answer to the GOLD answer for the QUESTION. Judge only
whether the candidate's answer is factually correct, ignoring phrasing, formatting, and extra detail.

Output rules (CRITICAL): respond with ONE line of compact JSON and nothing else:
{"verdict":"correct","reason":"<=15 words"}
- "correct": the candidate's answer matches the gold answer in meaning (a superset with the right core
  fact is still correct).
- "not_attempted": the candidate refused, hedged without committing, or gave no answer.
- "incorrect": it committed to an answer that conflicts with gold, or is missing the key fact.
Do not output anything except that single JSON line.

EOF
  echo "QUESTION: $question"
  echo "GOLD: $gold"
  echo "CANDIDATE: $candidate"
} > "$prompt"

raw="$scratch/raw.txt"
case "$grader" in
  gpt5.5)
    command -v codex >/dev/null 2>&1 || { echo "[grade] codex missing" >&2; exit 2; }
    export CODEX_HOME="$(fusion_codex_home)"
    fusion_run_timeout 180 codex exec --skip-git-repo-check --ignore-user-config --cd "$scratch" \
      -s read-only -c "model_reasoning_effort=low" -m "${JUDGE_MODEL:-gpt-5.5}" \
      -o "$raw" - < "$prompt" >"$scratch/log" 2>&1 || true
    ;;
  opus|sonnet|haiku)
    fusion_run_timeout 180 claude --print --model "$grader" "$(cat "$prompt")" >"$raw" 2>"$scratch/log" || true
    ;;
  *) echo "[grade] unknown grader: $grader" >&2; exit 2 ;;
esac

# Extract the JSON object (last {...} on any line) robustly.
verdict_json="$(grep -oE '\{[^{}]*"verdict"[^{}]*\}' "$raw" | tail -1)"
if [ -z "$verdict_json" ] || ! echo "$verdict_json" | jq -e . >/dev/null 2>&1; then
  verdict_json='{"verdict":"ungraded","reason":"grader produced no parseable verdict"}'
fi
echo "$verdict_json" | jq -c \
  --arg grader "$grader" '. + {grader:$grader}' > "$out"
echo "[grade] $(jq -r '.verdict' "$out")  (grader=$grader)"
