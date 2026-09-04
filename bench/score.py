#!/usr/bin/env python3
"""score.py — aggregate bench results into per-arm metrics + paired significance vs a baseline arm.

Reads graded.jsonl (one JSON object per run, written by run_bench.sh). Computes:
  - accuracy (all graded items) and accuracy-when-attempted
  - not_attempted_rate and HALLUCINATION rate (incorrect / attempted) — the "confidently wrong" metric
    Fusion is meant to beat single models on, even when raw accuracy ties
  - mean latency (authoritative) and mean answer chars (rough size proxy)
  - paired bootstrap 95% CI of per-item accuracy delta vs the baseline arm
  - exact McNemar test on majority-vote correctness vs the baseline arm

Usage:
  python3 score.py results/smoke/graded.jsonl [--baseline fusion-default] [--kappa other_graded.jsonl]

Stats are intentionally pure-stdlib (no numpy/scipy) so the harness has no Python deps.
"""
import sys, json, argparse, random, math
from collections import defaultdict

random.seed(20260622)  # deterministic CIs across re-runs


def load(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def correctness(v):
    return 1.0 if v == "correct" else 0.0


def per_item_accuracy(rows):
    """arm -> item -> mean correctness over repeats."""
    acc = defaultdict(lambda: defaultdict(list))
    for r in rows:
        acc[r["arm"]][r["item"]].append(correctness(r.get("verdict")))
    return {a: {i: sum(v) / len(v) for i, v in items.items()} for a, items in acc.items()}


def arm_summary(rows):
    by = defaultdict(list)
    for r in rows:
        by[r["arm"]].append(r)
    out = {}
    for arm, rs in by.items():
        n = len(rs)
        c = sum(1 for r in rs if r.get("verdict") == "correct")
        inc = sum(1 for r in rs if r.get("verdict") == "incorrect")
        na = sum(1 for r in rs if r.get("verdict") == "not_attempted")
        ung = sum(1 for r in rs if r.get("verdict") not in ("correct", "incorrect", "not_attempted"))
        attempted = c + inc
        lat = [r.get("latency", {}).get("total_s", 0) for r in rs]
        chars = [r.get("answer_chars", 0) for r in rs]
        drops = sum(r.get("panel_dropped", 0) for r in rs)
        fb = sum(1 for r in rs if r.get("judge_fellback"))
        out[arm] = dict(
            n=n, correct=c, incorrect=inc, not_attempted=na, ungraded=ung,
            acc_all=c / n if n else 0.0,
            acc_attempted=c / attempted if attempted else 0.0,
            na_rate=na / n if n else 0.0,
            hallucination=inc / attempted if attempted else 0.0,
            mean_lat=sum(lat) / n if n else 0.0,
            mean_chars=sum(chars) / n if n else 0.0,
            drops=drops, judge_fellback=fb,
        )
    return out


def paired_bootstrap(arm_acc, base_acc, B=10000):
    items = sorted(set(arm_acc) & set(base_acc))
    if not items:
        return None
    diffs = [arm_acc[i] - base_acc[i] for i in items]
    mean = sum(diffs) / len(diffs)
    boots = []
    k = len(diffs)
    for _ in range(B):
        s = sum(diffs[random.randrange(k)] for _ in range(k)) / k
        boots.append(s)
    boots.sort()
    lo = boots[int(0.025 * B)]
    hi = boots[int(0.975 * B)]
    return dict(n_items=k, mean_delta=mean, ci_lo=lo, ci_hi=hi)


def mcnemar(arm_acc, base_acc):
    """Majority-vote correctness per item -> exact binomial McNemar on discordant pairs."""
    items = sorted(set(arm_acc) & set(base_acc))
    b = c = 0  # b: arm right & base wrong ; c: arm wrong & base right
    for i in items:
        a = 1 if arm_acc[i] >= 0.5 else 0
        z = 1 if base_acc[i] >= 0.5 else 0
        if a == 1 and z == 0:
            b += 1
        elif a == 0 and z == 1:
            c += 1
    nd = b + c
    if nd == 0:
        return dict(b=b, c=c, p=1.0)
    # two-sided exact binomial p (p=0.5)
    k = min(b, c)
    tail = sum(math.comb(nd, j) for j in range(0, k + 1)) / (2 ** nd)
    p = min(1.0, 2 * tail)
    return dict(b=b, c=c, p=p)


def cohen_kappa(rows_a, rows_b):
    """Agreement between two grader passes keyed by run 'key'."""
    va = {r["key"]: r.get("verdict") for r in rows_a if "key" in r}
    vb = {r["key"]: r.get("verdict") for r in rows_b if "key" in r}
    keys = sorted(set(va) & set(vb))
    if not keys:
        return None
    cats = ["correct", "incorrect", "not_attempted"]
    agree = sum(1 for k in keys if va[k] == vb[k]) / len(keys)
    pa = {c: sum(1 for k in keys if va[k] == c) / len(keys) for c in cats}
    pb = {c: sum(1 for k in keys if vb[k] == c) / len(keys) for c in cats}
    pe = sum(pa[c] * pb[c] for c in cats)
    kappa = (agree - pe) / (1 - pe) if pe < 1 else 1.0
    return dict(n=len(keys), observed_agreement=agree, kappa=kappa)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("graded")
    ap.add_argument("--baseline", default="fusion-default")
    ap.add_argument("--kappa", help="second graded.jsonl from a different grader, for inter-grader Cohen's kappa")
    args = ap.parse_args()

    rows = load(args.graded)
    if not rows:
        print("no rows", file=sys.stderr); sys.exit(1)
    summ = arm_summary(rows)
    item_acc = per_item_accuracy(rows)

    print("\n=== PER-ARM SUMMARY ===")
    hdr = f"{'arm':24} {'n':>4} {'acc':>6} {'acc|att':>7} {'na%':>5} {'halluc':>6} {'lat_s':>7} {'chars':>7} {'drops':>5} {'jfb':>4}"
    print(hdr); print("-" * len(hdr))
    for arm in sorted(summ, key=lambda a: -summ[a]["acc_all"]):
        s = summ[arm]
        print(f"{arm:24} {s['n']:>4} {s['acc_all']*100:>5.1f}% {s['acc_attempted']*100:>6.1f}% "
              f"{s['na_rate']*100:>4.0f}% {s['hallucination']*100:>5.1f}% {s['mean_lat']:>7.1f} "
              f"{s['mean_chars']:>7.0f} {s['drops']:>5} {s['judge_fellback']:>4}")

    base = args.baseline
    if base in item_acc:
        print(f"\n=== PAIRED vs baseline '{base}' (per-item accuracy delta) ===")
        print("positive delta = arm beats baseline. CI excludes 0 => significant at ~95%.")
        for arm in sorted(summ):
            if arm == base:
                continue
            bs = paired_bootstrap(item_acc[arm], item_acc[base])
            mc = mcnemar(item_acc[arm], item_acc[base])
            if not bs:
                continue
            sig = "  *" if (bs["ci_lo"] > 0 or bs["ci_hi"] < 0) else ""
            print(f"{arm:24} delta={bs['mean_delta']*100:+5.1f}%  "
                  f"95%CI=[{bs['ci_lo']*100:+5.1f}%,{bs['ci_hi']*100:+5.1f}%]  "
                  f"McNemar b={mc['b']} c={mc['c']} p={mc['p']:.3f}{sig}")
    else:
        print(f"\n[score] baseline '{base}' not in data — skipping paired tests "
              f"(arms present: {', '.join(sorted(summ))})", file=sys.stderr)

    if args.kappa:
        ka = cohen_kappa(rows, load(args.kappa))
        print("\n=== INTER-GRADER AGREEMENT ===")
        if ka:
            print(f"n={ka['n']}  observed_agreement={ka['observed_agreement']*100:.1f}%  "
                  f"Cohen's kappa={ka['kappa']:.3f}  "
                  f"({'trustworthy' if ka['kappa']>=0.6 else 'WEAK — fix rubric before trusting deltas'})")
        else:
            print("no overlapping keys between the two grader files")
    print()


if __name__ == "__main__":
    main()
