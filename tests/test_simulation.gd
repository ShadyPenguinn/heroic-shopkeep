extends RefCounted

var db := ContentDB.load_from()


func _hero(class_id: String = "knight") -> Dictionary:
	var h := Hero.create(db, Rng.new(7), "h1")
	h.class_id = class_id
	h.traits = []  # traits like Glory-hound would change the floor under test
	return h


func _kit(ids: Array) -> Array:
	var out: Array = []
	for i in ids.size():
		out.append(Gear.create(db, ids[i], "g%d" % i))
	return out


func test_same_seed_same_run(t: TestContext) -> void:
	var gear := _kit(["iron_sword", "leather_vest"])
	for s in [1, 42, 999999]:
		var a := RunSimulator.simulate(db, _hero(), gear, 2, s)
		var b := RunSimulator.simulate(db, _hero(), gear, 2, s)
		t.eq(JSON.stringify(a), JSON.stringify(b), "seed %d:" % s)


func test_different_seeds_differ(t: TestContext) -> void:
	var gear := _kit(["iron_sword"])
	var logs := {}
	for s in 20:
		logs[JSON.stringify(RunSimulator.simulate(db, _hero(), gear, 2, s).events)] = true
	t.ok(logs.size() > 15, "20 seeds should give mostly different runs (got %d)" % logs.size())


func test_event_log_is_well_formed(t: TestContext) -> void:
	var gear := _kit(["iron_sword", "leather_vest"])
	for s in 200:
		var r := RunSimulator.simulate(db, _hero("wizard"), gear, 3, s)
		t.eq(r.events[0].type, "run_start", "first event")
		t.eq(r.events[-1].type, "run_end", "last event")
		t.eq(r.events[-1].outcome, r.outcome, "run_end outcome")
		if r.outcome == "died":
			t.ok(r.haul.is_empty(), "the dead bring nothing back")
			t.eq(r.events[-2].type, "death", "death before run_end")
		else:
			t.ok(r.haul.size() >= 1, "survivors bring a haul")
		if not t.failures.is_empty():
			return


func test_quick_sim_matches_recorded_sim(t: TestContext) -> void:
	# Estimates run without the event log; outcomes must not change because of it.
	var gear := _kit(["steel_sword", "chain_mail"])
	for s in 100:
		var a := RunSimulator.simulate(db, _hero(), gear, 4, s)
		var b := RunSimulator.simulate(db, _hero(), gear, 4, s, {"record_events": false})
		t.eq(b.outcome, a.outcome, "seed %d outcome" % s)
		t.eq(b.hp_left, a.hp_left, "seed %d hp" % s)


func test_deeper_is_deadlier(t: TestContext) -> void:
	var gear := _kit(["iron_sword", "leather_vest"])
	var shallow := SurvivalEstimator.estimate(db, _hero(), gear, 1, 5, 300)
	var deep := SurvivalEstimator.estimate(db, _hero(), gear, 5, 5, 300)
	t.ok(deep.death_rate > shallow.death_rate, "floor 5 (%.2f) should kill more than floor 1 (%.2f)" % [deep.death_rate, shallow.death_rate])


func test_better_gear_is_safer(t: TestContext) -> void:
	var iron := SurvivalEstimator.estimate(db, _hero(), _kit(["iron_sword", "leather_vest"]), 4, 9, 300)
	var mythril := SurvivalEstimator.estimate(db, _hero(), _kit(["mythril_blade", "mythril_plate", "mythril_ring"]), 4, 9, 300)
	t.ok(mythril.death_rate < iron.death_rate, "mythril (%.2f) should beat iron (%.2f)" % [mythril.death_rate, iron.death_rate])


func test_element_weakness_shows_in_log(t: TestContext) -> void:
	var gear := _kit(["iron_sword"])
	gear[0].mods.append("holy_rune")
	var weak_hits := 0
	for s in 50:
		for ev in RunSimulator.simulate(db, _hero(), gear, 2, s).events:  # crypt: skeletons, weak to holy
			if ev.type == "attack" and ev.eff == "weak":
				weak_hits += 1
	t.ok(weak_hits > 0, "holy rune should hit skeletons for WEAK damage")


func test_greedy_hides_a_card_loyal_adds_one(t: TestContext) -> void:
	var loot := {"gold": 20, "materials": {"bone_dust": 2, "orc_iron": 1}, "mods": []}
	var floor_def := db.floor_by_index(1)
	var plain := HaulGenerator.build(db, loot, {}, floor_def, Rng.new(1))
	var greedy := HaulGenerator.build(db, loot, {"hide_best_card": true}, floor_def, Rng.new(1))
	var loyal := HaulGenerator.build(db, loot, {"extra_cards": 1}, floor_def, Rng.new(1))
	t.eq(greedy.size(), plain.size() - 1, "greedy")
	t.eq(loyal.size(), plain.size() + 1, "loyal")


func test_sim_speed(t: TestContext) -> void:
	var gear := _kit(["iron_sword", "leather_vest"])
	var t0 := Time.get_ticks_usec()
	for s in 1000:
		RunSimulator.simulate(db, _hero(), gear, 3, s, {"record_events": false})
	var per_sim_us := (Time.get_ticks_usec() - t0) / 1000.0
	print("        (%.0f us per quick sim)" % per_sim_us)
	t.ok(per_sim_us < 2000.0, "a quick sim should take well under 2 ms (took %.0f us)" % per_sim_us)


func test_haste_means_more_actions(t: TestContext) -> void:
	# Same fights, faster hero: the hero should act more often relative to monsters.
	var ratios: Array = []
	for haste_bonus in [0, 6]:
		var h := _hero("soldier")
		var gear := _kit(["iron_sword"])
		var hero_acts := 0
		var monster_acts := 0
		for sd in 100:
			var db2 := db
			var hh := h.duplicate(true)
			var r := RunSimulator.simulate(db2, hh, gear, 2, sd)
			# haste via a stat mod stack: quicksilver x3 = +6
			if haste_bonus > 0:
				var g2 := _kit(["iron_sword"])
				g2[0].mods = ["quicksilver", "quicksilver", "quicksilver"]
				r = RunSimulator.simulate(db, hh, g2, 2, sd)
			for ev in r.events:
				if ev.type in ["attack", "miss"] and ev.get("tag", "") == "" and ev.actor == "hero":
					hero_acts += 1
				elif ev.type in ["hit", "block", "dodge"]:
					monster_acts += 1
		ratios.append(float(hero_acts) / maxi(1, monster_acts))
	t.ok(ratios[1] > ratios[0] * 1.3, "faster hero should act much more often (%.2f vs %.2f)" % [ratios[1], ratios[0]])


func test_meters_in_log(t: TestContext) -> void:
	var r := RunSimulator.simulate(db, _hero(), _kit(["iron_sword"]), 1, 3)
	var found := false
	for ev in r.events:
		if ev.type == "attack":
			found = ev.has("meters") and ev.has("tick") and ev.meters.has("hero")
			break
	t.ok(found, "attack events carry tick and meter snapshot for playback")
