---
description: Talk to a persistent codex (GPT-5.5) domain expert that remembers across turns
argument-hint: <expert-name> <prompt>
---
Use a **persistent codex domain expert** for iterative, context-heavy work (debugging a subsystem over many
turns, driving a migration, refactoring against a spec) — the opposite of the one-shot fusion panel. Read
the fusion skill's `references/persistent_experts.md`, then drive `scripts/codex_expert.sh`.

The first word of the arguments is the **expert name** (name it by domain, e.g. `payments-debugger`); the
rest is the prompt. The first call to a name starts a codex session and remembers its id; every later call
to the same name resumes that session, so the expert remembers earlier turns.

```bash
bash <skill_dir>/scripts/codex_expert.sh <expert-name> "<the rest of the prompt>"
```

If this is the first turn for that expert, prime it: give it its remit and point it at the relevant files.
On follow-ups, just continue — it has the prior context. Use `--list` to see known experts and `--forget
<name>` to start one fresh. Do NOT use an expert as a fusion panelist — experts accumulate context on
purpose and would break the panel's independence.

Arguments: $ARGUMENTS
