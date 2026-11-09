class_name DotProfilerReportText
extends RefCounted

## The text sections a version 2 report adds after the version 1 ones: frame statistics, physics ticks,
## engine monitors, the call tree, physics queries, the worst frames whole and the profiler's own cost.

## Tree nodes cheaper than this per frame are left out of the text (the JSON keeps them).
const TREE_MIN_MS := 0.05
## Worst-frame tree nodes cheaper than this are left out of the text.
const FRAME_MIN_MS := 0.2


static func lines(r: Dictionary, top: int = 20) -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_frames(r))
	out.append_array(_ticks(r))
	out.append_array(_monitors(r))
	out.append_array(_tree(r))
	out.append_array(_queries(r, top))
	out.append_array(_worst(r))
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
	return "  %-22s min %8.2f  avg %8.2f  p95 %8.2f  p99 %8.2f  max %8.2f%s" % [label, s.get("min", 0.0),
		s.get("avg", 0.0), s.get("p95", 0.0), s.get("p99", 0.0), s.get("max", 0.0), unit]


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
