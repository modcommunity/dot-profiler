class_name DotProfilerGraphData
extends RefCounted

## A ring of per-frame stacked costs for the graph: one value per band per frame, in ms, bottom band first.

const BANDS: PackedStringArray = ["physics", "script", "render", "wait", "other"]
const COLORS: Array[Color] = [
	Color(0.20, 0.55, 0.95), Color(0.95, 0.75, 0.15), Color(0.85, 0.30, 0.35),
	Color(0.45, 0.45, 0.55), Color(0.35, 0.80, 0.55)]

var capacity := 120
var _data := PackedFloat32Array()
var _head := 0
var _count := 0
## Network KB/s per frame (in, out), filled only while the graph is merged with the net readout.
var _net := PackedFloat32Array()
var _net_on := false


func _init(frames: int = 120) -> void:
	resize(frames)


## Resizes (and clears) the ring to [param frames] columns.
func resize(frames: int) -> void:
	capacity = maxi(frames, 2)
	_data.resize(capacity * BANDS.size())
	_data.fill(0.0)
	_net.resize(capacity * 2)
	_net.fill(0.0)
	_net_on = false
	_head = 0
	_count = 0


func count() -> int:
	return _count


## Adds a frame from a hitch record: its phase times, and "other" for what they leave of [code]ms[/code].
func push_record(rec: Dictionary) -> void:
	var o := _head * BANDS.size()
	var sum := 0.0
	for i in 4:
		var v := maxf(float(rec.get(BANDS[i], 0.0)), 0.0)
		_data[o + i] = v
		sum += v
	_data[o + 4] = maxf(float(rec.get("ms", 0.0)) - sum, 0.0)
	_head = (_head + 1) % capacity
	_count = mini(_count + 1, capacity)


## Records the network rate of the frame just pushed with [method push_record], in KB/s.
func push_net(kb_in: float, kb_out: float) -> void:
	if _count == 0:
		return
	var o := ((_head - 1 + capacity) % capacity) * 2
	_net[o] = kb_in
	_net[o + 1] = kb_out
	_net_on = true


## True once [method push_net] has been called since the last resize.
func has_net() -> bool:
	return _net_on


## Network KB/s [param dir] (0 in, 1 out) in the frame [param age] frames back.
func net_value(dir: int, age: int) -> float:
	if age < 0 or age >= _count:
		return 0.0
	return _net[((_head - 1 - age + capacity * 2) % capacity) * 2 + dir]


## Largest network rate (either direction) over the held frames.
func net_peak() -> float:
	var m := 0.0
	for a in _count:
		m = maxf(m, maxf(net_value(0, a), net_value(1, a)))
	return m


## Band [param band]'s value in the frame [param age] frames back (0 is the newest).
func value(band: int, age: int) -> float:
	if age < 0 or age >= _count:
		return 0.0
	return _data[((_head - 1 - age + capacity * 2) % capacity) * BANDS.size() + band]


## Stack tops of the newest [param frames] frames averaged: where each band ends, bottom band first.
## Band i starts at tops[i - 1] (0 for the first).
func tops(frames: int = 8) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BANDS.size())
	var n := mini(frames, _count)
	if n == 0:
		return out
	var run := 0.0
	for b in BANDS.size():
		var s := 0.0
		for a in n:
			s += value(b, a)
		run += s / n
		out[b] = run
	return out


## Label heights in pixels (0 at the bottom, up) for bands starting at [param starts] px, kept at least
## [param gap] apart and inside [0, top].
static func spread(starts: PackedFloat32Array, gap: float, top: float) -> PackedFloat32Array:
	var out := starts.duplicate()
	for i in range(1, out.size()):
		out[i] = maxf(out[i], out[i - 1] + gap)
	for i in range(out.size() - 1, -1, -1):
		var cap := top - (out.size() - 1 - i) * gap
		out[i] = minf(out[i], cap)
	return out
