extends Control

## Record and Stop through the settings panel in a browser, and whether the written report is still there after a reload.
## `?press=1` presses Record, waits, presses Stop; any load publishes `window.dotWeb.published.prof` (JSON) = {recent, saved, failures, web} for a driver.

const DIR := "user://profiler_web"

var _prof: DotProfiler = null
var _panel: DotProfilerPanel = null


func _ready() -> void:
	var kit := DotMenuKit.new()
	theme = kit.theme()
	add_child(kit.backdrop())
	_prof = DotProfiler.new()
	_prof.config = DotProfilerConfig.new()
	_prof.config.record_dir = DIR
	_prof.config.overlay = true
	add_child(_prof)
	var card := kit.card()
	card.position = Vector2(440, 120)
	card.custom_minimum_size = Vector2(780, 0)
	add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	body.add_child(kit.section("Performance"))
	_panel = _prof.make_menu_panel(kit) as DotProfilerPanel
	body.add_child(_panel)
	_publish("")
	if DotWeb.available() and DotWeb.query_param("press") == "1":
		_press.call_deferred()


func _press() -> void:
	for i in 30:
		await get_tree().process_frame
	_panel.press_record()
	await get_tree().create_timer(2.0).timeout
	var recording_mid := _prof.is_recording()
	_panel.press_record()
	for i in 30:
		await get_tree().process_frame
	_publish("mid_recording=%s" % recording_mid)


func _publish(note: String) -> void:
	var recent := _prof.recent_recordings(20)
	var body := JSON.stringify({"recent": recent.size(), "saved": _prof.last_saved_path(),
		"failures": DotWeb.sync_failures(), "note": note, "done": note != "" or true})
	print("web_record: ", body)
	DotWeb.publish("prof", body)
