extends RefCounted

var db := ContentDB.load_from()


func test_new_game_has_starting_kit(t: TestContext) -> void:
	var st := Season.new_game(db, 1)
	t.eq(st.inventory.size(), db.bal("start_inventory").size(), "inventory")
	t.eq(st.gold, int(db.bal("start_gold")), "gold")


func test_a_full_day(t: TestContext) -> void:
	var st := Season.new_game(db, 3)
	Season.start_day(db, st)
	t.ok(st.counter.size() >= 2, "heroes at the counter")
	var hero_uid: String = st.counter[0]
	var sword: Dictionary = st.inventory[0]
	t.eq(Season.lend(db, st, hero_uid, [sword.uid], 1), "", "lend")
	t.ok(st.find_gear(sword.uid).is_empty(), "lent gear leaves the racks")
	t.ok(Season.lend(db, st, hero_uid, [st.inventory[0].uid, st.inventory[1].uid], 1) != "", "two weapons rejected")
	Season.send_delves(db, st)
	t.eq(st.results.size(), 1, "one delve")
	var report := Season.begin_dusk(db, st)
	var r: Dictionary = st.results[0]
	if r.outcome == "died":
		t.eq(st.memorial.size(), 1, "memorial")
		t.ok(st.find_gear(sword.uid).is_empty(), "gear lost with the hero")
	else:
		t.ok(not st.find_gear(sword.uid).is_empty(), "gear comes back")
		var gold_before := st.gold
		var card: Dictionary = r.haul[0]
		t.eq(Season.take_card(db, st, hero_uid, 0), "", "take card")
		if card.kind == "gold":
			t.eq(st.gold, gold_before + int(card.amount), "gold card")
		t.ok(Season.take_card(db, st, hero_uid, 0) != "", "one pick only")
	t.eq(report.size(), 1, "report")
	Season.end_day(db, st)
	t.eq(st.day, 2, "next day")


func test_rent_day(t: TestContext) -> void:
	var st := Season.new_game(db, 4)
	st.day = 7
	st.phase = GameState.Phase.DUSK
	st.gold = 0
	var out := Season.end_day(db, st)
	t.ok(out.lost, "can't pay rent -> season lost")
	t.eq(st.phase, GameState.Phase.LOST, "phase")


func test_socketing_costs_materials(t: TestContext) -> void:
	var st := Season.new_game(db, 5)
	var g: Dictionary = st.inventory[0]
	t.ok(Season.socket_mod(db, st, g.uid, "holy_rune") != "", "no mod in stock")
	st.mod_stock["holy_rune"] = 1
	t.ok(Season.socket_mod(db, st, g.uid, "holy_rune") != "", "no materials")
	st.materials["bone_dust"] = 3
	t.eq(Season.socket_mod(db, st, g.uid, "holy_rune"), "", "socket")
	t.eq(int(st.materials.bone_dust), 0, "materials spent")
	t.ok(g.mods.has("holy_rune"), "mod on gear")


func test_save_round_trip_mid_season(t: TestContext) -> void:
	var st := Season.new_game(db, 11)
	var bot := AutoPlayer.new()
	bot.estimate_samples = 10
	for i in 5:
		if st.is_over():
			break
		bot.play_day(db, st)
	if not st.is_over():
		Season.start_day(db, st)
		bot.outfit(db, st)
		Season.send_delves(db, st)  # save mid-delve
	var json := JSON.stringify(st.to_dict(), "", false)  # same as SaveSystem
	var loaded := GameState.from_dict(JSON.parse_string(json))
	# JSON turns ints into floats, so compare parsed values, not text.
	t.ok(JSON.parse_string(JSON.stringify(loaded.to_dict())) == JSON.parse_string(json), "state survives JSON")
	if loaded.phase == GameState.Phase.DELVE:
		# The resumed game must play the same dusk as the original would have.
		var a := Season.begin_dusk(db, st)
		var b := Season.begin_dusk(db, loaded)
		t.ok(JSON.parse_string(JSON.stringify(b)) == JSON.parse_string(JSON.stringify(a)), "same dusk after reload")
		t.eq(loaded.gold, st.gold, "same gold")


func test_whole_season_is_deterministic(t: TestContext) -> void:
	var finals: Array = []
	for i in 2:
		var st := Season.new_game(db, 2024)
		var bot := AutoPlayer.new()
		bot.estimate_samples = 10
		while not st.is_over():
			bot.play_day(db, st)
		finals.append(JSON.stringify(st.to_dict()))
	t.eq(finals[0], finals[1], "same seed, same season")
