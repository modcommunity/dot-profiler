class_name DotProfilerSession
extends RefCounted

## The deep half of one recording: the call tree, physics ticks per frame, engine monitors, physics queries
## per system, the worst frames whole and the profiler's own cost. [method add] takes each frame,
## [method to_report] gives the report keys version 2 adds.

## Engine monitors read every frame: report name, monitor, scale.
const MONITORS: Array = [
	["time_process_ms", Performance.TIME_PROCESS, 1000.0],
	["time_physics_ms", Performance.TIME_PHYSICS_PROCESS, 1000.0],
	["time_navigation_ms", Performance.TIME_NAVIGATION_PROCESS, 1000.0],
	["physics_3d_active", Performance.PHYSICS_3D_ACTIVE_OBJECTS, 1.0],
	["physics_3d_pairs", Performance.PHYSICS_3D_COLLISION_PAIRS, 1.0],
	["physics_3d_islands", Performance.PHYSICS_3D_ISLAND_COUNT, 1.0],
	["draw_calls", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, 1.0],
	["objects_drawn", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, 1.0],
	["primitives", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, 1.0],
	["objects", Performance.OBJECT_COUNT, 1.0],
	["nodes", Performance.OBJECT_NODE_COUNT, 1.0],
	["orphan_nodes", Performance.OBJECT_ORPHAN_NODE_COUNT, 1.0],
	["static_mb", Performance.MEMORY_STATIC, 1.0 / 1048576.0],
	["video_mb", Performance.RENDER_VIDEO_MEM_USED, 1.0 / 1048576.0],
]
const PHASES: Array[String] = ["physics", "script", "render", "wait"]
## Read with [member render_detail]: report name, monitor, scale.
const RENDER_MONITORS: Array = [
	["texture_mb", Performance.RENDER_TEXTURE_MEM_USED, 1.0 / 1048576.0],
	["buffer_mb", Performance.RENDER_BUFFER_MEM_USED, 1.0 / 1048576.0],
	["resources", Performance.OBJECT_RESOURCE_COUNT, 1.0],
]
## Monitors whose first-to-last change the report gives as growth.
const GROWTH: Array[String] = ["nodes", "objects", "orphan_nodes", "resources", "static_mb", "video_mb", "texture_mb", "buffer_mb"]
## A timeline frame is flagged when it is this many times the running average and at least FLAG_MIN_MS above it.
const FLAG_X := 2.0
const FLAG_MIN_MS := 2.0
## Flagged frames kept, the slowest when there are more.
const FLAG_KEEP := 200

var tree := DotProfilerTree.new()
## Read [constant MONITORS] each frame.
var monitors := true
## Frames kept whole, worst first.
var worst_keep := 5
## Keep each frame's time and flag frames that jump above the running average ([member DotProfilerConfig.timeline]).
var timeline := false
## Budget in ms; a timeline frame over it is always flagged.
var budget_ms := 33.0
## Read [constant RENDER_MONITORS] and the draw split of [member viewport] each frame.
var render_detail := false
var viewport := RID()
## Counted each frame: [{group, prefix, count: Callable}] ([method DotProfiler.add_counter]).
var counters: Array[Dictionary] = []

var _frame_ms := PackedFloat32Array()
var _phase_ms := {}
var _mon := {}
var _ticks_hist := {}
var _ticks := 0
var _catch_up := 0
var _spiral := 0
var _queries := {}
var _worst: Array[Dictionary] = []
var _spans := 0
var _overhead_us := 0
var _overhead_max_us := 0
var _t := PackedFloat32Array()
var _ema := 0.0
var _flagged: Array[Dictionary] = []
var _counts: Array[Array] = []


func _init() -> void:
	for p in PHASES:
		_phase_ms[p] = []
	for m: Array in MONITORS:
		_mon[m[0]] = []


## Call after setting [member render_detail] and [member counters], before the first [method add].
func begin() -> void:
	if render_detail:
		for k in render_detail_keys():
			_mon[k] = []
		if viewport.is_valid():
			RenderingServer.viewport_set_measure_render_time(viewport, true)
	_counts.clear()
	for _c in counters:
		_counts.append([])


## The monitor names [member render_detail] adds.
static func render_detail_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for m: Array in RENDER_MONITORS:
		out.append(m[0])
	out.append_array(["draws_visible", "draws_shadow", "draws_canvas", "primitives_visible", "primitives_shadow",
		"objects_visible", "objects_shadow", "render_cpu_ms", "render_gpu_ms"])
	return out


## Adds one DotHitchLog record and the physics ticks stamped in its window ([method DotProfilerTicks.take]).
func add(rec: Dictionary, ticks: PackedInt64Array) -> void:
	var ms: float = rec.get("ms", 0.0)
	var _a := _frame_ms.append(ms)
	for p in PHASES:
		(_phase_ms[p] as Array).append(float(rec.get(p, 0.0)))
	var n := ticks.size() / 2
	_ticks += n
	_ticks_hist[n] = int(_ticks_hist.get(n, 0)) + 1
	if n > 1:
		_catch_up += 1
	if n >= Engine.max_physics_steps_per_frame:
		_spiral += 1
	if monitors:
		for m: Array in MONITORS:
			(_mon[m[0]] as Array).append(Performance.get_monitor(m[1]) * float(m[2]))
	if render_detail:
		_add_render()
	for i in counters.size():
		var c: Variant = (counters[i].count as Callable).call()
		_counts[i].append(float(c) if c is int or c is float else 0.0)
	var q: Dictionary = rec.get("queries", {})
	_merge_queries(q)
	var ev: Dictionary = rec.get("events", {})
	_spans += (ev.get("events", PackedInt64Array()) as PackedInt64Array).size() / 3
	var flat := tree.add_frame(rec, ticks)
	if timeline:
		_add_timeline(rec, ms, flat)
	if worst_keep > 0 and (_worst.size() < worst_keep or ms > float(_worst[-1].ms)):
		_keep_worst(rec, n, flat, q)


## Charges [param usec] of the profiler's own per-frame work to the recording.
func add_overhead(usec: int) -> void:
	_overhead_us += usec
	_overhead_max_us = maxi(_overhead_max_us, usec)


## The report keys this session adds: frame_stats, tree, worst_frames, monitors, queries, traced_queries,
## physics_ticks, overhead and growth, plus timeline and groups when those are on. [param min_tree_ms] leaves out tree nodes cheaper than that per frame.
func to_report(min_tree_ms: float = 0.001) -> Dictionary:
	var frames := maxi(_frame_ms.size(), 1)
	var stats := {"frame": stats_of(_frame_ms)}
	for p in PHASES:
		stats[p] = stats_of(PackedFloat32Array(_phase_ms[p]))
	var mon := {}
	for k: String in _mon:
		if not (_mon[k] as Array).is_empty():
			mon[k] = stats_of(PackedFloat32Array(_mon[k]))
	var q_rows: Array = []
	for sys: String in _queries:
		for kind: String in _queries[sys]:
			var r: Dictionary = _queries[sys][kind]
			q_rows.append({"system": sys, "kind": kind, "ms": r.ms, "calls": r.calls, "worst_ms": r.worst_ms,
				"ms_per_frame": r.ms / frames, "calls_per_frame": float(r.calls) / frames,
				"calls_per_tick": float(r.calls) / maxi(_ticks, 1), "us_per_call": r.ms * 1000.0 / maxi(r.calls, 1)})
	q_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	var hist := {}
	for k: int in _ticks_hist:
		hist[str(k)] = _ticks_hist[k]
	var wall_s := 0.0
	for v in _frame_ms:
		wall_s += v / 1000.0
	var dropped := maxi(int(round(wall_s * Engine.physics_ticks_per_second)) - _ticks, 0)
	var out := {
		"frame_stats": stats,
		"tree": tree.rows(min_tree_ms),
		"worst_frames": _worst,
		"monitors": mon,
		"queries": q_rows,
		"traced_queries": tree.traced_queries(),
		"physics_ticks": {"ticks": _ticks, "per_second": Engine.physics_ticks_per_second,
			"max_per_frame": Engine.max_physics_steps_per_frame, "per_frame": float(_ticks) / frames,
			"histogram": hist, "catch_up_frames": _catch_up, "spiral_frames": _spiral,
			"wall_s": wall_s, "ticks_per_sec": float(_ticks) / maxf(wall_s, 0.001), "dropped_ticks": dropped},
		"overhead": {"on_frame_avg_ms": _overhead_us / 1000.0 / frames, "on_frame_max_ms": _overhead_max_us / 1000.0,
			"spans_per_frame": float(_spans) / frames, "trace": _spans > 0},
		"growth": _growth(),
	}
	if timeline:
		out["timeline"] = _timeline_report()
	if not counters.is_empty():
		var g: Array = []
		for i in counters.size():
			g.append({"group": counters[i].group, "prefix": counters[i].prefix, "count": stats_of(PackedFloat32Array(_counts[i]))})
		out["groups"] = g
	return out


## Fills each [code]groups[/code] row of a built report with the systems under its prefix and their cost per unit.
static func attach_group_systems(report: Dictionary) -> void:
	for g: Dictionary in report.get("groups", []):
		var rows: Array = []
		var units := maxf(float((g.count as Dictionary).get("avg", 0.0)), 0.0)
		if String(g.prefix) != "":
			for s: Dictionary in report.get("systems", []):
				if String(s.system).begins_with(g.prefix):
					var ms := float(s.get("ms_per_frame", 0.0))
					rows.append({"system": s.system, "ms_per_frame": ms, "calls_per_frame": float(s.get("calls", 0)) / maxf(float(report.get("frames", 0)), 1.0),
						"us_per_unit": ms * 1000.0 / units if units > 0.0 else 0.0})
		g["systems"] = rows


## The recording's tree as folded stacks for a flamegraph.
func folded() -> String:
	return tree.folded()


## {min, avg, p50, p95, p99, max} of [param values], or zeros when empty.
static func stats_of(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0.0, "avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var s := values.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	return {"min": s[0], "avg": total / s.size(), "p50": DotProfilerReport.percentile(s, 0.5),
		"p95": DotProfilerReport.percentile(s, 0.95), "p99": DotProfilerReport.percentile(s, 0.99), "max": s[-1]}


func _add_render() -> void:
	for m: Array in RENDER_MONITORS:
		(_mon[m[0]] as Array).append(Performance.get_monitor(m[1]) * float(m[2]))
	var vp := viewport
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var sh := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var draws := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var prims := RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	var objs := RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
	var ok := vp.is_valid()
	(_mon.draws_visible as Array).append(RenderingServer.viewport_get_render_info(vp, vis, draws) if ok else 0)
	(_mon.draws_shadow as Array).append(RenderingServer.viewport_get_render_info(vp, sh, draws) if ok else 0)
	(_mon.draws_canvas as Array).append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, draws) if ok else 0)
	(_mon.primitives_visible as Array).append(RenderingServer.viewport_get_render_info(vp, vis, prims) if ok else 0)
	(_mon.primitives_shadow as Array).append(RenderingServer.viewport_get_render_info(vp, sh, prims) if ok else 0)
	(_mon.objects_visible as Array).append(RenderingServer.viewport_get_render_info(vp, vis, objs) if ok else 0)
	(_mon.objects_shadow as Array).append(RenderingServer.viewport_get_render_info(vp, sh, objs) if ok else 0)
	(_mon.render_cpu_ms as Array).append((RenderingServer.viewport_get_measured_render_time_cpu(vp) if ok else 0.0) + RenderingServer.get_frame_setup_time_cpu())
	(_mon.render_gpu_ms as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(vp) if ok else 0.0)


func _add_timeline(rec: Dictionary, ms: float, flat: PackedInt64Array) -> void:
	var _a := _t.append(float(rec.get("t", 0.0)))
	var avg := _ema if _ema > 0.0 else ms
	_ema = lerpf(avg, ms, 0.05)
	if ms < budget_ms and (ms < avg * FLAG_X or ms - avg < FLAG_MIN_MS):
		return
	if _flagged.size() >= FLAG_KEEP:
		var low := 0
		for i in _flagged.size():
			if float(_flagged[i].ms) < float(_flagged[low].ms):
				low = i
		if float(_flagged[low].ms) >= ms:
			return
		_flagged.remove_at(low)
	var rows := tree.frame_rows(flat)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms > b.self_ms)
	var top: Array = []
	for r: Dictionary in rows.slice(0, 5):
		top.append({"path": r.path, "self_ms": snappedf(r.self_ms, 0.001), "ms": snappedf(r.ms, 0.001)})
	var systems: Array = []
	var sys: Dictionary = rec.get("systems", {})
	for k: Variant in sys:
		systems.append({"system": String(k), "ms": snappedf(float(sys[k].get("ms", 0.0)), 0.001)})
	systems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	var e := {"t": rec.get("t", 0.0), "ms": ms, "avg_ms": snappedf(avg, 0.01), "top": top, "systems": systems.slice(0, 5)}
	for p in PHASES:
		e[p] = rec.get(p, 0.0)
	_flagged.append(e)


func _timeline_report() -> Dictionary:
	var secs: Array = []
	var flagged := _flagged.duplicate()
	flagged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	if _t.is_empty():
		return {"t0": 0.0, "frame_ms": [], "seconds": secs, "flagged": flagged}
	var t0 := _t[0]
	var cur := -1
	var row := {}
	for i in _t.size():
		var s := int(_t[i] - t0)
		if s != cur:
			if not row.is_empty():
				secs.append(_close_second(row))
			cur = s
			row = {"s": s, "frames": 0, "sum": 0.0, "max_ms": 0.0, "physics": 0.0, "script": 0.0, "render": 0.0, "wait": 0.0, "flagged": 0}
		var ms := _frame_ms[i] if i < _frame_ms.size() else 0.0
		row.frames += 1
		row.sum += ms
		row.max_ms = maxf(row.max_ms, ms)
		for p in PHASES:
			row[p] += float((_phase_ms[p] as Array)[i])
	secs.append(_close_second(row))
	for f: Dictionary in flagged:
		var s := int(float(f.t) - t0)
		for r: Dictionary in secs:
			if r.s == s:
				r.flagged += 1
	var frame_ms: Array = []
	for v in _frame_ms:
		frame_ms.append(snappedf(v, 0.01))
	return {"t0": t0, "frame_ms": frame_ms, "seconds": secs, "flagged": flagged}


static func _close_second(row: Dictionary) -> Dictionary:
	var n := maxf(float(row.frames), 1.0)
	var out := {"s": row.s, "frames": row.frames, "avg_ms": row.sum / n, "max_ms": row.max_ms, "flagged": row.flagged}
	for p in PHASES:
		out[p] = float(row[p]) / n
	return out


func _growth() -> Dictionary:
	var out := {}
	if _frame_ms.is_empty():
		return out
	var secs := 0.0
	for v in _frame_ms:
		secs += v / 1000.0
	for k in GROWTH:
		var arr: Array = _mon.get(k, [])
		if arr.is_empty():
			continue
		var first := float(arr[0])
		var last := float(arr[-1])
		out[k] = {"first": first, "last": last, "delta": last - first, "per_min": (last - first) * 60.0 / maxf(secs, 0.001),
			"max": float(arr.max())}
	return out


func _merge_queries(q: Dictionary) -> void:
	for sys: Variant in q:
		var by_kind: Dictionary = _queries.get(String(sys), {})
		for kind: Variant in q[sys]:
			var r: Dictionary = q[sys][kind]
			var row: Dictionary = by_kind.get(String(kind), {"ms": 0.0, "calls": 0, "worst_ms": 0.0})
			row.ms += float(r.get("ms", 0.0))
			row.calls += int(r.get("calls", 0))
			row.worst_ms = maxf(row.worst_ms, float(r.get("worst_ms", 0.0)))
			by_kind[String(kind)] = row
		_queries[String(sys)] = by_kind


func _keep_worst(rec: Dictionary, ticks: int, flat: PackedInt64Array, q: Dictionary) -> void:
	var mon := {}
	if monitors:
		for k: String in _mon:
			var arr: Array = _mon[k]
			mon[k] = arr[-1] if not arr.is_empty() else 0.0
	var entry := {"t": rec.get("t", 0.0), "ms": rec.get("ms", 0.0), "ticks": ticks, "tree": tree.frame_rows(flat),
		"queries": q.duplicate(true), "monitors": mon}
	for p in PHASES:
		entry[p] = rec.get(p, 0.0)
	_worst.append(entry)
	_worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	if _worst.size() > worst_keep:
		_worst.resize(worst_keep)
