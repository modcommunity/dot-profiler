class_name DotProfilerContext
extends RefCounted

## What a report needs to be comparable between machines: OS, CPU, GPU and driver, engine build, tick rate, window
## and vsync. [method machine] is read once when a recording starts; a game adds its own keys with
## [method DotProfiler.add_context] (build, map, bots, natives loaded, cvar overrides).


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
