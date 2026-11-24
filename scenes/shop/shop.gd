extends Node2D
## The shop: the whole day loop the player actually plays.
##
##   Counter (OUTFIT)  pick gear off the shelves and put it on heroes, order the
##                     stack, choose a floor, read the odds, visit the merchant
##                     or the workbench, then send the party.
##   Delve             watch the party's run (speed and skip).
##   Dusk              every survivor lays out their haul; take one card each.
##   Close up          rent, then the next morning.
##
## Built in code with the simple placeholder look until the real UI skin lands.
## Rules live in Season; this scene only calls Game and redraws.

const SHELF_COLS := 5
const TILE := 36
const ESTIMATE_SAMPLES := 120

var db: ContentDB
var playback: RunPlayback
var auto_bot := AutoPlayer.new()

var _layer: CanvasLayer
var _root: Control
var _top_day: Label
var _top_gold: Label
var _top_rent: Label
var _top_merchant: Label
var _gold_shown := -1
var _screen: Control
var _overlay: Control
var _info: RichTextLabel
var _info_actions: HBoxContainer
var _toast: Label

var _held := ""                 # uid of the shelf item the player picked up
var _estimate: Dictionary = {}
var _estimate_dirty := true
var _report: Array = []         # dusk report for the day (outcomes, level ups, lost gear)
var _busy := false


var st: GameState:
	get:
		return Game.state


func _ready() -> void:
	db = Content.db
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	Juice.register_camera(cam)
	playback = RunPlayback.new()
	playback.position = Vector2(0, 0)
	playback.visible = false
	add_child(playback)

	_layer = CanvasLayer.new()
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	_build_top_bar()
	_toast = Ui.label("", UiTheme.ACCENT, 10)
	_toast.position = Vector2(0, 340)
	_toast.size = Vector2(640, 14)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.z_index = 50
	_root.add_child(_toast)

	if Game.state == null:
		Game.new_game()
	Audio.music("shop")
	_enter_phase()


# --- flow --------------------------------------------------------------------------

func _enter_phase() -> void:
	_close_overlay()
	match st.phase:
		GameState.Phase.MORNING:
			Game.start_day()
			_held = ""
			_estimate_dirty = true
			_build_counter()
			_morning_banner()
		GameState.Phase.OUTFIT:
			_build_counter()
		GameState.Phase.DELVE:
			_play_delve()
		GameState.Phase.DUSK:
			_build_dusk()
		GameState.Phase.WON, GameState.Phase.LOST:
			_build_season_end()
	_refresh_top()


func _set_screen(c: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = c
	_root.add_child(c)
	_root.move_child(c, 0)


# --- top bar -------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := Ui.panel(UiTheme.PANEL.darkened(0.3), Color(0, 0, 0, 0), 2)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(640, 18)
	_root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)
	_top_day = Ui.label("", UiTheme.ACCENT)
	_top_gold = Ui.label("", Ui.GOLD)
	_top_rent = Ui.label("")
	_top_merchant = Ui.label("", Ui.MUTED)
	for l in [_top_day, _top_gold, _top_rent, _top_merchant]:
		h.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	h.add_child(Ui.button("Title", func(): Router.goto("title")))


func _refresh_top() -> void:
	if st == null:
		return
	_top_day.text = "Day %d / %d" % [st.day, int(db.bal("season_length", 28))]
	var rent := Season.next_rent(db, st)
	var days_left := int(rent.day) - st.day
	_top_rent.text = "Rent %d due %s" % [rent.amount, "tonight" if days_left == 0 else "in %d days" % days_left]
	_top_rent.add_theme_color_override("font_color", Ui.BAD if st.gold < int(rent.amount) and days_left <= 1 else UiTheme.INK)
	if Season.is_merchant_day(db, st) and st.phase == GameState.Phase.OUTFIT:
		_top_merchant.text = "The merchant is in town!"
		_top_merchant.add_theme_color_override("font_color", Ui.GOLD)
	else:
		_top_merchant.text = "Merchant on day %d" % Season.next_merchant_day(db, st)
		_top_merchant.add_theme_color_override("font_color", Ui.MUTED)
	if _gold_shown < 0 or _gold_shown == st.gold:
		_top_gold.text = "%d gold" % st.gold
	else:
		Juice.roll_number(_top_gold, _gold_shown, st.gold, 0.5, "%d gold")
		Juice.pop(_top_gold, 0.2)
	_gold_shown = st.gold


func _say(text: String, color: Color = UiTheme.ACCENT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	Juice.pop(_toast, 0.15)
	var t := _toast.create_tween()
	t.tween_interval(2.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.5)


# --- the counter ------------------------------------------------------------------------

func _build_counter() -> void:
	playback.visible = false
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_screen(screen)
	screen.add_child(_build_shelves())
	screen.add_child(_build_party_column())
	screen.add_child(_build_side_column())
	if _estimate_dirty:
		_refresh_estimate.call_deferred()


func _rebuild_counter() -> void:
	_estimate_dirty = true
	_build_counter()
	_refresh_top()


## Shelves: everything on the racks, plus the details of the picked/hovered item.
func _build_shelves() -> Control:
	var p := Ui.panel()
	p.position = Vector2(4, 22)
	p.size = Vector2(200, 334)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(Ui.label("Shelves  (%d)" % st.inventory.size(), UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = SHELF_COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	v.add_child(grid)
	var sorted: Array = st.inventory.duplicate()
	sorted.sort_custom(func(a, b): return _gear_sort_key(a) < _gear_sort_key(b))
	for g in sorted:
		grid.add_child(_gear_tile(g, _held == g.uid, func(): _pick_up(g.uid), true))
	if st.inventory.is_empty():
		v.add_child(Ui.label("Empty. Every piece is out\nwith a hero.", Ui.MUTED))
	var sep := HSeparator.new()
	v.add_child(sep)
	_info = Ui.rich()
	_info.custom_minimum_size = Vector2(190, 0)
	v.add_child(_info)
	_info_actions = HBoxContainer.new()
	v.add_child(_info_actions)
	if _held != "":
		_show_gear_info(st.find_gear(_held), true)
	else:
		_info.text = "[color=#%s]Click an item to pick it up, then click a hero to hand it over. Click a hero's item to take it back.[/color]" % Ui.hex(Ui.MUTED)
	return p


func _gear_sort_key(g: Dictionary) -> String:
	var def := Gear.def_of(db, g)
	return "%d%d%s%s" % [Ui.SLOTS.find(def.get("slot", "")), 9 - int(def.get("tier", 1)), def.get("kind", ""), g.uid]


func _gear_tile(g: Dictionary, selected: bool, on_click: Callable, hover_info: bool, tile_size: int = TILE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(tile_size, tile_size)
	b.focus_mode = Control.FOCUS_NONE
	var col := Ui.tier_color(db, g)
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL_LIGHT if not selected else UiTheme.PANEL_LIGHT.lightened(0.25)
	box.set_border_width_all(2 if selected else 1)
	box.border_color = UiTheme.ACCENT if selected else col.darkened(0.3)
	box.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = box.bg_color.lightened(0.12)
	hover.border_color = col
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var icon := ItemIcon.new(Gear.def_of(db, g))
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	b.add_child(icon)
	var mods: Array = g.get("mods", [])
	for i in mods.size():
		var dot := ColorRect.new()
		dot.color = Color(0.6, 0.9, 1.0)
		dot.size = Vector2(3, 3)
		dot.position = Vector2(tile_size - 6 - i * 4, 3)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
	if g.get("title", "") != "":
		var star := ColorRect.new()
		star.color = Ui.GOLD
		star.size = Vector2(3, 3)
		star.position = Vector2(3, 3)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(star)
	b.pressed.connect(on_click)
	if hover_info:
		b.mouse_entered.connect(func(): if _held == "": _show_gear_info(g, false))
	Juice.bind_button(b)
	return b


func _show_gear_info(g: Dictionary, held: bool) -> void:
	if g.is_empty() or _info == null:
		return
	_info.text = Ui.item_text(db, g)
	for c in _info_actions.get_children():
		c.queue_free()
	if held and st.find_gear(g.uid) == g:
		var price := roundi(Gear.value(db, g) * float(db.bal("sell_mult", 0.5)))
		_info_actions.add_child(Ui.button("Sell %dg" % price, func(): _sell(g.uid)))
		_info_actions.add_child(Ui.button("Put down", func():
			_held = ""
			_build_counter()))


func _pick_up(uid: String) -> void:
	_held = "" if _held == uid else uid
	Audio.play("click")
	_build_counter()
	if _held != "":
		_say("Now click a hero to hand it over.", Ui.MUTED)


func _sell(uid: String) -> void:
	var g := st.find_gear(uid)
	var item_name := Gear.display_name(db, g)
	if Game.sell(uid) == "":
		_held = ""
		Audio.play("treasure")
		_say("Sold %s." % item_name, Ui.GOLD)
		_rebuild_counter()


# --- party cards --------------------------------------------------------------------------

func _build_party_column() -> Control:
	var p := Ui.panel()
	p.position = Vector2(208, 22)
	p.size = Vector2(292, 334)
	var outer := VBoxContainer.new()
	p.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	scroll.add_child(v)
	v.add_child(Ui.label("Your party  (%d / %d)   top of the stack takes the most hits" % [st.party.size(), Season.party_size(db)], UiTheme.ACCENT))
	for i in st.party.size():
		v.add_child(_hero_card(st.party[i], i))
	for uid in st.candidates:
		if not st.party.has(uid):
			v.add_child(_hero_card(uid, -1))
	if st.party.is_empty() and st.candidates.is_empty():
		v.add_child(Ui.label("Nobody came in today.", Ui.MUTED))
	return p


func _hero_card(uid: String, slot: int) -> Control:
	var hero: Dictionary = st.roster[uid]
	var walk_in := slot < 0
	var loan := Season.loan_for(st, uid)
	var gear: Array = loan.get("gear", [])
	var s := Hero.combat_stats(db, hero, gear)
	var cls := db.get_row("classes", hero.class_id)

	var border := Color(0.45, 0.75, 1.0) if walk_in else (UiTheme.ACCENT.darkened(0.4) if not gear.is_empty() else Color(0, 0, 0, 0))
	var card := Ui.panel(UiTheme.PANEL_LIGHT.darkened(0.1), border, 3)
	card.custom_minimum_size = Vector2(282, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _held != "":
			_give(uid, _held))
	card.mouse_entered.connect(func(): if _held == "": _show_hero_info(hero, s))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.custom_minimum_size = Vector2(154, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	var tag := "[color=#%s]WALK-IN[/color] " % Ui.hex(Color(0.45, 0.75, 1.0)) if walk_in else "[color=#%s]%d.[/color] " % [Ui.hex(UiTheme.ACCENT), slot + 1]
	left.add_child(Ui.rich("%s%s" % [tag, hero.name]))
	left.add_child(Ui.rich("[color=#%s]Lv %d %s[/color]  %s" % [Ui.hex(Ui.MUTED), int(hero.level), cls.get("name", ""), Ui.trait_text(db, hero)], 8))
	left.add_child(Ui.rich("[color=#%s]HP %d  Might %d  Guard %d  Haste %d[/color]" % [Ui.hex(Ui.MUTED), s.max_hp, s.might, s.guard, s.haste], 8))
	var read := ""
	if gear.is_empty():
		read = "[color=#%s]%s[/color]" % [Ui.hex(Ui.MUTED), "Hand them gear to hire them" if walk_in else "Resting today"]
	elif _estimate.get("heroes", {}).has(uid):
		var e: Dictionary = _estimate.heroes[uid]
		var band: String = e.band
		read = "[color=#%s]%s[/color] [color=#%s]%d%% death, %d%% flee[/color]" % [Ui.hex(Ui.BAND_COLORS[band]), band.to_upper(), Ui.hex(Ui.MUTED), roundi(e.death_rate * 100), roundi(e.retreat_rate * 100)]
	else:
		read = "[color=#%s]reading the odds...[/color]" % Ui.hex(Ui.MUTED)
	left.add_child(Ui.rich(read, 8))

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 2)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(slots)
	for slot_name in Ui.SLOTS:
		var worn := {}
		for g in gear:
			if Gear.def_of(db, g).get("slot", "") == slot_name:
				worn = g
		slots.add_child(_slot_box(uid, slot_name, worn))

	var ctl := VBoxContainer.new()
	ctl.add_theme_constant_override("separation", 1)
	h.add_child(ctl)
	if not walk_in:
		var up := _mini_button("^", func(): _move(uid, slot - 1))
		up.disabled = slot == 0
		ctl.add_child(up)
		var dn := _mini_button("v", func(): _move(uid, slot + 1))
		dn.disabled = slot >= st.party.size() - 1
		ctl.add_child(dn)
		ctl.add_child(_mini_button("x", func(): _let_go(uid)))
	else:
		ctl.add_child(_mini_button("x", func(): _let_go(uid)))
	return card


func _slot_box(uid: String, slot_name: String, worn: Dictionary) -> Control:
	if not worn.is_empty():
		var tile := _gear_tile(worn, false, func(): _take_back(uid, worn.uid), false, 24)
		tile.mouse_entered.connect(func(): if _held == "": _show_gear_info(worn, false))
		return tile
	var b := Button.new()
	b.custom_minimum_size = Vector2(24, 24)
	b.focus_mode = Control.FOCUS_NONE
	b.text = Ui.SLOT_NAMES[slot_name].left(1)
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_color_override("font_color", Ui.MUTED.darkened(0.3))
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL.darkened(0.2)
	box.set_border_width_all(1)
	box.border_color = UiTheme.PANEL_LIGHT
	box.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", box)
	b.tooltip_text = Ui.SLOT_NAMES[slot_name]
	b.pressed.connect(func(): if _held != "": _give(uid, _held))
	return b


func _mini_button(text: String, cb: Callable) -> Button:
	var b := Ui.button(text, cb, Vector2(16, 17))
	b.add_theme_font_size_override("font_size", 8)
	return b


func _show_hero_info(hero: Dictionary, s: Dictionary) -> void:
	if _info == null:
		return
	for c in _info_actions.get_children():
		c.queue_free()
	var cls := db.get_row("classes", hero.class_id)
	var kinds: Array = cls.get("weapons", [])
	_info.text = "%s the %s\n[color=#%s]Lv %d  Bond %d  %d delves, %d kills[/color]\n%s\n[color=#%s]Nerve %d  Luck %d. Heads home below %d%% HP.\nFights with: %s[/color]" % [
		hero.name, cls.get("name", ""), Ui.hex(Ui.MUTED), int(hero.level), int(hero.bond), int(hero.get("runs", 0)), int(hero.get("kills", 0)),
		Ui.trait_desc(db, hero), Ui.hex(Ui.MUTED), s.nerve, s.luck, roundi(s.nerve_threshold * 100), ", ".join(kinds)]


func _give(uid: String, gear_uid: String) -> void:
	var g := st.find_gear(gear_uid)
	var err := Game.equip(uid, gear_uid)
	if err != "":
		Audio.play("whiff")
		_say(err.capitalize() + ".", Ui.BAD)
		return
	_held = ""
	Audio.play("block")
	var def := Gear.def_of(db, g)
	var kinds: Array = db.get_row("classes", st.roster[uid].class_id).get("weapons", [])
	if def.get("slot", "") == "weapon" and not kinds.has(def.get("kind", "")):
		_say("%s can't really use a %s: half strength." % [st.roster[uid].name, def.get("kind", "")], Color(1.0, 0.8, 0.3))
	elif Season.is_candidate(st, uid):
		_say("%s joins the party!" % st.roster[uid].name, Ui.GOOD)
	_rebuild_counter()


func _take_back(uid: String, gear_uid: String) -> void:
	if _held != "":
		_give(uid, _held)  # swapping: hand over what you're holding instead
		return
	Game.unequip(uid, gear_uid)
	Audio.play("click")
	_rebuild_counter()


func _move(uid: String, to: int) -> void:
	Game.move_in_party(uid, to)
	Audio.play("click")
	_rebuild_counter()


func _let_go(uid: String) -> void:
	var hero_name: String = st.roster[uid].name
	if Season.is_candidate(st, uid) and not st.party.has(uid):
		Game.turn_away(uid)
		_say("%s heads to the tavern." % hero_name, Ui.MUTED)
	else:
		_confirm("Let %s go? Their gear comes back to the shelves, and they may turn up at the tavern later." % hero_name, "Let them go", func():
			Game.dismiss(uid)
			_say("%s heads to the tavern." % hero_name, Ui.MUTED)
			_rebuild_counter())
		return
	_rebuild_counter()


# --- side column: floor, odds, merchant, workbench, send -----------------------------------------

func _build_side_column() -> Control:
	var p := Ui.panel()
	p.position = Vector2(504, 22)
	p.size = Vector2(132, 334)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	v.add_child(Ui.label("Today's delve", UiTheme.ACCENT))
	var boss_day := Season.is_boss_day(db, st)
	for f in range(1, db.floor_count() + 1):
		var fdef := db.floor_by_index(f)
		var text := "%d  %s" % [f, fdef.get("name", "")]
		if boss_day and f >= int(db.bal("boss.floor", 5)):
			text += " !"
		var b := Ui.button(text, func():
			Game.set_delve_floor(f)
			_rebuild_counter(), Vector2(124, 16))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 8)
		if f == st.delve_floor:
			var box := StyleBoxFlat.new()
			box.bg_color = UiTheme.ACCENT.darkened(0.45)
			box.set_border_width_all(1)
			box.border_color = UiTheme.ACCENT
			box.set_content_margin_all(3)
			b.add_theme_stylebox_override("normal", box)
		v.add_child(b)
	var fd := db.floor_by_index(st.delve_floor)
	v.add_child(Ui.rich("[color=#%s]Chests %d-%d gold.\n%s[/color]" % [Ui.hex(Ui.MUTED), int(fd.gold[0]), int(fd.gold[1]), _floor_monsters(fd)]))
	if boss_day:
		v.add_child(Ui.rich("[color=#%s]Boss day: the Deep Warden waits on floor %d. Kill it to win.[/color]" % [Ui.hex(Ui.BAD), int(db.bal("boss.floor", 5))]))
	var delving := Season.delving_party(st)
	if not delving.is_empty() and _estimate.has("band"):
		v.add_child(Ui.rich("Party: [color=#%s]%s[/color]\n[color=#%s]wipe %d%%[/color]" % [Ui.hex(Ui.BAND_COLORS[_estimate.band]), str(_estimate.band).to_upper(), Ui.hex(Ui.MUTED), roundi(_estimate.wipe_rate * 100)]))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	if Season.is_merchant_day(db, st):
		var m := Ui.button("Wandering Merchant", _open_merchant, Vector2(124, 20))
		m.add_theme_color_override("font_color", Ui.GOLD)
		v.add_child(m)
	v.add_child(Ui.button("Workbench", _open_workbench, Vector2(124, 18)))
	var auto := Ui.button("Auto-outfit", _auto_outfit, Vector2(124, 16))
	auto.add_theme_font_size_override("font_size", 8)
	v.add_child(auto)
	var send := Ui.button("Send the party  >" if not delving.is_empty() else "Close for the day  >", _send, Vector2(124, 26))
	send.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(send)
	return p


func _floor_monsters(fd: Dictionary) -> String:
	var names: PackedStringArray = []
	for m in fd.get("monsters", {}):
		names.append(db.get_row("monsters", m).get("name", m))
	return ", ".join(names)


func _refresh_estimate() -> void:
	if st == null or st.phase != GameState.Phase.OUTFIT:
		return
	_estimate = Season.estimate_party(db, st, -1, ESTIMATE_SAMPLES)
	_estimate_dirty = false
	_build_counter()


func _auto_outfit() -> void:
	auto_bot.outfit(db, st)
	_say("Auto-outfitted the party.", Ui.MUTED)
	_rebuild_counter()


func _send() -> void:
	if _busy:
		return
	if Season.delving_party(st).is_empty():
		_confirm("Nobody is kitted out. Close the shop and skip today's delve?", "Close up", func():
			Game.send_delves()
			_enter_phase())
		return
	Game.send_delves()
	_enter_phase()


# --- the wandering merchant ------------------------------------------------------------------

func _open_merchant() -> void:
	var box := _open_overlay(Vector2(568, 318), "The Wandering Merchant")
	box.add_child(Ui.rich("[color=#%s]\"Finest steel this side of the Deep. Today only, friend.\"[/color]   You have [color=#%s]%d gold[/color]." % [Ui.hex(Ui.MUTED), Ui.hex(Ui.GOLD), st.gold]))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(544, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	if st.merchant_stock.is_empty():
		box.add_child(Ui.label("Sold out. He tips his hat and starts packing.", Ui.MUTED))
	for i in st.merchant_stock.size():
		grid.add_child(_offer_card(i))


func _offer_card(i: int) -> Control:
	var offer: Dictionary = st.merchant_stock[i]
	var g: Dictionary = offer.gear
	var col := Ui.tier_color(db, g)
	var card := Ui.panel(UiTheme.PANEL_LIGHT.darkened(0.15), col.darkened(0.2), 4)
	card.custom_minimum_size = Vector2(176, 76)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	card.add_child(h)
	var icon_box := Ui.panel(UiTheme.PANEL.darkened(0.3), col.darkened(0.4), 2)
	icon_box.custom_minimum_size = Vector2(34, 34)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := ItemIcon.new(Gear.def_of(db, g))
	icon.custom_minimum_size = Vector2(28, 28)
	icon_box.add_child(icon)
	h.add_child(icon_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var text := Ui.rich(Ui.item_text(db, g, -2))
	text.add_theme_font_size_override("normal_font_size", 8)
	text.custom_minimum_size = Vector2(128, 0)
	v.add_child(text)
	var buy := Ui.button("Buy for %d" % int(offer.price), func(): _buy(i, card), Vector2(0, 16))
	buy.disabled = st.gold < int(offer.price)
	if buy.disabled:
		buy.text = "Need %d more" % (int(offer.price) - st.gold)
	v.add_child(buy)
	card.mouse_entered.connect(func(): Juice.pop(icon, 0.12))
	return card


func _buy(i: int, card: Control) -> void:
	var item_name := Gear.display_name(db, st.merchant_stock[i].gear)
	if Game.buy(i) != "":
		Audio.play("whiff")
		return
	Audio.play("treasure")
	Juice.flash(card, Color(2, 2, 1.4), 0.15)
	_say("Bought %s. It's on your shelves." % item_name, Ui.GOLD)
	_refresh_top()
	_estimate_dirty = true
	_open_merchant()


# --- the workbench ------------------------------------------------------------------------------

var _bench_mod := ""


func _open_workbench() -> void:
	var box := _open_overlay(Vector2(520, 290), "Workbench")
	var mats: PackedStringArray = []
	for m in db.rows("materials"):
		mats.append("%s %d" % [m.name, int(st.materials.get(m.id, 0))])
	box.add_child(Ui.rich("[color=#%s]Materials:[/color] %s" % [Ui.hex(Ui.MUTED), ",  ".join(mats)]))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	var mods_col := VBoxContainer.new()
	mods_col.custom_minimum_size = Vector2(250, 0)
	h.add_child(mods_col)
	mods_col.add_child(Ui.label("Mods in stock", UiTheme.ACCENT))
	var any := false
	for mod_id in st.mod_stock:
		if int(st.mod_stock[mod_id]) <= 0:
			continue
		any = true
		var row := db.get_row("mods", mod_id)
		var cost: PackedStringArray = []
		var affordable := true
		for mat in row.get("cost", {}):
			var need := int(row.cost[mat])
			var have := int(st.materials.get(mat, 0))
			affordable = affordable and have >= need
			cost.append("[color=#%s]%d %s[/color]" % [Ui.hex(Ui.GOOD if have >= need else Ui.BAD), need, db.get_row("materials", mat).get("name", mat)])
		var b := Ui.button("%s x%d" % [row.get("name", mod_id), int(st.mod_stock[mod_id])], func():
			_bench_mod = mod_id
			_open_workbench(), Vector2(240, 16))
		if _bench_mod == mod_id:
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
		mods_col.add_child(b)
		mods_col.add_child(Ui.rich("[color=#%s]%s[/color]  costs %s" % [Ui.hex(Ui.MUTED), row.get("desc", ""), ", ".join(cost)]))
	if not any:
		mods_col.add_child(Ui.rich("[color=#%s]No mods yet. Take mod cards from your heroes' hauls at dusk, then socket them here using materials.[/color]" % Ui.hex(Ui.MUTED)))
	var gear_col := VBoxContainer.new()
	h.add_child(gear_col)
	gear_col.add_child(Ui.label("Socket into" if _bench_mod != "" else "Pick a mod first", UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 6
	gear_col.add_child(grid)
	if _bench_mod != "":
		for g in st.inventory:
			if Gear.free_sockets(db, g) <= 0:
				continue
			var err := Season.can_socket(db, st, g.uid, _bench_mod)
			var tile := _gear_tile(g, false, func(): _socket(g.uid), false)
			tile.tooltip_text = Gear.display_name(db, g) + ("" if err == "" else "\n" + err)
			if err != "":
				tile.modulate = Color(1, 1, 1, 0.45)
			grid.add_child(tile)


func _socket(gear_uid: String) -> void:
	var err := Game.socket(gear_uid, _bench_mod)
	if err != "":
		_say(err.capitalize() + ".", Ui.BAD)
		Audio.play("whiff")
		return
	Audio.play("treasure")
	_say("Socketed %s." % db.get_row("mods", _bench_mod).get("name", ""), Ui.GOOD)
	if int(st.mod_stock.get(_bench_mod, 0)) <= 0:
		_bench_mod = ""
	_estimate_dirty = true
	_open_workbench()


# --- overlays ---------------------------------------------------------------------------------------

## A dimmed modal with a titled panel. Returns the panel's content box.
func _open_overlay(box_size: Vector2, title: String) -> VBoxContainer:
	_close_overlay(false)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var p := Ui.panel(UiTheme.PANEL, UiTheme.ACCENT.darkened(0.3), 8)
	p.size = box_size
	p.position = (Vector2(640, 360) - box_size) / 2.0 + Vector2(0, 8)
	_overlay.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Ui.label(title, UiTheme.ACCENT, 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Close", func(): _close_overlay()))
	return v


func _close_overlay(rebuild: bool = true) -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		if rebuild and st and st.phase == GameState.Phase.OUTFIT:
			_build_counter()
			_refresh_top()


func _confirm(question: String, yes_text: String, on_yes: Callable) -> void:
	var v := _open_overlay(Vector2(300, 110), "Are you sure?")
	var q := Ui.label(question)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(280, 0)
	v.add_child(q)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(Ui.button(yes_text, func():
		_close_overlay(false)
		on_yes.call()))
	h.add_child(Ui.button("Never mind", func(): _close_overlay()))


func _morning_banner() -> void:
	var lines: PackedStringArray = []
	var walk_ins := 0
	for uid in st.candidates:
		if not st.party.has(uid):
			walk_ins += 1
	if st.day == 1:
		lines.append("Four adventurers are at the counter. Hand gear to the ones you want in your party.")
	elif walk_ins > 0:
		lines.append("A walk-in is at the counter." + (" Your party is full: let someone go to hire them." if st.party.size() >= Season.party_size(db) else ""))
	if Season.is_merchant_day(db, st):
		lines.append("The wandering merchant is in town today!")
	if Season.rent_due_today(db, st) > 0:
		lines.append("Rent of %d is due tonight." % Season.rent_due_today(db, st))
	if Season.is_boss_day(db, st):
		lines.append("The Deep Warden stirs on floor %d. Slay it today to win the season." % int(db.bal("boss.floor", 5)))
	var banner := Ui.panel(UiTheme.PANEL.darkened(0.2), UiTheme.ACCENT, 8)
	banner.position = Vector2(170, 120)
	banner.size = Vector2(300, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	banner.add_child(v)
	var title := Ui.label("Day %d" % st.day, UiTheme.ACCENT, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for l in lines:
		var lab := Ui.label(l)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(284, 0)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lab)
	_root.add_child(banner)
	Juice.pop(banner, 0.2)
	Audio.play("spawn")
	var t := banner.create_tween()
	t.tween_interval(2.6)
	t.tween_property(banner, "modulate:a", 0.0, 0.5)
	t.tween_callback(banner.queue_free)


# --- the delve --------------------------------------------------------------------------------

func _play_delve() -> void:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_screen(screen)
	if st.delve.is_empty():
		_finish_delve()  # nobody went: straight to dusk
		return
	var fd := db.floor_by_index(int(st.delve.floor))
	var head := Ui.label("Floor %d: %s" % [int(st.delve.floor), fd.get("name", "")], UiTheme.ACCENT, 16)
	head.position = Vector2(0, 26)
	head.size = Vector2(640, 20)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(head)
	var names := Ui.rich()
	names.position = Vector2(8, 60)
	names.custom_minimum_size = Vector2(150, 0)
	var lines: PackedStringArray = []
	for r in st.results:
		lines.append("%d. %s" % [int(r.slot) + 1, st.roster[r.hero_uid].name])
	names.text = "[color=#%s]%s[/color]" % [Ui.hex(Ui.MUTED), "\n".join(lines)]
	screen.add_child(names)
	var row := HBoxContainer.new()
	row.position = Vector2(220, 334)
	screen.add_child(row)
	for sp in [1.0, 2.0, 4.0]:
		row.add_child(Ui.button("%dx" % int(sp), func(): playback.speed = sp, Vector2(34, 18)))
	row.add_child(Ui.button("Skip", func(): playback.skip(), Vector2(50, 18)))
	playback.visible = true
	playback.position = Vector2(0, 10)
	var heroes: Array = []
	for r in st.results:
		heroes.append(st.roster[r.hero_uid])
	_busy = true
	await playback.play(st.delve, heroes, db)
	await get_tree().create_timer(0.6).timeout
	_busy = false
	_finish_delve()


func _finish_delve() -> void:
	playback.visible = false
	_report = Game.begin_dusk()
	_enter_phase()


# --- dusk: take one card from each survivor -------------------------------------------------------

func _build_dusk() -> void:
	playback.visible = false
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_screen(screen)
	var p := Ui.panel()
	p.position = Vector2(4, 22)
	p.size = Vector2(632, 334)
	screen.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	var title := "Dusk. The party is back." if not st.results.is_empty() else "Dusk. A quiet day at the shop."
	v.add_child(Ui.label(title, UiTheme.ACCENT, 16))
	v.add_child(Ui.rich("[color=#%s]Each hero lays out what they found. Take one card from each; they keep the rest.[/color]" % Ui.hex(Ui.MUTED)))
	for r in st.results:
		v.add_child(_dusk_row(r))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var left := 0
	for uid in st.picks_left:
		left += int(st.picks_left[uid])
	var close := Ui.button("Close up shop  >" if left == 0 else "Close up (%d card%s left on the table)  >" % [left, "" if left == 1 else "s"], _close_day, Vector2(0, 24))
	close.add_theme_color_override("font_color", UiTheme.ACCENT)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(close)


func _dusk_row(r: Dictionary) -> Control:
	var hero: Dictionary = st.roster[r.hero_uid]
	var entry := {}
	for e in _report:
		if e.hero == r.hero_uid:
			entry = e
	var row := Ui.panel(UiTheme.PANEL_LIGHT.darkened(0.1), Color(0, 0, 0, 0), 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(170, 0)
	h.add_child(info)
	var outcome_col: Color = {"survived": Ui.GOOD, "retreated": Color(1.0, 0.85, 0.4), "died": Ui.BAD}.get(r.outcome, UiTheme.INK)
	var outcome_text: String = {"survived": "made it through", "retreated": "came home early", "died": "fell"}.get(r.outcome, r.outcome)
	info.add_child(Ui.rich("%s  [color=#%s]%s[/color]" % [hero.name, Ui.hex(outcome_col), outcome_text]))
	var notes: PackedStringArray = []
	if r.outcome == "died":
		var killer := str(r.get("killer", ""))
		notes.append("Killed by %s." % (db.get_row("monsters", killer).get("name", killer) if killer != "trap" else "a trap"))
		var lost: PackedStringArray = []
		for g in entry.get("lost_gear", []):
			lost.append(Gear.display_name(db, g))
		if not lost.is_empty():
			notes.append("[color=#%s]Lost: %s[/color]" % [Ui.hex(Ui.BAD), ", ".join(lost)])
	else:
		notes.append("%d kills, HP %d/%d" % [int(r.total_kills), int(r.hp_left), int(r.max_hp)])
		if entry.get("level_up", false):
			notes.append("[color=#%s]Level up! Now Lv %d.[/color]" % [Ui.hex(Ui.GOOD), int(hero.level)])
		for t in entry.get("titles", []):
			notes.append("[color=#%s]Gear earned a name: \"%s\"[/color]" % [Ui.hex(Ui.GOLD), t.title])
	var n := Ui.rich("[color=#%s]%s[/color]" % [Ui.hex(Ui.MUTED), "\n".join(notes)])
	n.custom_minimum_size = Vector2(170, 0)
	info.add_child(n)
	var picks := int(st.picks_left.get(r.hero_uid, 0))
	for i in r.haul.size():
		h.add_child(_haul_card(r, i, picks > 0))
	return row


func _haul_card(r: Dictionary, i: int, can_pick: bool) -> Control:
	var card: Dictionary = r.haul[i]
	var taken: bool = card.get("taken", false)
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 44)
	b.focus_mode = Control.FOCUS_NONE
	var col := Ui.card_color(card)
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL.darkened(0.15) if not taken else col.darkened(0.6)
	box.set_border_width_all(2 if taken else 1)
	box.border_color = col if taken or can_pick else col.darkened(0.6)
	box.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = box.bg_color.lightened(0.15)
	hover.border_color = col
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("disabled", box)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var kind_text: String = {"gold": "GOLD", "materials": "MATERIALS", "mod": "MOD"}.get(card.kind, "")
	var k := Ui.label(kind_text, col.darkened(0.2), 8)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var t := Ui.label(Ui.card_title(db, card), col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(80, 0)
	v.add_child(t)
	if taken:
		var tk := Ui.label("TAKEN", UiTheme.INK, 8)
		tk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tk)
	elif card.kind == "mod":
		b.tooltip_text = db.get_row("mods", card.mod).get("desc", "")
	b.disabled = taken or not can_pick
	if not can_pick and not taken:
		b.modulate = Color(1, 1, 1, 0.5)
	b.pressed.connect(func(): _take_card(r.hero_uid, i, b))
	Juice.bind_button(b)
	return b


func _take_card(hero_uid: String, i: int, from: Control) -> void:
	if Game.take_card(hero_uid, i) != "":
		return
	var card: Dictionary = Season.result_for(st, hero_uid).haul[i]
	Audio.play("treasure")
	Juice.popup(_root, from.global_position + Vector2(42, 0), "+" + Ui.card_title(db, card), Ui.card_color(card), true)
	_refresh_top()
	_build_dusk()


func _close_day() -> void:
	var out := Game.end_day()
	_report = []
	if out.won or out.lost:
		_enter_phase()
		return
	if out.rent > 0:
		var v := _open_overlay(Vector2(300, 100), "Rent day")
		v.add_child(Ui.rich("The landlord collects [color=#%s]%d gold[/color]. You have %d left." % [Ui.hex(Ui.GOLD), out.rent, st.gold]))
		v.add_child(Ui.button("Next morning  >", func():
			_close_overlay(false)
			_enter_phase()))
		_refresh_top()
		return
	_enter_phase()


# --- season end ---------------------------------------------------------------------------------

func _build_season_end() -> void:
	playback.visible = false
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_screen(screen)
	var won := st.phase == GameState.Phase.WON
	var p := Ui.panel(UiTheme.PANEL, UiTheme.ACCENT if won else Ui.BAD, 10)
	p.position = Vector2(150, 70)
	p.size = Vector2(340, 220)
	screen.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(Ui.label("Season won!" if won else "The shop has closed.", UiTheme.ACCENT if won else Ui.BAD, 20))
	var why := "The Deep Warden is dead, and your shop is the talk of the town." if won else ("You couldn't make rent on day %d." % st.day if st.day != int(db.bal("boss.day", 28)) else "The Deep Warden still stands.")
	var w := Ui.label(why)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.custom_minimum_size = Vector2(320, 0)
	v.add_child(w)
	v.add_child(Ui.rich("[color=#%s]Heroes lost: %d\nGear lost: %d\nGold earned: %d\nDays: %d[/color]" % [Ui.hex(Ui.MUTED), int(st.stats.get("deaths", 0)), int(st.stats.get("gear_lost", 0)), int(st.stats.get("gold_earned", 0)), st.day]))
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(Ui.button("New season", func():
		Game.new_game()
		_gold_shown = -1
		_enter_phase()))
	h.add_child(Ui.button("Title", func(): Router.goto("title")))


# --- dev / tests --------------------------------------------------------------------------------

## Plays the current phase with the bot (used by the smoke test).
func _on_advance() -> void:
	match st.phase:
		GameState.Phase.MORNING:
			_enter_phase()
		GameState.Phase.OUTFIT:
			auto_bot.shop_merchant(db, st)
			auto_bot.outfit(db, st)
			Game.send_delves()
			_close_overlay(false)
			await _play_delve()
		GameState.Phase.DELVE:
			await _play_delve()
		GameState.Phase.DUSK:
			auto_bot.pick_cards(db, st)
			auto_bot.tend_shop(db, st)
			_close_day()
			_close_overlay(false)
			if st.phase == GameState.Phase.MORNING:
				_enter_phase()
		GameState.Phase.WON, GameState.Phase.LOST:
			Game.new_game()
			_enter_phase()
