extends Node2D
## Dev sandbox: roll a hero, pick gear and a floor, see the survival estimate,
## then watch the seeded run play back. Use it to feel out combat and juice
## before the real counter screen exists. Not shipped in release menus.

var db: ContentDB
var rng := Rng.new(Rng.derive(1, ["sandbox"]))
var hero: Dictionary = {}
var seed_value := 1
var uid := 0

var playback: RunPlayback
var _class_opt: OptionButton
var _tier_opt: OptionButton
var _floor_spin: SpinBox
var _element_opt: OptionButton
var _action_opt: OptionButton
var _hero_label: Label
var _estimate_label: Label
var _log: RichTextLabel
var _delve_btn: Button


func _ready() -> void:
	db = Content.db
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	Juice.register_camera(cam)

	var floor_line := Line2D.new()
	floor_line.points = [Vector2(-120, 32), Vector2(320, 32)]
	floor_line.width = 1
	floor_line.default_color = Color(0.35, 0.28, 0.3)
	add_child(floor_line)

	playback = RunPlayback.new()
	playback.position = Vector2(110, 0)
	add_child(playback)
	playback.event_shown.connect(_on_event)
	playback.finished.connect(func(_r): _delve_btn.disabled = false)

	_build_ui()
	_new_hero()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(4, 4)
	panel.custom_minimum_size = Vector2(196, 352)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)

	_label(v, "SIM SANDBOX").modulate = UiTheme.ACCENT
	_class_opt = _option(v, "Class", db.ids("classes"))
	_class_opt.item_selected.connect(func(_i): _reroll_keep_class())
	_tier_opt = _option(v, "Gear tier", ["1 Iron", "2 Steel", "3 Mythril"])
	_element_opt = _option(v, "Element", ["none"] + Array(db.bal("elements", [])))
	var actions: Array = ["none"]
	for m in db.rows("mods"):
		if m.kind == "action":
			actions.append(m.id)
	_action_opt = _option(v, "Action mod", actions)
	var fh := HBoxContainer.new()
	_label(fh, "Floor")
	_floor_spin = SpinBox.new()
	_floor_spin.min_value = 1
	_floor_spin.max_value = db.floor_count()
	_floor_spin.value = 1
	fh.add_child(_floor_spin)
	v.add_child(fh)

	_hero_label = _label(v, "")
	_hero_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_label.custom_minimum_size = Vector2(186, 0)

	var row := HBoxContainer.new()
	v.add_child(row)
	_btn(row, "New hero", _new_hero)
	_btn(row, "Estimate", _estimate)
	_delve_btn = _btn(row, "Delve!", _delve)

	_estimate_label = _label(v, "")
	_estimate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_estimate_label.custom_minimum_size = Vector2(186, 0)

	var speeds := HBoxContainer.new()
	v.add_child(speeds)
	for s in [1.0, 2.0, 4.0]:
		_btn(speeds, "%dx" % int(s), func(): playback.speed = s)
	_btn(speeds, "Skip", func(): playback.skip())
	_btn(speeds, "Title", func(): Router.goto("title"))

	_log = RichTextLabel.new()
	_log.position = Vector2(208, 250)
	_log.size = Vector2(428, 106)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 8)
	layer.add_child(_log)


func _new_hero() -> void:
	uid += 1
	hero = Hero.create(db, rng, "sandbox%d" % uid)
	_class_opt.select(db.ids("classes").find(hero.class_id))
	_refresh_hero()


func _reroll_keep_class() -> void:
	hero.class_id = db.ids("classes")[_class_opt.selected]
	_refresh_hero()


func _refresh_hero() -> void:
	var s := Hero.combat_stats(db, hero, _gear())
	var traits: Array = []
	for t in hero.traits:
		traits.append(db.get_row("traits", t).name)
	_hero_label.text = "%s\nLv %d  HP %d  Might %d  Guard %d\nHaste %d  Nerve %d  Luck %d  Retreats < %d%%\n%s" % [
		Hero.display_name(db, hero), hero.level, s.max_hp, s.might, s.guard, s.haste, s.nerve, s.luck,
		roundi(s.nerve_threshold * 100), ", ".join(traits)]
	_estimate_label.text = ""


func _gear() -> Array:
	var tier := _tier_opt.selected + 1
	var kinds: Array = db.get_row("classes", hero.get("class_id", "")).get("weapons", [])
	var gear: Array = []
	var picks := {}
	for it in db.rows("items"):
		if int(it.tier) != tier or picks.has(it.slot):
			continue
		if it.slot == "weapon" and not kinds.has(it.get("kind")):
			continue
		picks[it.slot] = it.id
	for slot in picks:
		gear.append(Gear.create(db, picks[slot], "sg_" + slot))
	for g in gear:
		if Gear.def_of(db, g).slot != "weapon":
			continue
		if _element_opt.selected > 0:
			g.mods.append(str(db.bal("elements")[_element_opt.selected - 1]) + "_rune")
		if _action_opt.selected > 0 and Gear.free_sockets(db, g) > 0:
			g.mods.append(_action_opt.get_item_text(_action_opt.selected))
	return gear


func _estimate() -> void:
	var t0 := Time.get_ticks_usec()
	var est := SurvivalEstimator.estimate(db, hero, _gear(), int(_floor_spin.value), Rng.derive(seed_value, ["sandbox-est"]))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_estimate_label.text = "%s: %d%% death (%d-%d%%), %d%% retreat\nbest card ~%d gold  [%d sims, %.0f ms]" % [
		str(est.band).to_upper(), roundi(est.death_rate * 100), roundi(est.death_low * 100), roundi(est.death_high * 100),
		roundi(est.retreat_rate * 100), roundi(est.avg_best_card), est.samples, ms]
	Juice.pop(_estimate_label, 0.1)


func _delve() -> void:
	seed_value += 1
	_log.clear()
	var result := RunSimulator.simulate(db, hero, _gear(), int(_floor_spin.value), seed_value)
	_log.append_text("[b]Seed %d[/b], floor %d, %d rooms\n" % [seed_value, result.floor, result.rooms])
	_delve_btn.disabled = true
	await playback.play(result, hero, db)
	var haul: Array = []
	for c in result.haul:
		haul.append(_card_text(c))
	_log.append_text("[b]%s[/b]. Haul: %s\n" % [str(result.outcome).capitalize(), ", ".join(haul) if not haul.is_empty() else "nothing"])


func _on_event(ev: Dictionary) -> void:
	var skip := ["status_tick", "drop"]
	if skip.has(ev.type):
		return
	var parts: Array = []
	for k in ev:
		if k != "type" and k != "monsters":
			parts.append("%s=%s" % [k, str(ev[k])])
	_log.append_text("[color=#c8a]%s[/color] %s\n" % [ev.type, " ".join(parts)])


func _card_text(c: Dictionary) -> String:
	match c.kind:
		"gold":
			return "%d gold" % int(c.amount)
		"materials":
			return "%d %s" % [int(c.qty), db.get_row("materials", c.material).name]
		"mod":
			return db.get_row("mods", c.mod).name
	return "?"


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _option(parent: Control, label_text: String, items: Array) -> OptionButton:
	var h := HBoxContainer.new()
	var l := _label(h, label_text)
	l.custom_minimum_size = Vector2(60, 0)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.item_selected.connect(func(_i): _refresh_hero())
	h.add_child(o)
	parent.add_child(h)
	return o


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	Juice.bind_button(b)
	return b
