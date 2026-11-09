class_name DotProfilerReport
extends RefCounted

## A recording turned into a report, written as JSON, readable text and folded stacks side by side.
## [method build] makes it from frame times, spikes, systems and phases; [method write] saves it
## under a directory, keeping the newest N, and returns the JSON path. docs/report-format.md has the keys.

const CHANNEL := "dot.profiler"
const VERSION := 2


## The report for one recording. [param frames_ms] is every frame's wall time; [param spikes] the attributed spikes
## ([method DotProfiler.attribute]); [param systems] {name: {ms, calls, worst_ms, what}} summed over the recording;
## [param phases] {physics, script, render, wait} summed; [param meta] is merged in (budget_ms, seconds, scene).
static func build(frames_ms: PackedFloat32Array, spikes: Array, systems: Dictionary, phases: Dictionary, meta: Dictionary) -> Dictionary:
	var sorted := frames_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in frames_ms:
		total += ms
	var causes := {}
	for s: Dictionary in spikes:
		var c: String = s.get("cause", "")
		var row: Dictionary = causes.get(c, {"spikes": 0, "ms": 0.0, "worst_ms": 0.0, "period": ""})
		row.spikes += 1
		row.ms += float(s.get("ms", 0.0))
		row.worst_ms = maxf(row.worst_ms, float(s.get("ms", 0.0)))
		if s.get("period", "") != "":
			row.period = s.period
		causes[c] = row
	var sys_rows: Array = []
	for name: Variant in systems:
		var r: Dictionary = systems[name]
		sys_rows.append({"system": String(name), "ms": r.get("ms", 0.0), "calls": r.get("calls", 0),
			"worst_ms": r.get("worst_ms", 0.0), "what": r.get("what", ""),
			"ms_per_frame": float(r.get("ms", 0.0)) / maxf(frames_ms.size(), 1)})
	sys_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	var out := {
		"version": VERSION,
		"made": Time.get_datetime_string_from_system(true),
		"frames": frames_ms.size(),
		"wall_s": total / 1000.0,
		"p50_ms": percentile(sorted, 0.5),
		"p95_ms": percentile(sorted, 0.95),
		"p99_ms": percentile(sorted, 0.99),
		"worst_ms": sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0,
		"spike_count": spikes.size(),
		"causes": causes,
		"systems": sys_rows,
		"phases": phases,
		"spikes": spikes,
	}
	out.merge(meta)
	return out


## The [param p]th percentile (0..1) of an already sorted array, or 0 when it is empty.
static func percentile(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(p * (sorted.size() - 1)), 0, sorted.size() - 1)]


## The report as lines a person reads: totals, the causes worst first, the systems, then the worst spikes.
static func to_text(r: Dictionary, top: int = 20) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-profiler report %s  scene=%s" % [r.get("made", ""), r.get("scene", "")])
	out.append("frames=%d over %.1f s  p50=%.1f p95=%.1f p99=%.1f worst=%.1f ms  budget=%.1f ms  spikes=%d" % [
		r.get("frames", 0), r.get("wall_s", 0.0), r.get("p50_ms", 0.0), r.get("p95_ms", 0.0), r.get("p99_ms", 0.0),
		r.get("worst_ms", 0.0), r.get("budget_ms", 0.0), r.get("spike_count", 0)])
	var ph: Dictionary = r.get("phases", {})
	if not ph.is_empty():
		out.append("time in: physics %.0f ms, script %.0f ms, render %.0f ms, wait %.0f ms" % [
			ph.get("physics", 0.0), ph.get("script", 0.0), ph.get("render", 0.0), ph.get("wait", 0.0)])
	var causes: Dictionary = r.get("causes", {})
	if not causes.is_empty():
		out.append("")
		out.append("Spike causes:")
		var names := causes.keys()
		names.sort_custom(func(a: Variant, b: Variant) -> bool: return causes[a].spikes > causes[b].spikes)
		for c: Variant in names:
			var row: Dictionary = causes[c]
			out.append("  %-28s %4d spikes  worst %.1f ms%s" % [c, row.spikes, row.worst_ms,
				("  repeats " + row.period) if row.period != "" else ""])
	var systems: Array = r.get("systems", [])
	if not systems.is_empty():
		out.append("")
		out.append("Systems (reported through DotFrameCost):")
		for s: Dictionary in systems.slice(0, top):
			out.append("  %-28s %8.1f ms total  %6.2f ms/frame  worst %.1f ms  calls %d%s" % [s.system, s.ms,
				s.ms_per_frame, s.worst_ms, s.calls, ("  worst: " + s.what) if s.what != "" else ""])
	var spikes: Array = r.get("spikes", []).duplicate()
	if not spikes.is_empty():
		spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
		out.append("")
		out.append("Worst spikes:")
		for s: Dictionary in spikes.slice(0, top):
			out.append("  " + spike_line(s))
	out.append_array(DotProfilerReportText.lines(r, top))
	return out


## One spike as one line: when, how long, the cause and its evidence.
static func spike_line(s: Dictionary) -> String:
	return "t=%.2fs %.1f ms  %s%s  [phys %.1f script %.1f render %.1f wait %.1f]%s%s" % [
		s.get("t", 0.0), s.get("ms", 0.0), s.get("cause", "?"),
		(" (" + String(s.what) + ")") if String(s.get("what", "")) != "" else "",
		s.get("physics", 0.0), s.get("script", 0.0), s.get("render", 0.0), s.get("wait", 0.0),
		(" " + "; ".join(s.hints)) if not (s.get("hints", []) as Array).is_empty() else "",
		(" repeats " + String(s.period)) if String(s.get("period", "")) != "" else ""]


## Writes [param r] as <stamp>.json and <stamp>.txt, and [param folded] as <stamp>.folded when given,
## under [param dir] and keeps the newest [param keep]. The value is the JSON path.
static func write(r: Dictionary, dir: String, keep: int = 20, folded: String = "") -> DotResult:
	var made := DotPaths.ensure_dir(dir)
	if not made.ok:
		return made.wrap("profiler: cannot make %s" % dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "-").replace("-", "")
	var base := dir.path_join("profile-%s-%03d" % [stamp, Time.get_ticks_msec() % 1000])
	var j := DotPaths.write_json(base + ".json", r)
	if not j.ok:
		return j.wrap("profiler: cannot write the report")
	var t := DotPaths.write_text(base + ".txt", "\n".join(to_text(r)) + "\n")
	if not t.ok:
		return t.wrap("profiler: cannot write the text report")
	if folded != "":
		var f := DotPaths.write_text(base + ".folded", folded)
		if not f.ok:
			return f.wrap("profiler: cannot write the folded stacks")
	prune(dir, keep)
	return DotResult.success(base + ".json")


## Recordings under [param dir], newest first: [{path, text_path, name, bytes}].
static func list(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var names := Array(d.get_files()).filter(func(n: String) -> bool: return n.begins_with("profile-") and n.ends_with(".json"))
	names.sort()
	names.reverse()
	for n: String in names:
		var path := dir.path_join(n)
		out.append({"path": path, "text_path": path.get_basename() + ".txt", "folded_path": path.get_basename() + ".folded",
			"name": n.get_basename(),
			"bytes": DotPaths.file_size(path)})
	return out


## Deletes all but the newest [param keep] recordings in [param dir].
static func prune(dir: String, keep: int) -> void:
	var all := list(dir)
	for row: Dictionary in all.slice(keep):
		for p: String in [row.path, row.text_path, row.folded_path]:
			if FileAccess.file_exists(p):
				var err := DirAccess.remove_absolute(p)
				if err != OK:
					DotLog.warn(CHANNEL, "could not delete old recording %s: %s" % [p, error_string(err)])
	DotWeb.sync_filesystem()
