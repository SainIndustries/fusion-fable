#!/usr/bin/env bash
# detect_panel.sh — decide the panel, the judge, and the synthesizer for a Fusion run.
#
# Fusion (Sain Industries fork) splits the old single "judge + write" role into two stages:
#
#   fan out (blind panelists) → JUDGE (discernment) → SYNTHESIZE (creative final answer)
#
# - Panelists answer the task independently, in parallel, none seeing the others. The default panel is
#   deliberately CROSS-MODEL: one Claude Fable 5.1 + one GPT-6 Astra (codex) — two different model families,
#   maximum diversity per panelist. Opus 4.8 is the FALLBACK second panelist: it substitutes for GPT-6 Astra
#   automatically when the codex CLI isn't available (or when you don't want codex for the job).
# - The JUDGE does discernment only: scores the answers, finds consensus/contradictions, decides what's
#   load-bearing and well-supported vs weak. The default judge is Fable 5.1, run as a FRESH blind subprocess
#   over the anonymized answers. Set FUSION_JUDGE=astra to hand discernment to GPT-6 Astra (codex) instead.
# - The SYNTHESIZER is ALWAYS Claude Fable 5.1 — it writes the final answer grounded in the judge's
#   discernment. This is the invariant: Fable always drives and writes the final answer; the pipeline
#   can't be reversed.
#
# Claude panelists run the real models via the claude CLI (claude-fable-5-1 / opus). Override with
# FUSION_CLAUDE_MODEL (Fable panelist + judge) and FUSION_OPUS_MODEL (Opus panelist).
# Set FUSION_USE_GEMINI=1 to add Gemini as an optional extra panelist if its CLI is present.
#
# Output: human-readable lines, then a machine-parseable block the orchestrator greps:
#   PANEL=<comma-separated panelists>   JUDGE=<model>   SYNTH=<model>   SLUG=<slug>

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"   # also applies FUSION_VARIANT=<name> presets from <skill_dir>/variants/
SKILL_DIR="$(dirname "$HERE")"

have() { command -v "$1" >/dev/null 2>&1; }

codex_ok=false; gemini_ok=false
have codex  && codex_ok=true
# GPT-6 Astra needs a recent codex CLI. If the installed one is too old, treat the GPT panelist as
# unavailable (same path as "codex absent": Opus 4.8 steps in) and say exactly how to fix it.
codex_model="${CODEX_PANELIST_MODEL:-gpt-6-astra}"
codex_note=""
if $codex_ok && ! fusion_codex_supports_model "$codex_model"; then
  codex_ok=false
  codex_note="$(fusion_codex_upgrade_hint)"
fi
have gemini && gemini_ok=true

claude_ok=false; have claude && claude_ok=true
fable_model="${FUSION_CLAUDE_MODEL:-claude-fable-5-1}"
opus_model="${FUSION_OPUS_MODEL:-opus}"

echo "fusion panel detection (pipeline: fan out → judge → synthesize):"
printf "  fable5       : %s (Claude Fable 5.1 via claude CLI, model=%s; panelist + DEFAULT JUDGE + synthesizer)\n" \
  "$([ "$claude_ok" = true ] && echo yes || echo 'NO — claude CLI not on PATH')" "$fable_model"
printf "  astra        : %s (codex CLI, model=%s; DEFAULT 2nd panelist — judges only when FUSION_JUDGE=astra)\n" \
  "$([ "$codex_ok" = true ] && echo yes || echo NO)" "$codex_model"
[ -n "$codex_note" ] && echo "                 ^ $codex_note"
printf "  opus4.8      : %s (claude CLI, model=%s; FALLBACK 2nd panelist — used when codex/astra is absent)\n" \
  "$([ "$claude_ok" = true ] && echo yes || echo 'NO — claude CLI not on PATH')" "$opus_model"
printf "  gemini3.1pro : %s (optional extra panelist; off unless FUSION_USE_GEMINI=1)\n" \
  "$([ "$gemini_ok" = true ] && echo yes || echo NO)"
if [ -d "$SKILL_DIR/variants" ]; then
  variants="$(cd "$SKILL_DIR/variants" && ls -- *.env 2>/dev/null | sed 's/\.env$//' | tr '\n' ' ')"
  echo "  variants     : ${variants:-none} (select with FUSION_VARIANT=<name> or /fusion-variant)"
  [ -n "${FUSION_VARIANT:-}" ] && echo "  ACTIVE VARIANT: $FUSION_VARIANT"
fi
echo

# --- Panel: FUSION_PANEL (usually via a variant preset) wins verbatim; otherwise build the default from
# --- what's installed: one Fable 5.1 (claude CLI) + one GPT-6 Astra (codex). Opus 4.8 is the FALLBACK second
# --- panelist — it substitutes for GPT-6 Astra only when codex is missing. Gemini only when opted in.
if [ -n "${FUSION_PANEL:-}" ]; then
  panel="$FUSION_PANEL"
  panel_label="${FUSION_PANEL//,/+}"
  case ",$panel," in *,astra,*|*,gpt5.6,*|*,gpt5.5,*) $codex_ok  || echo "WARNING: panel names a GPT panelist but codex CLI is missing — that panelist will be dropped as absent." ;; esac
  case ",$panel," in *,fable5,*|*,opus4.8,*) $claude_ok || echo "WARNING: panel names a claude panelist but the claude CLI is missing." ;; esac
else
  panel=""
  panel_label=""
  if $claude_ok; then
    panel="fable5"
    panel_label="fable5"
  fi
  if $codex_ok; then
    # Preferred second panelist: GPT-6 Astra (cross-model diversity).
    panel="${panel:+$panel,}astra"
    panel_label="${panel_label:+$panel_label+}astra"
  elif $claude_ok; then
    # Fallback second panelist: Opus 4.8, used only when codex/GPT-6 Astra isn't available.
    panel="${panel:+$panel,}opus4.8"
    panel_label="${panel_label:+$panel_label+}opus4.8"
    echo "NOTE: ${codex_note:-codex CLI not found} — falling back to Opus 4.8 as the second panelist (default is GPT-6 Astra)."
  fi
  if [ "${FUSION_USE_GEMINI:-0}" = "1" ] && $gemini_ok; then
    panel="$panel,gemini3.1pro"
    panel_label="${panel_label}+gemini3.1pro"
  fi
fi
if [ -z "$panel" ]; then
  echo "ERROR: neither the claude nor the codex CLI is available — no panel can run." >&2
  exit 1
fi

# --- Judge: Fable 5.1 by default (fresh blind subprocess). FUSION_JUDGE=astra opts into a codex judge
# --- (legacy tokens gpt5.6 and gpt5.5 are still accepted for the preserved presets). ---
judge="${FUSION_JUDGE:-fable5}"
judge_note=""
case "$judge" in
  astra|gpt5.6|gpt5.5)
    if ! $codex_ok; then
      judge_note="   (FUSION_JUDGE=$judge but codex not found — falling back to Fable judging)"
      judge="fable5"
    fi
    ;;
esac
if [ "$judge" = "fable5" ] && ! $claude_ok; then
  judge="astra"
  judge_note="   (claude CLI not found — falling back to a GPT-6 Astra judge)"
fi

# --- Synthesizer: always Fable 5.1. The stable fable5 token is retained for preset compatibility. ---
synth="fable5"

slug="${FUSION_VARIANT:+$FUSION_VARIANT·}${panel_label}·judge:${judge}·synth:${synth}"

echo "recommended pipeline:"
echo "  panel       : $panel"
echo "  judge       : $judge$judge_note"
echo "  synthesize  : $synth"
echo "  claude panelists run: claude --print --dangerously-skip-permissions --model $fable_model | $opus_model"
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
