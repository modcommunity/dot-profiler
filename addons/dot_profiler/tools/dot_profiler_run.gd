extends Node

## Headless runner: loads a scene, warms up, records it and prints a `PERF {json}` line and a
## `PROFILER {json}` line naming spike causes. Flags: --profile-scene, -warmup, -seconds, -budget;
## the rest pass through. Exit 0 once the report is written, 1 when it is not, 2 on bad arguments.

const CHANNEL := "dot.profiler"

var _scene := ""
var _warmup := 5.0
var _seconds := 20.0
var _budget := 33.0
var _out := "user://profiles"
var _quit := true
var _prof: DotProfiler = null
var _load_s := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--profile-scene": _scene = args[i + 1]
			"--profile-warmup": _warmup = args[i + 1].to_float()
			"--profile-seconds": _seconds = args[i + 1].to_float()
			"--profile-budget": _budget = args[i + 1].to_float()
			"--profile-out": _out = args[i + 1]
	_quit = not ("--profile-stay" in args)
	if _scene == "" or not ResourceLoader.exists(_scene):
		printerr("dot_profiler_run: --profile-scene res://... is required and must exist (got '%s')" % _scene)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_prof = DotProfiler.new()
	_prof.config = DotProfilerConfig.new()
	_prof.config.budget_ms = _budget
	_prof.config.record_dir = _out
	_prof.config.keep_recordings = 200
	get_tree().root.add_child(_prof)
	var t0 := Time.get_ticks_usec()
	var packed := load(_scene) as PackedScene
	if packed == null:
		printerr("dot_profiler_run: %s is not a scene" % _scene)
		get_tree().quit(2)
		return
	var inst := packed.instantiate()
	# Added beside this runner rather than through change_scene, which would free the runner with it.
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	_load_s = (Time.get_ticks_usec() - t0) / 1.0e6
	DotLog.info(CHANNEL, "runner: %s loaded in %.2f s, warming up %.0f s" % [_scene, _load_s, _warmup])
	await get_tree().create_timer(_warmup, true, false, true).timeout
	var started := _prof.start_recording(_seconds)
	if not started.ok:
		printerr("dot_profiler_run: ", started.error.message)
		get_tree().quit(1)
		return
	var res: DotResult = await _prof.recording_finished
	if not res.ok:
		printerr("dot_profiler_run: report not written: ", res.error.message)
		get_tree().quit(1)
		return
	var r: Dictionary = (DotPaths.read_json(res.value) as DotResult).value
	print("PERF " + JSON.stringify(perf_line(r, _load_s)))
	print("PROFILER " + JSON.stringify({"report": ProjectSettings.globalize_path(res.value), "scene": _scene,
		"budget_ms": _budget, "spikes": r.get("spike_count", 0), "causes": r.get("causes", {}),
		"systems": (r.get("systems", []) as Array).slice(0, 8)}))
	for line in DotProfilerReport.to_text(r, 10):
		print(line)
	if _quit:
		get_tree().quit(0)


## The perf budget's numbers from a report: p50/p95/p99, the worst frame as stall_ms, load time, memory and device.
static func perf_line(r: Dictionary, load_s: float) -> Dictionary:
	return {"p50_ms": r.get("p50_ms", 0.0), "p95_ms": r.get("p95_ms", 0.0), "p99_ms": r.get("p99_ms", 0.0),
		"stall_ms": r.get("worst_ms", 0.0), "spikes": r.get("spike_count", 0), "frames": r.get("frames", 0),
		"load_s": load_s, "rss_mb": rss_mb(), "gpu": RenderingServer.get_video_adapter_name(),
		"resolution": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "source": "dot-profiler"}


## Resident memory in MB where the OS reports it, else Godot's own static memory.
static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		for line in f.get_as_text().split("\n"):
			if line.begins_with("VmRSS:"):
				return line.split(":")[1].strip_edges().split(" ")[0].to_float() / 1024.0
	return OS.get_static_memory_usage() / 1048576.0
