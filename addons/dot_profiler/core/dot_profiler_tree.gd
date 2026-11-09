class_name DotProfilerTree
extends RefCounted

## A call tree summed over a recording, rebuilt each frame from DotFrameCost's traced spans by time containment,
## under engine roots: frame > process | render | wait | physics > scripts | step (one scripts and step per tick).
## Paths are ";"-joined names, so [method folded] is flamegraph-ready as it is.

const ROOTS: Array[String] = ["frame", "physics", "scripts", "step", "process", "render", "wait"]
const FRAME := 0
const PHYSICS := 1
const SCRIPTS := 2
const STEP := 3
const PROCESS := 4
const RENDER := 5
const WAIT := 6
## Traced span names have keys from here up; below are [constant ROOTS].
const OFFSET := 16

var frames := 0
var paths := PackedStringArray()
var parents := PackedInt32Array()
var incl_us := PackedInt64Array()
var excl_us := PackedInt64Array()
var calls := PackedInt64Array()
var present := PackedInt32Array()
var max_us := PackedInt64Array()
## Per node, its inclusive ms in each frame it ran in (frames it missed count as 0 in the percentiles).
var samples: Array[Array] = []

var _child := {}
var _span_names: Array = []


## Adds one frame. [param rec] is a DotHitchLog record (usec, events); [param ticks] the frame's physics ticks
## as pairs [tick start, scripts end] (0 when the end was not seen). Returns the frame flat as pid, incl, excl, calls.
func add_frame(rec: Dictionary, ticks: PackedInt64Array) -> PackedInt64Array:
	var w: PackedInt64Array = rec.get("usec", PackedInt64Array())
	if w.size() < 5 or w[0] <= 0 or w[4] <= w[0]:
		return PackedInt64Array()
	var ev: Dictionary = rec.get("events", {})
	_span_names = ev.get("names", _span_names)
	var roots := _roots(w, ticks)
	var events: PackedInt64Array = ev.get("events", PackedInt64Array())
	var ns := PackedInt64Array()
	var ne := PackedInt64Array()
	var nk := PackedInt32Array()
	var ri := 0
	var ei := 0
	while ri < roots.size() or ei < events.size():
		# Merge by end time; on a tie the span goes first, since a root ending with it contains it.
		if ei < events.size() and (ri >= roots.size() or events[ei + 1] <= roots[ri + 1]):
			# A span from outside this frame (a stale start stamp, or one ending before the frame began) would
			# get a negative or oversized duration: keep only what overlaps the frame, clipped to it.
			var s0 := maxi(events[ei], w[0])
			var e0 := mini(events[ei + 1], w[4])
			if e0 > s0:
				var _a := ns.append(s0)
				var _b := ne.append(e0)
				var _c := nk.append(int(events[ei + 2]) + OFFSET)
			ei += 3
		else:
			var _a := ns.append(roots[ri])
			var _b := ne.append(roots[ri + 1])
			var _c := nk.append(int(roots[ri + 2]))
			ri += 3
	var parent := PackedInt32Array()
	var _r := parent.resize(ns.size())
	parent.fill(-1)
	var stack := PackedInt32Array()
	for i in ns.size():
		# Everything finished before this one and started inside it is a child.
		while not stack.is_empty() and ns[stack[stack.size() - 1]] >= ns[i]:
			parent[stack[stack.size() - 1]] = i
			stack.resize(stack.size() - 1)
		var _p := stack.append(i)
	return _sum(ns, ne, nk, parent)


## Frame, process, render, wait, physics and per-tick scripts/step intervals as start, end, key, in end order.
static func _roots(w: PackedInt64Array, ticks: PackedInt64Array) -> PackedInt64Array:
	var w0 := w[0]
	var w1 := w[4]
	var first_tick := w1
	var t := PackedInt64Array()
	for i in range(0, ticks.size(), 2):
		if ticks[i] >= w0 and ticks[i] <= w1:
			var _a := t.append(ticks[i])
			var _b := t.append(ticks[i + 1])
	if not t.is_empty():
		first_tick = t[0]
	var out := PackedInt64Array()
	var pre := w[2]
	var post := w[3] if w[3] > 0 else first_tick
	out.append_array([w0, pre if pre > 0 else first_tick, PROCESS])
	if pre > 0:
		out.append_array([pre, post, RENDER])
		if first_tick > post:
			out.append_array([post, first_tick, WAIT])
	for i in range(0, t.size(), 2):
		var next := t[i + 2] if i + 2 < t.size() else w1
		var tail := t[i + 1] if t[i + 1] >= t[i] and t[i + 1] <= next else next
		out.append_array([t[i], tail, SCRIPTS])
		if next > tail:
			out.append_array([tail, next, STEP])
	if not t.is_empty():
		out.append_array([first_tick, w1, PHYSICS])
	out.append_array([w0, w1, FRAME])
	return out


func _sum(ns: PackedInt64Array, ne: PackedInt64Array, nk: PackedInt32Array, parent: PackedInt32Array) -> PackedInt64Array:
	var n := ns.size()
	var pid := PackedInt32Array()
	var _r := pid.resize(n)
	var fi := {}
	# Parents come after their children, so walking backwards meets every parent first.
	for i in range(n - 1, -1, -1):
		var p := parent[i]
		var ppid := pid[p] if p >= 0 else -1
		pid[i] = _pid(ppid, nk[i])
		var us := ne[i] - ns[i]
		var row: PackedInt64Array = fi.get(pid[i], PackedInt64Array([0, 0, 0]))
		row[0] += us
		row[1] += us
		row[2] += 1
		fi[pid[i]] = row
		if ppid >= 0:
			var prow: PackedInt64Array = fi[ppid]
			prow[1] -= us
			fi[ppid] = prow
	frames += 1
	var flat := PackedInt64Array()
	for id: int in fi:
		var row: PackedInt64Array = fi[id]
		incl_us[id] += row[0]
		excl_us[id] += row[1]
		calls[id] += row[2]
		present[id] += 1
		max_us[id] = maxi(max_us[id], row[0])
		samples[id].append(row[0] / 1000.0)
		flat.append_array([id, row[0], row[1], row[2]])
	return flat


func _pid(ppid: int, key: int) -> int:
	var k := (ppid + 1) * 16777216 + key
	var id: int = _child.get(k, -1)
	if id >= 0:
		return id
	id = paths.size()
	_child[k] = id
	var name := ROOTS[key] if key < OFFSET else String(_span_names[key - OFFSET]) if key - OFFSET < _span_names.size() else "?"
	var _a := paths.append(name if ppid < 0 else paths[ppid] + ";" + name)
	var _b := parents.append(ppid)
	var _c := incl_us.append(0)
	_c = excl_us.append(0)
	_c = calls.append(0)
	_c = max_us.append(0)
	_c = present.append(0)
	samples.append([])
	return id


## The [param p]th percentile (0..1) of node [param id]'s per-frame inclusive ms over every frame.
func percentile(id: int, p: float) -> float:
	var s: Array = samples[id].duplicate()
	s.sort()
	var idx := clampi(int(p * (frames - 1)), 0, maxi(frames - 1, 0))
	var zeros := frames - s.size()
	return 0.0 if idx < zeros or s.is_empty() else float(s[mini(idx - zeros, s.size() - 1)])


## The tree as rows in depth-first order, costliest child first: {path, name, depth, ms, self_ms, calls,
## p95_ms, max_ms, frames} with ms, self_ms and calls per frame. Nodes under [param min_ms] per frame are left out.
func rows(min_ms: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if frames == 0 or paths.is_empty():
		return out
	var kids := {}
	for id in paths.size():
		if parents[id] >= 0:
			var list: Array = kids.get(parents[id], [])
			list.append(id)
			kids[parents[id]] = list
	var todo: Array = [[0, 0]]
	while not todo.is_empty():
		var top: Array = todo.pop_back()
		var id: int = top[0]
		var ms := incl_us[id] / 1000.0 / frames
		if ms < min_ms and id != 0:
			continue
		out.append({"path": paths[id], "name": paths[id].get_slice(";", paths[id].count(";")), "depth": top[1],
			"ms": ms, "self_ms": excl_us[id] / 1000.0 / frames, "calls": float(calls[id]) / frames,
			"p95_ms": percentile(id, 0.95), "max_ms": max_us[id] / 1000.0, "frames": present[id]})
		var list: Array = kids.get(id, [])
		list.sort_custom(func(a: int, b: int) -> bool: return incl_us[a] < incl_us[b])
		for c: int in list:
			todo.append([c, int(top[1]) + 1])
	return out


## One frame from [method add_frame]'s flat value as rows {path, ms, self_ms, calls}, in path order.
func frame_rows(flat: PackedInt64Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(0, flat.size(), 4):
		out.append({"path": paths[flat[i]], "ms": flat[i + 1] / 1000.0, "self_ms": flat[i + 2] / 1000.0, "calls": flat[i + 3]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	return out


## Folded stacks: "frame;physics;scripts;arena.physics 12345" per node, its exclusive microseconds over the recording.
## flamegraph.pl, speedscope and inferno read it as it is.
func folded() -> String:
	var lines := PackedStringArray()
	for id in paths.size():
		if excl_us[id] > 0:
			var _a := lines.append("%s %d" % [paths[id], excl_us[id]])
	return "\n".join(lines) + ("\n" if not lines.is_empty() else "")


## Queries seen in the tree by caller: {caller: {kind: {ms, calls}}}, the caller being the span a q.<kind> ran in.
func traced_queries() -> Dictionary:
	var out := {}
	for id in paths.size():
		var leaf := paths[id].get_slice(";", paths[id].count(";"))
		if not leaf.begins_with("q.") or parents[id] < 0:
			continue
		var p := paths[parents[id]]
		var caller := p.get_slice(";", p.count(";"))
		var by_kind: Dictionary = out.get(caller, {})
		var row: Dictionary = by_kind.get(leaf.substr(2), {"ms": 0.0, "calls": 0})
		row.ms += incl_us[id] / 1000.0
		row.calls += calls[id]
		by_kind[leaf.substr(2)] = row
		out[caller] = by_kind
	return out
