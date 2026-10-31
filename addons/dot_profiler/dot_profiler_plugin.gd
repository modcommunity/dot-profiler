@tool
extends EditorPlugin

## Editor entry point for dot-profiler. No autoloads: a game places one DotProfiler where it wants one.


func _enter_tree() -> void:
	add_custom_type("DotProfiler", "Node", load("res://addons/dot_profiler/runtime/dot_profiler.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("DotProfiler")
