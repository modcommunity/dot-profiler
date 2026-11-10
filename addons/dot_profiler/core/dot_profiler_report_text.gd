class_name DotProfilerReportText
extends RefCounted

## The text sections a version 2 report adds after the version 1 ones: frame statistics, physics ticks,
## engine monitors, growth, groups, the call tree, script functions, physics queries, the timeline, the worst
## frames whole, the node census and the profiler's own cost. Optional sections print only when recorded.

## Tree nodes cheaper than this per frame are left out of the text (the JSON keeps them).
const TREE_MIN_MS := 0.05
## Worst-frame tree nodes cheaper than this are left out of the text.
const FRAME_MIN_MS := 0.2
## Flagged timeline frames the text lists, slowest first.
const FLAGGED_LINES := 15
## Census classes the text lists.
const CENSUS_LINES := 12


static func lines(r: Dictionary, top: int = 20) -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_breakdown(r))
	out.append_array(_frames(r))
	out.append_array(_ticks(r))
	out.append_array(_monitors(r))
	out.append_array(_growth(r))
	out.append_array(_groups(r))
	out.append_array(_engine(r))
	out.append_array(DotProfilerSuspects.function_lines(r))
	out.append_array(_tree(r))
	out.append_array(_scripts(r, top))
	out.append_array(_queries(r, top))
	out.append_array(_timeline(r))
	out.append_array(_worst(r))
	out.append_array(_census(r))
	out.append_array(_extras(r))
	var o: Dictionary = r.get("overhead", {})
	if not o.is_empty():
		out.append("")
		out.append("Profiler overhead: on_frame avg %.3f ms, max %.2f ms; %.0f traced spans per frame%s" % [
			o.get("on_frame_avg_ms", 0.0), o.get("on_frame_max_ms", 0.0), o.get("spans_per_frame", 0.0),
			"" if o.get("trace", false) else " (trace off)"])
	var deep: Dictionary = r.get("deep", {})
	if not deep.is_empty():
		out.append("Deep mode: " + (("perf samples in " + String(deep.get("file", ""))) if deep.get("ok", false)
			else String(deep.get("reason", "off"))))
	return out


static func _stat_line(label: String, s: Dictionary, unit: String = "") -> String:
	return "  %-22s min %8.2f  avg %8.2f  p50 %8.2f  p95 %8.2f  p99 %8.2f  max %8.2f%s" % [label, s.get("min", 0.0),
		s.get("avg", 0.0), s.get("p50", 0.0), s.get("p95", 0.0), s.get("p99", 0.0), s.get("max", 0.0), unit]


static func _frames(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var fs: Dictionary = r.get("frame_stats", {})
	if fs.is_empty():
		return out
	out.append("")
	out.append("Frames (ms):")
	for k: String in ["frame", "physics", "script", "render", "wait"]:
		if fs.has(k):
			out.append(_stat_line(k, fs[k]))
	return out


## The frame as the sum of its parts: engine phases, then what is left over; and the named spans a game reported.
static func _breakdown(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ph: Dictionary = r.get("phases", {})
	var frames := maxf(float(r.get("frames", 0)), 1.0)
	if ph.is_empty() or float(r.get("frames", 0)) <= 0.0:
		return out
	var avg := float(r.get("wall_s", 0.0)) * 1000.0 / frames
	var parts := 0.0
	var cells := PackedStringArray()
	for k: String in ["physics", "script", "render", "wait"]:
		var v := float(ph.get(k, 0.0)) / frames
		parts += v
		cells.append("%s %.2f" % [k, v])
	out.append("")
	out.append("Per frame: %.2f ms (%.0f fps) = %s + unaccounted %.2f ms" % [avg, 1000.0 / maxf(avg, 0.001), " + ".join(cells), avg - parts])
	var named := 0.0
	for s: Dictionary in r.get("systems", []):
		named += float(s.get("ms_per_frame", 0.0))
	if named > 0.0:
		out.append("  named systems %.2f ms per frame (spans may nest, so this can exceed script time); see Systems below" % named)
	var m: Dictionary = r.get("monitors", {})
	if m.has("render_cpu_ms") or m.has("render_gpu_ms"):
		out.append("  render: cpu %.2f ms avg (p95 %.2f), gpu %.2f ms avg (p95 %.2f)" % [
			float((m.get("render_cpu_ms", {}) as Dictionary).get("avg", 0.0)), float((m.get("render_cpu_ms", {}) as Dictionary).get("p95", 0.0)),
			float((m.get("render_gpu_ms", {}) as Dictionary).get("avg", 0.0)), float((m.get("render_gpu_ms", {}) as Dictionary).get("p95", 0.0))])
	else:
		out.append("  render cpu/gpu ms: not recorded (profiler_render_time 1 records them)")
	if m.has("draw_calls"):
		out.append("  drawn per frame: %.0f draw calls, %.0f primitives, %.0f objects (p95 %.0f / %.0f / %.0f)" % [
			_stat(m, "draw_calls"), _stat(m, "primitives"), _stat(m, "objects_drawn"),
			_stat(m, "draw_calls", "p95"), _stat(m, "primitives", "p95"), _stat(m, "objects_drawn", "p95")])
	return out


static func _stat(m: Dictionary, key: String, stat: String = "avg") -> float:
	return float((m.get(key, {}) as Dictionary).get(stat, 0.0))


static func _engine(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var e: Dictionary = r.get("engine", {})
	if e.is_empty():
		return out
	out.append("")
	out.append("Engine work per tick (outside the spans; %d ticks):" % int(e.get("ticks", 0)))
	out.append("  physics queries        %8.1f calls  %8.3f ms  %6.1f us/call" % [float(e.get("queries_per_tick", 0.0)),
		float(e.get("query_ms_per_tick", 0.0)), float(e.get("query_us_per_call", 0.0))])
	out.append("  nodes entering tree    %8.2f        leaving %.2f  (%d / %d in all)" % [float(e.get("nodes_added_per_tick", 0.0)),
		float(e.get("nodes_removed_per_tick", 0.0)), int(e.get("nodes_added", 0)), int(e.get("nodes_removed", 0))])
	out.append("  objects grown          %8.2f        net %+.0f over the recording" % [float(e.get("objects_grown_per_tick", 0.0)), float(e.get("objects_net", 0.0))])
	out.append("  resources grown        %8.2f        net %+.0f" % [float(e.get("resources_grown_per_tick", 0.0)), float(e.get("resources_net", 0.0))])
	out.append("  static memory grown    %8.2f KB     net %+.0f KB, peak %.0f MB" % [float(e.get("static_kb_grown_per_tick", 0.0)),
		float(e.get("static_kb_net", 0.0)), float(e.get("static_peak_mb", 0.0))])
	var counts: Dictionary = e.get("counts", {})
	var names: Array = counts.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return float(counts[a].total) > float(counts[b].total))
	for k: Variant in names:
		out.append("  %-22s %8.2f        (%.0f in all)" % [String(k).left(22), float(counts[k].per_tick), float(counts[k].total)])
	out.append("  grown = summed over the frames the count rose (a floor for what was created). Not counted: %s." % String(e.get("not_counted", "")))
	return out


static func _extras(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ex: Dictionary = r.get("extras", {})
	for k: String in ex:
		if out.is_empty():
			out.append("")
			out.append("Game extras:")
		out.append("  %s: %s" % [k, DotProfilerContext.flat(ex[k])])
	return out


static func _ticks(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var t: Dictionary = r.get("physics_ticks", {})
	if t.is_empty():
		return out
	var frames := maxi(int(r.get("frames", 0)), 1)
	out.append("")
	out.append("Physics ticks: %d at %d/s, %.2f per frame (max %d); catch-up (2+ ticks) in %d frames (%.0f%%), spiral (max ticks) in %d" % [
		t.get("ticks", 0), t.get("per_second", 0), t.get("per_frame", 0.0), t.get("max_per_frame", 0),
		t.get("catch_up_frames", 0), 100.0 * float(t.get("catch_up_frames", 0)) / frames, t.get("spiral_frames", 0)])
	var hist: Dictionary = t.get("histogram", {})
	var keys := hist.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var parts := PackedStringArray()
	for k: Variant in keys:
		parts.append("%sx %d" % [k, hist[k]])
	out.append("  ticks per frame: " + "  ".join(parts))
	if t.has("ticks_per_sec"):
		out.append("  %.1f ticks/s achieved of %d/s; dropped (never simulated): %d" % [t.ticks_per_sec, t.get("per_second", 0), t.get("dropped_ticks", 0)])
	var ticks := maxi(int(t.get("ticks", 0)), 1)
	for row: Dictionary in r.get("tree", []):
		if row.path == "frame;physics;scripts" or row.path == "frame;physics;step":
			out.append("  %-22s %.2f ms per tick (%.2f ms per frame)" % [
				"scripts (_physics_process)" if row.path.ends_with("scripts") else "engine step + sync",
				float(row.ms) * frames / ticks, row.ms])
	return out


static func _monitors(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var m: Dictionary = r.get("monitors", {})
	if m.is_empty():
		return out
	out.append("")
	out.append("Engine monitors (per frame):")
	for k: String in m:
		out.append(_stat_line(k, m[k]))
	return out


static func _tree(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rows: Array = r.get("tree", [])
	if rows.is_empty():
		return out
	out.append("")
	out.append("Call tree (ms per frame; self is exclusive; frame > process | render | wait | physics > scripts | step):")
	out.append("  %-52s %8s %8s %8s %8s %9s" % ["", "incl", "self", "p95", "max", "calls/fr"])
	for row: Dictionary in rows:
		if float(row.ms) < TREE_MIN_MS and int(row.depth) > 0:
			continue
		var label := "  ".repeat(int(row.depth)) + String(row.get("name", row.path))
		out.append("  %-52s %8.2f %8.2f %8.2f %8.2f %9.1f" % [label.left(52), row.ms, row.self_ms, row.p95_ms,
			row.max_ms, row.calls])
	return out


static func _queries(r: Dictionary, top: int) -> PackedStringArray:
	var out := PackedStringArray()
	var rows: Array = r.get("queries", [])
	if rows.is_empty():
		return out
	out.append("")
	out.append("Physics queries (DotSpaceQuery / DotFrameCost.add_query):")
	out.append("  %-24s %-18s %10s %10s %9s %8s %8s" % ["system", "kind", "calls/fr", "calls/tick", "ms/frame", "us/call", "worst"])
	for q: Dictionary in rows.slice(0, top):
		out.append("  %-24s %-18s %10.1f %10.1f %9.2f %8.1f %8.2f" % [String(q.system).left(24), String(q.kind).left(18),
			q.calls_per_frame, q.calls_per_tick, q.ms_per_frame, q.us_per_call, q.worst_ms])
	var traced: Dictionary = r.get("traced_queries", {})
	if traced.is_empty():
		return out
	var frames := maxf(float(r.get("frames", 0)), 1.0)
	out.append("  by caller span (traced):")
	for caller: String in traced:
		for kind: String in traced[caller]:
			var t: Dictionary = traced[caller][kind]
			out.append("    %-22s %-18s %10.1f calls/fr %8.2f ms/frame" % [caller.left(22), kind.left(18),
				float(t.calls) / frames, float(t.ms) / frames])
	return out


static func _worst(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var worst: Array = r.get("worst_frames", [])
	if worst.is_empty():
		return out
	out.append("")
	out.append("Worst frames (whole tree, ms incl / self):")
	for w: Dictionary in worst:
		out.append("  t=%.2fs %.1f ms  ticks %d  [phys %.1f script %.1f render %.1f wait %.1f]" % [w.t, w.ms, w.ticks,
			w.get("physics", 0.0), w.get("script", 0.0), w.get("render", 0.0), w.get("wait", 0.0)])
		for row: Dictionary in w.get("tree", []):
			if float(row.ms) >= FRAME_MIN_MS:
				out.append("    %-60s %7.2f %7.2f  x%d" % [String(row.path).right(60), row.ms, row.self_ms, row.calls])
	return out


static func _growth(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var g: Dictionary = r.get("growth", {})
	if g.is_empty():
		return out
	out.append("")
	out.append("Growth over the recording (first -> last, per minute):")
	for k: String in g:
		var row: Dictionary = g[k]
		out.append("  %-22s %10.1f -> %10.1f  %+10.1f  (%+.1f/min, max %.1f)" % [k, row.first, row.last, row.delta,
			row.per_min, row.max])
	return out


static func _groups(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var groups: Array = r.get("groups", [])
	if groups.is_empty():
		return out
	out.append("")
	out.append("Groups (count per frame; systems under the prefix, cost per unit):")
	for g: Dictionary in groups:
		var c: Dictionary = g.count
		out.append("  %-22s avg %7.1f  min %5.0f  max %5.0f%s" % [String(g.group).left(22), c.avg, c.min, c.max,
			("  systems " + String(g.prefix) + "*") if String(g.prefix) != "" else ""])
		for s: Dictionary in g.get("systems", []):
			out.append("    %-34s %8.3f ms/frame  %9.1f us/unit  %7.1f calls/fr" % [String(s.system).left(34),
				s.ms_per_frame, s.us_per_unit, s.calls_per_frame])
	return out


static func _scripts(r: Dictionary, top: int) -> PackedStringArray:
	var out := PackedStringArray()
	var sf: Dictionary = r.get("script_functions", {})
	if sf.is_empty():
		return out
	out.append("")
	if not sf.get("ok", false):
		out.append("Script functions: off (%s)" % sf.get("reason", ""))
		return out
	out.append("Script functions (GDScript profiler, ms per frame; %d functions, %.2f ms self per frame):" % [
		sf.get("function_count", 0), sf.get("self_ms", 0.0)])
	out.append("  %-44s %8s %8s %9s %8s" % ["function", "self", "total", "calls/fr", "us/call"])
	for f: Dictionary in (sf.get("functions", []) as Array).slice(0, top):
		var label := "%s %s:%d" % [f.function, String(f.script).get_file(), f.line]
		out.append("  %-44s %8.3f %8.3f %9.1f %8.2f" % [label.left(44), f.self_ms, f.total_ms, f.calls_per_frame,
			f.us_per_call])
	var buckets: Array = sf.get("buckets", [])
	if not buckets.is_empty():
		out.append("  buckets (self ms per frame):")
		for b: Dictionary in buckets:
			out.append("    %-22s %8.3f ms  %9.1f calls/fr  %4d functions" % [String(b.bucket).left(22), b.self_ms,
				b.calls_per_frame, b.functions])
	var scripts: Array = sf.get("scripts", [])
	if not scripts.is_empty():
		out.append("  by script (self ms per frame):")
		for s: Dictionary in scripts.slice(0, mini(top, 10)):
			out.append("    %-44s %8.3f ms  %9.1f calls/fr" % [String(s.script).right(44), s.self_ms, s.calls_per_frame])
	return out


static func _timeline(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var tl: Dictionary = r.get("timeline", {})
	if tl.is_empty():
		return out
	out.append("")
	out.append("Timeline (per second; ms per frame; flagged = over budget or %.0fx the running average):" % DotProfilerSession.FLAG_X)
	out.append("  %4s %6s %8s %8s %8s %8s %8s %8s %8s" % ["s", "frames", "avg", "max", "physics", "script", "render", "wait", "flagged"])
	for row: Dictionary in tl.get("seconds", []):
		out.append("  %4d %6d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %8d" % [row.s, row.frames, row.avg_ms, row.max_ms,
			row.physics, row.script, row.render, row.wait, row.flagged])
	var flagged: Array = (tl.get("flagged", []) as Array).duplicate()
	if flagged.is_empty():
		return out
	flagged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	out.append("  flagged frames (%d, slowest first; what ran in them):" % flagged.size())
	var t0 := float(tl.get("t0", 0.0))
	for f: Dictionary in flagged.slice(0, FLAGGED_LINES):
		out.append("    t=%.2fs %.1f ms (avg %.1f)  [phys %.1f script %.1f render %.1f wait %.1f]" % [float(f.t) - t0,
			f.ms, f.avg_ms, f.get("physics", 0.0), f.get("script", 0.0), f.get("render", 0.0), f.get("wait", 0.0)])
		var parts := PackedStringArray()
		for s: Dictionary in f.get("systems", []):
			parts.append("%s %.2f" % [s.system, s.ms])
		if not parts.is_empty():
			out.append("      systems: " + ", ".join(parts))
		parts = PackedStringArray()
		for t: Dictionary in f.get("top", []):
			parts.append("%s %.2f" % [String(t.path).get_slice(";", String(t.path).get_slice_count(";") - 1), t.self_ms])
		if not parts.is_empty():
			out.append("      self: " + ", ".join(parts))
	return out


static func _census(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var c: Dictionary = r.get("census", {})
	if c.is_empty():
		return out
	out.append("")
	out.append("Node census: %d -> %d nodes (biggest changes):" % [c.get("start_nodes", 0), c.get("end_nodes", 0)])
	for row: Dictionary in (c.get("classes", []) as Array).slice(0, CENSUS_LINES):
		out.append("  %-32s %6d -> %6d  %+6d" % [String(row["class"]).left(32), row.start, row.end, row.delta])
	return out
