class_name UiTheme
extends RefCounted
## The global UI theme, built in code until the real UI skin arrives (Day 15).
## Drop a pixel font at assets/fonts/body.ttf (for example m5x7) and it is used
## automatically. Keep one pixel scale: font sizes should be multiples of the
## font's native size.

const BODY_FONT := "res://assets/fonts/body.ttf"
const BODY_SIZE := 10

const INK := Color(0.93, 0.89, 0.8)
const PANEL := Color(0.16, 0.12, 0.15)
const PANEL_LIGHT := Color(0.26, 0.2, 0.22)
const ACCENT := Color(0.95, 0.72, 0.3)


## Applies the theme to the engine's default theme, so every Control uses it,
## including ones under a CanvasLayer (theme inheritance stops at CanvasLayers).
static func install() -> void:
	var base := ThemeDB.get_default_theme()
	var ours := build()
	base.merge_with(ours)
	base.default_font_size = ours.default_font_size
	if ours.default_font:
		base.default_font = ours.default_font
	ThemeDB.fallback_font_size = ours.default_font_size


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = BODY_SIZE
	if ResourceLoader.exists(BODY_FONT):
		t.default_font = load(BODY_FONT)
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_stylebox("normal", "Button", _box(PANEL_LIGHT))
	t.set_stylebox("hover", "Button", _box(PANEL_LIGHT.lightened(0.15)))
	t.set_stylebox("pressed", "Button", _box(PANEL_LIGHT.darkened(0.2)))
	t.set_stylebox("disabled", "Button", _box(PANEL.darkened(0.2)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL))
	return t


static func _box(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_content_margin_all(4)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s
