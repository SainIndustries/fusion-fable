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
# Remove commands renamed in the Fable 5 migration so stale copies don't linger.
rm -f "$CLAUDE_DIR/commands/fusion-opus4.8.md"
cp -R "$HERE/skills/fusion" "$CLAUDE_DIR/skills/fusion"
chmod +x "$CLAUDE_DIR/skills/fusion/scripts/"*.sh

echo "✓ Installed Fusion-Fable (Sain Industries fork) into $CLAUDE_DIR"
echo "    skill    : $CLAUDE_DIR/skills/fusion"
echo "    commands : /fusion  /fusion-gpt5.5  /fusion-fable5  /codex-expert"
echo

# Report what the pipeline can do on this machine.
# Pipeline: fan out (blind panelists) → JUDGE (discernment) → Fable 5 SYNTHESIZE.
have() { command -v "$1" >/dev/null 2>&1; }
claude_model="${FUSION_CLAUDE_MODEL:-claude-fable-5}"
echo "Pipeline availability here (fan out → judge → synthesize):"
if have claude; then
  echo "  panelists: Claude Fable 5 via the claude CLI"
  echo "             (claude --print --dangerously-skip-permissions --model $claude_model)"
else
  echo "  panelists: WARNING — 'claude' CLI not on PATH; Fable panelists fall back to Agent subagents"
fi
if have codex; then
  echo "  flagship : ready — 2× Fable 5 + GPT-5.5 panel, GPT-5.5 judges, Fable 5 synthesizes"
  echo "             (codex found: $(codex --version 2>/dev/null | head -1))"
  echo "  experts  : ready — persistent codex domain experts via /codex-expert (codex exec resume)"
else
  echo "  flagship : needs the 'codex' CLI for the GPT-5.5 judge + panelist (install + log in)"
  echo "  fallback : ready — 2× Fable 5 runs, Fable judges + synthesizes (no external CLI)"
  echo "  experts  : needs the 'codex' CLI for persistent domain experts"
fi
if have gemini; then
  echo "  +gemini  : available as an OPTIONAL extra panelist — set FUSION_USE_GEMINI=1 (gemini found)"
else
  echo "  +gemini  : optional extra panelist (off by default; needs the 'gemini' CLI + FUSION_USE_GEMINI=1)"
fi
echo
echo "Reminder: the fusion skill only runs when EXPLICITLY invoked, and only from a Claude Fable 5"
echo "session (switch with: /model fable). A single Fable 5 answer is the default for everything else."
echo
echo "Next: restart Claude Code (or run /reload-skills) so 'fusion' and the slash commands load."
