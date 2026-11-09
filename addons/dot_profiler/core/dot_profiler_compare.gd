class_name DotProfilerCompare
extends RefCounted

## Two reports side by side: frame percentiles, engine phases, systems and (version 2) call-tree nodes in ms
## per frame, with B minus A; then group cost per unit (us), script functions (ms) and monitor averages (their
## own units) when both reports have them. tools/profile_compare.py prints the same from the JSON files.

## Default noise floor of [method changed], in percent: run-to-run spread of one build on one box.
const NOISE_PCT := 5.0


## Rows {section, name, a, b, delta} in ms per frame; systems and tree nodes changed most first.
## [param a] and [param b] are report Dictionaries (version 1 or 2).
static func compare(a: Dictionary, b: Dictionary, min_ms: float = 0.05) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: String in ["p50_ms", "p95_ms", "p99_ms", "worst_ms"]:
		out.append(_row("frame", k.trim_suffix("_ms"), float(a.get(k, 0.0)), float(b.get(k, 0.0))))
	var fa := maxf(float(a.get("frames", 0)), 1.0)
	var fb := maxf(float(b.get("frames", 0)), 1.0)
	var pa: Dictionary = a.get("phases", {})
	var pb: Dictionary = b.get("phases", {})
	for p: String in ["physics", "script", "render", "wait"]:
		out.append(_row("phase", p, float(pa.get(p, 0.0)) / fa, float(pb.get(p, 0.0)) / fb))
	out.append_array(_section("system", _by_key(a.get("systems", []), "system", "ms_per_frame"), _by_key(b.get("systems", []), "system", "ms_per_frame"), min_ms))
	out.append_array(_section("tree", _by_key(a.get("tree", []), "path", "ms"), _by_key(b.get("tree", []), "path", "ms"), min_ms))
	var qa := {}
	var qb := {}
	for pair: Array in [[a, qa], [b, qb]]:
		for r: Dictionary in (pair[0] as Dictionary).get("queries", []):
			(pair[1] as Dictionary)["%s %s" % [r.get("system", ""), r.get("kind", "")]] = float(r.get("ms_per_frame", 0.0))
	out.append_array(_section("query", qa, qb, min_ms))
	out.append_array(_section("group", _group_units(a), _group_units(b), 0.0))
	out.append_array(_section("script", _script_self(a), _script_self(b), min_ms))
	var ma := {}
	var mb := {}
	for pair: Array in [[a, ma], [b, mb]]:
		var mon: Dictionary = (pair[0] as Dictionary).get("monitors", {})
		for k: String in mon:
			(pair[1] as Dictionary)[k] = float((mon[k] as Dictionary).get("avg", 0.0))
	out.append_array(_section("monitor", ma, mb, 0.0))
	return out


## The rows of [method compare] that moved by at least [param noise_pct] percent of A (rows only in one report
## always count); [param min_abs] also drops changes smaller than that in absolute terms.
static func changed(rows: Array[Dictionary], noise_pct: float = NOISE_PCT, min_abs: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rows:
		var a := absf(float(r.a))
		var d := absf(float(r.delta))
		if d <= min_abs or d == 0.0:
			continue
		if a < 0.000001 or d * 100.0 / a >= noise_pct:
			out.append(r)
	return out


## The rows as aligned text, one section after another.
static func to_text(rows: Array[Dictionary], name_a: String = "A", name_b: String = "B") -> PackedStringArray:
	var out := PackedStringArray()
	out.append("profile compare  A=%s  B=%s  (ms per frame unless the section says; delta is B - A)" % [name_a, name_b])
	var section := ""
	for r in rows:
		if r.section != section:
			section = r.section
			out.append("")
			out.append("%s:" % section)
		out.append("  %-48s %9.2f %9.2f %+9.2f%s" % [String(r.name).right(48), r.a, r.b, r.delta,
			("  %+.0f%%" % (r.delta / r.a * 100.0)) if absf(r.a) > 0.0001 else ""])
	return out


## Reads a report JSON written by [method DotProfilerReport.write].
static func load_report(path: String) -> DotResult:
	var res := DotPaths.read_json(path)
	if not res.ok:
		return res.wrap("profiler: cannot read %s" % path)
	if not (res.value is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "%s is not a profiler report." % path)
	return DotResult.success(res.value)


static func _group_units(r: Dictionary) -> Dictionary:
	var out := {}
	for g: Dictionary in r.get("groups", []):
		out["%s count" % g.group] = float((g.get("count", {}) as Dictionary).get("avg", 0.0))
		for s: Dictionary in g.get("systems", []):
			out["%s us/unit %s" % [g.group, s.system]] = float(s.get("us_per_unit", 0.0))
	return out


static func _script_self(r: Dictionary) -> Dictionary:
	var out := {}
	var sf: Dictionary = r.get("script_functions", {})
	for f: Dictionary in sf.get("functions", []):
		out["%s %s:%d" % [f.function, String(f.script).get_file(), int(f.line)]] = float(f.get("self_ms", 0.0))
	for b: Dictionary in sf.get("buckets", []):
		out["bucket " + String(b.bucket)] = float(b.get("self_ms", 0.0))
	return out


static func _by_key(rows: Array, key: String, field: String) -> Dictionary:
	var out := {}
	for r: Dictionary in rows:
		out[String(r.get(key, ""))] = float(r.get(field, 0.0))
	return out


static func _section(section: String, a: Dictionary, b: Dictionary, min_ms: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names := a.keys()
	for k: Variant in b:
		if not a.has(k):
			names.append(k)
	for k: Variant in names:
		var r := _row(section, String(k), float(a.get(k, 0.0)), float(b.get(k, 0.0)))
		if maxf(absf(r.a), absf(r.b)) >= min_ms:
			out.append(r)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(x.delta) > absf(y.delta))
	return out


static func _row(section: String, name: String, a: float, b: float) -> Dictionary:
	return {"section": section, "name": name, "a": a, "b": b, "delta": b - a}
