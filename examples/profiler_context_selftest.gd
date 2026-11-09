extends Node

## The report's context: machine header, game context and recording hooks (extras), dropped ticks, the breakdown
## line, the capture key's render detail, the reference diff, and compare with one path.

const DIR := "user://profiler_context_selftest"
const CHECKS := 30

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
	prof.add_context("game", func() -> Dictionary: return {"commit": "abc123", "natives": false})
	var local := _FakeConsole.new()
	prof.bind_console(local)
	await get_tree().process_frame
	local.values["sv_cheats"] = "1"
	prof.add_recording_hook("native", func() -> void: began[0] += 1, func() -> Dictionary: return {"tick_us": 12.5})
	prof.add_recording_hook("empty", func() -> void: pass, func() -> Dictionary: return {})
	var r := await _record(prof, false)
	_check(r.context.machine.has("os") and r.context.game.commit == "abc123", "context holds the machine and the game's keys")
	_check(began[0] == 1 and r.extras.native.tick_us == 12.5 and not r.extras.has("empty"), "hooks run once and report; an empty one is left out")
	_check(r.context.build.has("commit") and r.context.build.has("source") and r.context.launch is Array, "context has the build and the launch arguments")
	var cv: Dictionary = r.context.cvars
	_check(cv.count == local.values.size() and cv.values.get("sv_gravity") == "800", "context lists every console variable")
	_check(cv.changed.size() == 1 and cv.changed.get("sv_cheats") == "1 (was 0)", "a variable changed since the console was bound is named")
	_test_build()
	var t: Dictionary = r.physics_ticks
	_check(t.has("ticks_per_sec") and t.has("dropped_ticks") and t.has("wall_s"), "ticks report the rate and dropped ticks")
	var text := "\n".join(DotProfilerReport.to_text(r))
	_check(text.contains("Machine:") and text.contains("Game: commit=abc123") and text.contains("Per frame:") and text.contains("unaccounted")
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


func _test_build() -> void:
	var root := ProjectSettings.globalize_path(DIR).path_join("repo")
	var git := root.path_join(".git")
	var _m := DirAccess.make_dir_recursive_absolute(git.path_join("refs/heads"))
	_write(git.path_join("HEAD"), "ref: refs/heads/main\n")
	_write(git.path_join("refs/heads/main"), "0123456789abcdef0123456789abcdef01234567\n")
	var h := DotProfilerContext.git_head(git)
	_check(h.get("commit") == "0123456789ab" and h.get("branch") == "main", "a branch's commit is read from its loose ref", str(h))
	var _d := DirAccess.remove_absolute(git.path_join("refs/heads/main"))
	_write(git.path_join("packed-refs"), "# pack-refs\nfedcba9876543210fedcba9876543210fedcba98 refs/heads/main\n")
	_check(DotProfilerContext.git_head(git).get("commit") == "fedcba987654", "and from packed-refs")
	_write(git.path_join("HEAD"), "89abcdef0123456789abcdef0123456789abcdef\n")
	h = DotProfilerContext.git_head(git)
	_check(h.get("commit") == "89abcdef0123" and h.get("branch") == "", "a detached HEAD is its own commit")
	var tree := root.path_join("tree")
	var _t := DirAccess.make_dir_recursive_absolute(tree)
	_write(tree.path_join(".git"), "gitdir: ../.git\n")
	_check(DotProfilerContext.git_head(tree.path_join(".git")).get("commit") == "89abcdef0123", "a gitdir file is followed")
	_check(DotProfilerContext.build(tree).source == "git", "build() reads the checkout")
	var bare := root.path_join("bare")
	var _b := DirAccess.make_dir_recursive_absolute(bare)
	_check(DotProfilerContext.build(bare).source == "unknown" and DotProfilerContext.build(bare).commit == "unknown", "no checkout and no stamp: unknown, no error")
	_write(bare.path_join(DotProfilerContext.STAMP), JSON.stringify({"commit": "5555555", "branch": "main"}))
	var st := DotProfilerContext.build(bare)
	_check(st.source == "stamp" and st.commit == "5555555", "the stamp file names the commit where there is no checkout", str(st))
	var args := DotProfilerContext.launch(PackedStringArray(["--map=x", "--token=abc", "--password", "hunter2", "--bots", "8"]))
	_check(args == ["--map=x", "--token=***", "--password", "***", "--bots", "8"], "launch arguments hide secrets", str(args))
	var many := {}
	for i in 40:
		many["k%d" % i] = i
	_check(DotProfilerContext.flat({"a": many}) == "a=40 entries (in the JSON)", "a long nested value prints its size")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


class _FakeConsole extends RefCounted:
	var values := {"sv_cheats": "0", "sv_gravity": "800"}
	var _vars := {}

	func _init() -> void:
		var held := values
		for k: String in values:
			_vars[k] = {"help": "", "get": func() -> Variant: return held[k]}

	func add_var(_n: Variant, _h: Variant, _g: Variant = null, _s: Variant = null) -> void:
		pass

	func add_command(_n: Variant, _h: Variant, _f: Variant = null) -> void:
		pass


func _record(prof: DotProfiler, capture: bool) -> Dictionary:
	prof.config.capture_seconds = 0.3
	var _s := prof.toggle_capture() if capture else prof.start_recording(0.3)
	var res: DotResult = await prof.recording_finished
	if not res.ok:
		return {}
	return DotPaths.read_json(res.value).value


func _check(ok: bool, what: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what, " ", detail)
