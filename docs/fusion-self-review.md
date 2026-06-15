# Fusion-Fable self-review — produced by running Fusion on itself

*Generated 2026-06-15 by dogfooding the skill: three blind panelists reviewed this repo, then the answers
were judged and synthesized. This document lives only on the Sain Industries fork.*

## How this was produced (and an important caveat)

The pipeline was run on the question *"how can this repo be improved, and does running multiple Fusion runs
at once interfere?"* Panel: two Opus 4.8 panelists (via `run_claude.sh`, Fable 5 prompt) + one GPT-5.5
panelist (codex). Intended judge: GPT-5.5 (codex).

**What actually happened is itself finding #0.** Both codex-backed stages — the GPT-5.5 *panelist* and the
GPT-5.5 *judge* — ignored the task they were given and instead answered an unrelated **"Aura MCP server"
design task** (moreaura.ai), which is one of this machine's other codex projects. The two Opus panelists
answered correctly. So the run fell back to **Opus doing the discernment** (the skill's documented codex-
unavailable path), treating the codex panelist as contaminated/absent. The findings below are synthesized
from the two on-task Opus reviews, cross-checked against the code directly.

---

## Finding #0 (new, highest-impact) — `codex exec` is not isolated; it leaks other projects' context

Two independent `codex exec` invocations (`run_codex.sh`, `run_judge.sh`), each given a fusion-repo prompt
in a fresh `mktemp` scratch `--cd`, both produced detailed answers about a *different* project ("Aura"). The
common cause is codex's persistent global state: `~/.codex/.codex-global-state.json` (~384 KB),
`~/.codex/session_index.jsonl`, and `~/.codex/external_agent_session_imports.json` are full of "aura"
references. `codex exec` is pulling that cross-project memory in regardless of `--cd`, and it can **override
the actual task**.

Why this matters for Fusion specifically:

- **The judge can confabulate the task** and reject correct panelist work (it happened here). A judge whose
  task can be silently replaced is worse than no judge.
- **A codex panelist can answer the wrong question** while looking confident — exactly the "confidently
  wrong" failure the skill exists to prevent.
- It undermines the independence/anonymization story: a contaminated codex stage isn't a clean blind run.

Recommended response (needs a focused repro once codex quota is free):
1. Make codex runs hermetic — investigate `codex exec --ephemeral` and/or config flags that disable memory
   / session-import / `AGENTS.md` discovery, and set them in `run_codex.sh` and `run_judge.sh`.
2. **Validate outputs against the task** before trusting them (see P1 "judge output validation" below) — a
   judge doc that doesn't engage the task should trigger the Opus fallback, which is what saved this run by
   hand.
3. Until hermeticity is confirmed, document that codex stages may inherit local codex project context.

**RESOLVED (2026-06-15).** Root cause located: `~/.codex` session-history/memory files (`session_index.jsonl`,
`transcription-history.jsonl`, `external_agent_session_imports.json`) carried other-project ("Aura") context
that `codex exec` pulled into fresh runs. Fix (by construction): `run_codex.sh` and `run_judge.sh` now run
codex in a dedicated **hermetic `CODEX_HOME`** containing only an `auth.json` symlink (no sessions, memory,
projects, or plugins), plus `--ignore-user-config` (helper `fusion_codex_home` in `_lib.sh`; disable with
`FUSION_CODEX_HERMETIC=0`). Verified live: a control prompt through the hermetic runner answered exactly the
task asked with zero cross-project leakage, and auth still worked.

---

## Part 1 — Concurrency: yes, simultaneous runs corrupt each other, silently

Running several Fusion runs at once on one machine (e.g. different Claude Code sessions in different
projects) **does interfere**, and the failure is silent — wrong answers, not crashes.

**The scripts themselves are safe.** Every runner mints a private sandbox with `mktemp -d` and cleans it on
exit (`run_claude.sh:47`, `run_codex.sh:23`, `run_judge.sh:51`, `codex_expert.sh:76`). Two runners never
collide *inside* a script.

**The bug is one layer up, in `SKILL.md`,** which hands the orchestrating Claude fixed, machine-global
`/tmp` paths as the contract between stages. Every session resolves `<skill_dir>` to the same
`~/.claude/skills/fusion` and is told to use the same constants:

- `SKILL.md:85-86` — `/tmp/fusion_claude1_prompt.txt`, `/tmp/fusion_claude1_out.md`, `/tmp/fusion_claude2_*`
- `SKILL.md:95` — `/tmp/fusion_codex_prompt.txt`, `/tmp/fusion_codex_out.md`
- `SKILL.md:98` — `/tmp/fusion_gemini_*`
- `SKILL.md:110` — `mkdir -p /tmp/fusion_answers && rm -f /tmp/fusion_answers/panelist_*.md`
- `SKILL.md:115` — `/tmp/fusion_task.txt`
- `SKILL.md:122` — `/tmp/fusion_judge.md`

Concrete races when two runs (A, B) overlap, worst first:

1. **Shared answers dir → confidently wrong answer.** Both runs write `panelist_A/B/C.md` into the same
   `/tmp/fusion_answers/`, and B's `rm -f` (`SKILL.md:110`) can fire while A's judge is reading
   (`run_judge.sh` globs `panelist_*.md` at `:45`). A's judge then scores a mixture of A's and B's panelists
   — or B's answers to a different question — and synthesis produces a polished answer to a question nobody
   asked. No crash, no warning.
2. **Output clobber / empty-output false failure.** Both write `/tmp/fusion_claude1_out.md`; last finisher
   wins, and the other run reads it as its own panelist. A clobber at the wrong instant leaves an empty file,
   which the runners treat as failure (`run_claude.sh:59`, `run_codex.sh:37`), silently shrinking the panel.
3. **Prompt-file TOCTOU.** The prompt is read at exec time via `"$(cat "$prompt_file")"` (`run_claude.sh:56`);
   a second run overwriting `/tmp/fusion_*_prompt.txt` in the window makes a panelist answer the wrong
   question.
4. **Judge-doc clobber.** `/tmp/fusion_judge.md` is shared; A can synthesize from B's discernment.
5. **Attribution map breaks.** `SKILL.md:114` keeps the label→model map only in the orchestrator's context;
   once the underlying files are mixed by (1)/(2), de-anonymization restores the *wrong* attribution.

**Persistent experts have a separate shared-state hazard.** Session ids live at
`$FUSION_HOME/experts/<name>.id` (`codex_expert.sh:75`), shared across the machine. Two concurrent first
calls to a new name both create a session and both `echo "$sid" > "$id_file"` (`:100`, non-atomic) — one
session is orphaned, its accumulated context lost. Two concurrent resumes of the same name append to one
codex session rollout simultaneously (`:90`) and can interleave/corrupt it. (Distinct names are safe.)

### The fix

Stop using machine-global paths as the inter-stage contract. Because each Claude Code `Bash` call is a fresh
shell (an `export RUN_DIR=` in one call is gone in the next), the robust approach is to have a *script* mint
the run dir and emit it, then have the orchestrator substitute that literal path everywhere:

```bash
# in detect_panel.sh, alongside PANEL=/JUDGE=/SYNTH=/SLUG=
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/fusion-run.XXXXXX")"
echo "RUN_DIR=$run_dir"
```

Then rewrite `SKILL.md:85-122` to use `<RUN_DIR>/claude1_prompt.txt`, `<RUN_DIR>/answers/`,
`<RUN_DIR>/task.txt`, `<RUN_DIR>/judge.md`, …, with an explicit instruction to grep `RUN_DIR=` and use that
exact directory for every intermediate file — never a shared `/tmp/fusion_*` path. Delete the `rm -f` at
`:110` (a fresh dir is already empty). This makes every run's intermediates disjoint by construction and
closes races 1–5.

For experts: serialize per name with a lock and write the id atomically.

```bash
exec 9>"$id_file.lock"; flock 9                                   # queue same-name calls
tmp="$id_file.$$"; echo "$sid" > "$tmp" && mv -f "$tmp" "$id_file"  # atomic id write
```

Note `flock` (and `timeout`, below) are **absent on stock macOS** — ship a `mkdir`-based lock fallback.

*(Caveat on evidence: a panelist cited "wreckage" already in `/tmp` — zero-byte and renamed `fusion_*` out
files. Some of that is leftover from this repo's own manual test runs this session, not purely organic
collisions. The races above are real from the code paths regardless.)*

---

## Part 2 — Highest-impact innovations, prioritized

### P0 — silent correctness bugs that violate the skill's own promises

- **Pin the codex panelist model.** `run_codex.sh:26-34` calls `codex exec` with **no `-m` flag**, so the
  panelist runs codex's configured default — which may not be GPT-5.5. The judge *does* pin `-m`
  (`run_judge.sh`), so the README's "2× Opus + GPT-5.5" is only guaranteed for the judge. One-line fix: add
  `-m "${CODEX_PANELIST_MODEL:-gpt-5.5}"`. (Combined with Finding #0, codex stages need both a pinned model
  *and* hermetic context.)
- **Stop the SLUG/docs lying about Gemini.** `detect_panel.sh` labels it `gemini3.1pro` and the README says
  "Gemini 3.1 Pro," but `run_gemini.sh:26` runs `gemini-2.5-pro` (the script's own comment notes 3.1 Pro
  404s). Derive the label from `${GEMINI_MODEL:-gemini-2.5-pro}` so provenance can't drift — corrosive in a
  tool whose value is auditability.
- **Make anonymization mechanical.** `SKILL.md:110-115` asks Opus to write answers "in a RANDOM order" and
  "keep the label→model map yourself." LLMs randomize poorly (positional bias defeats the anti-self-
  preference purpose) and an in-context map invites mis-attribution. Add `anonymize.sh` that shuffles with a
  real RNG and writes `panelist_*.md` + `map.json` into the run dir. Optionally strip first-person model
  self-references ("I ran the code…") that de-anonymize by style.

### P1 — reliability & observability (runs can hang or vanish)

- **Timeouts everywhere.** No runner bounds its CLI call; a wedged panelist (with skip-permissions / gemini
  `--yolo`) hangs the whole fan-out forever — acute in the `/loop` pattern the README promotes. Wrap each in
  `FUSION_TIMEOUT` (~600s) with a macOS-safe shim (`gtimeout`, else `perl -e 'alarm shift; exec @ARGV'`).
- **Keep logs on failure.** Every runner's `trap 'rm -rf "$scratch"' EXIT` deletes the only forensic trail;
  on a surprising answer the panelist answers, judge doc, and stream logs are already gone. Honor
  `FUSION_KEEP=1`/`FUSION_DEBUG=1` and copy logs into `<RUN_DIR>/logs/` on non-zero exit.
- **Validate the judge's output.** `run_judge.sh` checks only non-empty (`:127`). Grep for the required
  section headers; if missing (or, per Finding #0, if it doesn't engage the task), exit non-zero so the Opus
  fallback engages instead of synthesizing over garbage. *This is the guard that would have auto-caught this
  very run.*
- **Enforce the partial-panel guarantee.** "A dropped panelist is absent, never silent agreement" is
  documented (`SKILL.md:101`) but not enforced — nothing refuses to judge when <2 panelists returned. Add a
  fan-out/collect wrapper that checks the count.
- **Retry transient failures.** A single codex rate-limit or transient `claude` error drops a panelist
  permanently. Add bounded retry+backoff (`FUSION_RETRIES=2`) before declaring it dead.
- **Optional repo-grounding for panelists.** Panelists run in an empty scratch `--cd`, so a question *about
  the user's codebase* is answered from generic web knowledge unless the repo path is passed in by hand (as
  was needed for this very review). Add an opt-in read-only view (`FUSION_PANEL_CWD` / `--add-dir`) so
  repo-grounded questions are actually grounded, keeping writes contained.
- **Make Track A real.** The judge is told to "RUN" candidate code, but code arrives embedded in markdown
  fences inside `panelist_*.md` (`run_judge.sh:55`) — nothing extracts it to runnable files, so "verified to
  run" rarely happens. Have panelists emit artifacts as real files, or extract fenced blocks before judging.

### P2 — cost / latency

- **Content-addressed caching.** The README sells the `/loop` pattern and warns cost compounds, yet
  identical prompts re-run the full panel+judge every iteration. Cache panelist answers keyed on
  `sha256(prompt+model+effort)` under `$FUSION_HOME/cache/` with a TTL and `FUSION_NO_CACHE` escape — the
  biggest cost lever given intended usage.
- **Per-run manifest.** Persist `<RUN_DIR>/manifest.json` (which panelists launched/returned/timed out,
  time + token/cost per stage) for honest cost accounting and observability in one artifact.

### P3 — configurability, testing, portability

- **One config source of truth.** Model ids are scattered (`run_judge.sh`, `codex_expert.sh`,
  `run_claude.sh`, `run_gemini.sh`); a sourced `config.sh` (`FUSION_OPUS_MODEL`, `FUSION_CODEX_MODEL`,
  `FUSION_JUDGE_MODEL`, `FUSION_GEMINI_MODEL`) stops drift (and fixes the SLUG-lies item structurally).
- **Expose hardcoded knobs.** Panelist count (fixed at two in prose) and efforts (`medium`/`high` at call
  sites) → `FUSION_OPUS_PANELISTS`, `FUSION_PANEL_EFFORT`, `FUSION_JUDGE_EFFORT`, emitted by
  `detect_panel.sh`.
- **Add tests + a dry run.** No tests exist for logic whose failures are silent: the judge exit-code
  contract, the expert session-id capture regex (`codex_expert.sh:97-98`, breaks if codex changes log
  format), detection/fallback selection. Add `tests/` with stub `claude`/`codex`/`gemini` shims on PATH and
  a `FUSION_DRY_RUN=1` that echoes commands without calling the CLIs.
- **Detection should probe auth, not just presence.** `detect_panel.sh` only runs `command -v`; a
  logged-out/capped codex passes detection then fails at runtime. A cheap auth probe lets the skill say up
  front "codex present but not authenticated; running fallback."
- **Portability snags.** `run_gemini.sh:26` uses bash process substitution (`2> >(tail …)`), which breaks
  under `sh` and isn't covered by `pipefail`; `install.sh` `cp commands/*.md` clobbers same-named user
  commands with no backup; `--system-prompt-file` works but is absent from `claude --help`, so a CLI bump
  could silently neuter the Fable 5 prompt — have `install.sh` probe and warn.

---

## If you ship only a few things

1. **Per-run directories + expert locks** (Part 1) — stop silent cross-run corruption.
2. **Hermetic + model-pinned codex, and judge-output validation** (Finding #0, P0 model pin, P1 validation)
   — so the judge/panelist can't be silently hijacked or mis-modeled. This run is the proof it can happen.
3. **Timeouts + kept logs** (P1) — so runs can't hang forever and failures are debuggable.
4. **Scripted anonymization with a durable map** (P0) — make the anti-bias mechanism and attribution real.
5. **Content-addressed caching** (P2) — the biggest cost lever for the `/loop` usage the docs promote.

---

## Audit trail — panel `opus4.8x2+gpt5.5 · judge:gpt5.5 · synth:opus4.8` (degraded)

- **Opus run 1 (panelist A)** and **Opus run 2 (panelist C)** — both on-task, code-grounded, strongly
  convergent; the substance above is theirs, cross-checked against the code. Run 2 added the unpinned-codex-
  panelist catch, judge-output validation, auth-probe, and portability snags; Run 1 added partial-panel
  enforcement, retries, repo-grounding, and the Track-A extraction gap.
- **GPT-5.5 panelist (B)** — **contaminated/off-task** (answered an "Aura MCP" task); treated as absent.
- **GPT-5.5 judge** — **contaminated/off-task** (same Aura task); discernment fell back to Opus per the
  skill's documented codex-unavailable path.
- **Opus synthesis** — this document.

The contamination wasn't a flaw in the panel *idea* — independence still surfaced the truth, because the two
clean Opus panelists agreed and the dirty codex stages were caught and discarded. But it is a concrete,
reproduced argument for Finding #0 and the P1 output-validation guard.
