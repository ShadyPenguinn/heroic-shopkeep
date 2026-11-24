extends CanvasLayer
## Scene changes with a fade, so the game never hard-cuts.
##   Router.goto("shop")   or   Router.goto("res://scenes/...tscn")

const SCENES := {
	"title": "res://scenes/title/title.tscn",
	"shop": "res://scenes/shop/shop.tscn",
	"sandbox": "res://scenes/dev/sim_sandbox.tscn",
}

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.03, 0.07)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)


func goto(scene: String, duration: float = 0.25) -> void:
	if _busy:
		return
	_busy = true
	var path: String = SCENES.get(scene, scene)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween().set_ignore_time_scale()
	t.tween_property(_fade, "modulate:a", 1.0, duration)
	await t.finished
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	t = create_tween().set_ignore_time_scale()
	t.tween_property(_fade, "modulate:a", 0.0, duration)
	await t.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
