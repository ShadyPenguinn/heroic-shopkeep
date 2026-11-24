class_name AutoPlayer
extends RefCounted
## A simple, sensible bot that plays a season. Used by the headless season sim
## to check the economy and by the dev "auto" buttons. It is deliberately not
## clever: if this bot can win every time, the game is too easy.

var max_death_risk := 0.2
var estimate_samples := 40


## Plays a whole day from MORNING through end_day. Returns end_day's result.
func play_day(db: ContentDB, st: GameState) -> Dictionary:
	Season.start_day(db, st)
	shop_merchant(db, st)
	outfit(db, st)
	Season.send_delves(db, st)
	Season.begin_dusk(db, st)
	pick_cards(db, st)
	tend_shop(db, st)
	return Season.end_day(db, st)


## Buys gear that fills a gap on the racks, keeping enough gold for the coming rent.
func shop_merchant(db: ContentDB, st: GameState) -> Array:
	var bought: Array = []
	var reserve := int(Season.next_rent(db, st).amount)
	var buying := true
	while buying:
		buying = false
		var best := -1
		var best_score := 0.0
		for i in st.merchant_stock.size():
			var offer: Dictionary = st.merchant_stock[i]
			if st.gold - int(offer.price) < reserve:
				continue
			var def := Gear.def_of(db, offer.gear)
			var have := 0
			for g in st.inventory:
				if Gear.def_of(db, g).slot == def.slot and int(g.durability) > 0:
					have += 1
			var score := float(def.get("tier", 1)) * 10.0 / maxf(1.0, float(have)) - float(offer.price) * 0.05
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			bought.append(st.merchant_stock[best].gear)
			Season.buy(db, st, best)
			buying = true
	return bought


func outfit(db: ContentDB, st: GameState) -> void:
	var heroes: Array = st.counter.duplicate()
	heroes.sort_custom(func(a, b): return int(st.roster[a].level) > int(st.roster[b].level))
	var boss_day := Season.is_boss_day(db, st)
	for i in heroes.size():
		var uid: String = heroes[i]
		var kit := _best_kit(db, st, uid)
		var gear: Array = []
		for g in kit:
			gear.append(g)
		var floor_index := 1
		if boss_day and i == 0:
			floor_index = int(db.bal("boss.floor", 5))
		else:
			for f in range(db.floor_count(), 0, -1):
				var est := Season.estimate_loan(db, st, uid, gear, f, estimate_samples)
				if est.death_rate <= max_death_risk:
					floor_index = f
					break
		var uids: Array = []
		for g in gear:
			uids.append(g.uid)
		Season.lend(db, st, uid, uids, floor_index)


func _best_kit(db: ContentDB, st: GameState, hero_uid: String) -> Array:
	var cls := db.get_row("classes", st.roster[hero_uid].class_id)
	var kinds: Array = cls.get("weapons", [])
	var best := {}
	for g in st.inventory:
		if int(g.durability) <= 0:
			continue
		var def := Gear.def_of(db, g)
		var slot: String = def.get("slot", "")
		var score: float = float(def.get("tier", 1)) * 10.0 + g.mods.size() * 4.0
		if slot == "weapon" and not kinds.has(def.get("kind")):
			score -= 25.0
		if not best.has(slot) or score > best[slot].score:
			best[slot] = {"gear": g, "score": score}
	var kit: Array = []
	for slot in best:
		if best[slot].score > 0.0:
			kit.append(best[slot].gear)
	return kit


func pick_cards(db: ContentDB, st: GameState) -> void:
	for r in st.results:
		while int(st.picks_left.get(r.hero_uid, 0)) > 0:
			var rent := Season.next_rent(db, st)
			var need_gold := st.gold < int(rent.amount)
			var best := -1
			var best_score := -1.0
			for i in r.haul.size():
				var c: Dictionary = r.haul[i]
				if c.get("taken", false):
					continue
				var score := float(c.value)
				if need_gold and c.kind == "gold":
					score *= 3.0
				if score > best_score:
					best_score = score
					best = i
			if best < 0:
				break
			Season.take_card(db, st, r.hero_uid, best)


func tend_shop(db: ContentDB, st: GameState) -> void:
	# Socket any mod we can afford onto the best gear with a free socket.
	for mod_id in st.mod_stock.keys():
		while int(st.mod_stock.get(mod_id, 0)) > 0:
			var target := ""
			var best_tier := -1
			for g in st.inventory:
				if Season.can_socket(db, st, g.uid, mod_id) == "":
					var tier := int(Gear.def_of(db, g).get("tier", 1))
					if tier > best_tier:
						best_tier = tier
						target = g.uid
			if target == "" or Season.socket_mod(db, st, target, mod_id) != "":
				break
	# Repair badly worn gear if rent is covered.
	var rent := Season.next_rent(db, st)
	for g in st.inventory:
		if float(g.durability) / Gear.max_durability(db, g) < 0.4:
			var cost := Season.repair_cost(db, st, g.uid)
			if st.gold - cost >= int(rent.amount):
				Season.repair(db, st, g.uid)
