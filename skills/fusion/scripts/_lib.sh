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
