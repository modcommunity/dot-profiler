extends Node

## The report's context: machine header, game context and recording hooks (extras), dropped ticks, the breakdown
## line, the capture key's render detail, the reference diff, and compare with one path.

const DIR := "user://profiler_context_selftest"
const CHECKS := 18

var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	var m := DotProfilerContext.machine()
	for k in ["os", "cpu", "gpu", "driver", "renderer", "godot", "tick_rate", "window", "vsync"]:
		_check(m.has(k), "machine has %s" % k)
	var prof := DotProfiler.new()
	prof.register_as_service = false
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR
	prof.config.sample_hz = 0.0
	add_child(prof)
	var began := [0]
	prof.add_context("build", func() -> Dictionary: return {"commit": "abc123", "natives": false})
	prof.add_recording_hook("native", func() -> void: began[0] += 1, func() -> Dictionary: return {"tick_us": 12.5})
	prof.add_recording_hook("empty", func() -> void: pass, func() -> Dictionary: return {})
	var r := await _record(prof, false)
	_check(r.context.machine.has("os") and r.context.build.commit == "abc123", "context holds the machine and the game's keys")
	_check(began[0] == 1 and r.extras.native.tick_us == 12.5 and not r.extras.has("empty"), "hooks run once and report; an empty one is left out")
	var t: Dictionary = r.physics_ticks
	_check(t.has("ticks_per_sec") and t.has("dropped_ticks") and t.has("wall_s"), "ticks report the rate and dropped ticks")
	var text := "\n".join(DotProfilerReport.to_text(r))
	_check(text.contains("Machine:") and text.contains("Build: commit=abc123") and text.contains("Per frame:") and text.contains("unaccounted")
		and text.contains("native: tick_us=12.5") and text.contains("dropped"), "the text shows context, breakdown, extras and dropped ticks")
	_check(not (r.monitors as Dictionary).has("render_gpu_ms"), "a plain recording leaves render cpu/gpu out")
	_check(FileAccess.file_exists(prof.last_saved_path()), "the report file exists")
	prof.config.reference = prof.last_saved_path()
	var cap := await _record(prof, true)
	_check((cap.monitors as Dictionary).has("render_gpu_ms"), "a capture records render cpu/gpu")
	_check(FileAccess.file_exists(prof.last_saved_path().get_basename() + ".diff.txt"), "a reference writes a diff beside the report")
	prof.config.reference = ""
	var c := prof.compare_recordings(prof.recent_recordings(2)[1].path)
	_check(c.ok, "compare with one path uses the newest as the other")
	prof.queue_free()
	await get_tree().process_frame
	var _c2 := DotPaths.remove_tree(DIR)
	print("profiler_context_selftest: %d checks (want %d), %d failed" % [_checks, CHECKS, _failed])
	get_tree().quit(0 if _failed == 0 and _checks == CHECKS else 1)


func _record(prof: DotProfiler, capture: bool) -> Dictionary:
	prof.config.capture_seconds = 0.3
	var _s := prof.toggle_capture() if capture else prof.start_recording(0.3)
	var res: DotResult = await prof.recording_finished
	if not res.ok:
		return {}
	return DotPaths.read_json(res.value).value


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
