class_name DotProfilerMetrics
extends RefCounted

## The engine's own numbers a profiler reports beside its spikes: frame times, memory and object counts, network bytes.
##
## Engine monitors only, so it works on a headless server with nothing instrumented.


## Frame, process and physics times from the engine's monitors, in ms.
static func frame() -> Dictionary:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	return {
		"fps": fps,
		"frame_ms": 1000.0 / fps if fps > 0.0 else 0.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"physics_fps": Engine.physics_ticks_per_second,
	}


## Static memory in MB and the object, node, orphan and resource counts.
static func memory() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


var _in := 0
var _out := 0
var _last_in := 0
var _last_out := 0
var _last_usec := 0


## Total bytes in and out on [param peer] and the rates since the last call, or {"metered": false} when it cannot be read.
## A [DotMeteredPeer] is read directly; an ENet peer's host statistics are drained and summed here, so nothing else may pop them.
func net(peer: MultiplayerPeer) -> Dictionary:
	if not _read(peer):
		return {"metered": false}
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1.0e6 if _last_usec > 0 else 0.0
	var out := {"metered": true, "bytes_in": _in, "bytes_out": _out,
		"kbps_in": (_in - _last_in) / 1024.0 / dt if dt > 0.0 else 0.0,
		"kbps_out": (_out - _last_out) / 1024.0 / dt if dt > 0.0 else 0.0}
	_last_in = _in
	_last_out = _out
	_last_usec = now
	return out


func _read(peer: MultiplayerPeer) -> bool:
	if peer == null:
		return false
	var meter := DotMeteredPeer.of(peer)
	if meter != null:
		_in = meter.bytes_in
		_out = meter.bytes_out
		return true
	# ENet is optional in a template, so it is reached by name, never typed.
	var host: Variant = peer.get(&"host")
	if not (host is Object) or host == null or not (host as Object).has_method(&"pop_statistic"):
		return false
	var h := host as Object
	_out += int(h.call(&"pop_statistic", ClassDB.class_get_integer_constant(&"ENetConnection", &"HOST_TOTAL_SENT_DATA")))
	_in += int(h.call(&"pop_statistic", ClassDB.class_get_integer_constant(&"ENetConnection", &"HOST_TOTAL_RECEIVED_DATA")))
	return true
