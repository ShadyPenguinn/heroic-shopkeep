class_name Ui
extends RefCounted
## Small builders and wording shared by the shop screens, so every panel,
## stat line and colour reads the same everywhere.

const TIER_COLORS := {1: Color(0.75, 0.75, 0.78), 2: Color(0.5, 0.78, 1.0), 3: Color(0.86, 0.58, 1.0)}
const TIER_NAMES := {1: "Iron", 2: "Steel", 3: "Mythril"}
const RARITY_COLORS := {"common": Color(0.8, 0.8, 0.8), "uncommon": Color(0.45, 0.9, 0.5), "rare": Color(0.55, 0.7, 1.0)}
const BAND_COLORS := {"safe": Color(0.45, 0.9, 0.5), "risky": Color(1.0, 0.8, 0.3), "deadly": Color(1.0, 0.35, 0.35)}
const GOLD := Color(1.0, 0.84, 0.35)
const MUTED := Color(0.62, 0.56, 0.58)
const BAD := Color(1.0, 0.4, 0.4)
const GOOD := Color(0.5, 0.95, 0.55)
const STAT_NAMES := {"might": "Might", "guard": "Guard", "haste": "Haste", "nerve": "Nerve", "luck": "Luck", "hp": "HP"}
const SLOTS := ["weapon", "armor", "charm", "pack"]
const SLOT_NAMES := {"weapon": "Weapon", "armor": "Armor", "charm": "Charm", "pack": "Pack"}


static func panel(bg: Color = UiTheme.PANEL, border: Color = Color(0, 0, 0, 0), margin: int = 4) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_content_margin_all(margin)
	s.set_corner_radius_all(2)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	p.add_theme_stylebox_override("panel", s)
	return p


static func label(text: String, color: Color = UiTheme.INK, font_size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(bbcode: String = "", font_size: int = 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	if font_size > 0:
		r.add_theme_font_size_override("normal_font_size", font_size)
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bbcode
	return r


static func button(text: String, cb: Callable, min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	Juice.bind_button(b)
	return b


static func hex(c: Color) -> String:
	return c.to_html(false)


static func tier_color(db: ContentDB, gear: Dictionary) -> Color:
	var def := Gear.def_of(db, gear)
	if def.get("slot", "") == "pack":
		return Color(0.9, 0.6, 0.9)
	return TIER_COLORS.get(int(def.get("tier", 1)), TIER_COLORS[1])


static func signed(n: float) -> String:
	return ("+%d" if n >= 0 else "%d") % int(n)


## Item details as BBCode: name, kind, stats, sockets and mods, story, value.
## price: >= 0 shows a price, -1 shows what it's worth, -2 shows neither.
static func item_text(db: ContentDB, gear: Dictionary, price: int = -1) -> String:
	var def := Gear.def_of(db, gear)
	var lines: PackedStringArray = []
	lines.append("[color=#%s]%s[/color]" % [hex(tier_color(db, gear)), Gear.display_name(db, gear)])
	if def.get("slot", "") == "pack":
		lines.append("[color=#%s]Potion, pack slot[/color]" % hex(MUTED))
		var pot: Dictionary = def.get("potion", {})
		match pot.get("kind", ""):
			"heal":
				lines.append("Drunk below %d%% HP: heals %d%%." % [roundi(float(pot.get("below", 0.35)) * 100), roundi(float(pot.amount) * 100)])
			"haste":
				lines.append("+%d Haste for the whole delve." % int(pot.amount))
			"courage":
				lines.append("Holds their nerve %d%% longer." % roundi(float(pot.amount) * 100))
	else:
		var kind: String = def.get("kind", def.get("slot", ""))
		lines.append("[color=#%s]%s %s[/color]" % [hex(MUTED), TIER_NAMES.get(int(def.get("tier", 1)), ""), kind.capitalize()])
		var stats: Dictionary = def.get("stats", {})
		var parts: PackedStringArray = []
		for k in STAT_NAMES:
			if stats.has(k) and int(stats[k]) != 0:
				var c := GOOD if int(stats[k]) > 0 else BAD
				parts.append("[color=#%s]%s %s[/color]" % [hex(c), signed(stats[k]), STAT_NAMES[k]])
		if not parts.is_empty():
			lines.append("  ".join(parts))
		var mods: Array = gear.get("mods", [])
		var sockets := int(def.get("sockets", 0))
		var sock_text: PackedStringArray = []
		for m in mods:
			var row := db.get_row("mods", m)
			sock_text.append("[color=#%s]%s[/color] (%s)" % [hex(Color(0.6, 0.9, 1.0)), row.get("name", m), row.get("desc", "")])
		for i in sockets - mods.size():
			sock_text.append("[color=#%s]empty socket[/color]" % hex(MUTED))
		if not sock_text.is_empty():
			lines.append("\n".join(sock_text))
		var h: Dictionary = gear.get("history", {})
		if int(h.get("runs", 0)) > 0:
			lines.append("[color=#%s]%d delves, %d kills, deepest floor %d[/color]" % [hex(MUTED), int(h.runs), int(h.kills), int(h.deepest)])
		if def.get("slot", "") == "weapon":
			var users: PackedStringArray = []
			for c in db.rows("classes"):
				if c.get("weapons", []).has(def.get("kind", "")):
					users.append(c.name)
			lines.append("[color=#%s]Suits: %s[/color]" % [hex(MUTED), ", ".join(users)])
	if price >= 0:
		lines.append("[color=#%s]%d gold[/color]" % [hex(GOLD), price])
	elif price == -1:
		lines.append("[color=#%s]Worth %d gold[/color]" % [hex(MUTED), Gear.value(db, gear)])
	return "\n".join(lines)


static func trait_text(db: ContentDB, hero: Dictionary) -> String:
	var parts: PackedStringArray = []
	for t in hero.get("traits", []):
		var row := db.get_row("traits", t)
		var c: Color = RARITY_COLORS.get(row.get("rarity", "common"), UiTheme.INK)
		parts.append("[color=#%s]%s[/color]" % [hex(c), row.get("name", t)])
	return ", ".join(parts)


static func trait_desc(db: ContentDB, hero: Dictionary) -> String:
	var parts: PackedStringArray = []
	for t in hero.get("traits", []):
		var row := db.get_row("traits", t)
		parts.append("%s (%s): %s" % [row.get("name", t), row.get("rarity", ""), row.get("desc", "")])
	return "\n".join(parts)


static func card_title(db: ContentDB, card: Dictionary) -> String:
	match card.get("kind", ""):
		"gold":
			return "%d gold" % int(card.amount)
		"materials":
			return "%d %s" % [int(card.qty), db.get_row("materials", card.material).get("name", "?")]
		"mod":
			return db.get_row("mods", card.mod).get("name", "Mod")
	return "?"


static func card_color(card: Dictionary) -> Color:
	match card.get("kind", ""):
		"gold":
			return GOLD
		"materials":
			return Color(0.85, 0.7, 0.5)
		"mod":
			return Color(0.6, 0.9, 1.0)
	return UiTheme.INK
