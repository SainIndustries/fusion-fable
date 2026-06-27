#!/usr/bin/env bash
# lib.sh — shared helpers for the Fusion benchmark harness (bench/).
#
# The harness benchmarks the SHIPPED pipeline by driving the real skill scripts in
# skills/fusion/scripts/ (run_claude.sh, run_codex.sh, run_gemini.sh, anonymize.sh). The only pieces
# bench/ adds are a scriptable JUDGE-any-model and SYNTH-any-model stage (the skill normally has the
# orchestrating Opus do those inline) plus a blind grader — so we can A/B the judge and synthesizer.
#
# Not executed directly; sourced by run_*.sh.

set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$BENCH_DIR/.." && pwd)"
SCRIPTS_DIR="$REPO_DIR/skills/fusion/scripts"

# Reuse the skill's timeout + hermetic-codex helpers so judge/synth codex calls behave like the real
# pipeline (no cross-project leakage — see _lib.sh "Finding #0").
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/_lib.sh"

# bench_now — high-resolution wall clock (seconds, fractional). Latency is the harness's AUTHORITATIVE
# efficiency metric; token/cost accounting is an estimate (see README "Cost accounting").
bench_now() { date +%s.%N 2>/dev/null || date +%s; }
bench_elapsed() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", b-a}'; }

# bench_panelist_prompt <question>
# The verbatim task plus the short independent-expert instruction (per references/panel.md: no lenses, no
# personas). A FINAL ANSWER line is appended so the grader can extract a clean answer deterministically.
# Single-model arms get the SAME prompt (a panel of one) so Fusion-vs-single is a fair comparison.
bench_panelist_prompt() {
  cat <<EOF
$1

---
You are one of several independent experts answering the task above. Research with web search and bash as
needed, then return a complete, self-contained answer. You will not see the other experts' work; answer it
straight, on substance and evidence.

When you are done, end your response with exactly one line, nothing after it:
FINAL ANSWER: <your single most concise, gradeable answer>
EOF
}

# bench_judge_prompt <task_file> <answers_dir>
# Emits the DISCERNMENT prompt. Mirrors the rubric embedded in skills/fusion/scripts/run_judge.sh so that
# swapping the judge model is apples-to-apples (same instructions, different model). Reads panelist_*.md.
bench_judge_prompt() {
  local task_file="$1" answers_dir="$2"
  cat <<'EOF'
You are the JUDGE in a panel pipeline. Several independent experts answered the SAME task below without
seeing each other's work. Your job is DISCERNMENT, not authorship: do not write the final answer — a
separate synthesizer will do that from your analysis. Be rigorous, skeptical, and decisive about what is
actually correct and well-supported versus what is plausible but weak.

The panelist answers are anonymized (Panelist A, B, ...). You do not know which model wrote which, and you
must not guess or favor any "style" — judge only on substance and evidence.

Produce a structured DISCERNMENT doc with exactly these sections:

## Per-panelist assessment
For each panelist (A, B, ...): its approach, what it gets right, where it's wrong/weak/unsupported, and the
quality of its evidence. One tight paragraph each.

## Consensus
Claims the panelists independently agree on. Independent agreement is the highest-confidence signal.

## Contradictions
Direct disagreements on fact or recommendation. State the competing positions and ADJUDICATE which side has
better evidence. If you can't resolve it, say what would settle it. Never bury a real conflict.

## Partial coverage
Important sub-questions only some panelists engaged.

## Unique insights
Non-obvious, valuable points raised by exactly one panelist — preserve them even if off the majority view.

## Blind spots
What the panel as a whole missed or got wrong, including shared assumptions none questioned.

## Discernment verdict
The payload for the synthesizer: which specific claims are load-bearing AND well-supported (keep), which are
weak/contradicted (discard or hedge), and the recommended spine for the final answer.

=== THE TASK (verbatim) ===
EOF
  cat "$task_file"
  echo
  local f label
  for f in "$answers_dir"/panelist_*.md; do
    [ -e "$f" ] || continue
    label="$(basename "$f" .md | sed 's/^panelist_/Panelist /')"
    echo; echo "=== ${label} ==="; cat "$f"; echo
  done
}

# bench_synth_prompt <task_file> <judge_file> <answers_dir>
# The synthesizer reads the discernment + raw answers and writes the final answer grounded in it.
bench_synth_prompt() {
  local task_file="$1" judge_file="$2" answers_dir="$3"
  cat <<'EOF'
You are the SYNTHESIZER. Independent experts answered the task below; a judge produced the DISCERNMENT that
follows. Write the final answer GROUNDED IN THE DISCERNMENT — lead with high-confidence consensus, fold in
unique insights the judge flagged as worth keeping, and explicitly flag what stays uncertain. The result
must follow FROM the discernment, not be one panelist's answer lightly edited.

When you are done, end your response with exactly one line, nothing after it:
FINAL ANSWER: <your single most concise, gradeable answer>

=== THE TASK (verbatim) ===
EOF
  cat "$task_file"
  echo; echo "=== DISCERNMENT ==="; cat "$judge_file"
  echo; echo "=== RAW PANELIST ANSWERS ==="
  local f label
  for f in "$answers_dir"/panelist_*.md; do
    [ -e "$f" ] || continue
    label="$(basename "$f" .md | sed 's/^panelist_/Panelist /')"
    echo; echo "--- ${label} ---"; cat "$f"; echo
  done
}

# bench_extract_final <file> — pull the text after the LAST "FINAL ANSWER:" marker; fall back to the last
# non-empty line if the model didn't emit the marker.
bench_extract_final() {
  local f="$1" line
  line="$(grep -iE '^[[:space:]]*FINAL ANSWER:' "$f" | tail -1 | sed -E 's/^[[:space:]]*FINAL ANSWER:[[:space:]]*//I')"
  if [ -z "$line" ]; then
    line="$(grep -v '^[[:space:]]*$' "$f" | tail -1)"
  fi
  printf '%s' "$line"
}

# bench_run_model <model> <prompt_file> <out_file> — dispatch one model as a PANELIST/single answer.
# opus|sonnet|haiku -> run_claude_sandboxed.sh (web-only — see that script's header for WHY the shipped
#                      skip-permissions panelist CANNOT be used in a benchmark: it reads the answer key off
#                      disk). Set BENCH_SANDBOX=0 to use the cheatable shipped run_claude.sh anyway.
# gpt5.5            -> run_codex.sh (codex's seatbelt sandbox already blocks the repo read)
# gemini            -> run_gemini.sh
# Returns the script's exit status (non-zero = dropped panelist; caller treats as absent).
bench_run_model() {
  local model="$1" prompt="$2" out="$3"
  case "$model" in
    opus|sonnet|haiku)
      if [ "${BENCH_SANDBOX:-1}" = "1" ]; then
        bash "$BENCH_DIR/run_claude_sandboxed.sh" "$prompt" "$out" "$model"
      else
        bash "$SCRIPTS_DIR/run_claude.sh" "$prompt" "$out" "$model"
      fi ;;
    gpt5.5)  bash "$SCRIPTS_DIR/run_codex.sh"  "$prompt" "$out" "${BENCH_CODEX_EFFORT:-medium}" ;;
    gemini)  bash "$SCRIPTS_DIR/run_gemini.sh" "$prompt" "$out" ;;
    *) echo "[bench] unknown model: $model" >&2; return 64 ;;
  esac
}
