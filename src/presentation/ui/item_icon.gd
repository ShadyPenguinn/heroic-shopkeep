class_name ItemIcon
extends Control
## A little vector icon for a piece of gear, drawn from its slot and kind until
## the real item art arrives. Tier sets the metal colour; potions use their kind.

const METAL := {1: Color(0.72, 0.72, 0.76), 2: Color(0.55, 0.78, 1.0), 3: Color(0.85, 0.6, 1.0)}
const WOOD := Color(0.62, 0.42, 0.26)
const POTION := {"heal": Color(0.95, 0.3, 0.35), "haste": Color(0.4, 0.85, 1.0), "courage": Color(1.0, 0.8, 0.3)}

var def: Dictionary = {}:
	set(v):
		def = v
		queue_redraw()


func _init(item_def: Dictionary = {}) -> void:
	def = item_def
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(16, 16)


func _draw() -> void:
	if def.is_empty():
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s / 16.0
	var w := maxf(1.0, s / 16.0)
	var metal: Color = METAL.get(int(def.get("tier", 1)), METAL[1])
	match def.get("slot", ""):
		"weapon":
			match def.get("kind", ""):
				"blade":
					draw_line(p.call(3, 13), p.call(12, 4), metal, 2 * w)
					draw_line(p.call(3, 9), p.call(7, 13), WOOD.lightened(0.2), 1.5 * w)
					draw_line(p.call(2, 14), p.call(4, 12), WOOD, 2 * w)
				"spear":
					draw_line(p.call(2, 14), p.call(11, 5), WOOD, 1.5 * w)
					draw_colored_polygon(PackedVector2Array([p.call(14, 2), p.call(9, 5), p.call(11, 7)]), metal)
				"axe":
					draw_line(p.call(4, 14), p.call(10, 3), WOOD, 1.5 * w)
					draw_colored_polygon(PackedVector2Array([p.call(8, 4), p.call(14, 3), p.call(14, 9), p.call(10, 8)]), metal)
				"bow":
					draw_arc(p.call(5, 8), 7 * s / 16.0, -PI / 2.2, PI / 2.2, 12, WOOD.lightened(0.1), 1.5 * w)
					draw_line(p.call(8, 1.5), p.call(8, 14.5), metal, w)
				"staff":
					draw_line(p.call(4, 14), p.call(10, 5), WOOD, 1.5 * w)
					draw_circle(p.call(11, 4), 2.5 * s / 16.0, metal)
				_:
					draw_line(p.call(3, 13), p.call(13, 3), metal, 2 * w)
		"armor":
			draw_colored_polygon(PackedVector2Array([p.call(4, 3), p.call(6, 2), p.call(8, 4), p.call(10, 2), p.call(12, 3), p.call(13, 7), p.call(11, 7), p.call(11, 14), p.call(5, 14), p.call(5, 7), p.call(3, 7)]), metal.darkened(0.15))
			draw_line(p.call(8, 5), p.call(8, 13), metal.lightened(0.3), w)
		"charm":
			draw_arc(p.call(8, 9), 4 * s / 16.0, 0, TAU, 16, metal, 1.5 * w)
			draw_line(p.call(8, 2), p.call(8, 5), metal.darkened(0.3), w)
			draw_circle(p.call(8, 9), 1.5 * s / 16.0, Color(1.0, 0.85, 0.35))
		"pack":
			var c: Color = POTION.get(def.get("potion", {}).get("kind", ""), Color.WHITE)
			draw_circle(p.call(8, 10), 4.5 * s / 16.0, c)
			draw_rect(Rect2(p.call(6.5, 2.5), Vector2(3, 4) * s / 16.0), Color(0.85, 0.85, 0.9, 0.9))
			draw_circle(p.call(6.5, 9), 1.2 * s / 16.0, Color(1, 1, 1, 0.6))
