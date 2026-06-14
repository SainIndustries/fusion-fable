#!/usr/bin/env bash
# codex_expert.sh — a PERSISTENT codex (GPT-5.5) domain expert you can talk to across many turns.
#
# Why this exists: for iterative, context-heavy work (debugging a subsystem over many steps, driving a
# migration, refactoring against a fixed spec), spawning a fresh subagent each turn throws away everything
# learned the turn before. codex's session compaction is good enough to keep a long-lived "domain expert"
# coherent across dozens of turns — so you prime it once and keep asking, instead of re-explaining context
# to a new agent every time. This is the iterative-work counterpart to the one-shot Fusion panel.
#
# It manages named sessions: the first call to a name starts a codex session and records its id; every
# later call to the same name RESUMES that session (codex exec resume <id>), so the expert remembers.
#
# Usage:
#   codex_expert.sh <expert-name> <prompt | path-to-prompt-file | ->   # ask the expert (- = stdin)
#   codex_expert.sh --list                                             # list known experts
#   codex_expert.sh --forget <expert-name>                             # drop the saved session id
#
# Env:
#   FUSION_HOME            state dir (default: ~/.fusion); ids live in $FUSION_HOME/experts/<name>.id
#   EXPERT_MODEL           model (default: gpt-5.5)
#   FUSION_EXPERT_SANDBOX  codex sandbox mode (default: workspace-write)
#   FUSION_EXPERT_CWD      working dir the expert operates in (default: current directory)
#
# Output: the expert's reply is printed to stdout (and is the only thing on stdout).

set -uo pipefail

FUSION_HOME="${FUSION_HOME:-$HOME/.fusion}"
experts_dir="$FUSION_HOME/experts"
mkdir -p "$experts_dir"

model="${EXPERT_MODEL:-gpt-5.5}"
sandbox="${FUSION_EXPERT_SANDBOX:-workspace-write}"
workdir="${FUSION_EXPERT_CWD:-$PWD}"

die() { echo "[codex_expert.sh] $*" >&2; exit 1; }

case "${1:-}" in
  --list)
    shopt -s nullglob
    found=false
    for f in "$experts_dir"/*.id; do
      found=true
      name="$(basename "$f" .id)"
      printf "  %-24s %s\n" "$name" "$(cat "$f")"
    done
    $found || echo "  (no experts yet)"
    exit 0
    ;;
  --forget)
    name="${2:?usage: codex_expert.sh --forget <expert-name>}"
    rm -f "$experts_dir/$name.id" && echo "[codex_expert.sh] forgot '$name'."
    exit 0
    ;;
  "" )
    die "usage: codex_expert.sh <expert-name> <prompt | file | ->"
    ;;
esac

command -v codex >/dev/null 2>&1 || die "codex CLI not installed."

name="$1"
prompt_arg="${2:?usage: codex_expert.sh <expert-name> <prompt | file | ->}"

# Resolve the prompt: a readable file path -> its contents; "-" -> stdin; otherwise the literal string.
if [ "$prompt_arg" = "-" ]; then
  prompt="$(cat)"
elif [ -f "$prompt_arg" ]; then
  prompt="$(cat "$prompt_arg")"
else
  prompt="$prompt_arg"
fi
[ -n "$prompt" ] || die "empty prompt."

id_file="$experts_dir/$name.id"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-expert.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
out_file="$scratch/reply.md"
json_log="$scratch/events.jsonl"

# `codex exec` and `codex exec resume` accept different flags: resume rejects --cd/-s, so the working dir
# and sandbox mode are passed via -c config overrides on resume instead.
create_flags=(--skip-git-repo-check --cd "$workdir" -s "$sandbox" -c tools.web_search=true -m "$model"
              --json -o "$out_file")
resume_flags=(--skip-git-repo-check -c tools.web_search=true -c "sandbox_mode=\"$sandbox\"" -m "$model"
              --json -o "$out_file")

if [ -s "$id_file" ]; then
  session_id="$(cat "$id_file")"
  codex exec resume "${resume_flags[@]}" "$session_id" - <<<"$prompt" > "$json_log" 2>&1
  status=$?
else
  codex exec "${create_flags[@]}" - <<<"$prompt" > "$json_log" 2>&1
  status=$?
  # Record the session id so future calls resume this same expert. Prefer a "session"-tagged line; fall
  # back to the first UUID in the event stream.
  sid="$(grep -iE 'session' "$json_log" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -1)"
  [ -n "$sid" ] || sid="$(grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$json_log" | head -1)"
  if [ -n "$sid" ]; then
    echo "$sid" > "$id_file"
  else
    echo "[codex_expert.sh] WARNING: could not capture session id; this turn ran but won't be resumable." >&2
  fi
fi

if [ $status -ne 0 ] || [ ! -s "$out_file" ]; then
  echo "[codex_expert.sh] codex exited $status; tail of log:" >&2
  tail -20 "$json_log" >&2
  exit 1
fi

cat "$out_file"
