class_name HaulGenerator
extends RefCounted
## Turns what a surviving hero found into the cards they lay on the counter at
## dusk. The player takes one card (two at max Bond); the hero keeps the rest.
##
## Card shapes:
##   {kind: "gold", amount, value}
##   {kind: "materials", material, qty, value}
##   {kind: "mod", mod, value}


static func build(db: ContentDB, loot: Dictionary, stats: Dictionary, floor_def: Dictionary, rng: Rng) -> Array:
	var cards: Array = []
	if int(loot.get("gold", 0)) > 0:
		cards.append(_gold(int(loot.gold)))
	var mats: Dictionary = loot.get("materials", {})
	for mat in mats:
		if int(mats[mat]) > 0:
			cards.append(_materials(db, mat, int(mats[mat])))
	for mod_id in loot.get("mods", []):
		cards.append(_mod(db, mod_id))

	# A poor run still offers a choice: pad with small tips.
	var min_cards := int(db.bal("haul.min_cards", 2))
	while cards.size() < min_cards:
		cards.append(_gold(rng.range_arr(db.bal("haul.tip_gold", [3, 8]))))

	# Loyal heroes show you something extra.
	for i in int(stats.get("extra_cards", 0)):
		cards.append(_bonus_card(db, floor_def, rng))

	# Greedy heroes pocket the best card before you see it.
	if stats.get("hide_best_card", false) and cards.size() > 1:
		var best := 0
		for i in cards.size():
			if int(cards[i].value) > int(cards[best].value):
				best = i
		cards.remove_at(best)
	return cards


static func _gold(amount: int) -> Dictionary:
	return {"kind": "gold", "amount": amount, "value": amount}


static func _materials(db: ContentDB, mat: String, qty: int) -> Dictionary:
	return {"kind": "materials", "material": mat, "qty": qty, "value": qty * int(db.get_row("materials", mat).get("value", 1))}


static func _mod(db: ContentDB, mod_id: String) -> Dictionary:
	return {"kind": "mod", "mod": mod_id, "value": int(db.get_row("mods", mod_id).get("value", 10))}


static func _bonus_card(db: ContentDB, floor_def: Dictionary, rng: Rng) -> Dictionary:
	var monster_id: String = str(rng.weighted(floor_def.get("monsters", {})))
	var drops: Array = db.get_row("monsters", monster_id).get("drops", [])
	if drops.is_empty() or rng.chance(0.4):
		var g: Array = floor_def.get("gold", [5, 10])
		return _gold(rng.range_i(int(g[0]), int(g[1])))
	var d: Dictionary = rng.pick(drops)
	return _materials(db, d.get("material", ""), rng.range_arr(d.get("qty", [1, 1])))
