extends Control
## Title screen placeholder. The real one (shop at dawn, hero knocking) is a
## Day 25 juice-sprint job; this exists so the flow and transitions work now.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var title := Label.new()
	title.text = str(ProjectSettings.get_setting("application/config/name", "Game"))
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tag := Label.new()
	tag.text = "All loans final. Mostly."
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.modulate = Color(1, 1, 1, 0.6)
	box.add_child(tag)

	var buttons: Array[Button] = []
	if Game.has_save():
		buttons.append(_button(box, "Continue", func():
			if Game.continue_game():
				Router.goto("shop")))
	buttons.append(_button(box, "New season", func():
		Game.new_game()
		Router.goto("shop")))
	buttons.append(_button(box, "Sim sandbox (dev)", func(): Router.goto("sandbox")))
	buttons.append(_button(box, "Quit", func(): get_tree().quit()))

	box.reset_size()
	box.position = (Vector2(640, 360) - box.size) / 2.0
	Juice.slide_in(title, Vector2(0, -12), 0.4)
	for i in buttons.size():
		Juice.slide_in(buttons[i], Vector2(0, 10), 0.3, 0.1 + i * 0.05)
	if not buttons.is_empty():
		buttons[0].grab_focus.call_deferred()
	Audio.music("title")


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 18)
	b.pressed.connect(on_press)
	parent.add_child(b)
	Juice.bind_button(b)
	return b
