extends Node

## The opt-in detail options: config parsing, the timeline's flagged frames, growth, groups and cost per unit,
## the script function table, the node census, the noise-floor diff, and a live recording with them all on
## next to one with them off (the default report gains only growth).

const SECTIONS := 6
const CHECKS := 32
const DIR := "user://profiler_detail_selftest"
const SCRIPT_TABLE := """ACCUMULATED: total: 0.191661
0:res://bots/brain.gd::21::think
	total: 0.136697/71 % 	self: 0.100000/52 % tcalls: 600
1:res://bots/los.gd::13::can_see
	total: 0.054647/28 % 	self: 0.054647/28 % tcalls: 3000
2:res://player/motor.gd::26::move
	total: 0.003000/1 % 	self: 0.002000/1 % tcalls: 30
"""

var _sections := 0
var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_config()
	_timeline()
	_groups_and_growth()
	_scripts()
	_compare()
	await _live()
	var _c := DotPaths.remove_tree(DIR)
	print("profiler_detail_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	var ok := _failed == 0 and _sections == SECTIONS and _checks == CHECKS
	get_tree().quit(0 if ok else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _config() -> void:
	var c := DotProfilerConfig.new()
	_check(not c.timeline and not c.render_detail and c.groups == "" and not c.census and c.script_top == 0, "every detail option is off by default")
	var g := DotProfilerConfig.parse_groups("bots:arena.bot, players:arena.p_,props")
	_check(g.size() == 3 and g[0].group == "bots" and g[0].prefix == "arena.bot" and g[2].prefix == "", "groups parse as name and system prefix")
	var b := DotProfilerConfig.parse_buckets("motor=motor|move,weapons=weapon")
	_check(b.size() == 2 and (b[0].match as PackedStringArray).size() == 2 and b[1].name == "weapons", "script buckets parse as name and parts")
	_check(c.set_text("script_top", "40").ok and c.script_top == 40, "script_top is set from console text")
	_check(not c.set_text("script_top", "900").ok and c.script_top == 40, "an out-of-range script_top is refused and put back")
	_check(not c.set_text("script_buckets", "=x").ok and not c.set_text("groups", ":arena.bot").ok, "a bucket or group without a name is refused")
	_sections += 1


func _rec(i: int, ms: float, systems: Dictionary = {}) -> Dictionary:
	var start := 1000000 + i * 50000
	return {"t": i * 0.05, "ms": ms, "physics": 0.0, "script": ms, "render": 0.0, "wait": 0.0, "systems": systems,
		"queries": {}, "events": {}, "usec": PackedInt64Array([start, 0, 0, 0, start + int(ms * 1000.0)])}


func _timeline() -> void:
	var s := DotProfilerSession.new()
	s.monitors = false
	s.timeline = true
	s.budget_ms = 33.0
	s.begin()
	for i in 30:
		s.add(_rec(i, 10.0), PackedInt64Array())
	s.add(_rec(30, 25.0, {&"bots": {"ms": 14.0}}), PackedInt64Array())
	s.add(_rec(31, 11.0), PackedInt64Array())
	for i in range(32, 40):
		s.add(_rec(i, 40.0 if i == 35 else 10.0), PackedInt64Array())
	var tl: Dictionary = s.to_report().timeline
	var flagged: Array = tl.flagged
	_check(flagged.size() == 2 and is_equal_approx(flagged[0].ms, 25.0) and is_equal_approx(flagged[1].ms, 40.0),
		"a jump over twice the running average and a frame over budget are flagged, in time order")
	_check(flagged[0].systems[0].system == "bots" and is_equal_approx(flagged[0].systems[0].ms, 14.0), "a flagged frame names the systems that ran in it")
	_check((tl.frame_ms as Array).size() == 40 and (tl.seconds as Array).size() == 2 and int(tl.seconds[0].frames) == 20, "every frame time is kept and grouped per second")
	_check(int(tl.seconds[0].flagged) == 0 and int(tl.seconds[1].flagged) == 2, "each second counts its flagged frames")
	var plain := DotProfilerSession.new()
	plain.monitors = false
	plain.begin()
	plain.add(_rec(0, 10.0), PackedInt64Array())
	var pr := plain.to_report()
	_check(not pr.has("timeline") and not pr.has("groups"), "with the options off the session adds no timeline or groups")
	_sections += 1


func _groups_and_growth() -> void:
	var s := DotProfilerSession.new()
	var n := [16]
	var counters: Array[Dictionary] = [{"group": "bots", "prefix": "arena.bot", "count": func() -> int: return n[0]}]
	s.counters = counters
	s.begin()
	for i in 10:
		n[0] = 16 if i < 5 else 32
		s.add(_rec(i, 10.0), PackedInt64Array())
	var r := s.to_report()
	r["frames"] = 10
	r["systems"] = [{"system": "arena.bot_brain", "ms": 24.0, "calls": 240, "ms_per_frame": 2.4},
		{"system": "arena.p_motor", "ms": 5.0, "calls": 10, "ms_per_frame": 0.5}]
	DotProfilerSession.attach_group_systems(r)
	var g: Dictionary = r.groups[0]
	_check(is_equal_approx(g.count.avg, 24.0) and is_equal_approx(g.count.max, 32.0), "a counter is read every frame")
	_check((g.systems as Array).size() == 1 and is_equal_approx(g.systems[0].us_per_unit, 100.0) and is_equal_approx(g.systems[0].calls_per_frame, 24.0),
		"systems under the prefix get their cost per unit")
	_check((r.growth as Dictionary).has("nodes") and is_equal_approx(r.growth.nodes.delta, float(r.growth.nodes.last) - float(r.growth.nodes.first)),
		"growth gives first, last and the change of the node count")
	var diff := DotProfiler.census_diff({"Node3D": 10, "Bot": 16}, {"Node3D": 10, "Bot": 32, "Shot": 5})
	_check(diff.start_nodes == 26 and diff.end_nodes == 47 and diff.classes[0]["class"] == "Bot" and diff.classes[0].delta == 16, "the census diff lists the biggest change first")
	_check(diff.classes[1]["class"] == "Shot" and diff.classes[1].start == 0, "a class only at the end starts at 0")
	_sections += 1


func _scripts() -> void:
	var rows := DotProfilerScripts.parse(SCRIPT_TABLE.split("\n"))
	_check(rows.size() == 3 and rows[0].script == "res://bots/brain.gd" and rows[0].line == 21 and rows[0].function == "think", "a table row gives script, line and function")
	_check(is_equal_approx(rows[1].self_ms, 54.647) and rows[1].calls == 3000 and is_equal_approx(rows[0].total_ms, 136.697), "seconds become ms and tcalls the call count")
	var buckets := DotProfilerConfig.parse_buckets("bots=bots/,motor=motor")
	var sum := DotProfilerScripts.summarize(rows, 2, 100, buckets)
	_check((sum.functions as Array).size() == 2 and sum.functions[0].function == "think" and is_equal_approx(sum.functions[0].self_ms, 1.0),
		"the top functions by self time, ms per frame")
	_check(is_equal_approx(sum.functions[1].us_per_call, 18.2157) and is_equal_approx(sum.functions[1].calls_per_frame, 30.0), "us per call and calls per frame")
	var by := {}
	for b: Dictionary in sum.buckets:
		by[b.bucket] = b
	_check(is_equal_approx(by.bots.self_ms, 1.54647) and int(by.bots.functions) == 2 and is_equal_approx(by.motor.self_ms, 0.02)
		and int(by.other.functions) == 0, "buckets sum the functions whose script matches")
	var res := DotProfilerScripts.new().start()
	_check(EngineDebugger.is_active() or (not res.ok and res.error.message.contains("-d")), "without -d the script profiler says how to turn it on")
	_sections += 1


func _compare() -> void:
	var a := {"frames": 10, "p50_ms": 10.0, "phases": {}, "systems": [{"system": "bots", "ms_per_frame": 2.0},
		{"system": "hud", "ms_per_frame": 1.0}], "monitors": {"draw_calls": {"avg": 1000.0}},
		"groups": [{"group": "bots", "count": {"avg": 32.0}, "systems": [{"system": "arena.bot_brain", "us_per_unit": 50.0}]}],
		"script_functions": {"functions": [{"function": "think", "script": "res://brain.gd", "line": 3, "self_ms": 1.0}]}}
	var b := {"frames": 10, "p50_ms": 10.2, "phases": {}, "systems": [{"system": "bots", "ms_per_frame": 2.5},
		{"system": "hud", "ms_per_frame": 1.02}], "monitors": {"draw_calls": {"avg": 1200.0}},
		"groups": [{"group": "bots", "count": {"avg": 32.0}, "systems": [{"system": "arena.bot_brain", "us_per_unit": 60.0}]}],
		"script_functions": {"functions": [{"function": "think", "script": "res://brain.gd", "line": 3, "self_ms": 1.3}]}}
	var rows := DotProfilerCompare.compare(a, b)
	_check(rows.any(func(x: Dictionary) -> bool: return x.section == "group" and String(x.name).contains("us/unit") and is_equal_approx(x.delta, 10.0)),
		"groups compare their cost per unit")
	_check(rows.any(func(x: Dictionary) -> bool: return x.section == "script" and x.name == "think brain.gd:3")
		and rows.any(func(x: Dictionary) -> bool: return x.section == "monitor" and is_equal_approx(x.delta, 200.0)), "script functions and monitors compare")
	var moved := DotProfilerCompare.changed(rows)
	var names := moved.map(func(x: Dictionary) -> String: return "%s %s" % [x.section, x.name])
	_check(names.has("system bots") and not names.has("system hud") and not names.has("frame p50") and not names.has("group bots count"),
		"the diff keeps changes over the 5% noise floor and drops the rest")
	_check(DotProfilerCompare.changed(rows, 50.0).is_empty(), "a wider floor drops them all")
	_sections += 1


func _live() -> void:
	var dummy := Node3D.new()
	dummy.add_to_group(&"selftest_units")
	add_child(dummy)
	var prof := DotProfiler.new()
	prof.register_as_service = false
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR
	prof.config.sample_hz = 0.0
	add_child(prof)
	var base := await _record(prof)
	_check(base.has("growth") and not base.has("timeline") and not base.has("groups") and not base.has("census")
		and not base.has("script_functions") and not (base.monitors as Dictionary).has("texture_mb"), "the default report gains only growth")
	prof.config.timeline = true
	prof.config.render_detail = true
	prof.config.census = true
	prof.config.script_top = 10
	prof.config.groups = "selftest_units,made:selftest."
	prof.add_counter("made", func() -> int: return 7)
	var r := await _record(prof)
	_check((r.timeline.frame_ms as Array).size() == int(r.frames) and (r.monitors as Dictionary).has("texture_mb")
		and (r.monitors as Dictionary).has("draws_visible"), "timeline and render detail are recorded")
	var g: Array = r.groups
	_check(g.size() == 2 and is_equal_approx(g[0].count.avg, 1.0) and g[1].group == "made" and is_equal_approx(g[1].count.avg, 7.0),
		"a SceneTree group and a game counter are counted")
	_check(int(r.census.end_nodes) > 0 and (r.census.classes as Array).size() > 0, "the census counts nodes by class")
	_check((r.script_functions as Dictionary).has("ok"), "script functions report a table or why not")
	var text := "\n".join(DotProfilerReport.to_text(r))
	_check(text.contains("Timeline (per second") and text.contains("Groups (count") and text.contains("Growth over")
		and text.contains("Node census") and text.contains("Script functions") and text.contains(" p50 "), "the text has the new sections")
	prof.queue_free()
	dummy.queue_free()
	await get_tree().process_frame
	_sections += 1


func _record(prof: DotProfiler) -> Dictionary:
	var _s := prof.start_recording(0.3)
	var res: DotResult = await prof.recording_finished
	if not res.ok:
		return {}
	return DotPaths.read_json(res.value).value
