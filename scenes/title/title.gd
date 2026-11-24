extends Control
## Title screen placeholder. The real one (shop at dawn, hero knocking) is a
## Day 25 juice-sprint job; this exists so the flow and transitions work now.


func _ready() -> void:
	size = get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.06, 0.09)
	bg.size = size
	add_child(bg)

	var center := CenterContainer.new()
	center.size = size
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)

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

	# Containers own their children's positions, so entrances here fade, not slide.
	var items: Array = [title, tag]
	items.append_array(buttons)
	for i in items.size():
		items[i].modulate.a = 0.0
		var t: Tween = items[i].create_tween()
		t.tween_property(items[i], "modulate:a", 1.0, 0.3).set_delay(0.05 + i * 0.06)
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
