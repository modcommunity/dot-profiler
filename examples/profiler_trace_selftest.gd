extends Node

## The call tree, physics ticks, monitors, queries, worst frames, folded export, compare and capture key:
## a tree built from a hand-made frame, then a live recording of a physics script that casts rays.

const SECTIONS := 3
const CHECKS := 29
const DIR := "user://profiler_trace_selftest"

var _sections := 0
var _checks := 0
var _failed := 0


class Caster:
	extends Node3D

	func _physics_process(_delta: float) -> void:
		var t := DotFrameCost.now()
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 0, 0), Vector3(0, 0, -10))
		for i in 3:
			var _hit := DotSpaceQuery.ray(get_world_3d().direct_space_state, q, &"selftest.caster")
		DotFrameCost.add(&"selftest.caster", t, "3 rays")


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_tree()
	await _live()
	_compare()
	var _c := DotPaths.remove_tree(DIR)
	print("profiler_trace_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	var ok := _failed == 0 and _sections == SECTIONS and _checks == CHECKS
	get_tree().quit(0 if ok else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _row(rows: Array, path: String) -> Dictionary:
	for r: Dictionary in rows:
		if r.path == path:
			return r
	return {}


func _tree() -> void:
	var t := DotProfilerTree.new()
	# process 1000-3000, render 3000-4000, wait to the first tick at 5000; ticks 5000 and 7500, scripts end 7000 and 9000.
	var events := PackedInt64Array([1500, 2000, 0, 5200, 5300, 1, 5400, 5450, 2, 5100, 5600, 0])
	var rec := {"usec": PackedInt64Array([1000, 5000, 3000, 4000, 10000]),
		"events": {"events": events, "names": [&"bots", &"bot_los", &"q.intersect_ray"]}}
	var flat := t.add_frame(rec, PackedInt64Array([5000, 7000, 7500, 9000]))
	var rows := t.rows()
	_check(t.frames == 1 and not flat.is_empty() and rows[0].path == "frame" and is_equal_approx(rows[0].ms, 9.0), "the frame root covers the window")
	var bots := _row(rows, "frame;physics;scripts;bots")
	_check(is_equal_approx(bots.get("ms", 0.0), 0.5) and is_equal_approx(bots.get("self_ms", 0.0), 0.35), "inclusive and exclusive ms of a nested span")
	_check(_row(rows, "frame;physics;scripts;bots;bot_los").get("calls", 0.0) == 1.0, "a child span nests under its parent")
	_check(is_equal_approx(_row(rows, "frame;process;bots").get("ms", 0.0), 0.5), "a span in the process phase lands under process")
	var scripts := _row(rows, "frame;physics;scripts")
	_check(is_equal_approx(scripts.get("ms", 0.0), 3.5) and scripts.get("calls", 0.0) == 2.0, "two ticks of scripts")
	_check(is_equal_approx(_row(rows, "frame;physics;step").get("ms", 0.0), 1.5), "the engine step is what follows the scripts")
	_check(is_equal_approx(_row(rows, "frame;wait").get("ms", 0.0), 1.0) and is_equal_approx(_row(rows, "frame;render").get("ms", 0.0), 1.0),
		"render and wait come from the draw stamps")
	_check(t.folded().contains("frame;physics;scripts;bots 350\n"), "folded stacks carry exclusive microseconds")
	var tq := t.traced_queries()
	_check(tq.has("bots") and int(tq.bots.intersect_ray.calls) == 1, "a traced query is charged to the span it ran in")
	var _f := t.add_frame({"usec": PackedInt64Array([10000, 0, 0, 0, 20000])}, PackedInt64Array())
	_check(t.frames == 2 and is_equal_approx(t.percentile(0, 1.0), 10.0) and _row(t.rows(), "frame;physics").get("frames", 0) == 1,
		"a frame with no ticks and no trace still counts")
	_sections += 1


func _live() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, 0, -5)
	add_child(floor_body)
	var caster := Caster.new()
	add_child(caster)
	var prof := DotProfiler.new()
	prof.register_as_service = false
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR
	prof.config.capture_seconds = 0.6
	prof.config.sample_hz = 0.0
	add_child(prof)
	prof.enable_capture_key()
	_check(InputMap.has_action(DotProfiler.CAPTURE_ACTION) and prof.is_processing_input(), "the capture key is bound")
	var press := InputEventAction.new()
	press.action = DotProfiler.CAPTURE_ACTION
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(prof.is_recording() and DotFrameCost.trace, "the key starts a capture with tracing on")
	var res: DotResult = await prof.recording_finished
	_check(res.ok and not prof.is_recording() and not DotFrameCost.trace, "the capture stops itself and turns tracing off")
	var r: Dictionary = DotPaths.read_json(res.value).value
	_check(int(r.version) == 2 and (r.frame_stats as Dictionary).has("frame"), "a version 2 report with frame statistics")
	var path := "frame;physics;scripts;selftest.caster;q.intersect_ray"
	_check(not _row(r.tree, path).is_empty(), "queries nest under the system that ran them, under the physics scripts")
	var q: Array = (r.queries as Array).filter(func(x: Dictionary) -> bool: return x.system == "selftest.caster")
	_check(q.size() == 1 and q[0].kind == "intersect_ray" and is_equal_approx(q[0].calls_per_tick, 3.0), "three rays per tick, counted by kind")
	_check(int(r.physics_ticks.ticks) > 0 and (r.physics_ticks.histogram as Dictionary).size() > 0, "physics ticks per frame are counted")
	_check((r.monitors as Dictionary).has("physics_3d_pairs") and (r.monitors as Dictionary).has("draw_calls"), "engine monitors are read")
	_check((r.worst_frames as Array).size() > 0 and not ((r.worst_frames[0].tree) as Array).is_empty(), "the worst frames keep their tree")
	_check(float(r.overhead.on_frame_avg_ms) > 0.0 and float(r.overhead.spans_per_frame) > 0.0, "the profiler measures its own cost")
	_check(FileAccess.file_exists(String(res.value).get_basename() + ".folded"), "a .folded file sits next to the report")
	var text := FileAccess.get_file_as_string(String(res.value).get_basename() + ".txt")
	_check(text.contains("Call tree") and text.contains("Physics ticks:") and text.contains("Systems (reported"), "the text keeps the old sections and adds the new")
	var _s := prof.toggle_capture()
	_check(prof.is_recording(), "the toggle starts a capture")
	var stopped := prof.toggle_capture()
	_check(stopped.ok and not prof.is_recording(), "and the second toggle stops and writes it")
	var cmp := prof.compare_recordings()
	_check(cmp.ok and "\n".join(cmp.value).contains("tree:"), "the two newest recordings compare")
	prof.queue_free()
	caster.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	_sections += 1


func _compare() -> void:
	var a := {"frames": 10, "p50_ms": 10.0, "phases": {"physics": 50.0},
		"systems": [{"system": "bots", "ms": 20.0, "ms_per_frame": 2.0}], "tree": [{"path": "frame", "ms": 10.0}]}
	var b := {"frames": 10, "p50_ms": 12.0, "phases": {"physics": 80.0},
		"systems": [{"system": "bots", "ms": 50.0, "ms_per_frame": 5.0}, {"system": "new", "ms": 10.0, "ms_per_frame": 1.0}],
		"tree": [{"path": "frame", "ms": 12.0}]}
	var rows := DotProfilerCompare.compare(a, b)
	var sys := rows.filter(func(x: Dictionary) -> bool: return x.section == "system")
	_check(sys.size() == 2 and sys[0].name == "bots" and is_equal_approx(sys[0].delta, 3.0), "systems sorted by the size of the change")
	_check(sys[1].name == "new" and is_equal_approx(sys[1].a, 0.0), "a system only in B compares against 0")
	var ph := rows.filter(func(x: Dictionary) -> bool: return x.section == "phase" and x.name == "physics")
	_check(is_equal_approx(ph[0].delta, 3.0), "phases compare per frame")
	_check("\n".join(DotProfilerCompare.to_text(rows)).contains("+3.00"), "the text shows the signed delta")
	_sections += 1
