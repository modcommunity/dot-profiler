class_name DotProfilerWindow
extends CanvasLayer

## The profiler's options as a window over the running game (Shift+F10 or profiler_menu): the same panel as the
## settings menu, reachable while playing. It is a dot_pointer_modal, so game clients leave the mouse free while it is up.

## Emitted true when the window frees the mouse, false when it gives it back (the dot_pointer_modal contract).
signal pointer_mode_changed(on: bool)

const GROUP := &"dot_pointer_modal"
const WIDTH := 460.0
const MARGIN := 20.0

## The profiler shown; set before adding.
var profiler: DotProfiler = null
var panel: DotProfilerPanel = null
var close_button: Button = null

var _open := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	# Joined before entering the tree, so whoever watches node_added for the group sees it at once.
	add_to_group(GROUP)


func _ready() -> void:
	layer = 121
	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -WIDTH - MARGIN
	frame.offset_right = -MARGIN
	frame.offset_top = MARGIN
	frame.offset_bottom = -MARGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override(&"panel", style)
	add_child(frame)
	var box := VBoxContainer.new()
	frame.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Profiler   (Shift+F10 or Esc closes)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close_menu)
	head.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	panel = profiler.make_menu_panel(null) as DotProfilerPanel
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open = true
	pointer_mode_changed.emit(true)


## The window open on [param profiler], or null.
static func of(profiler: Node) -> DotProfilerWindow:
	for ch in profiler.get_children():
		if ch is DotProfilerWindow and (ch as DotProfilerWindow).is_pointer_mode():
			return ch as DotProfilerWindow
	return null


## Opens a window on [param profiler], or closes the open one. True when one is now open.
static func toggle(profiler: DotProfiler) -> bool:
	var open := of(profiler)
	if open != null:
		open.close_menu()
		return false
	var w := DotProfilerWindow.new()
	w.profiler = profiler
	profiler.add_child(w)
	return true


## Binds Shift+[param keycode] to [param action] when the project has no binding for it.
static func bind_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.shift_pressed = true
		InputMap.action_add_event(action, ev)


## True while the window is up and the mouse is a pointer.
func is_pointer_mode() -> bool:
	return _open


## Gives the mouse back as it was and removes the window.
func close_menu() -> void:
	if not _open:
		return
	_open = false
	# A browser refuses capture outside a click; the game recaptures on the next one.
	if OS.get_name() != "Web":
		Input.mouse_mode = _mouse_before
	pointer_mode_changed.emit(false)
	queue_free()


func _exit_tree() -> void:
	if _open:
		_open = false
		pointer_mode_changed.emit(false)


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()
