extends Node2D
## Placeholder shop: drives one whole day through the Game autoload with the
## AutoPlayer making the choices, and plays each run back. It proves the
## season loop end to end; the real counter, workbench and dusk screens replace
## it on Days 4 and 5.

var db: ContentDB
var playback: RunPlayback
var _status: Label
var _log: RichTextLabel
var _advance: Button
var _bot := AutoPlayer.new()


func _ready() -> void:
	db = Content.db
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	Juice.register_camera(cam)
	playback = RunPlayback.new()
	playback.position = Vector2(80, -10)
	add_child(playback)

	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(8, 6)
	layer.add_child(_status)
	_log = RichTextLabel.new()
	_log.position = Vector2(8, 26)
	_log.size = Vector2(220, 300)
	_log.scroll_following = true
	_log.bbcode_enabled = true
	_log.add_theme_font_size_override("normal_font_size", 8)
	layer.add_child(_log)
	var row := HBoxContainer.new()
	row.position = Vector2(8, 334)
	layer.add_child(row)
	_advance = _btn(row, "", _on_advance)
	for s in [1.0, 2.0, 4.0]:
		_btn(row, "%dx" % int(s), func(): playback.speed = s)
	_btn(row, "Skip", func(): playback.skip())
	_btn(row, "Title", func(): Router.goto("title"))

	if Game.state == null:
		Game.new_game()
	Audio.music("shop")
	_refresh()


func _refresh() -> void:
	var st := Game.state
	var rent := Season.next_rent(db, st)
	_status.text = "Day %d/%d   Gold %d   Rent %d due day %d   Merchant day %d   Racks %d   Lost %d" % [
		st.day, int(db.bal("season_length", 28)), st.gold, rent.amount, rent.day, Season.next_merchant_day(db, st), st.inventory.size(), int(st.stats.get("deaths", 0))]
	match st.phase:
		GameState.Phase.MORNING:
			_advance.text = "Open the shop"
		GameState.Phase.OUTFIT:
			_advance.text = "Auto-outfit and send"
		GameState.Phase.DELVE:
			_advance.text = "Watch the runs"
		GameState.Phase.DUSK:
			_advance.text = "Take cards, close up"
		GameState.Phase.WON, GameState.Phase.LOST:
			_advance.text = "New season"


func _on_advance() -> void:
	var st := Game.state
	_advance.disabled = true
	match st.phase:
		GameState.Phase.MORNING:
			Game.start_day()
			_say("[b]Day %d.[/b] Party (%d/%d):" % [st.day, st.party.size(), Season.party_size(db)])
			for uid in st.party:
				_say("  " + _hero_line(st.roster[uid]))
			for uid in st.candidates:
				_say("  [color=#8cf]Walk-in:[/color] " + _hero_line(st.roster[uid]))
			if not st.merchant_stock.is_empty():
				var offers: Array = []
				for o in st.merchant_stock:
					offers.append("%s %dg" % [Gear.display_name(db, o.gear), o.price])
				_say("[color=#fc6]The wandering merchant is in town:[/color] " + ", ".join(offers))
		GameState.Phase.OUTFIT:
			for g in _bot.shop_merchant(db, st):
				_say("  Bought %s." % Gear.display_name(db, g))
			var before_party: Array = st.party.duplicate()
			_bot.outfit(db, st)
			for uid in before_party:
				if not st.party.has(uid):
					_say("  Let %s go to make room." % st.roster[uid].name)
			_say("  The party heads to floor %d:" % st.delve_floor)
			var slot := 1
			for uid in Season.delving_party(st):
				var names: Array = []
				for g in Season.loan_for(st, uid).gear:
					names.append(Gear.display_name(db, g))
				_say("  %d. %s with %s" % [slot, st.roster[uid].name, ", ".join(names)])
				slot += 1
			Game.send_delves()
		GameState.Phase.DELVE:
			if not st.delve.is_empty():
				var heroes: Array = []
				for r in st.results:
					heroes.append(st.roster[r.hero_uid])
				_say("Watching the party...")
				await playback.play(st.delve, heroes, db)
			var report := Game.begin_dusk()
			for e in report:
				var line := "  %s: %s" % [st.roster[e.hero].name, e.outcome]
				if e.level_up:
					line += ", level up"
				for t in e.titles:
					line += ", gear earned \"%s\"" % t.title
				if not e.lost_gear.is_empty():
					line += ", [color=#e66]%d gear lost[/color]" % e.lost_gear.size()
				_say(line)
		GameState.Phase.DUSK:
			var before := st.gold
			_bot.pick_cards(db, st)
			_bot.tend_shop(db, st)
			var out := Game.end_day()
			_say("  Cards taken (+%d gold)." % (st.gold - before + int(out.rent if out.paid else 0)))
			if out.rent > 0:
				_say("  Rent %d: %s" % [out.rent, "paid" if out.paid else "[color=#e66]couldn't pay[/color]"])
			if out.won:
				_say("[b]The Deep Warden falls. Season won![/b]")
			elif out.lost:
				_say("[b][color=#e66]Season lost.[/color][/b]")
		GameState.Phase.WON, GameState.Phase.LOST:
			Game.new_game()
			_log.clear()
	_advance.disabled = false
	_refresh()


func _hero_line(h: Dictionary) -> String:
	var traits: Array = []
	for t in h.traits:
		var row := db.get_row("traits", t)
		traits.append("%s (%s)" % [row.get("name", t), row.get("rarity", "")])
	return "%s, Lv %d, bond %d, %s" % [Hero.display_name(db, h), h.level, h.bond, ", ".join(traits)]


func _say(text: String) -> void:
	_log.append_text(text + "\n")


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	Juice.bind_button(b)
	return b
