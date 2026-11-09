class_name DotProfilerPanel
extends VBoxContainer

## The settings menu's profiler section: overlay toggle, Record / Stop with the time so far, where the report went,
## and the recordings already on this device. Built with dot-menu's kit when given one, plain controls otherwise.

var overlay_toggle: CheckButton = null
var record_button: Button = null
var elapsed_label: Label = null
var result_label: Label = null
var open_button: Button = null
var copy_button: Button = null
var download_button: Button = null
var recent_label: Label = null

## Seconds the next recording runs (profiler_record_seconds): any value above 0.
var seconds_box: SpinBox = null
var catalog_button: Button = null
## Setting key -> its control, for the recording switches and the look options.
var controls := {}

## The look options: [key, label, kind (bool, int, float, corner), min, max, step].
const LOOK: Array = [
	["overlay_text", "Show text lines", "bool", 0, 0, 0],
	["overlay_top", "Systems listed", "int", 0, 20, 1],
	["overlay_text_size", "Text size", "int", 7, 40, 1],
	["overlay_scale", "Overall size", "float", 0.5, 3.0, 0.1],
	["graph", "Show graph", "bool", 0, 0, 0],
	["graph_height", "Graph height (px)", "int", 20, 400, 5],
	["graph_frames", "Graph frames kept", "int", 20, 600, 10],
	["graph_col_px", "Pixels per frame", "int", 1, 6, 1],
	["graph_legend", "Graph legend", "bool", 0, 0, 0],
	["overlay_merge_net", "Merge net graph into this graph", "bool", 0, 0, 0],
	["overlay_corner", "Corner", "corner", 0, 0, 0],
	["overlay_offset_x", "Distance from side (px)", "int", 0, 4000, 4],
	["overlay_offset_y", "Distance from edge (px)", "int", 0, 4000, 4],
	["overlay_opacity", "Opacity", "float", 0.1, 1.0, 0.05],
	["overlay_bg_opacity", "Background opacity", "float", 0.0, 1.0, 0.05],
]

var _profiler: DotProfiler = null
var _kit: Object = null
var _syncing := false
var _catalog: Node = null


## Builds the controls for [param profiler]; [param kit] is a DotMenuKit or null.
func setup(profiler: DotProfiler, kit: Object = null) -> void:
	_profiler = profiler
	_kit = kit
	add_theme_constant_override(&"separation", 8)
	overlay_toggle = CheckButton.new()
	overlay_toggle.text = "Show frame-cost overlay"
	overlay_toggle.button_pressed = profiler.config.overlay
	overlay_toggle.toggled.connect(func(on: bool) -> void: profiler.set_overlay_visible(on))
	add_child(overlay_toggle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	add_child(row)
	seconds_box = SpinBox.new()
	seconds_box.min_value = 0.1
	seconds_box.max_value = 100000.0
	seconds_box.step = 0.1
	seconds_box.allow_greater = true
	seconds_box.suffix = "s"
	seconds_box.value = profiler.config.record_seconds
	seconds_box.value_changed.connect(func(v: float) -> void: _put(&"record_seconds", str(v)))
	controls["record_seconds"] = seconds_box
	row.add_child(seconds_box)
	record_button = _button("Record profile", true)
	record_button.pressed.connect(press_record)
	row.add_child(record_button)
	elapsed_label = _label("Records %.0f s of frames and what each system cost." % profiler.config.record_seconds)
	elapsed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(elapsed_label)
	result_label = _label("")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.visible = false
	add_child(result_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	add_child(actions)
	if DotPlatform.is_web():
		download_button = _button("Download report", false)
		download_button.pressed.connect(download_last)
		actions.add_child(download_button)
	else:
		open_button = _button("Open folder", false)
		open_button.pressed.connect(open_folder)
		actions.add_child(open_button)
		copy_button = _button("Copy path", false)
		copy_button.pressed.connect(copy_path)
		actions.add_child(copy_button)
	recent_label = _label("")
	add_child(recent_label)
	_build_options()
	# A timer, not _process: the elapsed text changes a few times a second, not per frame.
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true  # setup runs before the panel is in the tree, so start() would error
	timer.timeout.connect(_tick)
	add_child(timer)
	profiler.recording_started.connect(_on_started)
	profiler.recording_finished.connect(_on_finished)
	profiler.config.changed.connect(_sync)
	_refresh()


func _build_options() -> void:
	catalog_button = _button("What does it record?", false)
	catalog_button.pressed.connect(open_catalog)
	add_child(catalog_button)
	var rec := _section("Recording options (what the next recording collects)")
	var cheap := _button("Cheap set", false)
	cheap.pressed.connect(func() -> void: _preset(true))
	var all := _button("All on", false)
	all.pressed.connect(func() -> void: _preset(false))
	var rhead := HBoxContainer.new()
	rhead.add_child(cheap)
	rhead.add_child(all)
	rec.add_child(rhead)
	var group := ""
	for r in DotProfilerCatalog.rows():
		if r.group != group:
			group = r.group
			rec.add_child(_label(group))
		rec.add_child(_record_control(r))
	var look := _section("Overlay and graph look")
	for spec: Array in LOOK:
		look.add_child(_look_control(spec))
	var reset := _button("Look back to default", false)
	reset.pressed.connect(reset_look)
	look.add_child(reset)


## A collapsible block: a toggle button that shows or hides the VBox it returns.
func _section(title: String) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override(&"separation", 4)
	var head := _button(title + "  (show)", false)
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		head.text = title + ("  (hide)" if body.visible else "  (show)"))
	add_child(head)
	add_child(body)
	return body


func _record_control(r: Dictionary) -> Control:
	var key: String = r.key
	var box := HBoxContainer.new()
	box.tooltip_text = "%s (cost: %s). Setting profiler_%s." % [r.what, r.cost, key]
	var c: Control
	match r.kind:
		"bool":
			var cb := CheckBox.new()
			cb.text = r.label
			cb.button_pressed = bool(_profiler.config.get(key))
			cb.toggled.connect(func(on: bool) -> void: _put(key, "1" if on else "0"))
			c = cb
			box.add_child(cb)
		"number":
			box.add_child(_label(r.label))
			var sb := _spin(r.min, r.max, r.step, float(_profiler.config.get(key)))
			var whole := typeof(_profiler.config.get(key)) == TYPE_INT
			sb.value_changed.connect(func(v: float) -> void: _put(key, str(int(v)) if whole else str(v)))
			c = sb
			box.add_child(sb)
		_:
			box.add_child(_label(r.label))
			var le := LineEdit.new()
			le.placeholder_text = "group, group:prefix"
			le.custom_minimum_size.x = 180
			le.text = _profiler.config.text_of(key)
			le.text_submitted.connect(func(t: String) -> void: _put(key, t))
			le.focus_exited.connect(func() -> void: _put(key, le.text))
			c = le
			box.add_child(le)
	controls[key] = c
	return box


func _look_control(spec: Array) -> Control:
	var key: String = spec[0]
	var box := HBoxContainer.new()
	var c: Control
	match spec[2]:
		"bool":
			var cb := CheckBox.new()
			cb.text = spec[1]
			cb.button_pressed = bool(_profiler.config.get(key))
			cb.toggled.connect(func(on: bool) -> void: _put(key, "1" if on else "0"))
			c = cb
			box.add_child(cb)
		"corner":
			box.add_child(_label(spec[1]))
			var ob := OptionButton.new()
			for corner in DotProfilerConfig.CORNERS:
				ob.add_item(corner.replace("_", " "))
			ob.selected = maxi(DotProfilerConfig.CORNERS.find(_profiler.config.overlay_corner), 0)
			ob.item_selected.connect(func(i: int) -> void: _put(key, DotProfilerConfig.CORNERS[i]))
			c = ob
			box.add_child(ob)
		_:
			box.add_child(_label(spec[1]))
			var sb := _spin(float(spec[3]), float(spec[4]), float(spec[5]), float(_profiler.config.get(key)))
			sb.value_changed.connect(func(v: float) -> void: _put(key, str(v) if spec[2] == "float" else str(int(v))))
			c = sb
			box.add_child(sb)
	controls[key] = c
	return box


func _spin(lo: float, hi: float, step: float, value: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	return sb


## Sets one setting from a control; a refused value is put back in the control.
func _put(key: StringName, text: String) -> void:
	if _syncing:
		return
	var res := _profiler.config.set_text(String(key), text)
	if not res.ok:
		_show_result(res.error.message)
		_sync()
		return
	if DotProfilerConfig.UI_KEYS.has(String(key)):
		var _e := _profiler.save_ui_prefs()


## Puts every control back in step with the config (after a console change, a preset or a refusal).
func _sync() -> void:
	_syncing = true
	var c := _profiler.config
	overlay_toggle.button_pressed = c.overlay
	for key: String in controls:
		var ctl: Control = controls[key]
		var v: Variant = c.get(key)
		if ctl is CheckBox:
			(ctl as CheckBox).button_pressed = bool(v)
		elif ctl is SpinBox:
			(ctl as SpinBox).value = float(v)
		elif ctl is OptionButton:
			(ctl as OptionButton).selected = maxi(DotProfilerConfig.CORNERS.find(String(v)), 0)
		elif ctl is LineEdit and not (ctl as LineEdit).has_focus():
			(ctl as LineEdit).text = c.text_of(key)
	_syncing = false


func _preset(cheap_only: bool) -> void:
	DotProfilerCatalog.set_all(_profiler.config, true, cheap_only)
	if cheap_only:
		for r in DotProfilerCatalog.rows():
			if r.cost in ["high", "medium"] and r.kind != "text":
				var _s := _profiler.config.set_text(r.key, "0")
	_sync()


## Puts every look setting back to the default (small, translucent, top left) and saves.
func reset_look() -> void:
	var fresh := DotProfilerConfig.new()
	for key in DotProfilerConfig.UI_KEYS:
		if key != "overlay":
			var _r := _profiler.config.set_text(key, fresh.text_of(key))
	var _e := _profiler.save_ui_prefs()
	_sync()


## Opens the list of everything the profiler records (see [DotProfilerCatalog]); closes it when open.
func open_catalog() -> void:
	if _catalog != null and is_instance_valid(_catalog):
		_catalog.queue_free()
		_catalog = null
		return
	_catalog = DotProfilerCatalogView.new()
	_catalog.profiler = _profiler
	add_child(_catalog)


## Record when idle, Stop when recording: what the button does.
func press_record() -> void:
	var res := _profiler.stop_recording() if _profiler.is_recording() else _profiler.start_recording()
	if not res.ok:
		_show_result("Could not: " + res.error.message)
	_refresh()


## Opens the recordings folder in the system file browser.
func open_folder() -> void:
	var dir := ProjectSettings.globalize_path(_profiler.config.record_dir)
	var _m := DotPaths.ensure_dir(_profiler.config.record_dir)
	var err := OS.shell_open(dir)
	if err != OK:
		_show_result("Cannot open %s here: %s. Use Copy path." % [dir, error_string(err)])


## Puts the last report's full path on the clipboard.
func copy_path() -> void:
	var p := _profiler.last_saved_path()
	if p == "":
		return
	DisplayServer.clipboard_set(ProjectSettings.globalize_path(p))
	_show_result("Copied " + ProjectSettings.globalize_path(p))


## In the browser, hands the last text report to the page as a download.
func download_last() -> void:
	var p := _profiler.last_saved_path()
	if p == "":
		return
	var text := DotPaths.read_text(p.get_basename() + ".txt")
	if not text.ok:
		_show_result("Cannot read the report: " + text.error.message)
		return
	var sent := DotWeb.download_text(text.value, p.get_file().get_basename() + ".txt")
	if not sent.ok:
		_show_result("Cannot hand the report to the browser: " + sent.error.message)


func _tick() -> void:
	if _profiler != null and _profiler.is_recording():
		elapsed_label.text = "Recording  %.1f / %.0f s" % [_profiler.elapsed_s(), _profiler.recording_length_s()]


func _on_started(_seconds: float) -> void:
	_refresh()
	_tick()


func _on_finished(res: DotResult) -> void:
	if res.ok:
		_show_result("Saved to %s (and .txt beside it)" % ProjectSettings.globalize_path(res.value))
	else:
		_show_result("Not saved: " + res.error.message)
	_refresh()


func _refresh() -> void:
	var rec := _profiler.is_recording()
	record_button.text = "Stop" if rec else "Record profile"
	if not rec:
		elapsed_label.text = "Records %.0f s of frames and what each system cost." % _profiler.config.record_seconds
	var has_last := _profiler.last_saved_path() != ""
	for b in [open_button, copy_button, download_button]:
		if b != null:
			(b as Button).disabled = not has_last and b != open_button
	var recent := _profiler.recent_recordings(5)
	if recent.is_empty():
		recent_label.text = "No recordings on this device yet."
	else:
		var lines := PackedStringArray(["Recent recordings:"])
		for r in recent:
			lines.append("  %s  (%s)" % [r.name, DotPaths.format_bytes(r.bytes)])
		recent_label.text = "\n".join(lines)


func _show_result(text: String) -> void:
	result_label.text = text
	result_label.visible = true


func _button(text: String, primary: bool) -> Button:
	var m := &"primary_button" if primary else &"secondary_button"
	if _kit != null and _kit.has_method(m):
		return _kit.call(m, text)
	var b := Button.new()
	b.text = text
	return b


func _label(text: String) -> Label:
	if _kit != null and _kit.has_method(&"paragraph"):
		return _kit.call(&"paragraph", text)
	var l := Label.new()
	l.text = text
	return l
