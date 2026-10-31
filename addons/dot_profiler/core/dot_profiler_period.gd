class_name DotProfilerPeriod
extends RefCounted

## Finds the fixed interval spikes repeat on, so "lag every second" points at a timer rather than at load.
##
## [codeblock]
## var p := DotProfilerPeriod.new()
## for t in spike_times: p.add(t)
## var found := p.detect()   # {period_s, beats, spikes, phase_s} or {} when there is no beat
## [/codeblock]
##
## Spikes may skip beats (a timer whose work is only sometimes slow), so a gap of two or three periods still counts.

## Spike times kept, newest last.
var keep := 64
## How far from a whole number of periods a gap may be, as a fraction of the period.
var tolerance := 0.12
## Spikes needed before a period is named.
var min_spikes := 4

var _times := PackedFloat64Array()


## Records a spike at [param t_s] seconds.
func add(t_s: float) -> void:
	_times.append(t_s)
	if _times.size() > keep:
		_times = _times.slice(_times.size() - keep)


func clear() -> void:
	_times.clear()


func count() -> int:
	return _times.size()


## {period_s, beats, spikes, phase_s} for the interval most gaps are a whole multiple of, or {}.
## [code]beats[/code] is how many gaps landed on it out of [code]spikes - 1[/code].
func detect() -> Dictionary:
	if _times.size() < min_spikes:
		return {}
	var gaps := PackedFloat64Array()
	for i in range(1, _times.size()):
		var g := _times[i] - _times[i - 1]
		if g > 0.0:
			gaps.append(g)
	if gaps.size() < min_spikes - 1:
		return {}
	var best := {}
	var tried := {}
	for g in gaps:
		# Every gap is a candidate, and so is its half and third, for a beat whose spikes skip.
		for div in [1.0, 2.0, 3.0]:
			var cand: float = g / div
			var key := int(round(cand * 200.0))
			if cand < 0.05 or tried.has(key):
				continue
			tried[key] = true
			var fit := _fit(gaps, cand)
			if fit.beats >= min_spikes - 1 and fit.beats >= ceili(gaps.size() * 0.75) \
					and (best.is_empty() or fit.beats > best.beats or (fit.beats == best.beats and fit.period_s > best.period_s)):
				best = fit
	if best.is_empty():
		return {}
	best["spikes"] = _times.size()
	best["phase_s"] = fmod(_times[_times.size() - 1], best.period_s)
	return best


## "every 1.00 s (8 of 9 gaps)" for a [method detect] result, or "".
static func describe_found(found: Dictionary) -> String:
	if found.is_empty():
		return ""
	return "every %.2f s (%d of %d gaps)" % [found.period_s, found.beats, int(found.spikes) - 1]


func describe() -> String:
	return "DotProfilerPeriod spikes=%d %s" % [_times.size(), describe_found(detect())]


func _fit(gaps: PackedFloat64Array, cand: float) -> Dictionary:
	var beats := 0
	var sum := 0.0
	var n := 0.0
	for g in gaps:
		var k := roundf(g / cand)
		if k < 1.0 or k > 4.0 or absf(g / cand - k) > tolerance:
			continue
		beats += 1
		sum += g
		n += k
	# The period is refined from the gaps that fit, so 0.98, 1.02 and 2.01 give 1.00.
	return {"period_s": sum / n if n > 0.0 else cand, "beats": beats}
