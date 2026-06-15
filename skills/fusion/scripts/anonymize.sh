#!/usr/bin/env bash
# anonymize.sh — shuffle panelist answers into blind Panelist A/B/C labels with a real RNG, and record a
# durable label->source map. Replaces the old "ask the orchestrator to shuffle in its head and remember the
# map" step, which was neither reliably random nor reliably remembered.
#
# Usage:
#   anonymize.sh <out_answers_dir> <src1> [<src2> ...]
#
# - <out_answers_dir> : directory to (re)create with panelist_A.md, panelist_B.md, ... in randomized order.
# - <srcN>            : source answer files, in their natural order (e.g. opus1, opus2, codex).
#
# Writes:
#   <out_answers_dir>/panelist_<LABEL>.md   one per non-empty source, shuffled
#   <out_answers_dir>/map.json              [{"label":"A","source":"/path/opus1_out.md"}, ...]
#
# The map is how you de-anonymize for attribution at synthesis — durable on disk, not in the model's head.
# Empty/missing sources are skipped (a dropped panelist is absent, never silent agreement).

set -uo pipefail

out_dir="${1:?usage: anonymize.sh <out_answers_dir> <src1> [src2 ...]}"; shift
[ "$#" -ge 1 ] || { echo "[anonymize.sh] need at least one source answer file." >&2; exit 1; }

# Collect only non-empty sources.
srcs=()
for f in "$@"; do
  [ -s "$f" ] && srcs+=("$f")
done
[ "${#srcs[@]}" -ge 1 ] || { echo "[anonymize.sh] no non-empty source answers." >&2; exit 1; }

# Shuffle the source order with a real RNG (shuf if present, else RANDOM+sort fallback). Built with a
# while-read loop rather than `mapfile` so it works on macOS's stock bash 3.2.
shuffled=()
if command -v shuf >/dev/null 2>&1; then
  while IFS= read -r line; do shuffled+=("$line"); done < <(printf '%s\n' "${srcs[@]}" | shuf)
else
  while IFS= read -r line; do shuffled+=("$line"); done \
    < <(for f in "${srcs[@]}"; do printf '%s\t%s\n' "$RANDOM" "$f"; done | sort -n | cut -f2-)
fi

rm -rf "$out_dir"; mkdir -p "$out_dir"
labels=(A B C D E F G H)
map="["
i=0
for f in "${shuffled[@]}"; do
  label="${labels[$i]}"
  cp "$f" "$out_dir/panelist_${label}.md"
  [ "$i" -gt 0 ] && map+=","
  # JSON-escape the path minimally (paths here are simple temp paths).
  map+="{\"label\":\"${label}\",\"source\":\"${f}\"}"
  i=$((i+1))
done
map+="]"
printf '%s\n' "$map" > "$out_dir/map.json"

echo "[anonymize.sh] wrote ${i} anonymized answers + map.json to $out_dir"
