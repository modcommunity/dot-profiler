extends Node

## dot-profiler's suite: period detection, attribution, config, a live run with a system that spikes on a beat,
## the console commands, the menu panel's Record then Stop writing a file, and sv_profiler_* on a real dot-server console. Exits non-zero on any failure.

const SECTIONS := 7
const CHECKS := 63
const DIR := "user://profiler_selftest"

var _checks := 0
var _failed := 0
var _sections := 0
var _beat_s := 0.4
var _next_beat := 0.0
var _busy := false


class FakeConsole:
	extends RefCounted
	var commands := {}
	var vars := {}

	func add_command(n: StringName, _help: String, fn: Callable) -> void:
		commands[String(n)] = fn

	func add_var(n: StringName, _help: String, get_fn: Callable, set_fn: Callable) -> void:
		vars[String(n)] = [get_fn, set_fn]


class FakeServerConfig:
	extends RefCounted
	var log_directory := "user://logs"


class FakeServer:
	extends Node
	var config := FakeServerConfig.new()
	var query_source := FakeQuery.new()

	func player_count() -> int:
		return 3


class FakeQuery:
	extends RefCounted
	var providers: Array = []

	func add_provider(p: Object) -> DotResult:
		var v := DotQueryProvider.validate(p)
		if v.ok:
			providers.append(p)
		return v

	func remove_provider(p: Object) -> void:
		providers.erase(p)

	func snapshot() -> DotQuerySnapshot:
		var s := DotQuerySnapshot.new()
		s.info["bots"] = 2
		return s


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_period()
	_attribution()
	_config()
	await _live()
	await _panel()
	await _server()
	_report()
	var _c := DotPaths.remove_tree(DIR)
	print("profiler_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	var ok := _failed == 0 and _sections == SECTIONS and _checks == CHECKS
	get_tree().quit(0 if ok else 1)


func _process(_delta: float) -> void:
	if not _busy:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_beat:
		return
	_next_beat = now + _beat_s
	var t := DotFrameCost.now()
	while Time.get_ticks_usec() - t < 45000 and t > 0:
		pass
	DotFrameCost.add(&"selftest.timer", t, "rebuild cache")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _period() -> void:
	var p := DotProfilerPeriod.new()
	for t in [0.0, 1.02, 1.98, 3.01, 5.0, 6.03, 6.99]:
		p.add(t)
	var f := p.detect()
	_check(not f.is_empty() and absf(f.period_s - 1.0) < 0.03, "a 1 s beat with a skipped beat is found: %s" % f)
	_check(f.get("beats", 0) == 6, "every gap fits the beat")
	_check(DotProfilerPeriod.describe_found(f).begins_with("every 1.0"), "the beat reads 'every 1.0x s'")
	var q := DotProfilerPeriod.new()
	for t in [0.0, 0.31, 1.7, 1.93, 3.6, 3.71, 5.9]:
		q.add(t)
	_check(q.detect().is_empty(), "irregular spikes have no beat: %s" % q.detect())
	var r := DotProfilerPeriod.new()
	for t in [0.0, 0.5, 1.0]:
		r.add(t)
	_check(r.detect().is_empty(), "three spikes are too few to name a beat")
	_sections += 1


func _attribution() -> void:
	var rec := {"t": 2.0, "ms": 50.0, "physics": 2.0, "script": 44.0, "render": 3.0, "wait": 1.0,
		"systems": {&"navigation": {"ms": 30.0, "calls": 1, "worst_ms": 30.0, "what": "rebuild"}, &"hud": {"ms": 1.0, "calls": 3, "worst_ms": 0.5, "what": ""}},
		"deltas": {"compile": 2, "added": 14, "kb": 900}, "marks": ["killcam"], "added": ["Ragdoll(ragdoll.gd)@3ms"]}
	var a := DotProfiler.attribute(rec)
	_check(a.cause == "navigation" and a.what == "rebuild", "the system with most of the frame is the cause: %s" % a.cause)
	_check("2 shader compile(s)" in a.hints and "+14 nodes" in a.hints, "compiles and new nodes are hints: %s" % [a.hints])
	_check(a.hints.any(func(h: String) -> bool: return h.begins_with("new=Ragdoll")), "the new subtree is named")
	_check(a.systems.get("hud", 0.0) == 1.0, "every system's cost is kept")
	rec.systems = {&"hud": {"ms": 5.0, "calls": 1, "worst_ms": 5.0, "what": ""}}
	_check(DotProfiler.attribute(rec).cause == "engine.script", "a small system leaves the cause to the slowest phase")
	rec.systems = {}
	rec.render = 60.0
	_check(DotProfiler.attribute(rec).cause == "engine.render", "with no system reports the render phase is blamed")
	var line := DotProfilerReport.spike_line(a)
	_check(line.contains("navigation (rebuild)") and line.contains("t=2.00s"), "a spike reads as one line: %s" % line)
	_sections += 1


func _config() -> void:
	var c := DotProfilerConfig.new()
	_check(not c.enabled and not c.overlay, "everything is off by default")
	_check(c.validate().ok, "the defaults validate")
	_check(not c.set_text("budget_ms", "-3").ok and c.budget_ms == 33.0, "a bad budget is refused and put back")
	_check(c.set_text("budget_ms", "16.6").ok and is_equal_approx(c.budget_ms, 16.6), "a good budget is taken")
	_check(not c.set_text("record_dir", "res://x").ok, "recordings never go into res://")
	_check(c.set_text("record_dir", "/tmp/x").ok and c.set_text("record_dir", "user://profiles").ok, "an absolute directory is taken, for a server's logs")
	_check(c.set_text("enabled", "on").ok and c.enabled, "a switch takes on")
	var made: Array = []
	var add := func(n: String, v: String, _h: String, _f: int) -> Object:
		made.append([n, v])
		return null
	var _b := c.bind_cvars(add)
	_check(made.size() == c.config_keys().size() and made.any(func(m: Array) -> bool: return m[0] == "profiler_budget_ms" and m[1] == "16.6"),
		"a profiler_* cvar per setting with its current text")
	_sections += 1


func _live() -> void:
	Engine.max_fps = 60
	var prof := DotProfiler.new()
	prof.config = DotProfilerConfig.new()
	prof.config.budget_ms = 30.0
	prof.config.record_dir = DIR
	prof.config.warn_every_s = 100.0
	add_child(prof)
	_check(DotRegistry.get_service(DotProfiler.SERVICE) == prof, "the profiler registers itself as dot_profiler")
	_check(not prof.is_watching() and not DotFrameCost.enabled, "nothing is watched while off")
	var spikes: Array = []
	prof.spike.connect(func(info: Dictionary) -> void: spikes.append(info))
	var started := prof.start_recording(3.2)
	_check(started.ok and prof.is_watching() and DotFrameCost.enabled, "recording turns watching on")
	_check(not prof.start_recording(1.0).ok, "a second recording is refused")
	_next_beat = Time.get_ticks_msec() / 1000.0 + 0.2
	_busy = true
	var res: DotResult = await prof.recording_finished
	_busy = false
	_check(res.ok and FileAccess.file_exists(res.value), "the recording stopped itself and wrote %s" % [res.value if res.ok else res.error.message])
	_check(FileAccess.file_exists(String(res.value).get_basename() + ".txt"), "a readable text report sits beside it")
	var timer := spikes.filter(func(s: Dictionary) -> bool: return s.cause == "selftest.timer")
	_check(timer.size() >= 5, "the beating system is named as the cause of %d of %d spikes" % [timer.size(), spikes.size()])
	var per := prof.period_of("selftest.timer")
	_check(not per.is_empty() and absf(per.period_s - _beat_s) < 0.05, "its beat is found: %s" % per)
	var rep: Dictionary = (DotPaths.read_json(res.value) as DotResult).value
	_check(rep.frames > 60 and rep.p50_ms < 30.0 and rep.worst_ms >= 40.0, "the report has frames, p50 and the worst spike")
	_check(rep.causes.has("selftest.timer") and String(rep.causes["selftest.timer"].period).begins_with("every 0.4"),
		"the report names the cause and its beat: %s" % [rep.causes.get("selftest.timer")])
	_check(not prof.is_watching() and not DotFrameCost.enabled, "watching stops with the recording when the profiler is off")
	var console := FakeConsole.new()
	prof.bind_console(console)
	_check(console.commands.has("record") and console.commands.has("profiler_stop") and console.vars.has("profiler_overlay"),
		"record, profiler_stop and profiler_* are on the console")
	var on: Variant = console.vars["profiler_overlay"][1].call("1")
	_check(on is DotResult and on.ok and prof.config.overlay and prof.get_children().any(func(n: Node) -> bool: return n is DotProfilerOverlay),
		"profiler_overlay 1 shows the overlay")
	_check(DotProfilerOverlay.lines(prof).size() >= 3, "the overlay has a header and rows")
	var _off: Variant = console.vars["profiler_overlay"][1].call("0")
	await get_tree().process_frame
	_check(not prof.is_watching(), "profiler_overlay 0 stops watching again")
	prof.queue_free()
	await get_tree().process_frame
	_check(not DotRegistry.has(DotProfiler.SERVICE), "freeing the profiler unregisters it")
	_sections += 1


func _panel() -> void:
	var prof := DotProfiler.new()
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR
	add_child(prof)
	var panel := prof.make_menu_panel(null) as DotProfilerPanel
	add_child(panel)
	var before := prof.recent_recordings(50).size()
	panel.record_button.pressed.emit()
	_check(prof.is_recording() and panel.record_button.text == "Stop", "Record starts a recording and becomes Stop")
	for i in 10:
		await get_tree().process_frame
	_check(panel.elapsed_label.text.begins_with("Recording"), "the elapsed time shows while recording")
	panel.record_button.pressed.emit()
	_check(not prof.is_recording() and FileAccess.file_exists(prof.last_saved_path()), "Stop writes the report: %s" % prof.last_saved_path())
	_check(panel.result_label.visible and panel.result_label.text.begins_with("Saved to ") and panel.result_label.text.contains("profile-"),
		"the saved path is shown: %s" % panel.result_label.text)
	_check(prof.recent_recordings(50).size() == before + 1 and panel.recent_label.text.contains("Recent recordings"), "the new recording is listed")
	_check(panel.copy_button != null and not panel.copy_button.disabled, "Copy path is offered once there is a report")
	panel.queue_free()
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1


## A console line run as [param source] with [param perms]; returns what it replied.
func _run(console: DotConsole, line: String, source := DotCmdContext.Source.RCON, perms := PackedStringArray(["config"])) -> String:
	var out := PackedStringArray()
	var ctx := DotCmdContext.new()
	ctx.source = source
	ctx.permissions = perms
	ctx.reply_sink = func(t: String) -> void: out.append(t)
	var _r := console.execute(line, ctx)
	return "\n".join(out)


func _server() -> void:
	var console := DotConsole.new()
	add_child(console)
	var server := FakeServer.new()
	var logs := ProjectSettings.globalize_path(DIR).path_join("logs")
	server.config.log_directory = logs
	add_child(server)
	var prof := DotProfiler.new()
	prof.config = DotProfilerConfig.new()
	prof.register_as_service = false
	add_child(prof)
	var ctl := DotProfilerServer.new()
	var res := ctl.install(prof, console, server, server.query_source)
	_check(res.ok and ctl.get_parent() == prof, "installs on a dot-server console under the profiler: %s" % [res.error.message if not res.ok else ""])
	_check(ctl.names().size() == 9 and Array(ctl.names()).all(func(n: String) -> bool: return console.has_name(n)), "every sv_profiler_* command is registered")
	_check(console.find_cvar("profiler_record_dir") != null and console.find_cvar("profiler_sample_hz") != null, "profiler_record_dir and profiler_sample_hz are server cvars")
	_check(prof.config.record_dir == logs.path_join("profiles"), "recordings go under the server's log directory: %s" % prof.config.record_dir)
	var refused := _run(console, "sv_profiler_record 1", DotCmdContext.Source.RCON, PackedStringArray())
	_check(not prof.is_recording() and refused.contains("permission"), "RCON without the config flag is refused: %s" % refused)
	_check(not _run(console, "sv_profiler_status", DotCmdContext.Source.CHAT, PackedStringArray()).contains("recording"), "a player in chat cannot read it either")
	var _hz := _run(console, "profiler_sample_hz 20")
	_check(is_equal_approx(prof.config.sample_hz, 20.0), "profiler_sample_hz set over RCON reaches the config")
	var started := _run(console, "sv_profiler_record 30")
	_check(prof.is_recording() and started.contains(logs), "sv_profiler_record over RCON starts a recording: %s" % started)
	for i in 30:
		await get_tree().process_frame
	var st := Array(_run(console, "sv_profiler_status").split("\n"))
	_check(st.any(func(l: String) -> bool: return l.begins_with("recording ") and l.ends_with("true")), "sv_profiler_status says it is recording")
	var parsed: Variant = JSON.parse_string(_run(console, "sv_profiler_metrics"))
	var keys_ok := parsed is Dictionary and ["frame", "memory", "net", "status", "hitches", "systems"].all(func(k: String) -> bool: return parsed.has(k))
	_check(keys_ok, "sv_profiler_metrics is one JSON line with every metric")
	_check(keys_ok and int(parsed.net.players) == 3 and int(parsed.net.bots) == 2, "players and bots come from the server and its query")
	_check(keys_ok and int(parsed.memory.nodes) > 0 and parsed.frame.has("physics_ms"), "memory counts and frame times are filled")
	_check(_run(console, "sv_profiler_frame").contains("frame_ms") and _run(console, "sv_profiler_memory").contains("orphans")
		and _run(console, "sv_profiler_net").contains("players") and _run(console, "sv_profiler_hitches") != "" and _run(console, "sv_profiler_systems 3") != "",
		"frame, memory, net, hitches and systems each answer")
	var stopped := _run(console, "sv_profiler_stop", DotCmdContext.Source.CONSOLE, PackedStringArray(["root"]))
	var path := prof.last_saved_path()
	_check(not prof.is_recording() and path.begins_with(logs) and FileAccess.file_exists(path) and stopped.contains("Saved to"), "sv_profiler_stop writes into the log directory: %s" % stopped)
	var rep: Dictionary = (DotPaths.read_json(path) as DotResult).value if path != "" else {}
	var samples: Array = rep.get("samples", [])
	_check(samples.size() >= 2 and samples[0].has("players") and samples[0].has("nodes"), "the report carries server samples: %d" % samples.size())
	var snap := DotQuerySnapshot.new()
	DotQueryProvider.contribute_to(ctl, snap)
	_check(server.query_source.providers.has(ctl) and snap.game.is_empty(), "the query provider publishes nothing while profiler_query is 0")
	var _q := _run(console, "profiler_query 1")
	DotQueryProvider.contribute_to(ctl, snap)
	_check(snap.game.has("profiler_ms") and snap.game.has("profiler_spikes"), "with profiler_query 1 the query's game section has the frame time")
	prof.queue_free()
	await get_tree().process_frame
	_check(not console.has_name("sv_profiler_status") and console.find_cvar("profiler_record_dir") == null and server.query_source.providers.is_empty(),
		"freeing the profiler takes the commands, cvars and query provider away")
	console.queue_free()
	server.queue_free()
	await get_tree().process_frame
	_sections += 1


func _report() -> void:
	var frames := PackedFloat32Array()
	for i in 100:
		frames.append(10.0 if i % 25 != 0 else 50.0)
	var r := DotProfilerReport.build(frames, [{"t": 1.0, "ms": 50.0, "cause": "a", "period": "every 0.40 s (3 of 3 gaps)"}], {}, {}, {"budget_ms": 33.0})
	_check(r.p50_ms == 10.0 and r.worst_ms == 50.0 and r.p99_ms == 50.0, "percentiles from the frames")
	_check("\n".join(DotProfilerReport.to_text(r)).contains("repeats every 0.40 s"), "the text names the beat")
	var cfg := DotProfilerConfig.new()
	cfg.keep_recordings = 2
	for i in 3:
		var _w := DotProfilerReport.write(r, DIR + "/prune", cfg.keep_recordings)
		OS.delay_msec(1100)
	_check(DotProfilerReport.list(DIR + "/prune").size() == 2, "only the newest recordings are kept")
	_sections += 1
