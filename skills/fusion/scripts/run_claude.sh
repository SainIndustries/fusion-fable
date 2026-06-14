#!/usr/bin/env bash
# run_claude.sh — run one Opus 4.8 panelist via the `claude` CLI, under the Claude Fable 5 system prompt.
#
# This is the DEFAULT way Fusion runs its Opus panelists in this fork: a headless `claude` subprocess that
# answers the task autonomously with web + bash. It runs Opus 4.8 (the accessible model) but loads the
# Claude Fable 5 system prompt, so the panelist presents as Fable 5 — the "Fable-tier" intent of the panel.
#
# Usage:
#   run_claude.sh <prompt_file> <output_file> [model]
#
# - <prompt_file>  : the FULL panelist prompt (verbatim user task + the short independent-expert instruction).
# - <output_file>  : where the panelist's final answer is written (clean text, just the answer).
# - model          : the claude model alias/name (default: opus, overridable via FUSION_CLAUDE_MODEL).
#
# Flags (matches the project convention; see README):
#   --print                       headless, non-interactive — print the answer and exit.
#   --dangerously-skip-permissions  the panelist uses tools (web, bash) WITHOUT permission prompts, so it
#                                 can research autonomously like the codex panelist. This bypasses ALL
#                                 permission checks — that's deliberate for an isolated panelist run, but it
#                                 IS dangerous; we run in a throwaway scratch dir to contain file writes.
#   --model opus                  pin to Opus 4.8; the CLI's own default may be a model the account can't use.
#   --system-prompt-file ...      load the Claude Fable 5 system prompt (resolved below).
#
# The Fable 5 prompt file is resolved from FUSION_FABLE5_PROMPT, else the copy shipped with the skill
# (<skill_dir>/CLAUDE-FABLE-5.md).

set -uo pipefail

prompt_file="${1:?usage: run_claude.sh <prompt_file> <output_file> [model]}"
output_file="${2:?usage: run_claude.sh <prompt_file> <output_file> [model]}"
model="${3:-${FUSION_CLAUDE_MODEL:-opus}}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$HERE")"
fable5="${FUSION_FABLE5_PROMPT:-$SKILL_DIR/CLAUDE-FABLE-5.md}"

if ! command -v claude >/dev/null 2>&1; then
  echo "[run_claude.sh] claude CLI not found on PATH." >&2
  exit 127
fi
if [ ! -s "$fable5" ]; then
  echo "[run_claude.sh] Fable 5 system prompt not found at: $fable5" >&2
  echo "                set FUSION_FABLE5_PROMPT to its path, or reinstall the skill." >&2
  exit 1
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-claude.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Run in the scratch dir so any file writes the panelist makes never touch your repo.
( cd "$scratch" && claude \
    --print \
    --dangerously-skip-permissions \
    --model "$model" \
    --system-prompt-file "$fable5" \
    "$(cat "$prompt_file")" ) > "$output_file" 2> "$scratch/err.log"

status=$?
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_claude.sh] claude exited $status; tail of stderr:" >&2
  tail -20 "$scratch/err.log" >&2
  exit 1
fi
echo "[run_claude.sh] ok -> $output_file (model=$model, system-prompt=Claude Fable 5)"
