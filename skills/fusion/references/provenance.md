# Provenance — optional Anchor'd attestation of a Fusion run

Fusion already produces an audit trail (panel composition, the judge's discernment, the final synthesis).
This optionally makes that trail **tamper-evident** by attesting it to Anchor'd (the Sain Industries
blockchain-agnostic accountability ledger). It is **opt-in and purely additive**: the local markdown audit
trail stays the record of truth, and the emitter (`scripts/anchor_emit.sh`) always exits 0 — it can never
break or alter a run.

## Turning it on

```bash
export FUSION_ANCHOR=1                       # master switch (off => emitter is a no-op)
export ANCHOR_API_URL=http://localhost:4000  # Anchor server (its default PORT is 4000)
export ANCHOR_API_TOKEN=dev-admin            # an X-API-Key entry from the server's ANCHOR_API_KEYS
```

With just `FUSION_ANCHOR=1` (no URL/token) you still get a **local signed attestation**; add the URL/token
to also anchor on the ledger. SKILL.md Step 6 calls the emitter at the end of a run.

## What is attested (and what stays private)

The emitter builds a canonical, **hashes-only** manifest and anchors `sha256(manifest)`. What ships to the
ledger: the `SLUG`, run id, ISO timestamps, the task's sha256, each panelist's `{label, model,
content_sha256, status}` (de-anonymized via `answers/map.json`), the judge's discernment sha256, the
synthesis sha256, and tool versions. What never leaves the machine: the raw task, prompts, answers, judge
doc, and synthesis text — unless you explicitly set `FUSION_ANCHOR_INCLUDE_CONTENT=1`. So anyone holding an
original answer can later prove it produced a given hash, but nobody can reconstruct content from the anchor.

## The call it makes

`POST $ANCHOR_API_URL/api/anchor` with header `X-API-Key: $ANCHOR_API_TOKEN` and body
`{contentHash: <manifest sha256>, hashAlgorithm: "SHA-256", metadata: {…hashes-only manifest…}}`, which
returns `{anchorId, transactionId, verificationUrl, …}`. Verify later, keyless, with
`GET $ANCHOR_API_URL/api/public/proofs?contentHash=<manifest sha256>` and re-derive the same hash from the
saved `attestation.json`.

## Degradation ladder (every rung exits 0)

`FUSION_ANCHOR!=1` → no-op · no `jq` → skipped · no URL/token → local signed JSON · Anchor unreachable
(health probe fails) → local signed JSON · non-2xx → local signed JSON · success → local JSON **plus** the
on-chain receipt merged in. Output is one `ANCHOR_RESULT=...` line for the orchestrator to surface.

## Signing & config knobs

The local attestation is signed with an ed25519 key auto-generated at
`~/.fusion/anchor/ed25519.pem` (chmod 600), falling back to HMAC-SHA256, then unsigned — whichever the local
`openssl` supports. Knobs: `FUSION_ANCHOR_HASH_ALGO` (SHA-256 | SHA-3-256 | SHA-3-512),
`FUSION_ANCHOR_TIMEOUT` (curl seconds), `FUSION_ANCHOR_SIGNING_KEY`, `FUSION_ANCHOR_INCLUDE_CONTENT`.

> Caveat: the local signing key is the trust root for degraded-mode signatures — keep it private (the
> emitter chmods it 600). The HMAC fallback is symmetric (a verifier needs the secret), so prefer ed25519.
