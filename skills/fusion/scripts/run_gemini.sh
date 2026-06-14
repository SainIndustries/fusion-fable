#!/usr/bin/env bash
# run_gemini.sh — run one OPTIONAL Gemini panelist on a prompt, with web search + bash.
#
# Usage:
#   run_gemini.sh <prompt_file> <output_file>
#
# Gemini is OFF by default in this fork (the default panel is 2× Opus 4.8 + GPT-5.5). Opt in with
# FUSION_USE_GEMINI=1, and only when its CLI is installed and authenticated. This script degrades
# gracefully: if `gemini` is missing it exits 127 so the orchestrator drops Gemini and continues.
#
# Model: overridable via GEMINI_MODEL (default gemini-2.5-pro). Note `gemini-3.1-pro` is NOT a valid
# id on gemini-cli 0.25.2 (it 404s); use gemini-2.5-flash if your account's Pro quota is exhausted.

set -uo pipefail

prompt_file="${1:?usage: run_gemini.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_gemini.sh <prompt_file> <output_file>}"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini.sh] gemini CLI not installed — skip this panelist." >&2
  exit 127
fi

# Non-interactive Gemini run. Adjust flags to your installed gemini version if needed.
# Many builds accept the prompt on stdin and stream to stdout; we capture stdout as the answer.
gemini --model "${GEMINI_MODEL:-gemini-2.5-pro}" --yolo --prompt "$(cat "$prompt_file")" > "$output_file" 2> >(tail -20 >&2)

status=$?
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_gemini.sh] gemini exited $status or produced no output." >&2
  exit 1
fi
echo "[run_gemini.sh] ok -> $output_file"
