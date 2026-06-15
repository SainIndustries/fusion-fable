#!/usr/bin/env bash
# anchor_emit.sh — OPTIONAL, opt-in (FUSION_ANCHOR=1) tamper-evident provenance for a Fusion run.
#
# Records an attestation of a completed run — per-answer sha256 hashes, judge & synthesis hashes, model
# ids, the SLUG, timestamps — as a local SIGNED JSON, and (if Anchor'd is reachable) ALSO anchors the
# manifest hash via POST /api/anchor. It ships ONLY hashes + ids by default; raw prompts/answers never
# leave the machine unless FUSION_ANCHOR_INCLUDE_CONTENT=1. It is PURELY ADDITIVE: the markdown audit
# trail stays the record of truth, and this script ALWAYS exits 0 — it can never break a Fusion run.
#
# Usage: anchor_emit.sh <run_dir> [slug]
#   <run_dir>: task.txt, answers/panelist_*.md (+ answers/map.json), judge.md, synthesis.md
#              (any missing file is hashed as "absent").
# Prints ANCHOR_RESULT=... for the caller to surface in the audit trail.
#
# Anchor API (see anchor repo): POST /api/anchor  {contentHash(hex 32-128), hashAlgorithm, metadata}
#   auth header X-API-Key; health GET /api/health; verify GET /api/public/proofs?contentHash=<hash>.
set -uo pipefail

RUN_DIR="${1:?usage: anchor_emit.sh <run_dir> [slug]}"
SLUG="${2:-${SLUG:-unknown}}"

# Master opt-in. Off => no-op (the markdown audit trail is unaffected).
if [ "${FUSION_ANCHOR:-0}" != "1" ]; then
  echo "ANCHOR_RESULT=disabled (set FUSION_ANCHOR=1 to enable)"; exit 0
fi
[ -d "$RUN_DIR" ] || { echo "[anchor_emit] no run dir: $RUN_DIR" >&2; echo "ANCHOR_RESULT=skipped (no run dir)"; exit 0; }

FUSION_HOME="${FUSION_HOME:-$HOME/.fusion}"
ALGO="${FUSION_ANCHOR_HASH_ALGO:-SHA-256}"
OUT="$RUN_DIR/anchor"; mkdir -p "$OUT"
warn(){ echo "[anchor_emit] $*" >&2; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

command -v jq >/dev/null 2>&1 || { warn "jq required; skipping"; echo "ANCHOR_RESULT=skipped (no jq)"; exit 0; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
       else shasum -a 256 "$1" | awk '{print $1}'; fi; }
hashfile(){ [ -s "$1" ] && sha "$1" || echo "absent"; }
ver(){ command -v "$1" >/dev/null 2>&1 && { "$1" --version 2>/dev/null | head -1; } || echo "absent"; }

# --- per-answer hashes with REAL model attribution from map.json (label -> source/model) ---
panel_json='[]'
for f in "$RUN_DIR"/answers/panelist_*.md; do
  [ -e "$f" ] || continue
  label="$(basename "$f" .md | sed 's/^panelist_//')"
  model="$label"
  if [ -s "$RUN_DIR/answers/map.json" ]; then
    # map.json is [{"label":"A","source":"..."}]; resolve label -> source basename as the model hint.
    src="$(jq -r --arg l "$label" '(map(select(.label==$l))|.[0].source) // ""' "$RUN_DIR/answers/map.json" 2>/dev/null)"
    [ -n "$src" ] && model="$(basename "$src")"
  fi
  h="$(hashfile "$f")"
  panel_json="$(jq -c --arg l "$label" --arg m "$model" --arg h "$h" \
    '. + [{label:$l, role:"panelist", model:$m, content_sha256:$h,
           status:($h|if .=="absent" then "absent" else "returned" end)}]' <<<"$panel_json")"
done

# --- canonical, hashes-only manifest ---
manifest="$(jq -cn \
  --arg run_id "$(basename "$RUN_DIR")" --arg slug "$SLUG" --arg algo "$ALGO" \
  --arg started "${FUSION_RUN_STARTED:-$(ts)}" --arg finished "$(ts)" \
  --arg task "$(hashfile "$RUN_DIR/task.txt")" \
  --arg judge_model "${JUDGE:-unknown}"  --arg judge_h "$(hashfile "$RUN_DIR/judge.md")" \
  --arg synth_model "${SYNTH:-opus4.8}"  --arg synth_h "$(hashfile "$RUN_DIR/synthesis.md")" \
  --arg cver "$(ver claude)" --arg xver "$(ver codex)" \
  --argjson panel "$panel_json" \
  '{schema:"fusion.attestation/v1", run_id:$run_id, slug:$slug, hash_algo:$algo,
    started_at:$started, finished_at:$finished, task_sha256:$task,
    panel:$panel, judge:{model:$judge_model, discernment_sha256:$judge_h},
    synthesis:{model:$synth_model, synthesis_sha256:$synth_h},
    tool_versions:{claude:$cver, codex:$xver}}')"

# canonical serialization (sorted keys, compact) -> the hash that gets anchored
printf '%s' "$manifest" | jq -S -cj . > "$OUT/manifest.canonical.json"
manifest_sha="$(sha "$OUT/manifest.canonical.json")"

# --- sign the manifest: ed25519 (preferred), HMAC-SHA256 fallback; key is chmod 600 ---
KEY="${FUSION_ANCHOR_SIGNING_KEY:-$FUSION_HOME/anchor/ed25519.pem}"; KEY="${KEY/#\~/$HOME}"
mkdir -p "$(dirname "$KEY")"; SIG_ALG="ed25519"; SIG=""; PUBSHA="absent"
if command -v openssl >/dev/null 2>&1; then
  if [ ! -s "$KEY" ]; then
    if openssl genpkey -algorithm ed25519 -out "$KEY" 2>/dev/null; then
      chmod 600 "$KEY" 2>/dev/null; openssl pkey -in "$KEY" -pubout -out "$KEY.pub" 2>/dev/null || true
    else openssl rand -hex 32 > "$KEY"; chmod 600 "$KEY" 2>/dev/null; SIG_ALG="HMAC-SHA256"; fi
  elif ! grep -q 'PRIVATE KEY' "$KEY" 2>/dev/null; then SIG_ALG="HMAC-SHA256"; fi
  if [ "$SIG_ALG" = "ed25519" ]; then
    SIG="$(openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$OUT/manifest.canonical.json" 2>/dev/null | base64 | tr -d '\n')" || SIG_ALG="HMAC-SHA256"
  fi
  if [ "$SIG_ALG" = "HMAC-SHA256" ]; then
    SIG="$(openssl dgst -sha256 -hmac "$(cat "$KEY")" -binary "$OUT/manifest.canonical.json" 2>/dev/null | base64 | tr -d '\n')"
  elif [ -s "$KEY.pub" ]; then PUBSHA="$(sha "$KEY.pub")"; fi
else
  warn "openssl missing — attestation left unsigned (manifest hash is its own integrity proof)"
  SIG_ALG="none"
fi

# the local signed attestation (always written when enabled — the degraded-mode artifact)
jq -cn --argjson m "$manifest" --arg mh "$manifest_sha" --arg alg "$SIG_ALG" --arg sig "$SIG" --arg pk "$PUBSHA" \
  '{manifest:$m, manifest_sha256:$mh, signature:{alg:$alg, sig:$sig, pubkey_sha256:$pk}}' \
  | jq -S . > "$OUT/attestation.json"

# --- additive Anchor'd anchoring; never fail the run ---
URL="${ANCHOR_API_URL:-}"; TOKEN="${ANCHOR_API_TOKEN:-}"
if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
  echo "ANCHOR_RESULT=local-only ($OUT/attestation.json sig=$SIG_ALG sha256=$manifest_sha)"; exit 0
fi
command -v curl >/dev/null 2>&1 || { warn "curl missing — local attestation only"; echo "ANCHOR_RESULT=local-only ($OUT/attestation.json)"; exit 0; }

# reachability probe (unauthenticated health) so we degrade instead of hanging
if ! curl -fsS --max-time "${FUSION_ANCHOR_TIMEOUT:-15}" "$URL/api/health" >/dev/null 2>&1; then
  warn "Anchor unreachable at $URL — kept local signed attestation."
  echo "ANCHOR_RESULT=local-only (anchor unreachable; $OUT/attestation.json)"; exit 0
fi

extra='{}'
if [ "${FUSION_ANCHOR_INCLUDE_CONTENT:-0}" = "1" ]; then
  warn "FUSION_ANCHOR_INCLUDE_CONTENT=1 — embedding raw task text (privacy off)"
  extra="$(jq -cn --rawfile t "$RUN_DIR/task.txt" '{raw_task:$t}' 2>/dev/null || echo '{}')"
fi
body="$(jq -cn --arg h "$manifest_sha" --arg algo "$ALGO" --arg slug "$SLUG" --arg rid "$(basename "$RUN_DIR")" \
  --argjson m "$manifest" --argjson extra "$extra" \
  '{contentHash:$h, hashAlgorithm:$algo,
    metadata:({source:"fusion-fable", kind:"run-attestation", slug:$slug, run_id:$rid, manifest:$m} + $extra)}')"

resp="$(curl -sS --max-time "${FUSION_ANCHOR_TIMEOUT:-15}" \
  -X POST "$URL/api/anchor" -H "X-API-Key: $TOKEN" -H 'Content-Type: application/json' \
  -w $'\n%{http_code}' -d "$body" 2>"$OUT/curl.err")" || {
    warn "Anchor POST failed: $(tail -1 "$OUT/curl.err" 2>/dev/null)"
    echo "ANCHOR_RESULT=local-only (anchor POST failed; $OUT/attestation.json)"; exit 0; }
code="$(printf '%s\n' "$resp" | tail -1)"; payload="$(printf '%s\n' "$resp" | sed '$d')"
if [ "$code" = "201" ] || [ "$code" = "200" ]; then
  anchor_id="$(jq -r '.anchorId // empty' <<<"$payload" 2>/dev/null)"
  vurl="$(jq -r '.verificationUrl // empty' <<<"$payload" 2>/dev/null)"
  jq --argjson a "$payload" '. + {anchor:$a}' "$OUT/attestation.json" > "$OUT/.t" && mv -f "$OUT/.t" "$OUT/attestation.json"
  echo "ANCHOR_RESULT=anchored (anchorId=$anchor_id verify=$vurl manifest_sha256=$manifest_sha)"
else
  warn "Anchor returned HTTP $code: $payload"
  echo "ANCHOR_RESULT=local-only (anchor HTTP $code; $OUT/attestation.json)"
fi
exit 0
