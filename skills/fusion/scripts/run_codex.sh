#!/usr/bin/env bash
# run_codex.sh — run one GPT-6 Astra panelist (via codex) on a prompt, with web search + bash.
#
# Usage:
#   run_codex.sh <prompt_file> <output_file> [reasoning_effort]
#
# Exit codes: 0 ok | 1 ran but failed/empty/timed out | 3 installed codex is too old for the pinned model
#             | 127 codex not installed. Any non-zero = this panelist is ABSENT (never silent agreement).
#
# - <prompt_file>   : path to a file containing the FULL panelist prompt (verbatim user task + brief instruction)
# - <output_file>   : where the panelist's final answer is written (clean, just the answer)
# - reasoning_effort: low | medium | high   (default: medium)
#
# Notes:
# - `-m` PINS the panelist model (default gpt-6-astra, overridable via CODEX_PANELIST_MODEL). Without this codex
#   runs the account's configured default, so the panel might silently not be the advertised GPT-6 Astra.
# - `-o/--output-last-message` writes ONLY the agent's final message — no streaming noise to parse.
# - `-s workspace-write` lets the panelist run shell commands in an isolated scratch dir (the "bash tool").
# - `-c tools.web_search=true` enables the web search tool.
# - We run in a throwaway scratch dir so a panelist's file writes never touch your repo.
# - The call is wall-clock bounded (FUSION_TIMEOUT, default 900s) so a wedged panelist can't hang the run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"

prompt_file="${1:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
output_file="${2:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
effort="${3:-medium}"
model="${CODEX_PANELIST_MODEL:-gpt-6-astra}"

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex.sh] codex CLI not found on PATH." >&2
  exit 127
fi
# Fail fast, with the fix, when the installed codex can't run the pinned model. No silent substitution:
# the panel must be the advertised model or the panelist is absent.
if ! fusion_codex_supports_model "$model"; then
  echo "[run_codex.sh] $(fusion_codex_upgrade_hint)" >&2
  exit 3
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-codex.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Hermetic codex home (auth only) + ignore user config, so this "fresh" run can't inherit cross-project
# session history / memory / project config from ~/.codex (Finding #0). Disable with FUSION_CODEX_HERMETIC=0.
export CODEX_HOME="$(fusion_codex_home)"

fusion_run_timeout "$(fusion_default_timeout)" codex exec \
  --skip-git-repo-check \
  --ignore-user-config \
  --cd "$scratch" \
  -s workspace-write \
  -c tools.web_search=true \
  -c "model_reasoning_effort=$effort" \
  -m "$model" \
  -o "$output_file" \
  - < "$prompt_file" \
  > "$scratch/stream.log" 2>&1

status=$?
if [ $status -eq 124 ]; then
  echo "[run_codex.sh] codex timed out after $(fusion_default_timeout)s (FUSION_TIMEOUT)." >&2
  fusion_discard_failed_output "$output_file"
  exit 1
fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_codex.sh] codex exited $status; tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  fusion_diagnose_log "$scratch/stream.log" "run_codex.sh"
  fusion_discard_failed_output "$output_file"
  exit 1
fi
echo "[run_codex.sh] ok -> $output_file (model=$model)"
