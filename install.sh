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
cp -R "$HERE/skills/fusion" "$CLAUDE_DIR/skills/fusion"
cp "$HERE/commands/"*.md "$CLAUDE_DIR/commands/"
chmod +x "$CLAUDE_DIR/skills/fusion/scripts/"*.sh

echo "✓ Installed Fusion-Fable (Sain Industries fork) into $CLAUDE_DIR"
echo "    skill    : $CLAUDE_DIR/skills/fusion"
echo "    commands : /fusion  /fusion-gpt5.5  /fusion-opus4.8  /codex-expert"
echo

# Report what the pipeline can do on this machine.
# Pipeline: fan out (blind panelists) → JUDGE (discernment) → Opus 4.8 SYNTHESIZE.
have() { command -v "$1" >/dev/null 2>&1; }
echo "Pipeline availability here (fan out → judge → synthesize):"
if have claude; then
  echo "  panelists: Opus 4.8 via claude CLI under the Claude Fable 5 system prompt"
  echo "             (claude --print --dangerously-skip-permissions --model opus --system-prompt-file CLAUDE-FABLE-5.md)"
else
  echo "  panelists: WARNING — 'claude' CLI not on PATH; Opus panelists fall back to Agent subagents"
fi
if [ -s "$CLAUDE_DIR/skills/fusion/CLAUDE-FABLE-5.md" ]; then
  echo "  fable5   : installed at skills/fusion/CLAUDE-FABLE-5.md"
else
  echo "  fable5   : WARNING — CLAUDE-FABLE-5.md missing from the skill; panelists can't load the Fable 5 prompt"
fi
if have codex; then
  echo "  flagship : ready — 2× Opus 4.8 + GPT-5.5 panel, GPT-5.5 judges, Opus 4.8 synthesizes"
  echo "             (codex found: $(codex --version 2>/dev/null | head -1))"
  echo "  experts  : ready — persistent codex domain experts via /codex-expert (codex exec resume)"
else
  echo "  flagship : needs the 'codex' CLI for the GPT-5.5 judge + panelist (install + log in)"
  echo "  fallback : ready — 2× Opus 4.8 runs, Opus judges + synthesizes (no external CLI)"
  echo "  experts  : needs the 'codex' CLI for persistent domain experts"
fi
if have gemini; then
  echo "  +gemini  : available as an OPTIONAL extra panelist — set FUSION_USE_GEMINI=1 (gemini found)"
else
  echo "  +gemini  : optional extra panelist (off by default; needs the 'gemini' CLI + FUSION_USE_GEMINI=1)"
fi
echo
echo "Next: restart Claude Code (or run /reload-skills) so 'fusion' and the slash commands load."
