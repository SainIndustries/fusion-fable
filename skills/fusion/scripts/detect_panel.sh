#!/usr/bin/env bash
# detect_panel.sh — decide the panel, the judge, and the synthesizer for a Fusion run.
#
# Fusion (Sain Industries fork) splits the old single "Opus judges + writes" role into two stages:
#
#   fan out (blind panelists) → JUDGE (discernment) → SYNTHESIZE (creative final answer)
#
# - Panelists answer the task independently, in parallel, none seeing the others.
# - The JUDGE does discernment only: scores the answers, finds consensus/contradictions, decides what's
#   load-bearing and well-supported vs weak. GPT-5.5 (codex) is the preferred judge — it's stronger at
#   discrimination. If codex is unavailable it falls back to Opus 4.8 judging.
# - The SYNTHESIZER is ALWAYS Opus 4.8 — it's better at creative synthesis and writes the final answer
#   grounded in the judge's discernment. This is the invariant: Opus always drives and writes the final
#   answer; the pipeline can't be reversed.
#
# Default panel drops Gemini in favor of a second Opus panelist (more within-model diversity, no extra
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

echo "fusion panel detection (pipeline: fan out → judge → synthesize):"
printf "  opus4.8      : %s (claude CLI panelists under the Fable 5 system prompt; also the synthesizer)\n" \
  "$([ "$claude_ok" = true ] && echo yes || echo 'NO — claude CLI not on PATH')"
printf "  gpt5.5       : %s (codex CLI — preferred JUDGE; also a panelist)\n" \
  "$([ "$codex_ok" = true ] && echo yes || echo NO)"
printf "  gemini3.1pro : %s (optional extra panelist; off unless FUSION_USE_GEMINI=1)\n" \
  "$([ "$gemini_ok" = true ] && echo yes || echo NO)"
echo

# --- Panel: two independent Opus runs + GPT-5.5 (if codex present). Gemini only when opted in. ---
panel="opus4.8,opus4.8"
panel_label="opus4.8x2"
if $codex_ok; then
  panel="$panel,gpt5.5"
  panel_label="${panel_label}+gpt5.5"
fi
if [ "${FUSION_USE_GEMINI:-0}" = "1" ] && $gemini_ok; then
  panel="$panel,gemini3.1pro"
  panel_label="${panel_label}+gemini3.1pro"
fi

# --- Judge: GPT-5.5 for discernment when codex is available, else Opus judges itself. ---
if $codex_ok; then judge="gpt5.5"; else judge="opus4.8"; fi

# --- Synthesizer: always Opus. ---
synth="opus4.8"

slug="${panel_label}·judge:${judge}·synth:${synth}"

echo "recommended pipeline:"
echo "  panel       : $panel"
echo "  judge       : $judge$([ "$judge" = opus4.8 ] && echo '   (codex not found — falling back to Opus judging)')"
echo "  synthesize  : $synth"
echo "  opus panelists run: claude --print --dangerously-skip-permissions --model opus --system-prompt-file CLAUDE-FABLE-5.md"
echo
echo "PANEL=$panel"
echo "JUDGE=$judge"
echo "SYNTH=$synth"
echo "SLUG=$slug"
