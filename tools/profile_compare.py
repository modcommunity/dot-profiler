#!/usr/bin/env python3
"""Compare two dot-profiler reports (JSON, version 1 or 2): B minus A in ms per frame.

Same sections and order as DotProfilerCompare in the addon: frame, phase, system, tree, query, then group
(count, us per unit), script (self ms) and monitor (average, its own unit) when the reports have them.
--diff A is the saved baseline: only rows that moved by at least --noise-pct percent of A are printed.
"""
import argparse
import json
import sys

NOISE_PCT = 5.0


def load(path):
    with open(path, encoding="utf-8") as f:
        r = json.load(f)
    if not isinstance(r, dict) or "frames" not in r:
        sys.exit(f"{path} is not a profiler report")
    return r


def by_key(rows, key, field):
    return {str(r.get(key, "")): float(r.get(field, 0.0)) for r in rows or []}


def section(name, a, b, min_ms):
    names = list(a) + [k for k in b if k not in a]
    rows = [(name, k, a.get(k, 0.0), b.get(k, 0.0)) for k in names]
    rows = [r for r in rows if max(abs(r[2]), abs(r[3])) >= min_ms]
    return sorted(rows, key=lambda r: -abs(r[3] - r[2]))


def group_units(r):
    out = {}
    for g in r.get("groups", []) or []:
        out[f"{g.get('group', '')} count"] = float(g.get("count", {}).get("avg", 0.0))
        for s in g.get("systems", []) or []:
            out[f"{g.get('group', '')} us/unit {s.get('system', '')}"] = float(s.get("us_per_unit", 0.0))
    return out


def script_self(r):
    sf = r.get("script_functions", {}) or {}
    out = {}
    for f in sf.get("functions", []) or []:
        script = str(f.get("script", "")).rsplit("/", 1)[-1]
        out[f"{f.get('function', '')} {script}:{int(f.get('line', 0))}"] = float(f.get("self_ms", 0.0))
    for b in sf.get("buckets", []) or []:
        out[f"bucket {b.get('bucket', '')}"] = float(b.get("self_ms", 0.0))
    return out


def monitor_avg(r):
    return {k: float(v.get("avg", 0.0)) for k, v in (r.get("monitors", {}) or {}).items()}


def compare(a, b, min_ms):
    out = [("frame", k[:-3], float(a.get(k, 0.0)), float(b.get(k, 0.0))) for k in ("p50_ms", "p95_ms", "p99_ms", "worst_ms")]
    fa, fb = max(float(a.get("frames", 0)), 1.0), max(float(b.get("frames", 0)), 1.0)
    pa, pb = a.get("phases", {}), b.get("phases", {})
    out += [("phase", p, float(pa.get(p, 0.0)) / fa, float(pb.get(p, 0.0)) / fb) for p in ("physics", "script", "render", "wait")]
    out += section("system", by_key(a.get("systems"), "system", "ms_per_frame"), by_key(b.get("systems"), "system", "ms_per_frame"), min_ms)
    out += section("tree", by_key(a.get("tree"), "path", "ms"), by_key(b.get("tree"), "path", "ms"), min_ms)
    qa = {f"{r.get('system', '')} {r.get('kind', '')}": float(r.get("ms_per_frame", 0.0)) for r in a.get("queries", [])}
    qb = {f"{r.get('system', '')} {r.get('kind', '')}": float(r.get("ms_per_frame", 0.0)) for r in b.get("queries", [])}
    out += section("query", qa, qb, min_ms)
    out += section("group", group_units(a), group_units(b), 0.0)
    out += section("script", script_self(a), script_self(b), min_ms)
    out += section("monitor", monitor_avg(a), monitor_avg(b), 0.0)
    return out


def changed(rows, noise_pct=NOISE_PCT, min_abs=0.0):
    """The rows that moved by at least noise_pct percent of A; a row only in B always counts."""
    keep = []
    for r in rows:
        a, d = abs(r[2]), abs(r[3] - r[2])
        if d == 0.0 or d <= min_abs:
            continue
        if a < 1e-6 or d * 100.0 / a >= noise_pct:
            keep.append(r)
    return keep


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("a", help="report A (the baseline with --diff)")
    ap.add_argument("b")
    ap.add_argument("--min-ms", type=float, default=0.05, help="leave out rows under this in both reports")
    ap.add_argument("--top", type=int, default=0, help="rows per section, 0 for all")
    ap.add_argument("--json", action="store_true", help="print the rows as JSON")
    ap.add_argument("--diff", action="store_true", help="only rows that moved past the noise floor")
    ap.add_argument("--noise-pct", type=float, default=NOISE_PCT, help="noise floor for --diff, percent of A (default 5)")
    ap.add_argument("--min-abs", type=float, default=0.0, help="with --diff, also drop changes smaller than this")
    args = ap.parse_args()
    rows = compare(load(args.a), load(args.b), args.min_ms)
    if args.diff:
        rows = changed(rows, args.noise_pct, args.min_abs)
    if args.json:
        print(json.dumps([{"section": s, "name": n, "a": x, "b": y, "delta": y - x} for s, n, x, y in rows], indent=1))
        return
    floor = f"; only changes of {args.noise_pct:g}% or more" if args.diff else ""
    print(f"profile compare  A={args.a}  B={args.b}  (ms per frame unless the section says; delta is B - A{floor})")
    if args.diff and not rows:
        print("\nno change above the noise floor")
    current, shown = "", 0
    for s, n, x, y in rows:
        if s != current:
            current, shown = s, 0
            print(f"\n{s}:")
        shown += 1
        if args.top and shown > args.top:
            continue
        pct = f"  {(y - x) / x * 100:+.0f}%" if abs(x) > 0.0001 else ""
        print(f"  {n[-48:]:<48} {x:9.2f} {y:9.2f} {y - x:+9.2f}{pct}")


if __name__ == "__main__":
    main()
