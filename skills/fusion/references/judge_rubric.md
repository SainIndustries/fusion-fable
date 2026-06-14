# Judge rubric — discernment, then synthesis

This fork splits the old single Opus "judge + write" pass into two stages, each given to the model that's
better at it:

1. **Discernment (the judge) — GPT-5.5 via `scripts/run_judge.sh`.** Reads every panelist answer *after*
   all returned independently and produces a structured analysis: who's right, where they conflict, what's
   load-bearing vs weak. It does **not** write the final answer.
2. **Synthesis (the writer) — Opus 4.8, the orchestrator (you).** Reads the judge's discernment doc plus
   the raw answers and writes the final answer grounded in it. Opus always writes the final answer — the
   invariant holds.

If codex is unavailable (not installed, or capped — `run_judge.sh` exits non-zero), **you (Opus) do the
discernment yourself** using this same rubric, then synthesize. A missing judge degrades the run; it never
breaks it.

Two non-negotiables for the discernment stage:

- **Anonymize.** Panelist answers go to the judge as Panelist A / B / C in shuffled order; the judge never
  learns which model wrote which. This is what stops a GPT-5.5 judge from favoring the GPT-5.5 panelist's
  own answer. You keep the label→model map and restore real attribution only at synthesis time.
- **Classify the deliverable first**, because code and prose are judged completely differently:
  - **Artifact task** (code, script, config, schema, datapack) → **Track A: run both, then merge.**
  - **Research / analysis task** (understanding, a recommendation, a written answer) → **Track B:
    structured synthesis** (the five sections).

  When a task is mixed ("design and implement X"), the implementation is the deliverable: Track A for the
  code, fold the reasoning in as brief rationale.

---

## Track A — run both, then merge (code / artifacts)

The output is **one working artifact**, not a prose report and not two solutions pasted together. Decide
what to keep by **actually running the candidates** — don't merge from reading alone.

The discernment stage is a strong fit for a codex judge here: `run_judge.sh` gives codex a writable sandbox
with the candidates copied in, so it can build and run each one and report observed behavior. Whoever does
discernment (codex judge, or Opus on fallback) should:

1. **Understand each candidate.** Architecture/approach, what it gets right, where it's buggy, incomplete,
   or fragile; the concrete differences (APIs, data structures, algorithms, file layouts, edge cases).
2. **Run each candidate.** Build them, run them, run tests, lint, feed representative inputs. Record what
   passes and breaks in each. Observed behavior is ground truth and outranks what "looks" better. (If it
   genuinely can't be executed here, say so, fall back to seam-reasoning, and mark the result unverified.)
3. **Resolve disagreements by what actually ran.** Prefer the version that demonstrably worked. Never
   average two answers or keep both "to be safe." Two candidates that ran correctly the same way is the
   strongest signal.

Then the synthesizer (Opus):

4. **Pick a foundation, then graft the parts that worked — don't blend.** Strongest implementation as the
   base; pull in the *specific* pieces from the other that were observed to work. One coherent design,
   consistent style — never a Frankenstein of two whole programs.
5. **Run the merged artifact and fix until it works.** The seam between grafted pieces (mismatched
   signatures, imports, types, units, indexing) is exactly where a merge silently breaks. Build/run/test
   the merged result; fix and re-run until it passes. Emit the whole thing — every file, ready to run.
6. **Brief merge rationale.** What each candidate did when run, what you took from each and why, which
   disagreements you resolved how, and what you verified.

The point of the panel for code is that two independent attempts expose each other's bugs — the merge
should end up *more correct than either input*.

---

## Track B — structured synthesis (research / analysis)

The discernment doc (from the judge) carries these sections; the synthesizer builds the final answer from
them.

### Per-panelist assessment
For each panelist: approach, what it gets right, where it's wrong/weak/unsupported, and evidence quality
(ran code / cited a primary source / reasoned from memory).

### Consensus
Points panelists independently agree on. Independent agreement — across model families, or even two cold
runs of the same model — is the highest-confidence signal. Note how many converged and whether by
different routes.

### Contradictions
Direct disagreements on fact or recommendation. State the competing positions, who holds them, and
adjudicate: which side ran the code, read the primary source, has better evidence? If unresolved, say so
and name what would settle it. Never bury a real conflict to look tidy.

### Partial coverage
Important sub-questions only some panelists engaged — depth a single answer would have missed.

### Unique insights
Non-obvious, valuable points raised by exactly one panelist — often the highest-leverage payoff of fanning
out. Preserve them even if off the majority view.

### Blind spots
What the panel as a whole missed or got wrong, including shared assumptions none questioned. The judge may
add one the panel didn't name.

### Discernment verdict
The handoff to synthesis: which specific claims are load-bearing AND well-supported (keep), which are
weak/contradicted (discard or hedge), and the recommended spine for the final answer.

### Final answer (written by Opus, the synthesizer)
Grounded in the above: lead with high-confidence consensus, fold in the unique insights, flag what stays
uncertain. It must follow *from* the discernment, not be one panelist's answer lightly edited. Restore real
panelist attribution here (de-anonymize A/B/C back to the models) so the user can trace each decision.

---

## Principles (both tracks)

- Evidence over assertion: a panelist that ran the code or read the primary source outranks one reasoning
  from memory, regardless of model.
- Be honest about confidence and disagreement — a result that hides a real conflict is worse than no panel.
- Keep attribution so the user can trace any decision back to its source.
- A failed or dropped panelist is **absent**, never silent agreement.
- For artifacts, "looks plausible" is not done; **verified to run** is. Fall back to seam-reasoning only
  when execution is genuinely impossible, and say so.
