@icon("res://addons/dot_profiler/icon.svg")
class_name DotProfiler
extends Node

## Watches every frame, names the system behind each over budget, spots spikes on a fixed beat and
## records reports. Off until profiler_enabled 1; [method bind_console] adds the profiler_* vars.
## Systems report through [DotFrameCost]; a frame with none is blamed on the slowest engine phase.

const CHANNEL := "dot.profiler"
const SERVICE := &"dot_profiler"
## A system must be at least this share of a spike to be its cause; below it the engine phase is.
const CAUSE_SHARE := 0.25
## The input action that starts a capture of profiler_capture_seconds, or stops and writes it.
const CAPTURE_ACTION := &"profiler_capture"

## A frame over budget, attributed: {t, ms, cause, what, hints, period, physics, script, render, wait, systems}.
signal spike(info: Dictionary)
signal recording_started(seconds: float)
## [param result] is [method stop_recording]'s: its value is the JSON path.
signal recording_finished(result: DotResult)

## The settings; made from defaults (then file, environment, command line) when left empty.
@export var config: DotProfilerConfig
## The layered config file read in [method Node._ready]; "" skips the file layer.
@export var config_file: String = ""
## Registers this node as [constant SERVICE] so menus and tools find it without a path.
@export var register_as_service: bool = true

## Returns one metrics sample (a Dictionary) for a recording, taken profiler_sample_hz times a second.
## The default is memory and object counts; [DotProfilerServer] adds network, players and bots.
var sampler: Callable = DotProfilerMetrics.memory

var _hitch: DotHitchLog = null
var _overlay: CanvasLayer = null
var _graph_data := DotProfilerGraphData.new()
var _periods := {}
var _all_period := DotProfilerPeriod.new()
var _last_warn := {}
var _suppressed := {}
var _avg_systems := {}
var _avg_phases := {"physics": 0.0, "script": 0.0, "render": 0.0, "wait": 0.0}
var _avg_ms := 0.0
var _spikes_seen := 0
var _last_spike: Dictionary = {}
var _by_cause := {}

var _recording := false
var _rec_started_usec := 0
var _rec_seconds := 0.0
var _rec_frames := PackedFloat32Array()
var _rec_spikes: Array = []
var _rec_systems := {}
var _rec_phases := {}
var _rec_samples: Array = []
var _next_sample_usec := 0
var _last_saved := ""
var _stop_pending := false
var _session: DotProfilerSession = null
var _ticks: DotProfilerTicks = null
var _deep := {}
var _counters: Array[Dictionary] = []
var _scripts: DotProfilerScripts = null
var _script_report := {}
var _census_start := {}
var _census := {}


func _ready() -> void:
	if config == null:
		config = DotProfilerConfig.new()
		var res := config.load_layered(config_file)
		if not res.ok:
			DotLog.warn(CHANNEL, "profiler settings: %s; using defaults" % res.error.message)
			config = DotProfilerConfig.new()
	config.changed.connect(_apply)
	if register_as_service:
		DotRegistry.register(SERVICE, self)
	set_process_input(InputMap.has_action(CAPTURE_ACTION))
	_apply()


func _exit_tree() -> void:
	_stop_watch()
	DotFrameCost.reset()
	if register_as_service:
		DotRegistry.unregister_instance(SERVICE, self)


## True while frames are being watched: enabled, overlay shown, or recording.
func is_watching() -> bool:
	return _hitch != null


func is_recording() -> bool:
	return _recording


## Seconds since the recording began, or 0.
func elapsed_s() -> float:
	return (Time.get_ticks_usec() - _rec_started_usec) / 1.0e6 if _recording else 0.0


## How long the current recording runs, or 0.
func recording_length_s() -> float:
	return _rec_seconds if _recording else 0.0


## The JSON path of the last recording written, or "".
func last_saved_path() -> String:
	return _last_saved


## Starts a recording of [param seconds] (the config's default when 0 or less); stops itself when done.
func start_recording(seconds: float = 0.0) -> DotResult:
	if _recording:
		return DotResult.fail(DotError.CODE_STATE, "A recording is already running (%.0f s in)." % elapsed_s())
	_rec_seconds = seconds if seconds > 0.0 else config.record_seconds
	_recording = true
	_rec_started_usec = Time.get_ticks_usec()
	_rec_frames = PackedFloat32Array()
	_rec_spikes = []
	_rec_systems = {}
	_rec_phases = {"physics": 0.0, "script": 0.0, "render": 0.0, "wait": 0.0}
	_rec_samples = []
	_next_sample_usec = 0
	_session = DotProfilerSession.new()
	_session.monitors = config.monitors
	_session.worst_keep = config.worst_frames
	_session.timeline = config.timeline
	_session.budget_ms = config.budget_ms
	_session.render_detail = config.render_detail
	_session.viewport = get_viewport().get_viewport_rid()
	_session.counters = _recording_counters()
	_session.begin()
	_census = {}
	_census_start = census() if config.census else {}
	_script_report = {}
	if config.script_top > 0:
		_scripts = DotProfilerScripts.new()
		var sr := _scripts.start()
		if not sr.ok:
			_scripts = null
			_script_report = {"ok": false, "reason": sr.error.message}
			DotLog.warn(CHANNEL, "script functions off: %s" % sr.error.message)
	if _ticks == null:
		_ticks = DotProfilerTicks.new()
		add_child(_ticks)
	var _t := _ticks.take()
	_deep = _start_deep(_rec_seconds)
	_apply()
	DotLog.info(CHANNEL, "recording %.0f s of frames (budget %.1f ms)" % [_rec_seconds, config.budget_ms])
	recording_started.emit(_rec_seconds)
	return DotResult.success(_rec_seconds)


## Ends the recording and writes it; the value is the JSON path.
func stop_recording() -> DotResult:
	if not _recording:
		return DotResult.fail(DotError.CODE_STATE, "No recording is running.")
	_recording = false
	if _scripts != null:
		_script_report = _scripts.stop(config.script_top, _rec_frames.size(),
			DotProfilerConfig.parse_buckets(config.script_buckets))
		_scripts = null
	if config.census and not _census_start.is_empty():
		_census = census_diff(_census_start, census())
	var report := build_report()
	var res := DotProfilerReport.write(report, config.record_dir, config.keep_recordings,
		_session.folded() if _session != null else "")
	if _ticks != null:
		_ticks.queue_free()
		_ticks = null
	_apply()
	if res.ok:
		_last_saved = res.value
		DotLog.info(CHANNEL, "profile saved to %s (%d frames, %d spikes, p99 %.1f ms)" % [
			_last_saved, report.frames, report.spike_count, report.p99_ms])
	else:
		DotLog.warn(CHANNEL, "profile not saved: %s" % res.error.message)
	recording_finished.emit(res)
	return res


## The report of the recording so far (or the last one), without writing it.
func build_report() -> Dictionary:
	var scene := get_tree().current_scene
	var meta := {
		"budget_ms": config.budget_ms, "seconds": _rec_seconds,
		"scene": scene.scene_file_path if scene != null else "",
		"period": DotProfilerPeriod.describe_found(_all_period.detect()),
		"sample_hz": config.sample_hz, "samples": _rec_samples, "deep": _deep}
	if _session != null:
		meta.merge(_session.to_report())
	if not _script_report.is_empty():
		meta["script_functions"] = _script_report
	if not _census.is_empty():
		meta["census"] = _census
	var report := DotProfilerReport.build(_rec_frames, _rec_spikes, _rec_systems, _rec_phases, meta)
	DotProfilerSession.attach_group_systems(report)
	return report


## Adds a count read every frame while recording, reported beside the cost of systems starting with
## [param prefix] (e.g. bots and "arena.bot"). [param count] returns an int; it replaces a group of that name.
func add_counter(group: String, count: Callable, prefix: String = "") -> void:
	remove_counter(group)
	_counters.append({"group": group, "prefix": prefix, "count": count})


func remove_counter(group: String) -> void:
	for i in range(_counters.size() - 1, -1, -1):
		if _counters[i].group == group:
			_counters.remove_at(i)


## Nodes in the tree by class (a script's class_name when it has one): {name: count}.
func census() -> Dictionary:
	var out := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key := n.get_class()
		var sc := n.get_script() as Script
		if sc != null and sc.get_global_name() != &"":
			key = String(sc.get_global_name())
		out[key] = int(out.get(key, 0)) + 1
		stack.append_array(n.get_children(true))
	return out


## Two [method census] results as {start_nodes, end_nodes, classes: [{class, start, end, delta}]}, biggest change first.
static func census_diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var rows: Array = []
	var total_a := 0
	var total_b := 0
	var names := a.keys()
	for k: Variant in b:
		if not a.has(k):
			names.append(k)
	for k: Variant in names:
		var x: int = a.get(k, 0)
		var y: int = b.get(k, 0)
		total_a += x
		total_b += y
		rows.append({"class": String(k), "start": x, "end": y, "delta": y - x})
	rows.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return absi(p.delta) > absi(q.delta) or (p.delta == q.delta and p.end > q.end))
	return {"start_nodes": total_a, "end_nodes": total_b, "classes": rows}


func _recording_counters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in DotProfilerConfig.parse_groups(config.groups):
		var made := false
		for c: Dictionary in _counters:
			if c.group == g.group:
				out.append({"group": c.group, "prefix": g.prefix if g.prefix != "" else String(c.prefix), "count": c.count})
				made = true
		if not made:
			out.append({"group": g.group, "prefix": g.prefix, "count": get_tree().get_node_count_in_group.bind(StringName(g.group))})
	for c: Dictionary in _counters:
		var listed := false
		for o: Dictionary in out:
			listed = listed or o.group == c.group
		if not listed:
			out.append(c)
	return out


## Starts a capture of profiler_capture_seconds, or stops the running recording and writes it: the one-key profile.
func toggle_capture() -> DotResult:
	return stop_recording() if _recording else start_recording(config.capture_seconds)


## Binds [param keycode] to [constant CAPTURE_ACTION] when the project has no binding, and listens for it.
func enable_capture_key(keycode: Key = KEY_F10) -> void:
	if not InputMap.has_action(CAPTURE_ACTION):
		InputMap.add_action(CAPTURE_ACTION)
	if InputMap.action_get_events(CAPTURE_ACTION).is_empty():
		var ev := InputEventKey.new()
		ev.keycode = keycode
		InputMap.action_add_event(CAPTURE_ACTION, ev)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(CAPTURE_ACTION, false, true):
		var res := toggle_capture()
		if not res.ok:
			DotLog.warn(CHANNEL, "capture: %s" % res.error.message)


## Compares two recordings (JSON paths); with none, the two newest. The value is the text lines.
func compare_recordings(path_a: String = "", path_b: String = "") -> DotResult:
	if path_a == "" or path_b == "":
		var recent := recent_recordings(2)
		if recent.size() < 2:
			return DotResult.fail(DotError.CODE_STATE, "Two recordings are needed to compare; %d found in %s." % [recent.size(), config.record_dir])
		path_a = recent[1].path
		path_b = recent[0].path
	var a := DotProfilerCompare.load_report(path_a)
	if not a.ok:
		return a
	var b := DotProfilerCompare.load_report(path_b)
	if not b.ok:
		return b
	return DotResult.success(DotProfilerCompare.to_text(DotProfilerCompare.compare(a.value, b.value),
		path_a.get_file(), path_b.get_file()))


func _start_deep(seconds: float) -> Dictionary:
	if not config.deep:
		return {}
	var dir := ProjectSettings.globalize_path(config.record_dir)
	var made := DotPaths.ensure_dir(config.record_dir)
	var file := dir.path_join("perf-%d.data" % Time.get_unix_time_from_system())
	var res := DotProfilerDeep.start(seconds, file) if made.ok else made
	if not res.ok:
		DotLog.warn(CHANNEL, "deep mode off: %s" % res.error.message)
		return {"ok": false, "reason": res.error.message}
	var info: Dictionary = res.value
	info["ok"] = true
	return info


## Recordings already written, newest first, at most [param n].
func recent_recordings(n: int = 8) -> Array[Dictionary]:
	return DotProfilerReport.list(config.record_dir).slice(0, n)


## The [param n] costliest systems, smoothed: [{system, ms}]; engine phases fill in when no system reports.
func top_costs(n: int = 6) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Variant in _avg_systems:
		out.append({"system": String(s), "ms": _avg_systems[s]})
	for p: String in _avg_phases:
		out.append({"system": "engine." + p, "ms": _avg_phases[p]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	return out.slice(0, n)


## Smoothed engine phases in ms: {physics, script, render, wait}; zero until watching.
func phase_ms() -> Dictionary:
	return _avg_phases.duplicate()


## Spikes seen per cause since start: {cause: {spikes, worst_ms, period}}.
func spikes_by_cause() -> Dictionary:
	var out := {}
	for c: String in _by_cause:
		out[c] = _by_cause[c].duplicate()
		out[c]["period"] = DotProfilerPeriod.describe_found(_periods[c].detect()) if _periods.has(c) else ""
	return out


## Smoothed frame time in ms, spikes seen, the last spike and the repeating beat, for the overlay.
func status() -> Dictionary:
	return {"ms": _avg_ms, "spikes": _spikes_seen, "last": _last_spike,
		"period": DotProfilerPeriod.describe_found(_all_period.detect()), "recording": _recording,
		"elapsed_s": elapsed_s(), "budget_ms": config.budget_ms}


## The beat spikes blamed on [param cause] repeat on ("" for all), or {}.
func period_of(cause: String = "") -> Dictionary:
	if cause == "":
		return _all_period.detect()
	var p: DotProfilerPeriod = _periods.get(cause)
	return p.detect() if p != null else {}


## Shows or hides the overlay; the same as setting profiler_overlay.
func set_overlay_visible(on: bool) -> void:
	var _r := config.set_text("overlay", "1" if on else "0")


## Registers profiler_* variables and the record, stop and report commands on a dot-console [code]DotConsoleLocal[/code].
func bind_console(local: Object) -> void:
	if local == null or not local.has_method(&"add_command"):
		return
	for key in config.config_keys():
		local.call(&"add_var", DotProfilerConfig.cvar_name(key), "Profiler: %s." % key,
			config.text_of.bind(key), _set_from_console.bind(key))
	var rec := func(args: PackedStringArray) -> Variant:
		return start_recording(args[0].to_float() if not args.is_empty() else 0.0)
	local.call(&"add_command", &"profiler_record", "Record frames for N seconds (default profiler_record_seconds) to user://.", rec)
	local.call(&"add_command", &"record", "Same as profiler_record.", rec)
	local.call(&"add_command", &"profiler_stop", "Stop the recording and write the report.",
		func(_a: PackedStringArray) -> Variant: return stop_recording())
	local.call(&"add_command", &"profiler_report", "The top costs and the spike beat now.",
		func(_a: PackedStringArray) -> Variant: return describe_lines())
	local.call(&"add_command", &"profiler_capture", "Start a capture of profiler_capture_seconds, or stop and write it.",
		func(_a: PackedStringArray) -> Variant: return toggle_capture())
	local.call(&"add_command", &"profiler_compare", "Compare two recordings (JSON paths; default the two newest), ms per frame.",
		func(a: PackedStringArray) -> Variant: return compare_recordings(a[0] if a.size() > 1 else "", a[1] if a.size() > 1 else ""))


## The panel the settings menu shows: overlay toggle, record and stop, the saved path and recent recordings.
## [param kit] is dot-menu's DotMenuKit, used by duck typing; null builds plain controls.
func make_menu_panel(kit: Object = null) -> Control:
	var panel := DotProfilerPanel.new()
	panel.setup(self, kit)
	return panel


func describe() -> String:
	return "DotProfiler watching=%s recording=%s spikes=%d %s" % [is_watching(), _recording, _spikes_seen,
		DotProfilerPeriod.describe_found(_all_period.detect())]


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray([describe()])
	out.append("  frame %.1f ms (budget %.1f)" % [_avg_ms, config.budget_ms])
	for row in top_costs(config.overlay_top):
		out.append("  %-28s %.2f ms" % [row.system, row.ms])
	if not _last_spike.is_empty():
		out.append("  last spike: " + DotProfilerReport.spike_line(_last_spike))
	return out


## Attributes one [DotHitchLog] hitch record: the system that took at least [constant CAUSE_SHARE] of it,
## else "engine.<phase>", plus hints read from its counter deltas, marks and new nodes.
static func attribute(rec: Dictionary) -> Dictionary:
	var ms: float = rec.get("ms", 0.0)
	var systems: Dictionary = rec.get("systems", {})
	var cause := ""
	var what := ""
	var top_ms := 0.0
	for s: Variant in systems:
		var v: float = systems[s].get("ms", 0.0)
		if v > top_ms:
			top_ms = v
			cause = String(s)
			what = systems[s].get("what", "")
	if cause == "" or top_ms < ms * CAUSE_SHARE:
		var phase := "script"
		for p: String in ["physics", "script", "render", "wait"]:
			if float(rec.get(p, 0.0)) > float(rec.get(phase, 0.0)):
				phase = p
		cause = "engine." + phase
		what = ""
	var hints: Array[String] = []
	var d: Dictionary = rec.get("deltas", {})
	if int(d.get("compile", 0)) > 0:
		hints.append("%d shader compile(s)" % d.compile)
	if int(d.get("added", 0)) > 0:
		hints.append("+%d nodes" % d.added)
	if int(d.get("res", 0)) > 0:
		hints.append("+%d resources" % d.res)
	if int(d.get("kb", 0)) > 512:
		hints.append("+%d KB static memory" % d.kb)
	if int(d.get("logs", 0)) > 0:
		hints.append("%d log line(s)" % d.logs)
	var added: Array = rec.get("added", [])
	if not added.is_empty():
		hints.append("new=" + ", ".join(added.slice(0, 3)))
	var marks: Array = rec.get("marks", [])
	if not marks.is_empty():
		hints.append("marks=" + ", ".join(marks.slice(0, 3)))
	var out := {"t": rec.get("t", 0.0), "ms": ms, "cause": cause, "what": what, "hints": hints, "period": ""}
	for p: String in ["physics", "script", "render", "wait"]:
		out[p] = rec.get(p, 0.0)
	var sys_ms := {}
	for s: Variant in systems:
		sys_ms[String(s)] = systems[s].get("ms", 0.0)
	out["systems"] = sys_ms
	return out


func _set_from_console(text: Variant, key: String) -> Variant:
	return config.set_text(key, str(text))


func _apply() -> void:
	var want := config.enabled or config.overlay or _recording
	if want and _hitch == null:
		_hitch = DotHitchLog.new()
		_hitch.keep = 64
		_hitch.frame_measured.connect(_on_frame)
		_hitch.start(get_tree())
		DotLog.debug(CHANNEL, "watching frames, budget %.1f ms" % config.budget_ms)
	elif not want and _hitch != null:
		_stop_watch()
	if _hitch != null:
		_hitch.threshold_ms = config.budget_ms
	DotFrameCost.enabled = want
	DotFrameCost.trace = want and _recording and config.trace
	for c: Variant in _periods:
		_periods[c].tolerance = config.period_tolerance
		_periods[c].min_spikes = config.period_min_spikes
	_all_period.tolerance = config.period_tolerance
	_all_period.min_spikes = config.period_min_spikes
	if _graph_data.capacity != config.graph_frames:
		_graph_data.resize(config.graph_frames)
	_show_overlay(config.overlay)
	if _overlay != null:
		_overlay.call(&"apply_graph")


## The per-frame stacked costs the overlay graph draws.
func graph_data() -> DotProfilerGraphData:
	return _graph_data


func _stop_watch() -> void:
	if _hitch != null:
		_hitch.stop()
		_hitch = null
	DotFrameCost.enabled = false
	DotFrameCost.trace = false


func _show_overlay(on: bool) -> void:
	if on and _overlay == null:
		_overlay = DotProfilerOverlay.new()
		_overlay.profiler = self
		add_child(_overlay)
	elif not on and _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _on_frame(rec: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var ms: float = rec.get("ms", 0.0)
	if config.overlay and config.graph:
		_graph_data.push_record(rec)
	var k := 0.1
	_avg_ms = lerpf(_avg_ms, ms, k)
	for p: String in _avg_phases:
		_avg_phases[p] = lerpf(_avg_phases[p], float(rec.get(p, 0.0)), k)
	var systems: Dictionary = rec.get("systems", {})
	for s: Variant in _avg_systems.keys():
		if not systems.has(s):
			_avg_systems[s] = _avg_systems[s] * (1.0 - k)
			if _avg_systems[s] < 0.005:
				_avg_systems.erase(s)
	for s: Variant in systems:
		_avg_systems[s] = lerpf(_avg_systems.get(s, 0.0), float(systems[s].ms), k)
	if _recording:
		_rec_frames.append(ms)
		for p: String in _rec_phases:
			_rec_phases[p] += float(rec.get(p, 0.0))
		for s: Variant in systems:
			var row: Dictionary = _rec_systems.get(s, {"ms": 0.0, "calls": 0, "worst_ms": 0.0, "what": ""})
			var r: Dictionary = systems[s]
			row.ms += float(r.ms)
			row.calls += int(r.calls)
			if float(r.worst_ms) >= float(row.worst_ms):
				row.worst_ms = r.worst_ms
				if String(r.get("what", "")) != "":
					row.what = r.what
			_rec_systems[s] = row
	if _recording and config.sample_hz > 0.0 and sampler.is_valid() and Time.get_ticks_usec() >= _next_sample_usec:
		_next_sample_usec = Time.get_ticks_usec() + int(1.0e6 / config.sample_hz)
		var row: Variant = sampler.call()
		if row is Dictionary:
			(row as Dictionary)["t"] = snappedf(elapsed_s(), 0.001)
			_rec_samples.append(row)
	if ms >= config.budget_ms:
		_on_spike(rec)
	if _recording and _session != null:
		_session.add(rec, _ticks.take() if _ticks != null else PackedInt64Array())
		_session.add_overhead(Time.get_ticks_usec() - t0)
	if _recording and not _stop_pending and elapsed_s() >= _rec_seconds:
		# Deferred: stopping disconnects the hitch log that is emitting this.
		_stop_pending = true
		_finish_recording.call_deferred()


func _finish_recording() -> void:
	_stop_pending = false
	if _recording:
		var _r := stop_recording()


func _on_spike(rec: Dictionary) -> void:
	var info := attribute(rec)
	var cause: String = info.cause
	_spikes_seen += 1
	_all_period.add(info.t)
	if not _periods.has(cause):
		var p := DotProfilerPeriod.new()
		p.tolerance = config.period_tolerance
		p.min_spikes = config.period_min_spikes
		_periods[cause] = p
	_periods[cause].add(info.t)
	info.period = DotProfilerPeriod.describe_found(_periods[cause].detect())
	_last_spike = info
	var tally: Dictionary = _by_cause.get(cause, {"spikes": 0, "worst_ms": 0.0})
	tally.spikes += 1
	tally.worst_ms = maxf(tally.worst_ms, info.ms)
	_by_cause[cause] = tally
	if _recording:
		_rec_spikes.append(info)
	spike.emit(info)
	if not config.enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_warn.get(cause, -1.0e9)) < config.warn_every_s:
		_suppressed[cause] = int(_suppressed.get(cause, 0)) + 1
		return
	var skipped: int = _suppressed.get(cause, 0)
	_last_warn[cause] = now
	_suppressed[cause] = 0
	DotLog.warn(CHANNEL, "frame %.1f ms over %.1f ms budget: %s%s" % [info.ms, config.budget_ms,
		DotProfilerReport.spike_line(info), (" (+%d more since last)" % skipped) if skipped > 0 else ""],
		{"cause": cause, "ms": info.ms, "period": info.period})
