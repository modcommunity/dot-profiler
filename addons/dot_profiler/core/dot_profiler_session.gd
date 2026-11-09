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

var tree := DotProfilerTree.new()
## Read [constant MONITORS] each frame.
var monitors := true
## Frames kept whole, worst first.
var worst_keep := 5

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


func _init() -> void:
	for p in PHASES:
		_phase_ms[p] = []
	for m: Array in MONITORS:
		_mon[m[0]] = []


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
	var q: Dictionary = rec.get("queries", {})
	_merge_queries(q)
	var ev: Dictionary = rec.get("events", {})
	_spans += (ev.get("events", PackedInt64Array()) as PackedInt64Array).size() / 3
	var flat := tree.add_frame(rec, ticks)
	if worst_keep > 0 and (_worst.size() < worst_keep or ms > float(_worst[-1].ms)):
		_keep_worst(rec, n, flat, q)


## Charges [param usec] of the profiler's own per-frame work to the recording.
func add_overhead(usec: int) -> void:
	_overhead_us += usec
	_overhead_max_us = maxi(_overhead_max_us, usec)


## The report keys this session adds: frame_stats, tree, worst_frames, monitors, queries, traced_queries,
## physics_ticks and overhead. [param min_tree_ms] leaves out tree nodes cheaper than that per frame.
func to_report(min_tree_ms: float = 0.001) -> Dictionary:
	var frames := maxi(_frame_ms.size(), 1)
	var stats := {"frame": stats_of(_frame_ms)}
	for p in PHASES:
		stats[p] = stats_of(PackedFloat32Array(_phase_ms[p]))
	var mon := {}
	if monitors:
		for k: String in _mon:
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
	return {
		"frame_stats": stats,
		"tree": tree.rows(min_tree_ms),
		"worst_frames": _worst,
		"monitors": mon,
		"queries": q_rows,
		"traced_queries": tree.traced_queries(),
		"physics_ticks": {"ticks": _ticks, "per_second": Engine.physics_ticks_per_second,
			"max_per_frame": Engine.max_physics_steps_per_frame, "per_frame": float(_ticks) / frames,
			"histogram": hist, "catch_up_frames": _catch_up, "spiral_frames": _spiral},
		"overhead": {"on_frame_avg_ms": _overhead_us / 1000.0 / frames, "on_frame_max_ms": _overhead_max_us / 1000.0,
			"spans_per_frame": float(_spans) / frames, "trace": _spans > 0},
	}


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
