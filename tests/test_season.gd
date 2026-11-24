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
	t.eq(Season.lend(db, st, hero_uid, [sword.uid]), "", "lend")
	t.ok(st.find_gear(sword.uid).is_empty(), "lent gear leaves the racks")
	t.ok(Season.lend(db, st, hero_uid, [st.inventory[0].uid, st.inventory[1].uid]) != "", "two weapons rejected")
	t.ok(Season.set_delve_floor(db, st, 99) != "", "no such floor")
	t.eq(Season.set_delve_floor(db, st, 1), "", "pick a floor")
	Season.send_delves(db, st)
	t.eq(st.results.size(), 1, "one delve")
	t.ok(not st.delve.get("events", []).is_empty(), "the party run is kept for playback")
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


func test_merchant_comes_mid_week(t: TestContext) -> void:
	var st := Season.new_game(db, 8)
	var days: Array = []
	for d in range(1, 29):
		st.day = d
		if Season.is_merchant_day(db, st):
			days.append(d)
	t.eq(days, [4, 11, 18, 25], "merchant days")
	st.day = 5
	t.eq(Season.next_merchant_day(db, st), 11, "next visit after day 4")


func test_buying_from_merchant(t: TestContext) -> void:
	var st := Season.new_game(db, 9)
	st.day = 4
	Season.start_day(db, st)
	t.ok(st.merchant_stock.size() >= 4, "merchant has stock on day 4")
	var offer: Dictionary = st.merchant_stock[0]
	st.gold = int(offer.price) - 1
	t.ok(Season.buy(db, st, 0) != "", "can't buy without the gold")
	st.gold = int(offer.price)
	var racks := st.inventory.size()
	t.eq(Season.buy(db, st, 0), "", "buy")
	t.eq(st.gold, 0, "gold spent")
	t.eq(st.inventory.size(), racks + 1, "gear on the racks")
	st.phase = GameState.Phase.DUSK
	Season.end_day(db, st)
	t.ok(st.merchant_stock.is_empty(), "merchant leaves at night")
	st.day = 6
	st.phase = GameState.Phase.MORNING
	Season.start_day(db, st)
	t.ok(st.merchant_stock.is_empty(), "no merchant on day 6")


func test_merchant_stock_improves_over_season(t: TestContext) -> void:
	var early := 0.0
	var late := 0.0
	for sd in 30:
		for pair in [[4, "early"], [25, "late"]]:
			var st := Season.new_game(db, sd)
			st.day = pair[0]
			Season.start_day(db, st)
			for o in st.merchant_stock:
				var tier := float(Gear.def_of(db, o.gear).tier)
				if pair[1] == "early":
					early += tier
				else:
					late += tier
	t.ok(late > early * 1.3, "week 4 stock should be clearly better (%.0f vs %.0f)" % [late, early])


func test_day_one_four_walk_ins_unkitted_leave(t: TestContext) -> void:
	var st := Season.new_game(db, 21)
	Season.start_day(db, st)
	t.eq(st.candidates.size(), 4, "four walk-ins on day 1")
	t.eq(st.party.size(), 0, "nobody has joined yet")
	var weapons: Array = []
	for g in st.inventory:
		if Gear.def_of(db, g).slot == "weapon":
			weapons.append(g.uid)
	t.eq(Season.lend(db, st, st.candidates[0], [weapons[0]]), "", "kit out first")
	t.eq(Season.lend(db, st, st.candidates[1], [weapons[1]]), "", "kit out second")
	t.eq(st.party.size(), 2, "kitted walk-ins join")
	var left: String = st.candidates[3]
	Season.send_delves(db, st)
	t.ok(st.tavern.has(left), "un-kitted walk-in goes to the tavern")
	t.ok(not st.party.has(left), "and is not in the party")


func test_full_party_must_let_someone_go(t: TestContext) -> void:
	var st := Season.new_game(db, 22)
	for i in 4:
		var h := Hero.create(db, Rng.new(i), st.new_uid("h"))
		st.roster[h.uid] = h
		st.party.append(h.uid)
	var found := false
	for d in range(2, 30):
		st.day = d
		st.phase = GameState.Phase.MORNING
		Season.start_day(db, st)
		if not st.candidates.is_empty():
			found = true
			break
	t.ok(found, "a walk-in eventually shows up")
	t.eq(st.candidates.size(), 1, "only one walk-in when the party is full")
	var cand: String = st.candidates[0]
	var sword: String = st.inventory[0].uid
	t.ok(Season.lend(db, st, cand, [sword]) != "", "full party blocks the walk-in")
	var leaving: String = st.party[0]
	t.eq(Season.dismiss(st, leaving), "", "let someone go")
	t.eq(Season.lend(db, st, cand, [sword]), "", "now the walk-in can join")
	t.ok(st.party.has(cand) and st.tavern.has(leaving), "swap done")


func test_every_hero_has_one_rarity_trait(t: TestContext) -> void:
	var counts := {"common": 0, "uncommon": 0, "rare": 0}
	var rng := Rng.new(5)
	for i in 400:
		var h := Hero.create(db, rng, "x%d" % i)
		t.eq(h.traits.size(), 1, "one trait")
		counts[Hero.trait_rarity(db, h)] += 1
	t.ok(counts.common > counts.uncommon and counts.uncommon > counts.rare and counts.rare > 0, "rarity spread %s" % str(counts))


func test_potions(t: TestContext) -> void:
	var h := Hero.create(db, Rng.new(1), "p")
	h.traits = []
	h.class_id = "knight"
	var sword := Gear.create(db, "iron_sword", "s")
	var base := Hero.combat_stats(db, h, [sword])
	var tonic := Hero.combat_stats(db, h, [sword, Gear.create(db, "haste_tonic", "t")])
	t.eq(int(tonic.haste), int(base.haste) + 4, "haste tonic")
	h.traits = ["alchemist"]
	var strong := Hero.combat_stats(db, h, [sword, Gear.create(db, "haste_tonic", "t")])
	t.eq(int(strong.haste), int(base.haste) + 6, "alchemist makes it stronger")
	h.traits = []
	var drank := 0
	for sd in 100:
		var r := RunSimulator.simulate(db, h, [sword, Gear.create(db, "healing_draught", "d")], 3, sd)
		if r.potions_used > 0:
			drank += 1
			var seen := false
			for ev in r.events:
				if ev.type == "potion":
					seen = true
			t.ok(seen, "potion shows in the log")
	t.ok(drank > 0, "heroes drink healing draughts when hurt")


func test_the_party_delves_together(t: TestContext) -> void:
	var st := Season.new_game(db, 31)
	Season.start_day(db, st)
	var weapons: Array = []
	for g in st.inventory:
		if Gear.def_of(db, g).slot == "weapon":
			weapons.append(g.uid)
	var kitted := mini(3, weapons.size())
	for i in kitted:
		t.eq(Season.lend(db, st, st.candidates[i], [weapons[i]]), "", "kit %d" % i)
	var bottom: String = st.party[kitted - 1]
	t.eq(Season.move_in_party(st, bottom, 0), "", "reorder")
	t.eq(Season.delving_party(st)[0], bottom, "moved to the top of the stack")
	Season.set_delve_floor(db, st, 2)
	Season.send_delves(db, st)
	t.eq(st.results.size(), kitted, "one result per hero, from one run")
	t.eq(st.results[0].hero_uid, bottom, "results follow slot order")
	t.eq(int(st.delve.floor), 2, "everyone went to the same floor")
	t.eq(st.delve.party["h0"], bottom, "playback knows who is who")
	var est := Season.estimate_party(db, st, 2, 20)
	t.eq(est.heroes.size(), kitted, "estimate covers the party")


func test_old_save_migrates(t: TestContext) -> void:
	var st := Season.new_game(db, 32)
	var d := st.to_dict()
	d.save_version = 1
	d.erase("delve_floor")
	d.loans = [{"hero": "h1", "gear": [], "floor": 3}, {"hero": "h2", "gear": [], "floor": 2}]
	var back := GameState.from_dict(d)
	t.eq(back.delve_floor, 3, "deepest old loan floor becomes the party floor")
	t.ok(not back.loans[0].has("floor"), "loans lose their floor")
