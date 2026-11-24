class_name Season
extends RefCounted
## The rules of a season, as plain functions over (GameState, ContentDB).
##
## No nodes, no signals, no UI: the Game autoload calls these and announces what
## changed. Keeping the rules here means the headless season sim plays exactly
## the same game the player does.
##
## A day:   start_day -> lend / turn_away (outfit) -> send_delves -> begin_dusk
##          -> take_card (per survivor) -> end_day
## Functions that can fail return "" on success or a short reason string.


static func new_game(db: ContentDB, seed_value: int, difficulty: String = "normal") -> GameState:
	var st := GameState.new()
	st.run_seed = seed_value
	st.difficulty = difficulty
	st.gold = int(db.bal("start_gold", 50))
	for item_id in db.bal("start_inventory", []):
		st.inventory.append(Gear.create(db, item_id, st.new_uid("g")))
	return st


static func is_boss_day(db: ContentDB, st: GameState) -> bool:
	return st.day == int(db.bal("boss.day", 28))


static func rent_due_today(db: ContentDB, st: GameState) -> int:
	var interval := int(db.bal("rent_interval", 7))
	if st.day % interval != 0:
		return 0
	var table: Array = db.bal("rent", [50])
	var idx := mini(st.day / interval - 1, table.size() - 1)
	return int(table[idx])


static func next_rent(db: ContentDB, st: GameState) -> Dictionary:
	var interval := int(db.bal("rent_interval", 7))
	var due_day := int(ceil(float(st.day) / interval)) * interval
	var table: Array = db.bal("rent", [50])
	var idx := mini(due_day / interval - 1, table.size() - 1)
	return {"day": due_day, "amount": int(table[idx])}


# --- morning -----------------------------------------------------------------

static func start_day(db: ContentDB, st: GameState) -> void:
	assert(st.phase == GameState.Phase.MORNING)
	var rng := Rng.new(Rng.derive(st.run_seed, ["counter", st.day]))
	st.counter.clear()
	st.loans.clear()
	st.results.clear()
	st.picks_left.clear()
	var size_range: Array = db.bal("counter_size", [2, 4])
	var want := rng.range_i(int(size_range[0]), int(size_range[1]) + int(st.upgrades.get("counter_spot", 0)))
	# Regulars first: living heroes come back more often the higher their Bond.
	var regulars: Array = []
	for uid in st.roster:
		var h: Dictionary = st.roster[uid]
		if not h.alive:
			continue
		var p := float(db.bal("hero.return_chance_base", 0.3)) + int(h.bond) * float(db.bal("hero.return_chance_per_bond", 0.12))
		if rng.chance(p):
			regulars.append(uid)
	rng.shuffle(regulars)
	for uid in regulars:
		if st.counter.size() >= want:
			break
		st.counter.append(uid)
	while st.counter.size() < want:
		var h := Hero.create(db, rng, st.new_uid("h"), st.day)
		st.roster[h.uid] = h
		st.counter.append(h.uid)
	_stock_merchant(db, st)
	st.phase = GameState.Phase.OUTFIT


# --- the wandering merchant -------------------------------------------------------

static func is_merchant_day(db: ContentDB, st: GameState) -> bool:
	var interval := int(db.bal("rent_interval", 7))
	return (st.day - 1) % interval + 1 == int(db.bal("merchant.week_day", 4))


## The next day the merchant is in town (today counts if it's a merchant day).
static func next_merchant_day(db: ContentDB, st: GameState) -> int:
	var interval := int(db.bal("rent_interval", 7))
	var week_day := int(db.bal("merchant.week_day", 4))
	var week_start := ((st.day - 1) / interval) * interval
	var d := week_start + week_day
	if d < st.day:
		d += interval
	return d


static func _stock_merchant(db: ContentDB, st: GameState) -> void:
	st.merchant_stock.clear()
	if not is_merchant_day(db, st):
		return
	var rng := Rng.new(Rng.derive(st.run_seed, ["merchant", st.day]))
	var week := (st.day - 1) / int(db.bal("rent_interval", 7))
	var weights_table: Array = db.bal("merchant.tier_weights_by_week", [[1, 0, 0]])
	var weights: Array = weights_table[mini(week, weights_table.size() - 1)]
	var tier_weights := {}
	for i in weights.size():
		tier_weights[i + 1] = float(weights[i])
	var by_tier := {}
	for it in db.rows("items"):
		var tier := int(it.get("tier", 1))
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(it.id)
	var price_range: Array = db.bal("merchant.price_mult", [1.0, 1.0])
	for i in rng.range_arr(db.bal("merchant.stock_size", [4, 6])):
		var tier: int = rng.weighted(tier_weights)
		var item_id: String = rng.pick(by_tier.get(tier, by_tier[1]))
		var g := Gear.create(db, item_id, st.new_uid("g"))
		var price := roundi(float(Gear.def_of(db, g).get("value", 10)) * rng.range_f(float(price_range[0]), float(price_range[1])))
		st.merchant_stock.append({"gear": g, "price": price})


static func buy(db: ContentDB, st: GameState, offer_index: int) -> String:
	if offer_index < 0 or offer_index >= st.merchant_stock.size():
		return "the merchant has nothing like that"
	var offer: Dictionary = st.merchant_stock[offer_index]
	if st.gold < int(offer.price):
		return "not enough gold"
	st.gold -= int(offer.price)
	st.inventory.append(offer.gear)
	st.merchant_stock.remove_at(offer_index)
	st.bump_stat("gold_spent_gear", int(offer.price))
	st.bump_stat("gear_bought")
	return ""


# --- outfitting ----------------------------------------------------------------

static func lend(db: ContentDB, st: GameState, hero_uid: String, gear_uids: Array, floor_index: int) -> String:
	if st.phase != GameState.Phase.OUTFIT:
		return "not outfitting"
	if not st.counter.has(hero_uid):
		return "hero is not at the counter"
	if floor_index < 1 or floor_index > db.floor_count():
		return "no such floor"
	# Gear can come from the racks or from this hero's current loan (re-outfitting).
	var available: Array = st.inventory.duplicate()
	available.append_array(loan_for(st, hero_uid).get("gear", []))
	var slots_used := {}
	for uid in gear_uids:
		var g := {}
		for candidate in available:
			if candidate.uid == uid:
				g = candidate
		if g.is_empty():
			return "gear %s is not on the racks" % uid
		var slot: String = Gear.def_of(db, g).get("slot", "")
		if slots_used.has(slot):
			return "two items in the %s slot" % slot
		slots_used[slot] = true
	# Valid: return any previous loan to the racks, then take the new kit.
	unlend(st, hero_uid)
	var gear: Array = []
	for uid in gear_uids:
		var g := st.find_gear(uid)
		st.inventory.erase(g)
		gear.append(g)
	st.loans.append({"hero": hero_uid, "gear": gear, "floor": floor_index})
	return ""


static func unlend(st: GameState, hero_uid: String) -> void:
	for loan in st.loans.duplicate():
		if loan.hero == hero_uid:
			st.inventory.append_array(loan.gear)
			st.loans.erase(loan)


static func turn_away(st: GameState, hero_uid: String) -> void:
	unlend(st, hero_uid)
	st.counter.erase(hero_uid)


static func loan_for(st: GameState, hero_uid: String) -> Dictionary:
	for loan in st.loans:
		if loan.hero == hero_uid:
			return loan
	return {}


static func estimate_loan(db: ContentDB, st: GameState, hero_uid: String, gear: Array, floor_index: int, samples: int = -1) -> Dictionary:
	var opts := {}
	if is_boss_day(db, st) and floor_index >= int(db.bal("boss.floor", 5)):
		opts["boss"] = db.bal("boss.monster", "")
	var seed_value := Rng.derive(st.run_seed, ["estimate", st.day, hero_uid])
	return SurvivalEstimator.estimate(db, st.roster[hero_uid], gear, floor_index, seed_value, samples, opts)


# --- the delve -----------------------------------------------------------------

static func send_delves(db: ContentDB, st: GameState) -> void:
	assert(st.phase == GameState.Phase.OUTFIT)
	st.results.clear()
	for loan in st.loans:
		var hero: Dictionary = st.roster[loan.hero]
		var opts := {}
		if is_boss_day(db, st) and int(loan.floor) >= int(db.bal("boss.floor", 5)):
			opts["boss"] = db.bal("boss.monster", "")
		var seed_value := Rng.derive(st.run_seed, ["delve", st.day, loan.hero])
		st.results.append(RunSimulator.simulate(db, hero, loan.gear, int(loan.floor), seed_value, opts))
		st.bump_stat("loans")
	st.phase = GameState.Phase.DELVE


# --- dusk ------------------------------------------------------------------------

## Applies every run's consequences and returns a report the UI can stage:
## [{hero, outcome, titles: [{gear, title}], level_up, bond_delta, lost_gear: [...]}]
static func begin_dusk(db: ContentDB, st: GameState) -> Array:
	assert(st.phase == GameState.Phase.DELVE)
	var report: Array = []
	for r in st.results:
		var loan := loan_for(st, r.hero_uid)
		var hero: Dictionary = st.roster[r.hero_uid]
		var entry := {"hero": hero.uid, "outcome": r.outcome, "titles": [], "level_up": false, "bond_delta": 0, "lost_gear": []}
		hero.runs = int(hero.runs) + 1
		hero.kills = int(hero.kills) + int(r.total_kills)
		if r.outcome == "died":
			hero.alive = false
			entry.lost_gear = loan.gear.duplicate()
			st.memorial.append({
				"hero": hero.name, "class_id": hero.class_id, "day": st.day,
				"floor": r.floor, "killer": _killer_of(r), "gear": loan.gear.duplicate(true),
			})
			st.bump_stat("deaths")
			st.bump_stat("gear_lost", loan.gear.size())
		else:
			for g in loan.gear:
				var title := Gear.record_run(db, g, hero.name, r)
				if title != "":
					entry.titles.append({"gear": g.uid, "title": title})
				st.inventory.append(g)
			var old_level := int(hero.level)
			hero.xp = int(hero.xp) + int(r.xp)
			hero.level = Hero.level_for_xp(db, int(hero.xp))
			entry.level_up = int(hero.level) > old_level
			var bond_delta := 0.0
			if r.outcome == "survived":
				bond_delta += float(db.bal("bond.safe_return", 1))
			for g in loan.gear:
				if int(Gear.def_of(db, g).get("tier", 1)) >= int(db.bal("bond.good_gear_tier", 2)):
					bond_delta += float(db.bal("bond.good_gear", 1))
					break
			var stats := Hero.combat_stats(db, hero, [])
			bond_delta *= float(stats.bond_mult)
			var max_bond := int(db.bal("bond.max", 5))
			var before := int(hero.bond)
			hero.bond = clampi(before + roundi(bond_delta), 0, max_bond)
			entry.bond_delta = int(hero.bond) - before
			if not r.haul.is_empty():
				st.picks_left[hero.uid] = 2 if int(hero.bond) >= max_bond else 1
		report.append(entry)
	st.loans.clear()
	st.phase = GameState.Phase.DUSK
	return report


static func _killer_of(r: Dictionary) -> String:
	for i in range(r.events.size() - 1, -1, -1):
		if r.events[i].type == "death":
			return r.events[i].get("killer", "")
	return ""


static func result_for(st: GameState, hero_uid: String) -> Dictionary:
	for r in st.results:
		if r.hero_uid == hero_uid:
			return r
	return {}


static func take_card(db: ContentDB, st: GameState, hero_uid: String, card_index: int) -> String:
	if st.phase != GameState.Phase.DUSK:
		return "not dusk"
	if int(st.picks_left.get(hero_uid, 0)) <= 0:
		return "no picks left from this hero"
	var r := result_for(st, hero_uid)
	if card_index < 0 or card_index >= r.haul.size():
		return "no such card"
	var card: Dictionary = r.haul[card_index]
	if card.get("taken", false):
		return "already taken"
	card["taken"] = true
	match card.kind:
		"gold":
			st.gold += int(card.amount)
			st.bump_stat("gold_earned", int(card.amount))
		"materials":
			st.materials[card.material] = int(st.materials.get(card.material, 0)) + int(card.qty)
		"mod":
			st.mod_stock[card.mod] = int(st.mod_stock.get(card.mod, 0)) + 1
	st.picks_left[hero_uid] = int(st.picks_left[hero_uid]) - 1
	return ""


## Ends the day: rent, boss outcome, advance. Returns {rent, paid, won, lost}.
static func end_day(db: ContentDB, st: GameState) -> Dictionary:
	assert(st.phase == GameState.Phase.DUSK)
	var out := {"rent": 0, "paid": false, "won": false, "lost": false}
	var rent := rent_due_today(db, st)
	if rent > 0:
		out.rent = rent
		if st.gold >= rent:
			st.gold -= rent
			out.paid = true
			st.bump_stat("rent_paid")
		else:
			out.lost = true
	if is_boss_day(db, st) and not out.lost:
		var won := false
		for r in st.results:
			if r.get("boss_killed", false):
				won = true
		out.won = won
		out.lost = not won
	st.counter.clear()
	st.results.clear()
	st.picks_left.clear()
	st.merchant_stock.clear()  # the merchant moves on at nightfall
	if out.won:
		st.phase = GameState.Phase.WON
	elif out.lost:
		st.phase = GameState.Phase.LOST
	else:
		st.day += 1
		st.phase = GameState.Phase.MORNING
	return out


# --- the workbench and the buyer -------------------------------------------------

static func can_socket(db: ContentDB, st: GameState, gear_uid: String, mod_id: String) -> String:
	var g := st.find_gear(gear_uid)
	if g.is_empty():
		return "gear is not on the racks"
	if int(st.mod_stock.get(mod_id, 0)) <= 0:
		return "you don't have that mod"
	if Gear.free_sockets(db, g) <= 0:
		return "no free socket"
	var cost: Dictionary = db.get_row("mods", mod_id).get("cost", {})
	for mat in cost:
		if int(st.materials.get(mat, 0)) < int(cost[mat]):
			return "not enough %s" % db.get_row("materials", mat).get("name", mat)
	return ""


static func socket_mod(db: ContentDB, st: GameState, gear_uid: String, mod_id: String) -> String:
	var err := can_socket(db, st, gear_uid, mod_id)
	if err != "":
		return err
	var cost: Dictionary = db.get_row("mods", mod_id).get("cost", {})
	for mat in cost:
		st.materials[mat] = int(st.materials[mat]) - int(cost[mat])
	st.mod_stock[mod_id] = int(st.mod_stock[mod_id]) - 1
	st.find_gear(gear_uid).mods.append(mod_id)
	return ""


static func repair_cost(db: ContentDB, st: GameState, gear_uid: String) -> int:
	var g := st.find_gear(gear_uid)
	if g.is_empty():
		return 0
	return (Gear.max_durability(db, g) - int(g.durability)) * int(db.bal("repair_cost_per_point", 1))


static func repair(db: ContentDB, st: GameState, gear_uid: String) -> String:
	var cost := repair_cost(db, st, gear_uid)
	if cost <= 0:
		return "nothing to repair"
	if st.gold < cost:
		return "not enough gold"
	st.gold -= cost
	var g := st.find_gear(gear_uid)
	g.durability = Gear.max_durability(db, g)
	return ""


static func sell_gear(db: ContentDB, st: GameState, gear_uid: String) -> String:
	var g := st.find_gear(gear_uid)
	if g.is_empty():
		return "gear is not on the racks"
	var price := roundi(Gear.value(db, g) * float(db.bal("sell_mult", 0.5)))
	st.gold += price
	st.inventory.erase(g)
	st.bump_stat("gold_earned", price)
	return ""
