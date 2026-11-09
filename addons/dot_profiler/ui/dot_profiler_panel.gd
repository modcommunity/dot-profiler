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

var _profiler: DotProfiler = null
var _kit: Object = null


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
	# A timer, not _process: the elapsed text changes a few times a second, not per frame.
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true  # setup runs before the panel is in the tree, so start() would error
	timer.timeout.connect(_tick)
	add_child(timer)
	profiler.recording_started.connect(_on_started)
	profiler.recording_finished.connect(_on_finished)
	_refresh()


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
