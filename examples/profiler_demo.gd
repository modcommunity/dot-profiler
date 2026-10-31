extends Control

## The overlay and the settings panel after a short recording of a system that spikes on a beat.
## `-- --shot out.png` saves a frame once the recording is written, then quits.

const DIR := "user://profiler_demo"

var _prof: DotProfiler = null
var _next := 0.0


func _ready() -> void:
	var kit := DotMenuKit.new()
	theme = kit.theme()
	add_child(kit.backdrop())
	_prof = DotProfiler.new()
	_prof.config = DotProfilerConfig.new()
	_prof.config.budget_ms = 25.0
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
	body.add_child(_prof.make_menu_panel(kit))
	var _r := _prof.start_recording(2.5)
	_prof.recording_finished.connect(_on_finished)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _prof.is_recording() or now < _next:
		return
	_next = now + 0.5
	var t := DotFrameCost.now()
	OS.delay_msec(35)
	DotFrameCost.add(&"demo.minimap", t, "redraw")


func _on_finished(_res: DotResult) -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i < 0 or i + 1 >= args.size():
		return
	for f in 30:
		await get_tree().process_frame
	_prof.get_children().filter(func(n: Node) -> bool: return n is DotProfilerOverlay).map(func(o: Node) -> Variant: return o.call(&"refresh"))
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(args[i + 1])
	print("profiler_demo: shot %s (%s) %s" % [args[i + 1], error_string(err), _prof.describe()])
	var _c := DotPaths.remove_tree(DIR)
	get_tree().quit(0 if err == OK else 1)
