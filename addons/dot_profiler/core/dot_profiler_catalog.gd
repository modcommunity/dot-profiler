class_name DotProfilerCatalog
extends RefCounted

## Everything a recording can contain, as data: the menu builds its switches from it, the "what does it record"
## list prints it, and [method strip] leaves the switched-off report sections out. One row per setting:
## {key, label, group, kind, what, cost, keys, min, max, step}. [code]kind[/code] is bool, number (0 is off) or text (empty is off).

const GROUP_REPORT := "Report sections"
const GROUP_COLLECT := "Collected while recording"
const GROUP_EXTRA := "Detail options"


static func rows() -> Array[Dictionary]:
	return [
		_b("rec_frame_stats", "Frame time statistics", GROUP_REPORT, "min, average, p50, p95, p99 and max of the frame and of each engine phase (physics, script, render, wait).", "none", ["frame_stats"]),
		_b("rec_spikes", "Spikes and causes", GROUP_REPORT, "every frame over the budget with the system or engine phase blamed, hints (shader compiles, new nodes, log lines) and the beat spikes repeat on.", "none", ["spikes", "causes"]),
		_b("rec_systems", "System costs", GROUP_REPORT, "ms, calls and worst call of every system reported through DotFrameCost.", "none", ["systems"]),
		_b("rec_phases", "Engine phase totals", GROUP_REPORT, "total time in physics, script, render and wait.", "none", ["phases"]),
		_b("rec_physics_ticks", "Physics ticks per frame", GROUP_REPORT, "ticks, catch-up frames, spiral-of-death frames and the per-frame histogram.", "none", ["physics_ticks"]),
		_b("rec_queries", "Physics queries", GROUP_REPORT, "raycasts, shape casts and point queries per system: ms, calls, per frame and per tick.", "none", ["queries", "traced_queries"]),
		_b("rec_growth", "Growth", GROUP_REPORT, "first to last value of nodes, objects, orphans, resources and memory, and per minute.", "none", ["growth"]),
		_b("rec_overhead", "Profiler overhead", GROUP_REPORT, "the profiler's own cost per frame and spans timed per frame.", "none", ["overhead"]),
		_b("rec_suspects", "Suspects and functions", GROUP_REPORT, "the costliest spans by self time against the tick budget and the per-unit target, and every span summed by name with self, total, calls and cost per call, tick and unit.", "none", ["suspects", "functions", "budget"]),
		_b("rec_engine", "Engine work per tick", GROUP_REPORT, "queries, nodes entering and leaving the tree, growth of objects, resources and static memory, and counts a game reports (DotProfilerCounts), all per tick.", "none", ["engine"]),
		_b("trace", "Call tree (span tracing)", GROUP_COLLECT, "times every span reported through DotFrameCost so the report has a tree below the systems, plus folded stacks for a flamegraph.", "medium", ["tree", "traced_queries"]),
		_b("monitors", "Engine monitors", GROUP_COLLECT, "every frame: process and physics ms, navigation ms, active bodies, pairs, islands, draw calls, objects, primitives, nodes, orphans, memory, video memory.", "low", ["monitors"]),
		_n("sample_hz", "Metric samples per second", GROUP_COLLECT, "memory, object and node counts (a server adds players, bots and network) sampled this many times a second; 0 takes none.", "low", ["samples"], 0.0, 60.0, 0.5),
		_n("worst_frames", "Worst frames kept whole", GROUP_COLLECT, "the slowest N frames with their full call tree, queries and monitors; 0 keeps none.", "low", ["worst_frames"], 0.0, 50.0, 1.0),
		_b("timeline", "Timeline", GROUP_EXTRA, "every frame's time, a per-second table and the frames well above the running average with the spans that ran in them.", "low", ["timeline"]),
		_b("render_time", "Render cpu and gpu time", GROUP_COLLECT, "the viewport's measured render cpu and gpu ms every frame.", "low", ["monitors"]),
		_b("render_detail", "Render detail", GROUP_EXTRA, "texture and buffer memory, resource count, the viewport's visible/shadow/canvas draw split and render cpu/gpu ms.", "low", ["monitors"]),
		_b("census", "Node census", GROUP_EXTRA, "nodes counted by class when the recording starts and stops, so the report says which kinds grew.", "low", ["census"]),
		_b("deep", "Native stacks (Linux perf)", GROUP_EXTRA, "samples native stacks with perf while recording (docs/deep-mode.md); needs perf installed.", "high", ["deep"]),
		_n("script_top", "Script functions listed", GROUP_EXTRA, "the engine's script profiler: the N costliest GDScript functions by self time, in script buckets. Needs the game run with -d; 0 is off.", "medium", ["script_functions"], 0.0, 500.0, 5.0),
		_t("groups", "Counted groups", GROUP_EXTRA, "comma-separated group or group:system-prefix counted every frame (SceneTree groups or counters a game registers); the report gives each prefixed system's cost per unit.", "low", ["groups"]),
	]


## The row for [param key], or {}.
static func row(key: String) -> Dictionary:
	for r in rows():
		if r.key == key:
			return r
	return {}


## True when [param r]'s setting is on in [param config].
static func is_on(r: Dictionary, config: DotProfilerConfig) -> bool:
	var v: Variant = config.get(r.key)
	match r.kind:
		"bool":
			return bool(v)
		"number":
			return float(v) > 0.0
	return String(v).strip_edges() != ""


## A line per setting a person can read: on/off, name, what it records, cost and the report keys it adds.
static func lines(config: DotProfilerConfig) -> PackedStringArray:
	var out := PackedStringArray()
	var group := ""
	for r in rows():
		if r.group != group:
			group = r.group
			if not out.is_empty():
				out.append("")
			out.append(group.to_upper())
		var state := "on " if is_on(r, config) else "off"
		var val := ""
		if r.kind != "bool":
			val = "  [%s]" % config.text_of(r.key)
		out.append("[%s] %s%s  (cost: %s)" % [state, r.label, val, r.cost])
		out.append("      " + String(r.what))
		out.append("      setting profiler_%s   report: %s" % [r.key, ", ".join(r.keys)])
	return out


## Sets every switch to [param on] (numbers and text go to a useful value or zero); true for the cheap ones only when [param cheap_only].
static func set_all(config: DotProfilerConfig, on: bool, cheap_only: bool = false) -> void:
	for r in rows():
		if cheap_only and r.cost in ["high", "medium"]:
			continue
		var text := "0"
		match r.kind:
			"bool":
				text = "1" if on else "0"
			"number":
				text = _on_value(r) if on else "0"
			_:
				continue
		var _s := config.set_text(r.key, text)


static func _on_value(r: Dictionary) -> String:
	match r.key:
		"sample_hz":
			return "1"
		"worst_frames":
			return "5"
		"script_top":
			return "40"
	return "1"


## Removes from [param report] the keys of every report section that is switched off in [param config].
static func strip(report: Dictionary, config: DotProfilerConfig) -> void:
	for r in rows():
		if r.group != GROUP_REPORT or bool(config.get(r.key)):
			continue
		for k: String in r.keys:
			report.erase(k)


static func _b(key: String, label: String, group: String, what: String, cost: String, keys: Array) -> Dictionary:
	return {"key": key, "label": label, "group": group, "kind": "bool", "what": what, "cost": cost, "keys": keys, "min": 0.0, "max": 1.0, "step": 1.0}


static func _n(key: String, label: String, group: String, what: String, cost: String, keys: Array, lo: float, hi: float, step: float) -> Dictionary:
	return {"key": key, "label": label, "group": group, "kind": "number", "what": what, "cost": cost, "keys": keys, "min": lo, "max": hi, "step": step}


static func _t(key: String, label: String, group: String, what: String, cost: String, keys: Array) -> Dictionary:
	return {"key": key, "label": label, "group": group, "kind": "text", "what": what, "cost": cost, "keys": keys, "min": 0.0, "max": 0.0, "step": 0.0}
