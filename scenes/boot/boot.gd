extends Node
## First scene. Autoloads are ready by now (content, platform, settings).
## If the data files have errors, show them on screen instead of starting:
## a designer editing JSON should see the typo, not a silent bug.


func _ready() -> void:
	await get_tree().process_frame
	if not Content.db.is_valid():
		_show_errors(Content.db.errors)
		return
	Router.goto("title", 0.15)


func _show_errors(errors: PackedStringArray) -> void:
	var label := Label.new()
	label.text = "Content errors in data/*.json:\n\n" + "\n".join(errors)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector2(8, 8)
	label.size = Vector2(624, 344)
	label.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	add_child(label)
