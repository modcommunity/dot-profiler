class_name DotProfilerConfig
extends DotConfig

## The profiler's settings: exported defaults < JSON file < environment < command line, and the profiler_* cvars.
##
## Everything is off by default; turning [member enabled] on is what makes systems' [DotFrameCost] reports count.

## Master switch: watch every frame and log the cause of each one over budget.
@export var enabled: bool = false

## A frame longer than this, in milliseconds, is a spike.
@export var budget_ms: float = 33.0

## Draw the top costs over the game.
@export var overlay: bool = false

## Rows the overlay lists.
@export var overlay_top: int = 6

## How far, as a fraction of the period, a spike may land from the beat and still count as on it.
@export var period_tolerance: float = 0.12

## Spikes needed before a repeating interval is named.
@export var period_min_spikes: int = 4

## Seconds between two WARN lines blaming the same cause; the rest are counted, not logged.
@export var warn_every_s: float = 5.0

## Seconds a recording runs when none is given.
@export var record_seconds: float = 30.0

## Where recordings are written: under user://, or an absolute path (a dedicated server's log directory).
@export var record_dir: String = "user://profiles"

## Recordings kept; the oldest are deleted past this.
@export var keep_recordings: int = 20

## Metric samples (memory, nodes, objects, network, players) a recording takes per second; 0 takes none.
@export var sample_hz: float = 1.0

## Publish frame time, spikes and memory in the server query's game section (dot-server-query).
@export var query: bool = false

var _cvars: Dictionary = {}


func env_prefix() -> String:
	return "DOT_PROFILER_"


func cli_prefix() -> String:
	return "--profiler-"


func validate() -> DotResult:
	if budget_ms <= 0.0 or budget_ms > 10000.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_budget_ms is %s; it must be above 0 and at most 10000." % budget_ms)
	if overlay_top < 1 or overlay_top > 32:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_overlay_top must be 1 to 32.")
	if period_tolerance <= 0.0 or period_tolerance >= 0.5:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_period_tolerance must be above 0 and below 0.5.")
	if period_min_spikes < 3:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_period_min_spikes must be 3 or more.")
	if record_seconds <= 0.0 or keep_recordings < 1:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_record_seconds must be above 0 and profiler_keep_recordings 1 or more.")
	if not (record_dir.begins_with("user://") or (record_dir.is_absolute_path() and not record_dir.contains("://"))):
		return DotResult.fail(DotError.CODE_INVALID, "profiler_record_dir must be under user:// or an absolute path, not '%s'." % record_dir)
	if sample_hz < 0.0 or sample_hz > 60.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_sample_hz must be 0 to 60.")
	return DotResult.success(self)


## The cvar for [param key]: profiler_enabled, profiler_budget_ms and so on.
static func cvar_name(key: String) -> String:
	return "profiler_" + key


## Registers a profiler_* cvar per setting through dot-server's `add_cvar`, by duck typing; returns them.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for key in config_keys():
		var c: Variant = add.call(cvar_name(key), text_of(key), "Profiler: %s." % key, flags)
		if not (c is Object) or c == null:
			continue
		var cv := c as Object
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar.bind(key))
		_cvars[key] = cv
		made.append(cv)
		var waiting: Variant = cv.call(&"get_string") if cv.has_method(&"get_string") else ""
		if String(waiting) != "" and String(waiting) != text_of(key):
			var _r := set_text(key, String(waiting))
	return made


## [param key]'s value as console text.
func text_of(key: String) -> String:
	var v: Variant = get(key)
	if v is bool:
		return "1" if v else "0"
	if v is float:
		return String.num(v, 3)
	return str(v)


## Sets [param key] from console text and emits [signal Resource.changed]; a value that fails [method validate] is put back.
func set_text(key: String, text: String) -> DotResult:
	if not has_key(key):
		return DotResult.fail(DotError.CODE_INVALID, "No profiler setting '%s'." % key)
	var old: Variant = get(key)
	var t := text.strip_edges()
	match typeof(old):
		TYPE_BOOL:
			if not t.to_lower() in ["1", "0", "true", "false", "on", "off"]:
				return DotResult.fail(DotError.CODE_INVALID, "%s is 0 or 1." % cvar_name(key))
			set(key, t.to_lower() in ["1", "true", "on"])
		TYPE_INT:
			if not t.is_valid_int():
				return DotResult.fail(DotError.CODE_INVALID, "%s is a whole number." % cvar_name(key))
			set(key, t.to_int())
		TYPE_FLOAT:
			if not t.is_valid_float():
				return DotResult.fail(DotError.CODE_INVALID, "%s is a number." % cvar_name(key))
			set(key, t.to_float())
		_:
			set(key, t)
	var res := validate()
	if not res.ok:
		set(key, old)
		return res
	emit_changed()
	return DotResult.success(get(key))


func _on_cvar(_old: String, new_value: String, key: String) -> void:
	var res := set_text(key, new_value)
	if not res.ok:
		DotLog.warn("dot.profiler", res.error.message)
