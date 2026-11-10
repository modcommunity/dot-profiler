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
@export var overlay_top: int = 4

## Draw a solid stacked area graph of frame cost under the overlay text.
@export var graph: bool = true

## Height of the graph in pixels.
@export var graph_height: int = 60

## Milliseconds the graph's full height stands for; 0 uses twice the budget.
@export var graph_scale_ms: float = 0.0

## Frames (2 px columns each) the graph shows.
@export var graph_frames: int = 120

## Y legend: each band's name and the ms where it starts, in small text.
@export var graph_legend: bool = true

## Client look of the overlay (the UI_KEYS below; the menu saves them per device): the text lines above the graph.
@export var overlay_text: bool = true

## Font size of the overlay's text and of the graph's legend, in pixels.
@export var overlay_text_size: int = 11

## Scale of the whole overlay (text and graph together), 0.5 to 3.
@export var overlay_scale: float = 1.0

## Which corner the overlay sits in: one of [constant CORNERS].
@export var overlay_corner: String = "top_left"

## Distance from that corner's two edges, in pixels.
@export var overlay_offset_x: int = 12
@export var overlay_offset_y: int = 12

## Opacity of everything the overlay draws, 0.1 to 1.
@export var overlay_opacity: float = 0.85

## Opacity of the plate behind the text and graph, 0 to 1.
@export var overlay_bg_opacity: float = 0.5

## Width of one frame's column in the graph, in pixels (1 to 6); the graph is graph_frames of these wide.
@export var graph_col_px: int = 2

## Draw the connection (ping, bytes in and out) in the profiler's graph and hide dot-menu's separate net_stat panel while the overlay is up.
@export var overlay_merge_net: bool = true

## Report sections (docs/report-format.md); off leaves the section out of the report. Collection that costs time
## has its own switch above (trace, monitors, timeline, render_detail, census, deep, sample_hz, worst_frames, script_top).
@export var rec_frame_stats: bool = true
@export var rec_spikes: bool = true
@export var rec_systems: bool = true
@export var rec_phases: bool = true
@export var rec_physics_ticks: bool = true
@export var rec_queries: bool = true
@export var rec_growth: bool = true
@export var rec_overhead: bool = true
@export var rec_suspects: bool = true
@export var rec_engine: bool = true

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

## While recording, time every span reported through DotFrameCost so the report has a call tree below the systems.
@export var trace: bool = true

## While recording, read the engine monitors (physics pairs, islands, draw calls, nodes, memory) every frame.
@export var monitors: bool = true

## Frames a recording keeps whole (their full tree), worst first.
@export var worst_frames: int = 5

## A saved report (JSON path) every recording is diffed against when it is written; the diff is logged and saved as .diff.txt.
@export var reference: String = ""

## Seconds the capture key (or profiler_capture) records.
@export var capture_seconds: float = 10.0

## Also sample native stacks with Linux perf while recording (docs/deep-mode.md).
@export var deep: bool = false

## While recording, keep every frame's time and flag frames well above the running average with the spans that ran in them.
@export var timeline: bool = false

## While recording, also read texture and buffer memory, resources, the viewport's draw split and render cpu/gpu ms.
@export var render_detail: bool = false

## While recording, read the viewport's render cpu and gpu ms every frame (the render line of the report).
@export var render_time: bool = true

## Suspects the report lists first: the costliest spans by self time against the tick budget. 0 lists none.
@export var suspects_top: int = 10

## The counter ([method DotProfiler.add_counter]) or SceneTree group costs are divided by, e.g. players; empty is none.
@export var per_unit: String = ""

## Microseconds one unit of [member per_unit] may cost per physics tick; the suspects are held against it. 0 is no target.
@export var unit_target_us: float = 0.0

## Counted every frame while recording: comma-separated `group` or `group:system-prefix` (SceneTree groups, or
## counters a game adds with [method DotProfiler.add_counter]); the report gives each prefixed system's cost per unit.
@export var groups: String = ""

## Count nodes by class when a recording starts and stops, so the report says which kinds grew.
@export var census: bool = false

## GDScript functions the report lists by self time; needs the game run with -d (docs/report-format.md). 0 is off.
@export var script_top: int = 0

## Buckets for the script functions: comma-separated `name=substring|substring` matched against script paths.
@export var script_buckets: String = ""

## The settings the overlay's look is made of; the menu saves exactly these (see [method DotProfiler.save_ui_prefs]).
const UI_KEYS: PackedStringArray = ["overlay_top", "overlay_text", "overlay_text_size", "overlay_scale",
	"overlay_corner", "overlay_offset_x", "overlay_offset_y", "overlay_opacity", "overlay_bg_opacity", "graph",
	"graph_height", "graph_frames", "graph_col_px", "graph_legend", "overlay_merge_net"]
const CORNERS: PackedStringArray = ["top_left", "top_right", "bottom_left", "bottom_right"]

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
	if graph_height < 20 or graph_height > 400 or graph_frames < 20 or graph_frames > 600 or graph_scale_ms < 0.0 or graph_scale_ms > 10000.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_graph_height is 20 to 400, profiler_graph_frames 20 to 600, profiler_graph_scale_ms 0 to 10000.")
	if overlay_text_size < 7 or overlay_text_size > 40 or overlay_scale < 0.5 or overlay_scale > 3.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_overlay_text_size is 7 to 40 and profiler_overlay_scale 0.5 to 3.")
	if not overlay_corner in CORNERS:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_overlay_corner is one of %s." % ", ".join(CORNERS))
	if overlay_offset_x < 0 or overlay_offset_x > 4000 or overlay_offset_y < 0 or overlay_offset_y > 4000:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_overlay_offset_x and _y are 0 to 4000.")
	if overlay_opacity < 0.1 or overlay_opacity > 1.0 or overlay_bg_opacity < 0.0 or overlay_bg_opacity > 1.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_overlay_opacity is 0.1 to 1 and profiler_overlay_bg_opacity 0 to 1.")
	if graph_col_px < 1 or graph_col_px > 6:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_graph_col_px is 1 to 6.")
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
	if worst_frames < 0 or worst_frames > 50 or capture_seconds <= 0.0 or capture_seconds > 3600.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_worst_frames must be 0 to 50 and profiler_capture_seconds above 0, at most 3600.")
	if suspects_top < 0 or suspects_top > 100 or unit_target_us < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_suspects_top must be 0 to 100 and profiler_unit_target_us 0 or more.")
	if script_top < 0 or script_top > 500:
		return DotResult.fail(DotError.CODE_INVALID, "profiler_script_top must be 0 to 500.")
	for entry in parse_groups(groups):
		if entry.group == "":
			return DotResult.fail(DotError.CODE_INVALID, "profiler_groups is 'group' or 'group:prefix', comma-separated; '%s' has an empty name." % groups)
	for b in parse_buckets(script_buckets):
		if b.name == "" or (b.match as PackedStringArray).is_empty():
			return DotResult.fail(DotError.CODE_INVALID, "profiler_script_buckets is 'name=part|part', comma-separated, not '%s'." % script_buckets)
	return DotResult.success(self)


## [param text] as [{group, prefix}]; a missing prefix is "".
static func parse_groups(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in text.split(",", false):
		var bits := part.strip_edges().split(":", true, 1)
		out.append({"group": bits[0].strip_edges(), "prefix": bits[1].strip_edges() if bits.size() > 1 else ""})
	return out


## [param text] as [{name, match: PackedStringArray}].
static func parse_buckets(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in text.split(",", false):
		var bits := part.strip_edges().split("=", true, 1)
		var parts := PackedStringArray()
		if bits.size() > 1:
			for m in bits[1].split("|", false):
				if m.strip_edges() != "":
					parts.append(m.strip_edges())
		out.append({"name": bits[0].strip_edges(), "match": parts})
	return out


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
