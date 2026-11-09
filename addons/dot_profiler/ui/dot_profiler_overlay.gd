class_name DotProfilerOverlay
extends CanvasLayer

## The top costs drawn over the game: frame time against budget, the last spike and its beat, then the costliest systems.

const REFRESH_S := 0.25

## The profiler read from; set before adding.
var profiler: DotProfiler = null

var _label: Label = null
var _graph: DotProfilerGraph = null
var _bg: PanelContainer = null
var _style: StyleBoxFlat = null
var _hidden_net: CanvasItem = null


func _ready() -> void:
	layer = 120
	var bg := PanelContainer.new()
	_bg = bg
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.06, 0.08, 0.5)
	_style.set_content_margin_all(6)
	_style.set_corner_radius_all(6)
	bg.add_theme_stylebox_override(&"panel", _style)
	add_child(bg)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 11)
	_label.add_theme_color_override(&"font_color", Color(0.9, 0.95, 1.0))
	var box := VBoxContainer.new()
	bg.add_child(box)
	box.add_child(_label)
	_graph = DotProfilerGraph.new()
	_graph.data = profiler.graph_data()
	box.add_child(_graph)
	apply_graph()
	get_viewport().size_changed.connect(_place)
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
	_graph.col_w = c.graph_col_px
	_graph.font_size = maxi(c.overlay_text_size - 2, 6)
	_graph.show_net = c.overlay_merge_net and c.graph
	_graph.fit()
	apply_look()


## Applies the look settings: text shown and its size, scale, opacity, background and corner.
func apply_look() -> void:
	if _bg == null or not is_instance_valid(profiler):
		return
	var c := profiler.config
	_label.visible = c.overlay_text
	_label.add_theme_font_size_override(&"font_size", c.overlay_text_size)
	_bg.scale = Vector2.ONE * c.overlay_scale
	_bg.modulate.a = c.overlay_opacity
	_style.bg_color.a = c.overlay_bg_opacity
	_bg.reset_size()
	_hide_net_readout(c.overlay_merge_net and c.graph)
	_place()


## Puts the panel in the chosen corner, [code]overlay_offset_x/y[/code] pixels in.
func _place() -> void:
	if _bg == null or not is_instance_valid(profiler):
		return
	var c := profiler.config
	var sz := _bg.get_combined_minimum_size() * c.overlay_scale
	_bg.position = corner_pos(c.overlay_corner, get_viewport().get_visible_rect().size, sz, c.overlay_offset_x, c.overlay_offset_y)


## Where a panel of [param size] sits in the [param corner] of a [param view], [param ox]/[param oy] pixels in; never off the top left.
static func corner_pos(corner: String, view: Vector2, size: Vector2, ox: float, oy: float) -> Vector2:
	var x := ox
	var y := oy
	if corner.ends_with("right"):
		x = view.x - size.x - ox
	if corner.begins_with("bottom"):
		y = view.y - size.y - oy
	return Vector2(maxf(x, 0.0), maxf(y, 0.0))


## The net readout dot-menu draws (a node named NetStat) is hidden while the graph carries the net lines.
func _hide_net_readout(on: bool) -> void:
	if _hidden_net != null and (not on or not is_instance_valid(_hidden_net)):
		if is_instance_valid(_hidden_net):
			_hidden_net.visible = true
		_hidden_net = null
	if on and _hidden_net != null:
		_hidden_net.visible = false
	elif on:
		var n := get_tree().root.find_child("NetStat", true, false) as CanvasItem
		if n != null and n.visible:
			_hidden_net = n
			n.visible = false


func _exit_tree() -> void:
	_hide_net_readout(false)


## Redraws the text and graph now.
func refresh() -> void:
	if _label == null or not is_instance_valid(profiler):
		return
	if _graph != null and _graph.visible:
		_graph.queue_redraw()
	_hide_net_readout(profiler.config.overlay_merge_net and profiler.config.graph)
	_place()
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
