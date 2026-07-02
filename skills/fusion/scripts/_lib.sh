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
