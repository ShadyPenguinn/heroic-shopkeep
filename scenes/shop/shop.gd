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
	playback.position = Vector2(60, -10)
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
	_status.text = "Day %d/%d   Gold %d   Rent %d due day %d   Racks %d   Lost so far %d" % [
		st.day, int(db.bal("season_length", 28)), st.gold, rent.amount, rent.day, st.inventory.size(), int(st.stats.get("deaths", 0))]
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
			_say("[b]Day %d.[/b] At the counter:" % st.day)
			for uid in st.counter:
				var h: Dictionary = st.roster[uid]
				_say("  %s, Lv %d, bond %d" % [Hero.display_name(db, h), h.level, h.bond])
		GameState.Phase.OUTFIT:
			_bot.outfit(db, st)
			for loan in st.loans:
				var names: Array = []
				for g in loan.gear:
					names.append(Gear.display_name(db, g))
				_say("  %s -> floor %d with %s" % [st.roster[loan.hero].name, loan.floor, ", ".join(names)])
			Game.send_delves()
		GameState.Phase.DELVE:
			for r in st.results:
				_say("Watching %s..." % st.roster[r.hero_uid].name)
				await playback.play(r, st.roster[r.hero_uid], db)
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


func _say(text: String) -> void:
	_log.append_text(text + "\n")


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	Juice.bind_button(b)
	return b
