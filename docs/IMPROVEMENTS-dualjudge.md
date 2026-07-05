# Fusion harness — dual-judge + cross-model enforcement (proposal)

Improvements requested by Shadman (2026-07-05) after a `fable5-duo` run dropped GPT-5.5. Goal:
**maximum diversity of thought AND diversity of judgment, with Fable 5 as the accountable
synthesizer — but pay for Fable only where it's accountable, not everywhere.**

## The rule to enforce
- **Panel is ALWAYS cross-model:** Fable 5 + Opus 4.8 + **GPT-5.5**. Never the Fable+Opus duo — GPT-5.5
  must always be a panelist. (The default `fable5-crossmodel` already does this; the `fable5-duo` variant
  is the anti-pattern to avoid.)
- **Dual judge:** Fable 5 **and** GPT-5.5 both adjudicate (different model families → different priors →
  they catch different things). New this proposal.
- **Synthesizer/orchestrator is ALWAYS Fable 5** — writes the final answer over BOTH discernments.
- **Cost tiering:** Fable (frontier, pricey) is reserved for the accountable synthesis; the workhorse
  panelist + judge roles lean on the cheaper frontier models (Opus 4.8, GPT-5.5 — much cheaper). Diversity
  without paying Fable-everywhere.

## What this proposal adds (additive — no edits to existing files)
1. **`skills/fusion/scripts/run_dual_judge.sh`** — runs N judges (default Fable 5 + GPT-5.5) over the same
   anonymized answers, in parallel and blind, writing `judge_<model>.md` each. A failed judge is ABSENT
   (never silent agreement); exits 0 if ≥1 survives, 1 if all fail (→ inline discernment). Verified:
   both judges ran and produced discernments on a smoke task.
2. **`skills/fusion/variants/fable5-crossmodel-dualjudge.env`** — the preset encoding the rule above
   (`FUSION_PANEL=fable5,opus4.8,gpt5.5`, `FUSION_JUDGES=fable5,gpt5.5`, `FUSION_SYNTH=fable5`). Recommend
   making this (or its behavior) the **default** so a bare `/fusion` is cross-model + dual-judge.

## SKILL.md patch (apply on the fable5-era SKILL.md — the branch that ships variants/)
**Step 3 — after the single `run_judge.sh` block, add:**
> **Dual judge (diversity of judgment).** When `FUSION_JUDGES` names more than one judge — e.g. the
> `fable5-crossmodel-dualjudge` variant sets `FUSION_JUDGES=fable5,gpt5.5` — run **both** judges over the
> same anonymized answers, in parallel and blind:
> ```bash
> bash <skill_dir>/scripts/run_dual_judge.sh "$RUN_DIR/task.txt" "$RUN_DIR/answers" "$RUN_DIR/answers" high
> ```
> Two adjudicators of different model families catch different things: where they agree, trust it hard;
> where they disagree, that's where the synthesizer must decide. Fable 5 still writes the final answer,
> now grounded in BOTH discernment docs. If only one survives, proceed with it; if the helper exits
> non-zero, do the discernment inline.

**Step 4 — synthesis, add:**
> **Dual-judge synthesis.** If two discernments exist (`judge_fable5.md` + `judge_gpt5.5.md`), read BOTH.
> Lead with what the two judges agree on (highest confidence — two families, independently). Where they
> disagree, resolve it and say which judge you sided with and why. Note in the audit trail that two
> judges ran and where they diverged.

## detect_panel.sh (optional surface)
Emit a `JUDGES=` line alongside `JUDGE=` (from `$FUSION_JUDGES`, falling back to the single `JUDGE`) so
the orchestrator can branch on dual- vs single-judge without re-deriving it.

## Other areas of improvement worth a look
- **Make dual-judge cross-model the DEFAULT** (bare `/fusion`), with `/fusion-quick` for the single-judge
  fast path — matches "diversity by default, pay less by using cheaper panelists/judges."
- **Judge-of-judges only on disagreement:** when the two judges' verdicts conflict on a load-bearing
  point, that's the signal to spend more scrutiny there — cheap way to focus Fable's synthesis effort.
- **Cost telemetry:** the SLUG/attestation could record per-role model + a rough token/$ split so the
  Fable-only-where-accountable policy is measurable.
- **Verify codex hermetic-home** (already in `_lib.sh` `fusion_codex_home`) is applied to the judge path
  too, so a GPT-5.5 judge can't pull cross-project context.
