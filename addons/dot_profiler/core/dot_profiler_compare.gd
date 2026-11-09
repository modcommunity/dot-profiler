class_name DotProfilerCompare
extends RefCounted

## Two reports side by side: frame percentiles, engine phases, systems and (version 2) call-tree nodes in ms
## per frame, with B minus A. tools/profile_compare.py prints the same from the JSON files.


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
	return out


## The rows as aligned text, one section after another.
static func to_text(rows: Array[Dictionary], name_a: String = "A", name_b: String = "B") -> PackedStringArray:
	var out := PackedStringArray()
	out.append("profile compare  A=%s  B=%s  (ms per frame; delta is B - A)" % [name_a, name_b])
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
