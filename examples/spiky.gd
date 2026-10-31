extends Node

## A scene with one system that costs 30 ms every 0.5 s and reports it: the headless runner's target in CI.


var _next := 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next:
		return
	_next = now + 0.5
	var t := DotFrameCost.now()
	OS.delay_msec(30)
	DotFrameCost.add(&"spiky.rebuild", t, "every half second")
