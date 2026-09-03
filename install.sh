#!/usr/bin/env bash
# install.sh — install the Fusion-Fable skill + slash commands into your Claude Code config.
#
# Copies:
#   skills/fusion        -> $CLAUDE_DIR/skills/fusion
#   commands/*.md         -> $CLAUDE_DIR/commands/
# where CLAUDE_DIR defaults to ~/.claude (override with CLAUDE_CONFIG_DIR).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"

rm -rf "$CLAUDE_DIR/skills/fusion"
cp "$HERE/commands/"*.md "$CLAUDE_DIR/commands/"
# Remove commands renamed in past migrations so stale copies don't linger.
rm -f "$CLAUDE_DIR/commands/fusion-opus4.8.md"   # pre-Fable-GA
rm -f "$CLAUDE_DIR/commands/fusion-gpt5.5.md"    # renamed to fusion-gpt5.6 in the GPT-5.6 migration
cp -R "$HERE/skills/fusion" "$CLAUDE_DIR/skills/fusion"
chmod +x "$CLAUDE_DIR/skills/fusion/scripts/"*.sh

echo "✓ Installed Fusion-Fable (Sain Industries fork) into $CLAUDE_DIR"
echo "    skill    : $CLAUDE_DIR/skills/fusion"
echo "    commands : /fusion  /fusion-gpt5.6  /fusion-fable5  /fusion-variant  /codex-expert"
echo "    variants : $(cd "$CLAUDE_DIR/skills/fusion/variants" 2>/dev/null && ls -- *.env 2>/dev/null | sed 's/\.env$//' | tr '\n' ' ')"
echo

# Report what the pipeline can do on this machine.
# Pipeline: fan out (blind cross-model panelists) → Fable 5.1 JUDGE (fresh blind subprocess) → Fable 5.1 SYNTHESIZE.
have() { command -v "$1" >/dev/null 2>&1; }
claude_model="${FUSION_CLAUDE_MODEL:-claude-fable-5-1}"
opus_model="${FUSION_OPUS_MODEL:-opus}"
echo "Pipeline availability here (fan out → judge → synthesize):"
if have claude; then
  echo "  claude   : Claude Fable 5.1 panelist + blind Fable 5.1 judge + synthesizer, via the claude CLI"
  echo "             (claude --print --dangerously-skip-permissions --model $claude_model)"
else
  echo "  claude   : WARNING — 'claude' CLI not on PATH; Claude panelists fall back to Agent subagents"
fi
if have codex; then
  echo "  flagship : ready — Fable 5.1 + GPT-5.6 Sol panel, Fable 5.1 judges + synthesizes"
  echo "             (GPT-5.6 Sol judging available via FUSION_JUDGE=gpt5.6 or /fusion-gpt5.6)"
  echo "             (codex found: $(codex --version 2>/dev/null | head -1))"
  echo "  experts  : ready — persistent codex domain experts via /codex-expert (codex exec resume)"
else
  echo "  flagship : needs the 'codex' CLI for the GPT-5.6 Sol panelist (install + log in)"
  echo "  fallback : ready — Fable 5.1 + Opus 4.8 panel (Opus is the codex-absent fallback), Fable judges (claude CLI only)"
  echo "  experts  : needs the 'codex' CLI for persistent domain experts"
fi
if have gemini; then
  echo "  +gemini  : available as an OPTIONAL extra panelist — set FUSION_USE_GEMINI=1 (gemini found)"
else
  echo "  +gemini  : optional extra panelist (off by default; needs the 'gemini' CLI + FUSION_USE_GEMINI=1)"
fi
echo
echo "Reminder: the fusion skill only runs when EXPLICITLY invoked, and only from a Claude Fable 5.1"
echo "session (switch with: /model fable). A single Fable 5.1 answer is the default for everything else."
echo
echo "Next: restart Claude Code (or run /reload-skills) so 'fusion' and the slash commands load."
