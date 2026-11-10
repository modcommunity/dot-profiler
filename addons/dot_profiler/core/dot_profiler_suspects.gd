class_name DotProfilerSuspects
extends RefCounted

## Where to look first: every traced span summed by name over the whole call tree ([code]functions[/code]) and
## the costliest of them by self time against the tick budget and a per-unit target ([code]suspects[/code]).
## Built from a finished report, so a saved JSON can be re-ranked.

## Tree roots that are not a suspect: the frame itself and the idle wait.
const SKIP: PackedStringArray = ["frame", "frame;wait"]
## What the engine's own tree nodes are called in the tables.
const ROOT_LABELS := {
	"frame;physics": "physics (untimed rest)",
	"frame;physics;scripts": "physics scripts (no span)",
	"frame;physics;step": "physics engine step",
	"frame;process": "process scripts (no span)",
	"frame;render": "render (engine)",
}
const TICK_PREFIX := "frame;physics"


## Adds [code]functions[/code], [code]suspects[/code] and [code]budget[/code] to [param report] from its tree,
## physics ticks and unit count. [param top] suspects are kept; [param target_us] is the cost one unit may have per tick.
static func attach(report: Dictionary, top: int = 10, target_us: float = 0.0) -> void:
	var tree: Array = report.get("tree", [])
	if tree.is_empty():
		return
	var pt: Dictionary = report.get("physics_ticks", {})
	var ticks_per_frame := maxf(float(pt.get("per_frame", 0.0)), 0.0)
	var tick_rate := float(pt.get("per_second", Engine.physics_ticks_per_second))
	var tick_budget := 1000.0 / maxf(tick_rate, 1.0)
	var frame_budget := float(report.get("budget_ms", 0.0))
	var unit: Dictionary = report.get("unit", {})
	var units := float((unit.get("count", {}) as Dictionary).get("avg", 0.0))
	var fns := functions(tree, ticks_per_frame, units)
	report["functions"] = fns
	var sim_ms := 0.0
	for row: Dictionary in tree:
		if row.path == "frame;physics;scripts" and ticks_per_frame > 0.0:
			sim_ms = float(row.ms) / ticks_per_frame
	report["budget"] = {"tick_ms": tick_budget, "tick_rate": tick_rate, "frame_ms": frame_budget,
		"ticks_per_frame": ticks_per_frame, "unit": String(unit.get("name", "")), "units": units,
		"target_us": target_us, "sim_ms_per_tick": sim_ms, "sim_pct_tick": 100.0 * sim_ms / tick_budget,
		"sim_us_per_unit": sim_ms * 1000.0 / units if units > 0.0 else 0.0}
	var ranked := fns.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms_per_frame > b.self_ms_per_frame)
	var out: Array = []
	for f: Dictionary in ranked.slice(0, maxi(top, 0)):
		var per_tick: bool = f.per == "tick"
		var budget := tick_budget if per_tick else frame_budget
		var s := {"name": f.name, "path": f.path, "per": f.per, "self_ms": f.self_ms, "total_ms": f.total_ms,
			"calls": f.calls, "us_per_call": f.us_per_call, "self_ms_per_frame": f.self_ms_per_frame,
			"pct_budget": 100.0 * float(f.self_ms) / budget if budget > 0.0 else 0.0,
			"us_per_unit": f.us_per_unit, "total_us_per_unit": f.total_us_per_unit,
			"pct_target": 100.0 * float(f.us_per_unit) / target_us if target_us > 0.0 and per_tick else 0.0}
		out.append(s)
	report["suspects"] = out


## Every span of [param tree] (report rows) summed by name: [{name, path, per, paths, self_ms, total_ms, calls,
## us_per_call, self_us_per_call, self_ms_per_frame, total_ms_per_frame, us_per_unit, total_us_per_unit}], costliest
## self first. A span under physics is per tick, any other per frame; [code]path[/code] is where most of it ran.
static func functions(tree: Array, ticks_per_frame: float, units: float) -> Array:
	var by := {}
	for row: Dictionary in tree:
		var path := String(row.path)
		if path in SKIP or path.get_slice(";", path.count(";")).begins_with("q."):
			continue
		var name: String = ROOT_LABELS.get(path, String(row.get("name", path)))
		var per_tick := path.begins_with(TICK_PREFIX) and ticks_per_frame > 0.0
		var key := name + ("|t" if per_tick else "|f")
		var f: Dictionary = by.get(key, {})
		if f.is_empty():
			f = {"name": name, "path": path, "per": "tick" if per_tick else "frame", "paths": 0, "own": 0.0,
				"total": 0.0, "calls": 0.0, "best": -1.0}
			by[key] = f
		f.paths += 1
		f.own += float(row.self_ms)
		f.calls += float(row.calls)
		# A span nested in one of its own name is already inside that one's total.
		if not _inside_same(path, String(row.get("name", ""))):
			f.total += float(row.ms)
		if float(row.self_ms) > float(f.best):
			f.best = float(row.self_ms)
			f.path = path
	var out: Array = []
	for key: String in by:
		var f: Dictionary = by[key]
		var div := ticks_per_frame if f.per == "tick" else 1.0
		var self_ms := float(f.own) / div
		var total_ms := float(f.total) / div
		var calls := float(f.calls) / div
		var per_unit: bool = units > 0.0 and f.per == "tick"
		out.append({"name": f.name, "path": f.path, "per": f.per, "paths": f.paths, "self_ms": self_ms,
			"total_ms": total_ms, "calls": calls, "us_per_call": float(f.total) * 1000.0 / maxf(float(f.calls), 0.0001),
			"self_us_per_call": float(f.own) * 1000.0 / maxf(float(f.calls), 0.0001),
			"self_ms_per_frame": f.own, "total_ms_per_frame": f.total,
			"us_per_unit": self_ms * 1000.0 / units if per_unit else 0.0,
			"total_us_per_unit": total_ms * 1000.0 / units if per_unit else 0.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms_per_frame > b.self_ms_per_frame)
	return out


static func _inside_same(path: String, name: String) -> bool:
	if name == "":
		return false
	var parts := path.split(";")
	for i in parts.size() - 1:
		if parts[i] == name:
			return true
	return false


## The suspects table, for the top of the text report.
static func lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rows: Array = r.get("suspects", [])
	var b: Dictionary = r.get("budget", {})
	if rows.is_empty() or b.is_empty():
		return out
	var units := float(b.get("units", 0.0))
	var target := float(b.get("target_us", 0.0))
	var unit := String(b.get("unit", ""))
	out.append("")
	var head := "Top %d suspects (self time, costliest first; tick budget %.2f ms at %.0f/s, %.2f ticks per frame" % [
		rows.size(), b.get("tick_ms", 0.0), b.get("tick_rate", 0.0), b.get("ticks_per_frame", 0.0)]
	if units > 0.0:
		head += "; %.1f %s" % [units, unit]
		if target > 0.0:
			head += ", target %.0f us per %s per tick" % [target, unit.trim_suffix("s")]
	out.append(head + "):")
	var sim := float(b.get("sim_ms_per_tick", 0.0))
	if sim > 0.0:
		var line := "  all physics scripts: %.2f ms/tick = %.0f%% of the tick budget" % [sim, b.get("sim_pct_tick", 0.0)]
		if units > 0.0:
			line += ", %.0f us/%s" % [b.get("sim_us_per_unit", 0.0), unit.trim_suffix("s")]
			if target > 0.0:
				line += " (%.1fx the target)" % (float(b.get("sim_us_per_unit", 0.0)) / target)
		out.append(line)
	var ucol := ("us/" + unit.trim_suffix("s")) if units > 0.0 else ""
	out.append("  %2s %-34s %-5s %8s %8s %9s %8s %9s %8s %8s" % ["#", "span", "per", "self ms", "% budget", ucol,
		"% target" if target > 0.0 and units > 0.0 else "", "total ms", "calls", "us/call"])
	var i := 0
	for s: Dictionary in rows:
		i += 1
		var tick: bool = s.per == "tick"
		out.append("  %2d %-34s %-5s %8.3f %7.1f%% %9s %8s %9.3f %8.1f %8.1f" % [i, String(s.name).left(34), s.per,
			s.self_ms, s.pct_budget, ("%.1f" % s.us_per_unit) if units > 0.0 and tick else "",
			("%.0f%%" % s.pct_target) if target > 0.0 and units > 0.0 and tick else "", s.total_ms, s.calls, s.us_per_call])
	out.append("  self = time in the span outside the spans it contains; \"(no span)\" rows are script time nothing timed.")
	return out


## The functions table: every span by name, self and total.
static func function_lines(r: Dictionary, top: int = 40) -> PackedStringArray:
	var out := PackedStringArray()
	var rows: Array = r.get("functions", [])
	if rows.is_empty():
		return out
	var b: Dictionary = r.get("budget", {})
	var units := float(b.get("units", 0.0))
	var unit := String(b.get("unit", "")).trim_suffix("s")
	out.append("")
	out.append("Functions (traced spans summed by name over the call tree; ms and calls per tick under physics, else per frame):")
	out.append("  %-34s %-5s %8s %8s %8s %8s %9s %9s %9s" % ["span", "per", "self ms", "total ms", "calls", "us/call",
		"self us/c", ("self/" + unit) if units > 0.0 else "", ("tot/" + unit) if units > 0.0 else ""])
	for f: Dictionary in rows.slice(0, top):
		var tick: bool = f.per == "tick" and units > 0.0
		out.append("  %-34s %-5s %8.3f %8.3f %8.1f %8.1f %9.1f %9s %9s" % [String(f.name).left(34), f.per, f.self_ms,
			f.total_ms, f.calls, f.us_per_call, f.self_us_per_call, ("%.1f" % f.us_per_unit) if tick else "",
			("%.1f" % f.total_us_per_unit) if tick else ""])
	if rows.size() > top:
		out.append("  ... %d more in the JSON (functions)" % (rows.size() - top))
	return out
