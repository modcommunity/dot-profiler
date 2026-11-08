class_name DotProfilerGraph
extends Control

## A net_graph-style stacked area chart of frame cost: solid fills, one colour per band (physics, script, render,
## wait, other), a budget line, and a Y legend naming the ms where each band starts. Redrawn on a timer, never per frame.

const LEGEND_W := 78.0
const COL_W := 2.0
const FONT_SIZE := 9

## The data drawn; set before adding.
var data: DotProfilerGraphData = null
var height_px := 80.0
## Milliseconds the full height stands for; 0 uses twice the budget.
var scale_ms := 0.0
var budget_ms := 33.0
var show_legend := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit()


## Sets the size from the settings; call after changing them.
func fit() -> void:
	if data == null:
		return
	var w := (LEGEND_W if show_legend else 0.0) + data.capacity * COL_W
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
	var x0 := LEGEND_W if show_legend else 0.0
	var k := h / full_ms()
	draw_rect(Rect2(x0, 0, data.capacity * COL_W, h), Color(0.05, 0.06, 0.08, 0.9))
	for age in data.count():
		var x := x0 + (data.capacity - 1 - age) * COL_W
		var y := h
		for b in DotProfilerGraphData.BANDS.size():
			var bh := minf(data.value(b, age) * k, y)
			if bh > 0.0:
				draw_rect(Rect2(x, y - bh, COL_W, bh), DotProfilerGraphData.COLORS[b])
				y -= bh
	var by := h - budget_ms * k
	if by > 0.0:
		draw_line(Vector2(x0, by), Vector2(x0 + data.capacity * COL_W, by), Color(1, 1, 1, 0.6))
	if show_legend:
		_draw_legend(k)


func _draw_legend(k: float) -> void:
	var font := ThemeDB.fallback_font
	var tops := data.tops()
	var starts := PackedFloat32Array([0.0])
	for b in range(1, tops.size()):
		starts.append(tops[b - 1] * k)
	var gap := FONT_SIZE + 1.0
	var ys := DotProfilerGraphData.spread(starts, gap, height_px - gap)
	for b in tops.size():
		var start_ms := 0.0 if b == 0 else tops[b - 1]
		var y := height_px - ys[b]
		var c := DotProfilerGraphData.COLORS[b]
		draw_rect(Rect2(0, y - 6, 5, 5), c)
		draw_line(Vector2(LEGEND_W - 6, height_px - starts[b]), Vector2(LEGEND_W, height_px - starts[b]), c)
		draw_string(font, Vector2(7, y), "%s %.1f" % [DotProfilerGraphData.BANDS[b], start_ms],
			HORIZONTAL_ALIGNMENT_LEFT, LEGEND_W - 8, FONT_SIZE, Color(0.9, 0.95, 1.0))
