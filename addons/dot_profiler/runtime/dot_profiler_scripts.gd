class_name DotProfilerScripts
extends RefCounted

## GDScript function times for a recording: total and self time and calls per function, from the engine's
## script profiler. Godot only runs that profiler under its local debugger, so the game must be started
## with -d; [method start] says so and does nothing otherwise. The table arrives as printed lines, which a
## [Logger] catches and [method parse] reads.

const CHANNEL := "dot.profiler"
const HEADER := "ACCUMULATED"


class Catcher extends Logger:
	var lines := PackedStringArray()
	var on := false
	var _lock := Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		# The debugger also prints a per-second table; only the final accumulated one is kept.
		if not on:
			if not message.begins_with(HEADER):
				return
			on = true
		_lock.lock()
		lines.append(message)
		_lock.unlock()


var _catcher: Catcher = null
var _started_usec := 0


## Starts the script profiler; fails when the game was not started with -d.
func start() -> DotResult:
	if not EngineDebugger.is_active():
		return DotResult.fail(DotError.CODE_STATE, "script functions need the game started with -d (the local debugger)")
	if not EngineDebugger.has_profiler(&"scripts"):
		return DotResult.fail(DotError.CODE_STATE, "this build has no scripts profiler")
	_catcher = Catcher.new()
	OS.add_logger(_catcher)
	EngineDebugger.profiler_enable(&"scripts", true)
	_started_usec = Time.get_ticks_usec()
	return DotResult.success(true)


func is_running() -> bool:
	return _catcher != null


## Stops it and returns the report's script_functions value: [param top] functions by self time, per script
## totals, and [param buckets] ([method DotProfilerConfig.parse_buckets]) summed; ms are per frame over [param frames].
func stop(top: int, frames: int, buckets: Array[Dictionary] = []) -> Dictionary:
	if _catcher == null:
		return {}
	EngineDebugger.profiler_enable(&"scripts", false)
	OS.remove_logger(_catcher)
	var lines := _catcher.lines
	_catcher = null
	var rows := parse(lines)
	return summarize(rows, top, frames, buckets)


## The rows in the debugger's accumulated table (`0:res://a.gd::13::f` then `total: 0.05/28 % self: 0.05/28 % tcalls: 30`, seconds): [{signature, script, line, function, total_ms, self_ms, calls}].
static func parse(lines: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text := "\n".join(lines).split("\n")
	var cur := {}
	for raw in text:
		var l := raw.strip_edges()
		if l.begins_with(HEADER) or l == "":
			continue
		if l.begins_with("total:"):
			if cur.is_empty():
				continue
			cur["total_ms"] = _secs(l, "total:") * 1000.0
			cur["self_ms"] = _secs(l, "self:") * 1000.0
			# Godot 4.7 prints "tcalls: N"; "calls:" covers both spellings.
			var c := l.find("calls:")
			cur["calls"] = l.substr(c + 6).strip_edges().get_slice(" ", 0).to_int() if c >= 0 else 0
			out.append(cur)
			cur = {}
			continue
		var colon := l.find(":")
		if colon > 0 and l.left(colon).is_valid_int():
			cur = _signature(l.substr(colon + 1))
	return out


## [param rows] from [method parse] as {functions, scripts, buckets, total_self_ms}, ms per frame.
static func summarize(rows: Array[Dictionary], top: int, frames: int, buckets: Array[Dictionary] = []) -> Dictionary:
	var n := maxf(float(frames), 1.0)
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms > b.self_ms)
	var total := 0.0
	var by_script := {}
	var by_bucket := {}
	for b: Dictionary in buckets:
		by_bucket[b.name] = {"bucket": b.name, "self_ms": 0.0, "calls": 0, "functions": 0}
	by_bucket["other"] = {"bucket": "other", "self_ms": 0.0, "calls": 0, "functions": 0}
	for r: Dictionary in sorted:
		total += r.self_ms
		var s: Dictionary = by_script.get(r.script, {"script": r.script, "self_ms": 0.0, "calls": 0, "functions": 0})
		s.self_ms += r.self_ms
		s.calls += r.calls
		s.functions += 1
		by_script[r.script] = s
		var name := "other"
		for b: Dictionary in buckets:
			for m: String in b.match:
				if String(r.script).contains(m) or String(r.function).contains(m):
					name = b.name
					break
			if name != "other":
				break
		var row: Dictionary = by_bucket[name]
		row.self_ms += r.self_ms
		row.calls += r.calls
		row.functions += 1
	var funcs: Array = []
	for r: Dictionary in sorted.slice(0, top):
		funcs.append({"function": r.function, "script": r.script, "line": r.line, "calls_per_frame": r.calls / n,
			"self_ms": r.self_ms / n, "total_ms": r.total_ms / n, "us_per_call": r.self_ms * 1000.0 / maxf(r.calls, 1.0)})
	var scripts: Array = []
	for s: Dictionary in by_script.values():
		scripts.append({"script": s.script, "self_ms": s.self_ms / n, "calls_per_frame": s.calls / n, "functions": s.functions})
	scripts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms > b.self_ms)
	var bucket_rows: Array = []
	if not buckets.is_empty():
		for b: Dictionary in by_bucket.values():
			bucket_rows.append({"bucket": b.bucket, "self_ms": b.self_ms / n, "calls_per_frame": b.calls / n, "functions": b.functions})
	return {"ok": true, "functions": funcs, "scripts": scripts.slice(0, top), "buckets": bucket_rows,
		"self_ms": total / n, "function_count": rows.size()}


static func _secs(line: String, key: String) -> float:
	var i := line.find(key)
	if i < 0:
		return 0.0
	var rest := line.substr(i + key.length()).strip_edges()
	var slash := rest.find("/")
	return (rest.left(slash) if slash >= 0 else rest.get_slice(" ", 0)).to_float()


static func _signature(sig: String) -> Dictionary:
	var parts := sig.split("::", false)
	var script := ""
	var line := 0
	var fn := sig
	for p in parts:
		if p.is_valid_int():
			line = p.to_int()
		elif p.contains("://") or p.ends_with(".gd"):
			script = p
	if not parts.is_empty():
		fn = parts[-1]
	return {"signature": sig, "script": script, "line": line, "function": fn}
