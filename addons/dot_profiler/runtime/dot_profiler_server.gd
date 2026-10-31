class_name DotProfilerServer
extends Node

## A dedicated server's profiler controls: sv_profiler_* console and RCON commands, profiler_* cvars, and the query's game keys.
##
## dot-server and dot-server-query are reached by duck typing through [DotRegistry], so neither is a dependency.
## [method install] parents it under the profiler, so it lives and goes with it.

const CHANNEL := "dot.profiler.server"
const PERMISSION := "config"
const COMMANDS := {
	"sv_profiler_record": "Record frames for N seconds (default profiler_record_seconds) to the server's profile directory.",
	"sv_profiler_stop": "Stop the recording and write the JSON and text report.",
	"sv_profiler_status": "Watching, recording, spikes, the repeating beat and the last saved report.",
	"sv_profiler_frame": "Frame, process and physics times now, and the smoothed engine phases.",
	"sv_profiler_hitches": "Spikes seen per cause, worst first, with the beat each repeats on.",
	"sv_profiler_systems": "The N costliest systems reported through DotFrameCost (default 10).",
	"sv_profiler_memory": "Static memory, object, node, orphan and resource counts.",
	"sv_profiler_net": "Bytes and rates in and out, players and bots.",
	"sv_profiler_metrics": "Every metric as one JSON line, for tools reading over RCON.",
}

## The profiler this serves.
var profiler: DotProfiler = null
var _console: Object = null
var _server: Object = null
var _query: Object = null
var _cvar_names := PackedStringArray()
var _net := DotProfilerMetrics.new()
var _record_dir_was := ""


## Registers the commands and cvars on [param console] and a query provider on [param query]; null ones are found in [DotRegistry].
## A default record directory moves under the server's log directory, so recordings land beside its logs.
func install(p: DotProfiler, console: Object = null, server: Object = null, query: Object = null) -> DotResult:
	if p == null or p.config == null:
		return DotResult.fail(DotError.CODE_INVALID, "DotProfilerServer needs a profiler with a config.")
	profiler = p
	if get_parent() == null:
		p.add_child(self)
	_console = console if console != null else _service(&"dot_console")
	_server = server if server != null else _service(&"dot_server")
	_query = query if query != null else _service(&"dot_query_source")
	if _console == null or not _console.has_method(&"add_source"):
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "No dot-server console to register sv_profiler_* on.")
	_move_record_dir()
	if _console.has_method(&"cvar"):
		for cv: Object in profiler.config.bind_cvars(Callable(_console, &"cvar")):
			_cvar_names.append(String(cv.get(&"name")))
	var res: Variant = _console.call(&"add_source", self, PERMISSION)
	if res is DotResult and not (res as DotResult).ok:
		return (res as DotResult).wrap("registering sv_profiler_*")
	profiler.sampler = sample
	if _query != null and _query.has_method(&"add_provider"):
		var q: Variant = _query.call(&"add_provider", self)
		if q is DotResult and not (q as DotResult).ok:
			DotLog.warn(CHANNEL, "query provider refused: %s" % (q as DotResult).error.message)
	DotLog.debug(CHANNEL, "sv_profiler_* installed", {"record_dir": profiler.config.record_dir,
		"query": _query != null})
	return DotResult.success(self)


func _exit_tree() -> void:
	uninstall()


## Removes everything [method install] added.
func uninstall() -> void:
	if _console != null and is_instance_valid(_console):
		_console.call(&"remove_source", self)
		for n in _cvar_names:
			_console.call(&"unregister_cvar", n)
	if _query != null and is_instance_valid(_query) and _query.has_method(&"remove_provider"):
		_query.call(&"remove_provider", self)
	if profiler != null and is_instance_valid(profiler):
		profiler.sampler = DotProfilerMetrics.memory
		if _record_dir_was != "":
			profiler.config.record_dir = _record_dir_was
	_cvar_names = PackedStringArray()
	_console = null
	_server = null
	_query = null


func names() -> PackedStringArray:
	return PackedStringArray(COMMANDS.keys())


func help_for(name: String) -> String:
	return COMMANDS.get(name, "")


## Runs one sv_profiler_* line; dot-server's console has already checked the caller's permission.
func execute(line: String) -> Variant:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "Empty command.")
	var args := words.slice(1)
	match words[0].to_lower():
		"sv_profiler_record":
			var r := profiler.start_recording(args[0].to_float() if not args.is_empty() else 0.0)
			if not r.ok:
				return r
			return "Recording %.0f s to %s." % [r.value, ProjectSettings.globalize_path(profiler.config.record_dir)]
		"sv_profiler_stop":
			var r := profiler.stop_recording()
			if not r.ok:
				return r
			return "Saved to %s." % ProjectSettings.globalize_path(String(r.value))
		"sv_profiler_status":
			return _lines(status())
		"sv_profiler_frame":
			return _lines(frame())
		"sv_profiler_hitches":
			return hitch_lines()
		"sv_profiler_systems":
			return system_lines(args[0].to_int() if not args.is_empty() else 10)
		"sv_profiler_memory":
			return _lines(DotProfilerMetrics.memory())
		"sv_profiler_net":
			return _lines(net())
		"sv_profiler_metrics":
			return JSON.stringify(metrics())
	return DotResult.fail(DotError.CODE_INVALID, "Not a profiler command: %s" % words[0])


## Watching, recording, spikes, the beat and the last saved path.
func status() -> Dictionary:
	var s := profiler.status()
	return {"watching": profiler.is_watching(), "recording": profiler.is_recording(),
		"elapsed_s": snappedf(profiler.elapsed_s(), 0.1), "length_s": profiler.recording_length_s(),
		"spikes": s.spikes, "smoothed_ms": snappedf(s.ms, 0.01), "budget_ms": s.budget_ms,
		"period": s.period, "record_dir": profiler.config.record_dir, "last_saved": profiler.last_saved_path()}


## The engine's frame times now and the profiler's smoothed phases, in ms.
func frame() -> Dictionary:
	var out := DotProfilerMetrics.frame()
	for k: String in profiler.phase_ms():
		out["phase_" + k + "_ms"] = profiler.phase_ms()[k]
	out["smoothed_ms"] = profiler.status().ms
	return out


## Bytes and rates in and out on the server's peer, and the players and bots on it.
func net() -> Dictionary:
	var out := _net.net(_peer())
	out["players"] = int(_server.call(&"player_count")) if _server != null and _server.has_method(&"player_count") else 0
	out["bots"] = _bots()
	return out


## Every metric in one dictionary: frame, memory, net, status, spikes per cause and the top systems.
func metrics() -> Dictionary:
	return {"frame": frame(), "memory": DotProfilerMetrics.memory(), "net": net(), "status": status(),
		"hitches": profiler.spikes_by_cause(), "systems": profiler.top_costs(10)}


## The sampler a recording calls on a server: memory, net, players and bots.
func sample() -> Dictionary:
	var out := DotProfilerMetrics.memory()
	out.merge(net())
	return out


func hitch_lines() -> PackedStringArray:
	var by := profiler.spikes_by_cause()
	if by.is_empty():
		return PackedStringArray(["No spikes seen%s." % ("" if profiler.is_watching() else " (profiler_enabled is 0)")])
	var causes := by.keys()
	causes.sort_custom(func(a: Variant, b: Variant) -> bool: return by[a].spikes > by[b].spikes)
	var out := PackedStringArray()
	for c: Variant in causes:
		out.append("%-28s %4d spikes  worst %.1f ms%s" % [c, by[c].spikes, by[c].worst_ms,
			("  repeats " + by[c].period) if by[c].period != "" else ""])
	return out


func system_lines(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in profiler.top_costs(maxi(n, 1)):
		out.append("%-28s %7.2f ms" % [s.system, s.ms])
	return out


func describe() -> String:
	return "DotProfilerServer console=%s server=%s query=%s cvars=%d" % [_console != null, _server != null,
		_query != null, _cvar_names.size()]


func describe_lines() -> PackedStringArray:
	return PackedStringArray([describe()])


func _provider_name() -> String:
	return "profiler"


## Adds profiler_* keys to the query's game section, only while profiler_query is 1: the query is public.
func _contribute(snapshot: Object) -> void:
	if profiler == null or not profiler.config.query or not snapshot.has_method(&"contribute_game"):
		return
	var s := profiler.status()
	var m := DotProfilerMetrics.memory()
	snapshot.call(&"contribute_game", {"profiler_ms": snappedf(s.ms, 0.1), "profiler_spikes": s.spikes,
		"profiler_period": s.period, "profiler_static_mb": snappedf(m.static_mb, 0.1), "profiler_nodes": m.nodes})


func _move_record_dir() -> void:
	if profiler.config.record_dir != DotProfilerConfig.new().record_dir or _server == null:
		return
	var cfg: Variant = _server.get(&"config")
	if not (cfg is Object) or cfg == null:
		return
	var logs := String((cfg as Object).get(&"log_directory"))
	if logs == "":
		return
	_record_dir_was = profiler.config.record_dir
	profiler.config.record_dir = logs.path_join("profiles")


func _peer() -> MultiplayerPeer:
	var host: Node = _server as Node if _server is Node else self
	if host == null or not host.is_inside_tree() or host.multiplayer == null:
		return null
	return host.multiplayer.multiplayer_peer


func _bots() -> int:
	if _server == null:
		return 0
	var src: Variant = _server.get(&"query_source")
	if not (src is Object) or src == null or not (src as Object).has_method(&"snapshot"):
		return 0
	var snap: Variant = (src as Object).call(&"snapshot")
	return int((snap as Object).call(&"bot_count")) if snap is Object and (snap as Object).has_method(&"bot_count") else 0


static func _service(key: StringName) -> Object:
	var v: Variant = DotRegistry.get_service(key)
	return v as Object if v is Object else null


static func _lines(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in d:
		var v: Variant = d[k]
		out.append("%-20s %s" % [k, String.num(v, 2) if v is float else str(v)])
	return out
