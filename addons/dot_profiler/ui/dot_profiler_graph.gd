class_name DotProfilerGraph
extends Control

## A net_graph-style stacked area chart of frame cost: solid fills, one colour per band (physics, script, render,
## wait, other), a budget line, and a Y legend naming the ms where each band starts. Redrawn on a timer, never per frame.

const NET_IN := Color(0.40, 0.90, 1.0)
const NET_OUT := Color(1.0, 0.55, 0.85)

## The data drawn; set before adding.
var data: DotProfilerGraphData = null
var height_px := 60.0
## Milliseconds the full height stands for; 0 uses twice the budget.
var scale_ms := 0.0
var budget_ms := 33.0
var show_legend := true
## Pixels per frame column and the legend's font size (profiler_graph_col_px, profiler_overlay_text_size).
var col_w := 2.0
var font_size := 9
## Draws the network rate (KB/s in and out) as two lines over the bands: the merged net graph.
var show_net := false


func legend_w() -> float:
	return 78.0 * font_size / 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit()


## Sets the size from the settings; call after changing them.
func fit() -> void:
	if data == null:
		return
	var w := (legend_w() if show_legend else 0.0) + data.capacity * col_w
	custom_minimum_size = Vector2(w, height_px)
	size = custom_minimum_size
	queue_redraw()


## Milliseconds the full height stands for.
func full_ms() -> float:
	return scale_ms if scale_ms > 0.0 else budget_ms * 2.0


func _draw() -> void:
	if data == null:
		return
	var h := height_px
	var x0 := legend_w() if show_legend else 0.0
	var k := h / full_ms()
	draw_rect(Rect2(x0, 0, data.capacity * col_w, h), Color(0.05, 0.06, 0.08, 0.9))
	for age in data.count():
		var x := x0 + (data.capacity - 1 - age) * col_w
		var heights := PackedFloat32Array()
		for b in DotProfilerGraphData.BANDS.size():
			heights.append(data.value(b, age) * k)
		var _drawn := DotStackedColumn.draw(self, x, h, col_w, heights, DotProfilerGraphData.COLORS, h)
	var by := h - budget_ms * k
	if by > 0.0:
		draw_line(Vector2(x0, by), Vector2(x0 + data.capacity * col_w, by), Color(1, 1, 1, 0.6))
	if show_net and data.has_net():
		_draw_net(x0, h)
	if show_legend:
		_draw_legend(k)


func _draw_net(x0: float, h: float) -> void:
	var peak := maxf(data.net_peak(), 1.0)
	for dir in 2:
		var col := NET_IN if dir == 0 else NET_OUT
		var prev := Vector2.ZERO
		for age in data.count():
			var pt := Vector2(x0 + (data.capacity - 1 - age) * col_w + col_w * 0.5, h - 2.0 - data.net_value(dir, age) / peak * (h - 4.0))
			if age > 0:
				draw_line(prev, pt, col, 1.0)
			prev = pt
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x0 + 3, font_size + 1.0), "net in %.1f out %.1f KB/s (top %.0f)" % [data.net_value(0, 0), data.net_value(1, 0), peak],
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.95, 1.0))


func _draw_legend(k: float) -> void:
	var font := ThemeDB.fallback_font
	var tops := data.tops()
	var starts := PackedFloat32Array([0.0])
	for b in range(1, tops.size()):
		starts.append(tops[b - 1] * k)
	var gap := font_size + 1.0
	var ys := DotProfilerGraphData.spread(starts, gap, height_px - gap)
	for b in tops.size():
		var start_ms := 0.0 if b == 0 else tops[b - 1]
		var y := height_px - ys[b]
		var c := DotProfilerGraphData.COLORS[b]
		draw_rect(Rect2(0, y - 6, 5, 5), c)
		draw_line(Vector2(legend_w() - 6, height_px - starts[b]), Vector2(legend_w(), height_px - starts[b]), c)
		draw_string(font, Vector2(7, y), "%s %.1f" % [DotProfilerGraphData.BANDS[b], start_ms],
			HORIZONTAL_ALIGNMENT_LEFT, legend_w() - 8, font_size, Color(0.9, 0.95, 1.0))
