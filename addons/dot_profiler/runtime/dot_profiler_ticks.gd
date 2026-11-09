class_name DotProfilerTicks
extends Node

## Stamps each physics tick: its start at SceneTree.physics_frame and the end of every script's
## _physics_process, by running last of all. What follows the end, up to the next tick, is the engine's step.

## Kept unread past this many ticks (a profiler that stopped reading), the stamps are dropped.
const LIMIT := 8192

## Pairs of tick start and scripts end in microseconds; an end of 0 was not seen.
var stamps := PackedInt64Array()


func _init() -> void:
	name = "DotProfilerTicks"
	process_physics_priority = 1_000_000_000
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	if not get_tree().physics_frame.is_connected(_on_tick):
		var _c := get_tree().physics_frame.connect(_on_tick)


func _exit_tree() -> void:
	if get_tree().physics_frame.is_connected(_on_tick):
		get_tree().physics_frame.disconnect(_on_tick)


func _physics_process(_delta: float) -> void:
	var n := stamps.size()
	if n >= 2:
		stamps[n - 1] = Time.get_ticks_usec()


## The ticks stamped since the last call, and forgets them.
func take() -> PackedInt64Array:
	var out := stamps
	stamps = PackedInt64Array()
	return out


func _on_tick() -> void:
	if stamps.size() >= LIMIT:
		stamps.clear()
	var _a := stamps.append(Time.get_ticks_usec())
	var _b := stamps.append(0)
