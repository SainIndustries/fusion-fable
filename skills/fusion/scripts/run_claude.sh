#!/usr/bin/env bash
# run_claude.sh — run one Claude panelist via the `claude` CLI (Fable 5.1 by default; pass `opus` as the
# model arg for the Opus 4.8 panelist).
#
# This is the DEFAULT way Fusion runs its Claude panelists: a headless `claude` subprocess that answers
# the task autonomously with web + bash. The panelist runs the real Fable 5.1 model
# (`claude-fable-5-1`) with its native system prompt — no persona injection needed.
#
# Usage:
#   run_claude.sh <prompt_file> <output_file> [model]
#
# - <prompt_file>  : the FULL panelist prompt (verbatim user task + the short independent-expert instruction).
# - <output_file>  : where the panelist's final answer is written (clean text, just the answer).
# - model          : the claude model alias/name (default: claude-fable-5-1, overridable via FUSION_CLAUDE_MODEL).
#
# Flags (matches the project convention; see README):
#   --print                       headless, non-interactive — print the answer and exit.
#   --dangerously-skip-permissions  the panelist uses tools (web, bash) WITHOUT permission prompts, so it
#                                 can research autonomously like the codex panelist. This bypasses ALL
#                                 permission checks — that's deliberate for an isolated panelist run, but it
#                                 IS dangerous; we run in a throwaway scratch dir to contain file writes.
#   --model claude-fable-5-1      pin to Fable 5.1; the CLI's own default may be a different model.
#
# Legacy fallback: if your account has NO Fable 5 access, set FUSION_CLAUDE_MODEL=opus and
# FUSION_FABLE5_PROMPT to a Fable 5 system-prompt file — that reproduces the pre-Fable behavior (Opus 4.8
# wearing the Fable 5 persona). The persona prompt is ONLY loaded when FUSION_FABLE5_PROMPT is explicitly
# set; by default the real model's own system prompt is used.

set -uo pipefail

prompt_file="${1:?usage: run_claude.sh <prompt_file> <output_file> [model]}"
output_file="${2:?usage: run_claude.sh <prompt_file> <output_file> [model]}"
model="${3:-${FUSION_CLAUDE_MODEL:-claude-fable-5-1}}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"

if ! command -v claude >/dev/null 2>&1; then
  echo "[run_claude.sh] claude CLI not found on PATH." >&2
  exit 127
fi

# Optional legacy persona injection — only when explicitly requested via FUSION_FABLE5_PROMPT.
extra_args=()
if [ -n "${FUSION_FABLE5_PROMPT:-}" ]; then
  if [ ! -s "$FUSION_FABLE5_PROMPT" ]; then
    echo "[run_claude.sh] FUSION_FABLE5_PROMPT is set but not readable: $FUSION_FABLE5_PROMPT" >&2
    exit 1
  fi
  extra_args+=(--system-prompt-file "$FUSION_FABLE5_PROMPT")
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-claude.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Run in the scratch dir so any file writes the panelist makes never touch your repo. Wall-clock bounded
# (FUSION_TIMEOUT, default 900s) so a wedged panelist can't hang the whole fan-out forever.
( cd "$scratch" && fusion_run_timeout "$(fusion_default_timeout)" claude \
    --print \
    --dangerously-skip-permissions \
    --model "$model" \
    ${extra_args[@]+"${extra_args[@]}"} \
    "$(cat "$prompt_file")" ) > "$output_file" 2> "$scratch/err.log"

status=$?
if [ $status -eq 124 ]; then
  echo "[run_claude.sh] claude timed out after $(fusion_default_timeout)s (FUSION_TIMEOUT)." >&2
  fusion_discard_failed_output "$output_file"
  exit 1
fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_claude.sh] claude exited $status; tail of stderr:" >&2
  tail -20 "$scratch/err.log" >&2
  # claude --print reports auth failures on STDOUT, i.e. inside the output file — diagnose both, then
  # move the file aside so the error text can never be anonymized and judged as an answer.
  cat "$scratch/err.log" "$output_file" > "$scratch/diag.log" 2>/dev/null
  fusion_diagnose_log "$scratch/diag.log" "run_claude.sh"
  fusion_discard_failed_output "$output_file"
  exit 1
fi
echo "[run_claude.sh] ok -> $output_file (model=$model)"
