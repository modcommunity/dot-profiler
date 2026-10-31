extends SceneTree

## Renders dot-menu's stock Advanced page with a DotProfiler placed, scrolled to its Performance card.
## `godot --path . --script tools/menu_tab_shot.gd -- <out.png>`; needs a renderer (xvfb-run or a GPU box).

const DIR := "user://menu_tab_shot"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "screenshots/menu_tab.png"
	var schema := DotSettingsSchema.new()
	DotMenuStock.declare(schema)
	var settings := DotMenuStock.manager(schema, DIR, &"menu_tab_shot", &"")
	root.add_child(settings)
	var _loaded := settings.setup()
	var prof := DotProfiler.new()
	prof.config = DotProfilerConfig.new()
	prof.config.record_dir = DIR + "/profiles"
	root.add_child(prof)
	var menu := DotMenu.new()
	menu.settings = settings
	menu.manage_pointer = false
	root.add_child(menu)
	var _set := menu.setup()
	for f in 4:
		await process_frame
	var rec := prof.start_recording(1.0)
	while prof.is_recording():
		await process_frame
	menu.open(&"advanced")
	for f in 6:
		await process_frame
	var perf := menu.find_child("Performance", true, false) as Control
	var p: Node = perf
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p != null and perf != null:
		(p as ScrollContainer).ensure_control_visible(perf)
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out)
	print("menu_tab_shot: %s (%s) performance=%s recording=%s %s" % [out, error_string(err), perf != null, rec.ok, prof.describe()])
	var _c := DotPaths.remove_tree(DIR)
	quit(0 if err == OK and perf != null else 1)
