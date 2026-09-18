#!/usr/bin/env bash
# _lib.sh — shared helpers sourced by the fusion runner scripts. Not executed directly.

# fusion_run_timeout <seconds> <command...>
# Bound a command's wall-clock time, portably. Uses `timeout`, else `gtimeout` (coreutils on macOS),
# else a perl-based alarm, else (no timer available) runs the command unbounded. A timed-out command
# exits 124, matching GNU `timeout`. Output redirections stay with the CALLER, e.g.:
#     fusion_run_timeout 600 claude --print ...  > "$out" 2> "$err"
fusion_run_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'my $s=shift; local $SIG{ALRM}=sub{exit 124}; alarm $s; my $rc=system(@ARGV); alarm 0; exit($rc==-1?127:($rc>>8))' "$secs" "$@"
  else
    "$@"
  fi
}

# fusion_default_timeout — the per-CLI wall-clock budget, overridable via FUSION_TIMEOUT (seconds).
fusion_default_timeout() { echo "${FUSION_TIMEOUT:-900}"; }

# fusion_codex_version — echo the installed codex CLI version (e.g. 0.153.1), or nothing if unknown.
fusion_codex_version() {
  codex --version 2>/dev/null | sed -n 's/.*[^0-9]\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1
}

# fusion_version_ge <have> <need> — true when dotted version <have> >= <need>. Pure bash, no sort -V.
fusion_version_ge() {
  local IFS=. i a b
  # shellcheck disable=SC2206
  local have=($1) need=($2)
  for i in 0 1 2; do
    a="${have[$i]:-0}"; b="${need[$i]:-0}"
    [ "$a" -gt "$b" ] 2>/dev/null && return 0
    [ "$a" -lt "$b" ] 2>/dev/null && return 1
  done
  return 0
}

# fusion_codex_supports_model <model> — can the INSTALLED codex CLI run this model?
# GPT-6 Astra needs codex >= 0.153.1 (override the floor with FUSION_CODEX_MIN_FOR_ASTRA). On an older
# CLI the API answers 400 "requires a newer version of Codex" (older builds mislabel it as "not supported
# when using Codex with a ChatGPT account"), so we check locally and say how to fix it instead.
# Unknown version => assume supported and let the API be the judge.
fusion_codex_supports_model() {
  case "$1" in
    gpt-6-astra*)
      local v; v="$(fusion_codex_version)"
      [ -n "$v" ] || return 0
      fusion_version_ge "$v" "${FUSION_CODEX_MIN_FOR_ASTRA:-0.153.1}"
      ;;
    *) return 0 ;;
  esac
}

# fusion_codex_upgrade_hint — one line telling the user how to get a codex new enough for GPT-6 Astra.
fusion_codex_upgrade_hint() {
  echo "codex $(fusion_codex_version) is too old for GPT-6 Astra (needs >= ${FUSION_CODEX_MIN_FOR_ASTRA:-0.153.1}). Upgrade: 'brew upgrade --cask codex' or 'npm i -g @openai/codex@latest'. To run the previous era meanwhile: FUSION_VARIANT=fable5-gpt5.6."
}

# fusion_diagnose_log <log_file> <who> — turn the common, non-obvious CLI failures into one actionable line.
fusion_diagnose_log() {
  local log="$1" who="$2"
  [ -s "$log" ] || return 0
  if grep -qiE 'OAuth access token has been revoked|Failed to authenticate|401' "$log"; then
    echo "[$who] the claude CLI is not logged in (token revoked/expired). Fix: run 'claude' and /login. Until then, run the Claude panelists and the judge as blind Agent subagents (SKILL.md, Step 1 and Step 3)." >&2
  fi
  if grep -qiE 'requires a newer version of Codex|not supported when using Codex' "$log"; then
    echo "[$who] $(fusion_codex_upgrade_hint)" >&2
  fi
  if grep -qiE "hit your usage limit" "$log"; then
    echo "[$who] the codex account hit its usage limit — this panelist is ABSENT for this run (fall back to the Opus 4.8 panelist); see the reset time in the log above." >&2
  fi
}

# fusion_discard_failed_output <output_file> — a failed CLI can leave its ERROR TEXT in the output file
# (claude --print writes "Failed to authenticate…" to stdout). anonymize.sh keeps any non-empty source, so
# that text would be judged as if it were a panelist's answer. Move it aside so a failed panelist is
# truly ABSENT.
fusion_discard_failed_output() {
  [ -e "$1" ] || return 0
  mv -f "$1" "$1.failed" 2>/dev/null || rm -f "$1"
}

# fusion_codex_home — echo a HERMETIC CODEX_HOME for codex panelist/judge runs.
#
# Root cause of "Finding #0": codex exec pulls cross-project context (session history / memory / the
# [projects] table) out of the user's ~/.codex even for a fresh run, which once made the panelist AND judge
# answer an unrelated local project. Fix by construction: point codex at a private home that contains ONLY
# auth — no session history, no memory, no project config, no plugins — so there is nothing to leak.
#
# The real ~/.codex (or $CODEX_HOME) is used only as the auth source; we (sym)link its auth.json in.
# Disable with FUSION_CODEX_HERMETIC=0 to fall back to the user's normal codex home.
fusion_codex_home() {
  if [ "${FUSION_CODEX_HERMETIC:-1}" != "1" ]; then
    echo "${CODEX_HOME:-$HOME/.codex}"; return
  fi
  local src="${CODEX_HOME:-$HOME/.codex}"
  local home="${FUSION_HOME:-$HOME/.fusion}/codex-home"
  mkdir -p "$home" 2>/dev/null
  # Refresh auth each call so a re-login in the real home propagates. Symlink (so token refreshes write
  # through), falling back to a copy if symlinks aren't usable.
  if [ -f "$src/auth.json" ]; then
    ln -sf "$src/auth.json" "$home/auth.json" 2>/dev/null || cp -f "$src/auth.json" "$home/auth.json" 2>/dev/null
  fi
  echo "$home"
}

# fusion_load_variant — apply a named HARNESS PRESET from <skill_dir>/variants/<name>.env.
#
# A "variant" is one Fusion harness: a panel composition + judge + model strings, captured as a small env
# file. This is how the project swaps harnesses as models evolve — a new model era is a new preset file on
# main, not a branch. Select one by exporting FUSION_VARIANT=<name> (or via /fusion-variant).
#
# This runs automatically when _lib.sh is sourced, so EVERY stage of a run — detect_panel.sh and all the
# runner scripts — sees the same preset as long as FUSION_VARIANT is set for each call. Presets assign
# DEFAULTS only (: "${VAR:=...}"), so anything you export explicitly still wins over the preset.
# Presets may reference $SKILL_DIR (the installed skill root), e.g. for FUSION_FABLE5_PROMPT.
fusion_load_variant() {
  [ -n "${FUSION_VARIANT:-}" ] || return 0
  local here vfile
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SKILL_DIR="$(dirname "$here")"
  vfile="$SKILL_DIR/variants/${FUSION_VARIANT}.env"
  if [ -f "$vfile" ]; then
    # shellcheck source=/dev/null
    . "$vfile"
  else
    echo "[fusion] unknown FUSION_VARIANT '$FUSION_VARIANT' (no $vfile) — preset ignored." >&2
    FUSION_VARIANT=""   # don't let a bogus name label the run (e.g. in the SLUG)
  fi
}
fusion_load_variant
