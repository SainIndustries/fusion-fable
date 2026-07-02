#!/usr/bin/env bash
# detect_panel.sh — decide the panel, the judge, and the synthesizer for a Fusion run.
#
# Fusion (Sain Industries fork) splits the old single "judge + write" role into two stages:
#
#   fan out (blind panelists) → JUDGE (discernment) → SYNTHESIZE (creative final answer)
#
# - Panelists answer the task independently, in parallel, none seeing the others.
# - The JUDGE does discernment only: scores the answers, finds consensus/contradictions, decides what's
#   load-bearing and well-supported vs weak. GPT-5.5 (codex) is the preferred judge — it's stronger at
#   discrimination. If codex is unavailable it falls back to Fable 5 judging.
# - The SYNTHESIZER is ALWAYS Claude Fable 5 — it's better at creative synthesis and writes the final
#   answer grounded in the judge's discernment. This is the invariant: Fable always drives and writes the
#   final answer; the pipeline can't be reversed.
#
# Now that Fable 5 is generally available, the Claude panelists run the REAL model (claude-fable-5) —
# no more Opus-with-a-Fable-persona workaround. Override with FUSION_CLAUDE_MODEL (legacy: set it to
# `opus` plus FUSION_FABLE5_PROMPT for accounts without Fable access).
#
# Default panel drops Gemini in favor of a second Fable panelist (more within-model diversity, no extra
# CLI/auth to babysit). Set FUSION_USE_GEMINI=1 to add Gemini as an optional extra panelist if its CLI is
# present.
#
# Output: human-readable lines, then a machine-parseable block the orchestrator greps:
#   PANEL=<comma-separated panelists>   JUDGE=<model>   SYNTH=<model>   SLUG=<slug>

have() { command -v "$1" >/dev/null 2>&1; }

codex_ok=false; gemini_ok=false
have codex  && codex_ok=true
have gemini && gemini_ok=true

claude_ok=false; have claude && claude_ok=true
claude_model="${FUSION_CLAUDE_MODEL:-claude-fable-5}"

echo "fusion panel detection (pipeline: fan out → judge → synthesize):"
printf "  fable5       : %s (claude CLI panelists, model=%s; also the synthesizer)\n" \
  "$([ "$claude_ok" = true ] && echo yes || echo 'NO — claude CLI not on PATH')" "$claude_model"
printf "  gpt5.5       : %s (codex CLI — preferred JUDGE; also a panelist)\n" \
  "$([ "$codex_ok" = true ] && echo yes || echo NO)"
printf "  gemini3.1pro : %s (optional extra panelist; off unless FUSION_USE_GEMINI=1)\n" \
  "$([ "$gemini_ok" = true ] && echo yes || echo NO)"
echo

# --- Panel: two independent Fable 5 runs + GPT-5.5 (if codex present). Gemini only when opted in. ---
panel="fable5,fable5"
panel_label="fable5x2"
if $codex_ok; then
  panel="$panel,gpt5.5"
  panel_label="${panel_label}+gpt5.5"
fi
if [ "${FUSION_USE_GEMINI:-0}" = "1" ] && $gemini_ok; then
  panel="$panel,gemini3.1pro"
  panel_label="${panel_label}+gemini3.1pro"
fi

# --- Judge: GPT-5.5 for discernment when codex is available, else Fable judges itself. ---
if $codex_ok; then judge="gpt5.5"; else judge="fable5"; fi

# --- Synthesizer: always Fable 5. ---
synth="fable5"

slug="${panel_label}·judge:${judge}·synth:${synth}"

echo "recommended pipeline:"
echo "  panel       : $panel"
echo "  judge       : $judge$([ "$judge" = fable5 ] && echo '   (codex not found — falling back to Fable judging)')"
echo "  synthesize  : $synth"
echo "  fable panelists run: claude --print --dangerously-skip-permissions --model $claude_model"
echo
# Mint a private per-run directory so concurrent Fusion runs (different sessions/projects on one machine)
# can't clobber each other's intermediate files. The orchestrator must use THIS path for every temp file
# in the run — never a shared /tmp/fusion_* constant.
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/fusion-run.XXXXXX")"

echo "PANEL=$panel"
echo "JUDGE=$judge"
echo "SYNTH=$synth"
echo "SLUG=$slug"
echo "RUN_DIR=$run_dir"
