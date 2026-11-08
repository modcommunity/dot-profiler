class_name DotProfilerOverlay
extends CanvasLayer

## The top costs drawn over the game: frame time against budget, the last spike and its beat, then the costliest systems.

const REFRESH_S := 0.25

## The profiler read from; set before adding.
var profiler: DotProfiler = null

var _label: Label = null
var _graph: DotProfilerGraph = null


func _ready() -> void:
	layer = 120
	var bg := PanelContainer.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	bg.add_theme_stylebox_override(&"panel", style)
	add_child(bg)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color(0.9, 0.95, 1.0))
	var box := VBoxContainer.new()
	bg.add_child(box)
	box.add_child(_label)
	_graph = DotProfilerGraph.new()
	_graph.data = profiler.graph_data()
	box.add_child(_graph)
	apply_graph()
	# A timer, not _process: the text is rebuilt 4 times a second, never per frame.
	var timer := Timer.new()
	timer.wait_time = REFRESH_S
	timer.timeout.connect(refresh)
	add_child(timer)
	timer.start()
	refresh()




## Applies the graph settings (shown, height, scale, legend, frames).
func apply_graph() -> void:
	if _graph == null or not is_instance_valid(profiler):
		return
	var c := profiler.config
	_graph.visible = c.graph
	_graph.height_px = c.graph_height
	_graph.scale_ms = c.graph_scale_ms
	_graph.budget_ms = c.budget_ms
	_graph.show_legend = c.graph_legend
	_graph.fit()


## Redraws the text and graph now.
func refresh() -> void:
	if _label == null or not is_instance_valid(profiler):
		return
	if _graph != null and _graph.visible:
		_graph.queue_redraw()
	_label.text = "\n".join(lines(profiler))


## The overlay's text for [param p].
static func lines(p: DotProfiler) -> PackedStringArray:
	var st := p.status()
	var out := PackedStringArray()
	out.append("frame %.1f ms  budget %.0f  spikes %d%s" % [st.ms, st.budget_ms, st.spikes,
		("  REC %.0f s" % st.elapsed_s) if st.recording else ""])
	if String(st.period) != "":
		out.append("spikes repeat " + String(st.period))
	var last: Dictionary = st.last
	if not last.is_empty():
		out.append("last %.1f ms: %s%s" % [last.ms, last.cause, (" " + String(last.period)) if String(last.period) != "" else ""])
	for row in p.top_costs(p.config.overlay_top):
		out.append("%-22s %6.2f ms" % [row.system, row.ms])
	return out
