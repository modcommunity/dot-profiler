extends Node

## The menu and look options: the catalog, the panel's switches and custom seconds, report sections left out when
## switched off, the overlay's corner, size and opacity, the merged net graph, saved look settings, and the
## in-game options window on Shift+F10.

const SECTIONS := 7
const CHECKS := 36
const DIR := "user://profiler_ui_selftest"

var _sections := 0
var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_catalog()
	_config()
	_graph_and_net()
	await _panel()
	await _overlay()
	await _recording()
	await _window()
	var _c := DotPaths.remove_tree(DIR)
	print("profiler_ui_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	var ok := _failed == 0 and _sections == SECTIONS and _checks == CHECKS
	get_tree().quit(0 if ok else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _profiler() -> DotProfiler:
	var prof := DotProfiler.new()
	prof.register_as_service = false
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR
	prof.config.sample_hz = 0.0
	prof.ui_prefs_file = DIR.path_join("ui.cfg")
	return prof


func _catalog() -> void:
	var c := DotProfilerConfig.new()
	var rows := DotProfilerCatalog.rows()
	var ok := true
	for r in rows:
		ok = ok and c.has_key(r.key) and String(r.what) != "" and not (r.keys as Array).is_empty()
	_check(ok, "every catalog row names a real setting, what it records and the report keys it adds")
	_check(rows.size() >= 15, "the catalog covers the report sections, the collectors and the detail options")
	for k in ["timeline", "render_detail", "census", "script_top", "groups", "deep", "trace", "monitors"]:
		ok = ok and not DotProfilerCatalog.row(k).is_empty()
	_check(ok, "the detail options from the profiler are all listed")
	var text := DotProfilerCatalogView.text(c)
	_check(text.contains("Node census") and text.contains("Native stacks") and text.contains("[on ] Frame time statistics"), "the list reads as text with on and off")
	DotProfilerCatalog.set_all(c, false)
	_check(not c.rec_spikes and not c.timeline and c.worst_frames == 0 and not DotProfilerCatalog.is_on(DotProfilerCatalog.row("rec_spikes"), c), "set_all off switches every row off")
	DotProfilerCatalog.set_all(c, true, true)
	_check(c.rec_spikes and c.timeline and not c.deep and c.script_top == 0, "the cheap set leaves the costly collectors off")
	_sections += 1


func _config() -> void:
	var c := DotProfilerConfig.new()
	_check(not c.overlay and not c.enabled and c.record_seconds == 30.0, "off by default and 30 seconds")
	_check(c.overlay_corner == "top_left" and c.overlay_opacity < 1.0 and c.overlay_text_size <= 12 and c.graph_height == 60, "the default look is small and translucent")
	_check(not c.set_text("overlay_corner", "middle").ok and c.overlay_corner == "top_left", "a corner that does not exist is refused")
	_check(not c.set_text("overlay_opacity", "2").ok and not c.set_text("overlay_scale", "9").ok and not c.set_text("graph_col_px", "0").ok, "out of range look values are refused")
	_check(c.set_text("record_seconds", "0.5").ok and c.set_text("record_seconds", "7200").ok and not c.set_text("record_seconds", "0").ok, "any recording length above zero is allowed")
	_sections += 1


func _graph_and_net() -> void:
	var d := DotProfilerGraphData.new(10)
	d.push_record({"ms": 10.0, "physics": 2.0})
	d.push_net(5.0, 7.0)
	d.push_record({"ms": 10.0, "physics": 2.0})
	_check(d.has_net() and is_equal_approx(d.net_value(0, 1), 5.0) and is_equal_approx(d.net_value(1, 1), 7.0) and d.net_value(0, 0) == 0.0, "net rate is stored with its frame")
	_check(is_equal_approx(d.net_peak(), 7.0), "the net peak scales the lines")
	d.resize(20)
	_check(not d.has_net() and d.net_peak() == 0.0, "resizing clears the net lines")
	var n := DotProfilerNet.new()
	var s := n.sample(get_tree(), 16.0)
	_check(s[0] == 0.0 and s[1] == 0.0, "no metered peer reads zero")
	_sections += 1


func _panel() -> void:
	var prof := _profiler()
	add_child(prof)
	var panel := prof.make_menu_panel(null) as DotProfilerPanel
	add_child(panel)
	await get_tree().process_frame
	_check(panel.seconds_box.value == 30.0 and panel.catalog_button != null, "the panel shows 30 seconds and the catalog button")
	panel.seconds_box.value = 4.5
	_check(is_equal_approx(prof.config.record_seconds, 4.5), "the seconds box sets any length")
	(panel.controls["timeline"] as CheckBox).button_pressed = true
	(panel.controls["rec_queries"] as CheckBox).button_pressed = false
	(panel.controls["script_top"] as SpinBox).value = 25
	_check(prof.config.timeline and not prof.config.rec_queries and prof.config.script_top == 25, "switches and numbers write the settings")
	(panel.controls["overlay_scale"] as SpinBox).value = 1.5
	(panel.controls["overlay_corner"] as OptionButton).select(3)
	(panel.controls["overlay_corner"] as OptionButton).item_selected.emit(3)
	_check(is_equal_approx(prof.config.overlay_scale, 1.5) and prof.config.overlay_corner == "bottom_right", "look controls write the settings")
	_check(FileAccess.file_exists(prof.ui_prefs_file), "look changes are saved")
	var again := _profiler()
	var _l := again.load_ui_prefs()
	again.config = DotProfilerConfig.new()
	_l = again.load_ui_prefs()
	_check(_l and is_equal_approx(again.config.overlay_scale, 1.5) and again.config.overlay_corner == "bottom_right" and again.config.record_seconds == 30.0, "saved look is read back, recording options are not")
	again.free()
	prof.config.set_text("graph_height", "100")
	panel._sync()
	_check((panel.controls["graph_height"] as SpinBox).value == 100.0, "a console change shows in the panel")
	panel.open_catalog()
	await get_tree().process_frame
	var view := panel._catalog as DotProfilerCatalogView
	_check(view != null and view.text_label.text.contains("Timeline"), "the button opens the list")
	panel.reset_look()
	_check(prof.config.overlay_corner == "top_left" and prof.config.graph_height == 60 and prof.config.timeline, "look back to default leaves recording options alone")
	panel.queue_free()
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1


func _overlay() -> void:
	var prof := _profiler()
	prof.config.overlay = true
	add_child(prof)
	var net_stat := Control.new()
	net_stat.name = "NetStat"
	add_child(net_stat)
	await get_tree().process_frame
	var ov: DotProfilerOverlay = null
	for ch in prof.get_children():
		if ch is DotProfilerOverlay:
			ov = ch
	ov.refresh()
	_check(ov != null and not net_stat.visible, "with the graph on, the separate net readout is hidden")
	var bg := ov.get_child(0) as Control
	prof.config.set_text("overlay_scale", "2")
	prof.config.set_text("overlay_opacity", "0.4")
	prof.config.set_text("overlay_corner", "bottom_right")
	_check(bg.scale == Vector2(2, 2) and is_equal_approx(bg.modulate.a, 0.4), "scale and opacity apply live")
	var view := Vector2(1000, 800)
	var size := Vector2(300, 100)
	_check(DotProfilerOverlay.corner_pos("top_left", view, size, 12, 12) == Vector2(12, 12)
		and DotProfilerOverlay.corner_pos("bottom_right", view, size, 12, 20) == Vector2(688, 680)
		and DotProfilerOverlay.corner_pos("top_right", view, size, 0, 0) == Vector2(700, 0)
		and DotProfilerOverlay.corner_pos("bottom_left", Vector2(100, 50), size, 0, 0) == Vector2(0, 0), "each corner places the panel and stays on screen")
	prof.config.set_text("overlay_merge_net", "0")
	_check(net_stat.visible, "unmerged, the net readout comes back")
	prof.config.set_text("overlay_merge_net", "1")
	prof.config.set_text("overlay", "0")
	await get_tree().process_frame
	_check(net_stat.visible, "closing the overlay returns the net readout")
	net_stat.queue_free()
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1


func _recording() -> void:
	var prof := _profiler()
	prof.config.set_text("rec_queries", "0")
	prof.config.set_text("rec_growth", "0")
	prof.config.set_text("rec_spikes", "0")
	add_child(prof)
	var _s := prof.start_recording(0.3)
	var res: DotResult = await prof.recording_finished
	var r: Dictionary = DotPaths.read_json(res.value).value if res.ok else {}
	_check(res.ok and r.has("frame_stats") and not r.has("growth") and not r.has("queries") and not r.has("spikes"), "switched-off report sections are left out")
	_check(is_equal_approx(float(r.get("seconds", 0.0)), 0.3), "a custom length is recorded")
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1


func _key(keycode: Key, shift: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.shift_pressed = shift
	ev.pressed = true
	return ev


func _window() -> void:
	var prof := _profiler()
	add_child(prof)
	prof.enable_capture_key()
	var menu_ev := InputMap.action_get_events(DotProfiler.MENU_ACTION)
	_check(menu_ev.size() == 1 and (menu_ev[0] as InputEventKey).shift_pressed and (menu_ev[0] as InputEventKey).keycode == KEY_F10
		and InputMap.has_action(DotProfiler.CAPTURE_ACTION), "the capture key brings Shift+F10 for the options window")
	var seen: Array[bool] = []
	get_viewport().push_input(_key(KEY_F10, true))
	await get_tree().process_frame
	var win := DotProfilerWindow.of(prof)
	if win != null:
		win.pointer_mode_changed.connect(func(on: bool) -> void: seen.append(on))
	_check(prof.is_menu_open() and win.is_in_group(&"dot_pointer_modal") and win.panel != null and not prof.is_recording(),
		"Shift+F10 opens the window as a pointer modal, and does not start a capture")
	(win.panel.controls["graph_scale_ms"] as SpinBox).value = 40.0
	_check(is_equal_approx(prof.config.graph_scale_ms, 40.0) and DotProfilerConfig.UI_KEYS.has("graph_scale_ms"), "the graph's top is a look option and saved")
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	await get_tree().process_frame
	_check(not prof.is_menu_open() and seen.size() == 1 and not seen[0], "Esc closes the window and gives the mouse back")
	var opened := prof.toggle_menu()
	var closed := not prof.toggle_menu()
	await get_tree().process_frame
	_check(opened and closed and get_tree().get_nodes_in_group(&"dot_pointer_modal").is_empty(), "toggle_menu opens and closes, leaving nothing behind")
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1
