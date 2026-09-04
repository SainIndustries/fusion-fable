#!/usr/bin/env bash
# run_claude_sandboxed.sh — a BENCHMARK-ONLY claude panelist with NO local filesystem access.
#
# Why this exists: the shipped run_claude.sh uses --dangerously-skip-permissions, which grants the panelist
# unrestricted shell + filesystem reads. In production that's fine (there is no answer key on disk). In a
# BENCHMARK it is fatal: an agentic Opus panelist walks the filesystem, finds bench/tasks/<set>.jsonl, reads
# the gold answers, and "answers" by copying the key (observed: a single-question prompt produced all-24
# answers + "All 24 match the provided gold answers"). That contaminates every Opus-based arm.
#
# Fix: run the panelist with web research ONLY. We pass the prompt on STDIN (so the variadic --disallowedTools
# can't swallow it) and deny every shell/file tool. WebSearch stays (not in the deny list); WebFetch is denied
# too so it can't read file:// URLs. Verified: this blocks reading a known local file while still answering
# web questions headless. For web-answerable benchmarks (FRAMES, SimpleQA) this is the fair, cheat-proof
# equivalent of the shipped panelist — and it matches codex's sandbox, which already couldn't read the repo.
#
# Usage: run_claude_sandboxed.sh <prompt_file> <output_file> [model]

set -uo pipefail
prompt_file="${1:?usage: run_claude_sandboxed.sh <prompt_file> <output_file> [model]}"
output_file="${2:?usage: run_claude_sandboxed.sh <prompt_file> <output_file> [model]}"
model="${3:-${FUSION_CLAUDE_MODEL:-opus}}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$HERE/../skills/fusion/scripts" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/_lib.sh"
fable5="${FUSION_FABLE5_PROMPT:-$SCRIPTS_DIR/../CLAUDE-FABLE-5.md}"

command -v claude >/dev/null 2>&1 || { echo "[run_claude_sandboxed] claude CLI not found" >&2; exit 127; }
[ -s "$fable5" ] || { echo "[run_claude_sandboxed] Fable 5 prompt not found at $fable5" >&2; exit 1; }

# Every shell/file tool denied; NO --allowedTools (mixing the two re-enables reads). WebSearch stays.
DENY=(--disallowedTools "Bash" "Read" "Glob" "Grep" "Edit" "Write" "NotebookEdit" "Task" "WebFetch")

scratch="$(mktemp -d "${TMPDIR:-/tmp}/bench-claude.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Capture the prompt BEFORE cd'ing into scratch — the caller may pass a relative path, which would not
# resolve once we're inside $scratch. (fable5 is already absolute via SCRIPTS_DIR.)
prompt_content="$(cat "$prompt_file")"
( cd "$scratch" && fusion_run_timeout "$(fusion_default_timeout)" claude \
    --print --model "$model" --system-prompt-file "$fable5" "${DENY[@]}" \
    <<<"$prompt_content" ) > "$output_file" 2> "$scratch/err.log"

status=$?
if [ $status -eq 124 ]; then echo "[run_claude_sandboxed] timed out after $(fusion_default_timeout)s" >&2; exit 1; fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_claude_sandboxed] claude exited $status; tail of stderr:" >&2; tail -20 "$scratch/err.log" >&2; exit 1
fi
echo "[run_claude_sandboxed] ok -> $output_file (model=$model, web-only, no local FS)"
