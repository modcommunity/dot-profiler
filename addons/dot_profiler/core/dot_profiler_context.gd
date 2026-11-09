class_name DotProfilerContext
extends RefCounted

## What a report needs to be comparable between machines: OS, CPU, GPU and driver, engine build, tick rate, window
## and vsync. [method machine] is read once when a recording starts; a game adds its own keys with
## [method DotProfiler.add_context] (map, bots, natives loaded). [method build] and [method cvars] say which code
## ran and with which settings; [DotProfiler] adds both to every report.

## Written beside project.godot where there is no checkout (an export, a served pack): {commit, branch, addons}.
const STAMP := "build_id.json"
## Longest nested value a text line spells out; a longer one prints its size (the JSON has it all).
const TEXT_ENTRIES := 12

static var _build: Dictionary = {}


## {os, cpu, cores, ram_mb, gpu, gpu_vendor, driver, renderer, godot, debug_build, tick_rate, max_fps, window,
## vsync, display}. Every value is plain data, so the dictionary goes straight into the JSON.
static func machine() -> Dictionary:
	var headless := DisplayServer.get_name() == "headless"
	var win := Vector2i.ZERO if headless else DisplayServer.window_get_size()
	var mem := OS.get_memory_info()
	return {
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"ram_mb": int(mem.get("physical", 0)) / 1048576,
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"renderer": String(RenderingServer.get_current_rendering_method()),
		"godot": Engine.get_version_info().get("string", ""),
		"debug_build": OS.is_debug_build(),
		"tick_rate": Engine.physics_ticks_per_second,
		"max_fps": Engine.max_fps,
		"window": "%dx%d" % [win.x, win.y],
		"vsync": "none" if headless else _vsync_name(DisplayServer.window_get_vsync_mode()),
		"display": DisplayServer.get_name(),
	}


## {name, version, commit, branch, source, addons}: the project and the commit it runs. `source` says where the commit
## came from: "git" (the checkout's .git, as the bootstrap leaves it), "stamp" ([constant STAMP]) or "unknown".
## `addons` maps each linked addon to its checkout's commit. Read once per run.
static func build(root: String = "res://") -> Dictionary:
	if root == "res://" and not _build.is_empty():
		return _build
	var out := {
		"name": str(ProjectSettings.get_setting("application/config/name", "")),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"commit": "unknown", "branch": "", "source": "unknown", "addons": {},
	}
	var dir := ProjectSettings.globalize_path(root) if root.begins_with("res://") else root
	var head := git_head(dir.path_join(".git"))
	if not head.is_empty():
		out.merge(head, true)
		out["source"] = "git"
		var addons := {}
		var linked := DirAccess.get_directories_at(root.path_join("addons")) if DirAccess.dir_exists_absolute(dir.path_join("addons")) else PackedStringArray()
		var links := DirAccess.open(dir.path_join("addons")) if not linked.is_empty() else null
		for name in linked:
			# A linked addon is its own checkout two levels above the link's target; else the sibling repository.
			var repo := dir.path_join("../%s" % name.replace("_", "-")).simplify_path()
			if links != null and links.is_link(name):
				var to := links.read_link(name)
				if to != "":
					repo = (to if to.is_absolute_path() else dir.path_join("addons").path_join(to)).simplify_path().path_join("../..").simplify_path()
			var h := git_head(repo.path_join(".git"))
			if not h.is_empty():
				addons[name] = h.commit
		out["addons"] = addons
	elif FileAccess.file_exists(root.path_join(STAMP)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(STAMP)))
		if parsed is Dictionary and str((parsed as Dictionary).get("commit", "")) != "":
			out.merge(parsed as Dictionary, true)
			out["source"] = "stamp"
	if root == "res://":
		_build = out
	return out


## {commit, branch} of the checkout whose `.git` is [param git] (a directory, or a worktree's `gitdir:` file);
## empty when it is no checkout. The commit is 12 characters; a detached HEAD has no branch.
static func git_head(git: String) -> Dictionary:
	if FileAccess.file_exists(git):
		var link := _text(git)
		if not link.begins_with("gitdir:"):
			return {}
		var to := link.trim_prefix("gitdir:").strip_edges()
		git = to if to.is_absolute_path() else git.get_base_dir().path_join(to).simplify_path()
	var head := _text(git.path_join("HEAD"))
	if head == "":
		return {}
	if not head.begins_with("ref:"):
		return {"commit": head.left(12), "branch": ""}
	var ref := head.trim_prefix("ref:").strip_edges()
	# A worktree keeps its refs in the main checkout, named by `commondir`.
	var common := _text(git.path_join("commondir"))
	var roots := [git]
	if common != "":
		roots.append(common if common.is_absolute_path() else git.path_join(common).simplify_path())
	for r: String in roots:
		var loose := _text(r.path_join(ref))
		if loose != "":
			return {"commit": loose.left(12), "branch": ref.trim_prefix("refs/heads/")}
		for line in _text(r.path_join("packed-refs")).split("\n"):
			if line.ends_with(" " + ref):
				return {"commit": line.left(12), "branch": ref.trim_prefix("refs/heads/")}
	return {"commit": "unknown", "branch": ref.trim_prefix("refs/heads/")}


## The launch arguments, with the value of anything that names a secret (token, password, key) left out.
static func launch(args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()) -> Array:
	var out := []
	var hide := false
	for a in args:
		var name := a.get_slice("=", 0).to_lower()
		var secret := name.contains("token") or name.contains("pass") or name.contains("secret") or name.contains("key")
		if hide and not a.begins_with("-"):
			out.append("***")
		elif secret and a.contains("="):
			out.append(a.get_slice("=", 0) + "=***")
		else:
			out.append(a)
		hide = secret and not a.contains("=")
	return out


static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


## The console variables of [param local] (a local console with `add_var`) as text: {count, changed, values}.
## [param first] holds each variable's text when first seen and is filled here; `changed` lists those that differ
## since, as "now (was then)". A value set before the first read (a launch argument) shows in `values` only.
static func cvars(local: Object, first: Dictionary) -> Dictionary:
	var values := {}
	if local != null and local.has_method(&"var_values"):
		var got: Variant = local.call(&"var_values")
		if got is Dictionary:
			for k: Variant in got:
				values[str(k)] = str(got[k])
	elif local != null:
		# The console has no public list of its variables yet, so its table is read as it is.
		var table: Variant = local.get(&"_vars")
		if table is Dictionary:
			for k: Variant in table:
				var entry: Variant = table[k]
				var getter: Variant = (entry as Dictionary).get("get") if entry is Dictionary else null
				if getter is Callable and (getter as Callable).is_valid():
					values[str(k)] = str((getter as Callable).call())
	var changed := {}
	for k: String in values:
		if not first.has(k):
			first[k] = values[k]
		elif first[k] != values[k]:
			changed[k] = "%s (was %s)" % [values[k], first[k]]
	values.sort()
	return {"count": values.size(), "changed": changed, "values": values}


## The context lines of a report: the machine, then one line per game key.
static func lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var c: Dictionary = r.get("context", {})
	if c.is_empty():
		return out
	var m: Dictionary = c.get("machine", {})
	if not m.is_empty():
		out.append("Machine: %s, %s (%d cores, %d MB); GPU %s, %s %s, %s; Godot %s%s" % [m.get("os", "?"), m.get("cpu", "?"),
			m.get("cores", 0), m.get("ram_mb", 0), m.get("gpu", "?"), m.get("renderer", "?"), m.get("driver", ""), m.get("display", ""),
			m.get("godot", "?"), " (debug build)" if m.get("debug_build", false) else ""])
		out.append("Display: window %s, vsync %s, max_fps %d, physics %d/s" % [m.get("window", "?"), m.get("vsync", "?"),
			m.get("max_fps", 0), m.get("tick_rate", 0)])
	for k: String in c:
		if k != "machine":
			out.append("%s: %s" % [k.capitalize(), flat(c[k])])
	return out


## One value as one line: "k=v, k=v" for a dictionary, the entries joined for an array.
static func flat(v: Variant) -> String:
	if v is Dictionary and (v as Dictionary).size() > TEXT_ENTRIES:
		return "%d entries (in the JSON)" % (v as Dictionary).size()
	if v is Array and (v as Array).size() > TEXT_ENTRIES:
		return "%d entries (in the JSON)" % (v as Array).size()
	if v is Dictionary:
		var parts := PackedStringArray()
		for k: Variant in v:
			parts.append("%s=%s" % [k, flat(v[k])])
		return ", ".join(parts)
	if v is Array:
		var parts := PackedStringArray()
		for e: Variant in v:
			parts.append(flat(e))
		return "[" + ", ".join(parts) + "]"
	return str(v)


static func _vsync_name(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED:
			return "off"
		DisplayServer.VSYNC_ENABLED:
			return "on"
		DisplayServer.VSYNC_ADAPTIVE:
			return "adaptive"
		DisplayServer.VSYNC_MAILBOX:
			return "mailbox"
	return str(mode)
