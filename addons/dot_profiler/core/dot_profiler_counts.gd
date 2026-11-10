class_name DotProfilerCounts
extends RefCounted

## Counts of things that are not a time, reported per tick under the report's [code]engine.counts[/code]:
## signal emits, node lookups, arrays built, anything a game suspects of churn. The engine keeps no such
## counts in a release build, so the code that does the work says so: [code]DotProfilerCounts.add(&"emit.hit")[/code].
##
## Main thread only. One bool test while no recording runs.

## True while a recording runs; [method add] does nothing otherwise.
static var enabled: bool = false

static var _counts: Dictionary = {}


## Adds [param amount] to [param name]; free unless a recording runs.
static func add(name: StringName, amount: int = 1) -> void:
	if enabled:
		_counts[name] = int(_counts.get(name, 0)) + amount


## Starts counting from zero.
static func begin() -> void:
	_counts = {}
	enabled = true


## Stops counting and returns {name: total}.
static func end() -> Dictionary:
	enabled = false
	var out := {}
	for k: Variant in _counts:
		out[String(k)] = _counts[k]
	return out


## What was counted so far: {name: total}.
static func peek() -> Dictionary:
	var out := {}
	for k: Variant in _counts:
		out[String(k)] = _counts[k]
	return out
