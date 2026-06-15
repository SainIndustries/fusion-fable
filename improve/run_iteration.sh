#!/usr/bin/env bash
# run_iteration.sh — deterministic driver + guardrails for the Fusion self-improvement /loop.
#
# Claude calls these subcommands; THIS SCRIPT enforces every guardrail. Claude proposes how to implement an
# item; the driver decides whether the loop may continue and whether a change may be committed. The model
# must never edit state.json/roadmap.json by hand — only this script mutates them (atomic mv writes).
#
# Subcommands:
#   init                  capture baseline (check.sh) + started_at; refuse if baseline is already red
#   next                  enforce ALL stop conditions; require clean tree + green baseline; pick next item
#   fused <id>            record one Fusion design run was spent (budget accounting)
#   commit <id>           run check.sh; commit atomically if green, else revert working tree + attempts++
#   gate  <id>            write a human-approval proposal, mark awaiting-human, move on (no code touched)
#   abort <id> <reason>   revert working tree, attempts++ (couldn't implement cleanly)
#   status                print the backlog + budget
#
# Stop conditions (next prints `HALT=<reason>` and exits 0): manual STOP sentinel, max_iterations,
# max_fusions, wall-clock deadline, thrash (consecutive_no_progress), dirty tree, red baseline, backlog done.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 3; }
cd "$ROOT" || exit 3
DIR="$ROOT/improve"; RM="$DIR/roadmap.json"; ST="$DIR/state.json"; LOG="$DIR/progress.md"
EXCL=":(exclude)improve"

now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
say(){ printf '%s\n' "$*"; }
logln(){ printf -- '- %s  %s\n' "$(now)" "$*" >> "$LOG"; }
jread(){ jq -r "$1" "$ST"; }
setst(){ local t="$ST.$$"; jq "$1" "$ST" > "$t" && mv -f "$t" "$ST"; }
setrm(){ local t="$RM.$$"; jq "$1" "$RM" > "$t" && mv -f "$t" "$RM"; }
item(){ jq -c --arg i "$1" '.items[]|select(.id==$i)' "$RM"; }
clean_tree(){ [ -z "$(git status --porcelain -- . "$EXCL")" ]; }
revert_tree(){ git checkout -q -- . "$EXCL" 2>/dev/null || true; git clean -fdq -e improve 2>/dev/null || true; }
halt(){ setst ".halted=true | .halt_reason=\"$1\""; logln "HALT: $1"; say "HALT=$1"; exit 0; }

cmd="${1:-status}"; shift 2>/dev/null || true
case "$cmd" in
  init)
    if [ "$(jread .baseline_pass)" != "null" ]; then say "already initialized (baseline_pass=$(jread .baseline_pass))"; exit 0; fi
    if bash "$DIR/check.sh" >/dev/null 2>&1; then base=true; else base=false; fi
    [ "$base" = true ] || { echo "BASELINE RED — fix the tree (check.sh fails at HEAD) before looping." >&2; exit 1; }
    setst ".baseline_pass=true | .started_at=\"$(now)\""
    logln "INIT baseline green"; say "baseline_pass=true" ;;

  next)
    [ -f "$DIR/STOP" ] && halt "manual-stop (improve/STOP present)"
    [ "$(jread .halted)" = "true" ] && halt "$(jread .halt_reason)"
    [ "$(jread .baseline_pass)" = "null" ] && { echo "run 'init' first" >&2; exit 2; }
    # init deadline on first next
    if [ "$(jread .deadline_epoch)" = "0" ]; then
      hrs="$(jread .max_runtime_hours)"; setst ".deadline_epoch=$(( $(date +%s) + hrs*3600 ))"
    fi
    it=$(jread .iteration); mx=$(jread .max_iterations); [ "$it" -ge "$mx" ] && halt "max-iterations ($mx)"
    fc=$(jread .fusion_calls); fm=$(jread .max_fusions); [ "$fc" -ge "$fm" ] && halt "fusion-budget ($fm runs)"
    [ "$(date +%s)" -ge "$(jread .deadline_epoch)" ] && halt "deadline (max_runtime_hours)"
    np=$(jread .consecutive_no_progress); nm=$(jread .max_no_progress); [ "$np" -ge "$nm" ] && halt "thrash-guard ($np no-progress iterations)"
    clean_tree || halt "dirty-working-tree (commit or discard manual edits, then resume)"
    bash "$DIR/check.sh" >/dev/null 2>&1 || halt "baseline-red (repo failing tests at HEAD — human needed)"

    nxt="$(jq -c '
      ([.items[]|select(.status=="done").id]) as $done
      | [ .items[]
          | select(.status=="todo" and ((.max_attempts//2) > (.attempts//0)))
          | select((.depends_on//[]) | all(. as $d | ($done|index($d)) != null)) ]
      | sort_by(.order) | (.[0] // empty)' "$RM")"
    if [ -z "$nxt" ]; then
      awa="$(jq '[.items[]|select(.status=="awaiting-human")]|length' "$RM")"
      blk="$(jq '[.items[]|select(.status=="blocked")]|length' "$RM")"
      halt "backlog-complete (awaiting-human=$awa, blocked=$blk — see improve/proposals/)"
    fi
    id="$(jq -r .id <<<"$nxt")"
    req="$(jq -r '.requires_approval // false' <<<"$nxt")"; appr="$(jq -r '.approved // false' <<<"$nxt")"
    setrm "(.items[]|select(.id==\"$id\")|.status)=\"in-progress\""
    setst ".iteration=($it+1) | .current_item=\"$id\""
    logln "ITER $((it+1)) picked $id"
    say "NEXTID=$id"
    say "TITLE=$(jq -r .title <<<"$nxt")"
    say "PRIORITY=$(jq -r .priority <<<"$nxt")"
    say "RISK=$(jq -r .risk <<<"$nxt")"
    say "TRIVIAL=$(jq -r '.trivial // false' <<<"$nxt")"
    say "FILES=$(jq -rc '.files // []' <<<"$nxt")"
    say "SOURCE=$(jq -r '.source // ""' <<<"$nxt")"
    say "ACCEPTANCE=$(jq -rc '.acceptance // []' <<<"$nxt")"
    if [ "$(jq -r '.design // "none"' <<<"$nxt")" = "fusion" ]; then
      [ -s "$DIR/designs/$id.md" ] && say "DESIGN=cached" || say "DESIGN=needed"
    else say "DESIGN=skip"; fi
    if [ "$req" = "true" ] && [ "$appr" != "true" ]; then say "ACTION=gate"; else say "ACTION=implement"; fi
    say "BUDGET=iter $((it+1))/$mx · fusions $fc/$fm · est \$$(jread '.fusion_calls') ·spent / cap \$$(jread .usd_cap_est)" ;;

  fused)
    id="${1:?id}"; setst ".fusion_calls=(.fusion_calls+1)"; logln "$id fused"; say "FUSED=$(jread .fusion_calls)" ;;

  gate)
    id="${1:?id}"; mkdir -p "$DIR/proposals"; prop="$DIR/proposals/$id.md"
    { echo "# Human approval required: $id"; echo;
      echo "**$(item "$id" | jq -r .title)**"; echo;
      echo "- risk: $(item "$id" | jq -r .risk)";
      echo "- source: $(item "$id" | jq -r '.source // ""')";
      echo "- files: $(item "$id" | jq -rc '.files // []')"; echo;
      echo "## Proposed change"; echo "_(Claude fills in the concrete plan + any Fusion design ref here.)_"; echo;
      echo "To approve: set this item's \`\"approved\": true\` in improve/roadmap.json, then resume the loop."; } > "$prop"
    setrm "(.items[]|select(.id==\"$id\")|.status)=\"awaiting-human\""
    setst ".consecutive_no_progress=0 | .current_item=\"\""
    logln "$id GATED -> $prop"; say "RESULT=gated"; say "PROPOSAL=$prop" ;;

  commit)
    id="${1:?id}"; amax="$(item "$id" | jq -r '.max_attempts // 2')"
    if ! bash "$DIR/check.sh" > "$DIR/.lastcheck.log" 2>&1; then
      revert_tree
      setrm "(.items[]|select(.id==\"$id\")|.attempts)=((.items[]|select(.id==\"$id\")|.attempts)+1)"
      at="$(item "$id" | jq -r .attempts)"; st="todo"; [ "$at" -ge "$amax" ] && st="blocked"
      setrm "(.items[]|select(.id==\"$id\")|.status)=\"$st\""
      setst ".consecutive_no_progress=(.consecutive_no_progress+1) | .current_item=\"\""
      logln "$id REVERTED (check failed, attempts=$at, now $st)"
      say "RESULT=reverted"; say "REASON=check-red"; tail -20 "$DIR/.lastcheck.log" >&2; exit 0
    fi
    if clean_tree; then
      setrm "(.items[]|select(.id==\"$id\")|.attempts)=((.items[]|select(.id==\"$id\")|.attempts)+1) | (.items[]|select(.id==\"$id\")|.status)=\"todo\""
      setst ".consecutive_no_progress=(.consecutive_no_progress+1) | .current_item=\"\""
      logln "$id NOOP (no changes made)"; say "RESULT=noop"; say "REASON=no-changes"; exit 0
    fi
    title="$(item "$id" | jq -r .title)"
    git add -A -- . "$EXCL"
    git commit -q -m "fusion(self-improve): $id — $title" -m "Roadmap item $id (docs/fusion-self-review.md). check.sh green. Auto-committed by the self-improvement loop." || { say "RESULT=error"; say "REASON=git-commit-failed"; exit 0; }
    sha="$(git rev-parse --short HEAD)"
    setrm "(.items[]|select(.id==\"$id\")|.status)=\"done\" | (.items[]|select(.id==\"$id\")|.commit)=\"$sha\""
    setst ".consecutive_no_progress=0 | .current_item=\"\""
    logln "$id DONE -> $sha"
    git add -A improve && git commit -q -m "chore(improve): mark $id done ($sha)" >/dev/null 2>&1 || true
    say "RESULT=committed"; say "SHA=$sha" ;;

  abort)
    id="${1:?id}"; reason="${2:-unspecified}"; amax="$(item "$id" | jq -r '.max_attempts // 2')"
    revert_tree
    setrm "(.items[]|select(.id==\"$id\")|.attempts)=((.items[]|select(.id==\"$id\")|.attempts)+1)"
    at="$(item "$id" | jq -r .attempts)"; st="todo"; [ "$at" -ge "$amax" ] && st="blocked"
    setrm "(.items[]|select(.id==\"$id\")|.status)=\"$st\""
    setst ".consecutive_no_progress=(.consecutive_no_progress+1) | .current_item=\"\""
    logln "$id ABORTED ($reason; attempts=$at, now $st)"; say "RESULT=aborted" ;;

  status)
    jq -r '["id","order","status","attempts","risk"], (.items[]|[.id,.order,.status,(.attempts|tostring),.risk]) | @tsv' "$RM" | column -t 2>/dev/null || \
      jq -r '.items[]|"\(.id)\t\(.status)\t\(.risk)"' "$RM"
    say "---"
    say "$(jq -r '"iter \(.iteration)/\(.max_iterations) · fusions \(.fusion_calls)/\(.max_fusions) · no_progress \(.consecutive_no_progress)/\(.max_no_progress) · halted \(.halted) \(.halt_reason)"' "$ST")" ;;

  *) say "usage: run_iteration.sh {init|next|fused <id>|commit <id>|gate <id>|abort <id> <reason>|status}" >&2; exit 64 ;;
esac
