#!/usr/bin/env bash
# check.sh — the no-regression gate for the Fusion self-improvement loop.
#
# Prefers the project's real test harness once it exists (roadmap item P3-tests-harness writes tests/run.sh);
# until then it runs a baseline smoke that already passes against the current repo, so the loop has a real
# gate from iteration 1. Exit 0 = green, non-zero = red (a change that breaks this can never be committed).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 3

# Upgrade automatically when a real suite lands.
if [ -x tests/run.sh ]; then exec bash tests/run.sh; fi

fail=0
# 1) every tracked shell script must parse
while IFS= read -r f; do
  [ -n "$f" ] || continue
  bash -n "$f" || { echo "[check] syntax error: $f" >&2; fail=1; }
done < <(git ls-files '*.sh')

# 2) shellcheck errors only (style ignored), if installed
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  shellcheck -S error $(git ls-files 'skills/fusion/scripts/*.sh') 2>/dev/null || fail=1
fi

# 3) the detector must still emit its machine contract (the inter-stage interface)
out="$(bash skills/fusion/scripts/detect_panel.sh 2>/dev/null)" || fail=1
for k in '^PANEL=' '^JUDGE=' '^SYNTH=' '^SLUG=' '^RUN_DIR='; do
  printf '%s\n' "$out" | grep -q "$k" || { echo "[check] detector missing $k" >&2; fail=1; }
done

[ "$fail" -eq 0 ] && echo "[check] green" || echo "[check] RED" >&2
exit "$fail"
