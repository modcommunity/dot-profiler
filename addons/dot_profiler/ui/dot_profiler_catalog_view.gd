class_name DotProfilerCatalogView
extends CanvasLayer

## A full-window list of everything the profiler records: each setting, whether it is on, what it adds to the report and what
## it costs. Built from [DotProfilerCatalog]; closes with its button or Escape.

## The profiler whose settings are listed; set before adding.
var profiler: DotProfiler = null
var text_label: RichTextLabel = null
var close_button: Button = null


func _ready() -> void:
	layer = 130
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := Label.new()
	head.text = "What the profiler records"
	box.add_child(head)
	text_label = RichTextLabel.new()
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.selection_enabled = true
	text_label.text = text(profiler.config)
	box.add_child(text_label)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(queue_free)
	box.add_child(close_button)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


## The whole list as text for [param config].
static func text(config: DotProfilerConfig) -> String:
	var out := PackedStringArray(DotProfilerCatalog.lines(config))
	out.append("")
	out.append("Report: every switched-off report section is left out of the saved JSON and text.")
	return "\n".join(out)
