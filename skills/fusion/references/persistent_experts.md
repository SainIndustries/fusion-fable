# Persistent codex domain experts

The panel is a **one-shot** pattern: fan out, judge, synthesize, done. Some work is the opposite shape —
**iterative** and context-heavy, where each step builds on everything learned in the steps before:
debugging a subsystem over many hypotheses, driving a migration file by file, refactoring against a fixed
spec, exploring an unfamiliar codebase.

For that work, a fresh subagent per turn is the wrong tool — it throws away the context each time and you
pay to rebuild it. codex's session compaction is good enough to keep a long-lived **domain expert**
coherent across dozens of turns, so you prime it once and keep asking. `scripts/codex_expert.sh` manages
these persistent sessions.

## When to use an expert vs the panel vs a subagent

- **Panel (the fusion skill)** — a single high-stakes question where being confidently wrong is expensive,
  and independent cross-checking is the point. One shot.
- **Persistent codex expert** — a long iterative thread on one domain where continuity pays off: the expert
  should remember the last 20 turns. Use when you'll ask the same expert many related follow-ups.
- **Ephemeral Opus subagent (Agent tool)** — a self-contained sub-task you only need answered once, where
  prior context doesn't matter. Still the right default for parallel one-off fan-out.

A natural combination: run the panel once to decide the approach, then spin up a persistent codex expert to
*execute* it across many iterative turns.

## Using `codex_expert.sh`

```bash
# First call to a name starts a session and remembers its id:
bash <skill_dir>/scripts/codex_expert.sh payments-debugger \
  "You are my expert on the payments service in this repo. Read src/payments/, then tell me where retries can double-charge."

# Every later call to the SAME name resumes that session — the expert remembers the earlier turns:
bash <skill_dir>/scripts/codex_expert.sh payments-debugger \
  "Now propose a fix for the double-charge path you found, with a test."

bash <skill_dir>/scripts/codex_expert.sh payments-debugger -   # prompt from stdin
echo "apply it and run the test" | bash <skill_dir>/scripts/codex_expert.sh payments-debugger -

bash <skill_dir>/scripts/codex_expert.sh --list                # list known experts + session ids
bash <skill_dir>/scripts/codex_expert.sh --forget payments-debugger   # start that expert fresh
```

Conventions that keep an expert useful:

- **Name by domain, not by task** — `payments-debugger`, `schema-migrator`, `frontend-refactor`. The name
  is the session key; reuse it for every turn on that domain.
- **Prime it on the first turn.** Give it its remit and point it at the relevant files. It has a writable
  sandbox and web search, so it can read, run, and verify, not just reason.
- **One expert per concern.** Don't pour unrelated threads into one session — separate experts stay sharper
  and compaction stays cleaner.
- **Reset when the thread goes stale** with `--forget <name>` (or after a big refactor invalidates its
  mental model).

## Knobs

- `FUSION_HOME` — where session ids are stored (default `~/.fusion`; experts under `$FUSION_HOME/experts`).
- `EXPERT_MODEL` — model for experts (default `gpt-5.5`).
- `FUSION_EXPERT_SANDBOX` — codex sandbox mode (default `workspace-write`).
- `FUSION_EXPERT_CWD` — directory the expert operates in (default: current directory).

## Caveats

- Experts are **not** independent panelists — they accumulate context on purpose. Never use one as a
  panelist in a fusion run; that would violate the independence the panel depends on.
- Session continuity depends on codex persisting sessions to disk; if you run with codex's
  no-persistence mode, resume won't work. `codex_expert.sh` captures the session id on the first turn and
  resumes by id thereafter.
