class_name Hero
extends RefCounted
## Helpers for hero records. A hero is a plain Dictionary so it saves as JSON
## with no glue code:
##   {uid, name, class_id, level, xp, traits: [ids], bond, alive, tint: [r,g,b],
##    runs, kills, deaths_witnessed, day_met}

const STAT_KEYS: PackedStringArray = ["might", "guard", "nerve", "luck"]


static func create(db: ContentDB, rng: Rng, uid: String, day: int = 1) -> Dictionary:
	var class_id: String = rng.pick(db.ids("classes"))
	var trait_pool := db.ids("traits")
	rng.shuffle(trait_pool)
	var first: Array = db.names.get("first", ["Hero"])
	var epithets: Array = db.names.get("epithet", [""])
	var hero_name: String = rng.pick(first)
	if rng.chance(0.35):
		hero_name += " " + str(rng.pick(epithets))
	# Higher days bring slightly more experienced walk-ins.
	var level := 1
	if day > 7 and rng.chance(0.5):
		level = 2
	if day > 14 and rng.chance(0.5):
		level += 1
	var xp_table: Array = db.bal("hero.xp_per_level", [0])
	var xp := int(xp_table[mini(level - 1, xp_table.size() - 1)])
	return {
		"uid": uid,
		"name": hero_name,
		"class_id": class_id,
		"level": level,
		"xp": xp,
		"traits": trait_pool.slice(0, 2),
		"bond": 0,
		"alive": true,
		"tint": [rng.range_f(0.85, 1.0), rng.range_f(0.85, 1.0), rng.range_f(0.85, 1.0)],
		"runs": 0,
		"kills": 0,
		"day_met": day,
	}


static func level_for_xp(db: ContentDB, xp: int) -> int:
	var table: Array = db.bal("hero.xp_per_level", [0])
	var level := 1
	for i in table.size():
		if xp >= int(table[i]):
			level = i + 1
	return level


## Everything the simulation needs about a hero carrying some gear, flattened
## into one Dictionary. `gear` is an Array of gear Dictionaries (see Gear).
static func combat_stats(db: ContentDB, hero: Dictionary, gear: Array) -> Dictionary:
	var cls := db.get_row("classes", hero.get("class_id", ""))
	var level := int(hero.get("level", 1))
	var s := {
		"max_hp": int(cls.get("hp", 20)) + (level - 1) * int(db.bal("hero.hp_per_level", 5)),
		"might": int(cls.get("might", 1)) + (level - 1) * int(db.bal("hero.might_per_level", 1)),
		"guard": int(cls.get("guard", 0)) + (level - 1) / maxi(1, int(db.bal("hero.guard_every_levels", 2))),
		"nerve": int(cls.get("nerve", 0)),
		"luck": int(cls.get("luck", 0)),
		"block": float(cls.get("block", 0.0)),
		"role": str(cls.get("role", "front")),
		"element": "",
		"actions": {},
		"crit": 0.0,
		"loot_mult": 1.0,
		"extra_cards": 0,
		"hide_best_card": false,
		"depth_bonus": 0,
		"wear_mult": 1.0,
		"xp_mult": 1.0,
		"bond_mult": 1.0,
		"nerve_threshold_mod": 0.0,
	}
	var weapon_kinds: Array = cls.get("weapons", [])
	for g in gear:
		var def := db.get_row("items", g.get("def", ""))
		if def.is_empty():
			continue
		var mult := 1.0
		if int(g.get("durability", 1)) <= 0:
			mult = float(db.bal("combat.broken_gear_stat_mult", 0.0))
		elif def.get("slot") == "weapon" and not weapon_kinds.has(def.get("kind")):
			mult = 0.5  # wrong weapon type for this class: half the benefit
		_add_stats(s, def.get("stats", {}), mult)
		for mod_id in g.get("mods", []):
			var mod := db.get_row("mods", mod_id)
			match mod.get("kind", ""):
				"element":
					s.element = mod.get("element", "")
				"stat":
					_add_stats(s, mod.get("stats", {}), 1.0)
				"action":
					s.actions[mod.get("action", "")] = true
	for trait_id in hero.get("traits", []):
		var fx: Dictionary = db.get_row("traits", trait_id).get("effects", {})
		_add_stats(s, fx, 1.0)
		s.nerve_threshold_mod += float(fx.get("nerve_threshold", 0.0))
		s.crit += float(fx.get("crit", 0.0))
		s.loot_mult *= float(fx.get("loot_mult", 1.0))
		s.extra_cards += int(fx.get("extra_cards", 0))
		s.depth_bonus += int(fx.get("depth_bonus", 0))
		s.wear_mult *= float(fx.get("wear_mult", 1.0))
		s.xp_mult *= float(fx.get("xp_mult", 1.0))
		s.bond_mult *= float(fx.get("bond_mult", 1.0))
		if fx.get("hide_best_card", false):
			s.hide_best_card = true
	s.max_hp = maxi(1, s.max_hp)
	s.might = maxi(1, s.might)
	s.guard = maxi(0, s.guard)
	s.crit += float(db.bal("combat.crit_base", 0.05)) + s.luck * float(db.bal("combat.crit_per_luck", 0.015))
	s["dodge"] = s.luck * float(db.bal("combat.dodge_per_luck", 0.012))
	var t: float = float(db.bal("nerve.base_threshold", 0.45)) - float(s.nerve) * float(db.bal("nerve.per_point", 0.04))
	t += s.nerve_threshold_mod
	s["nerve_threshold"] = clampf(t, float(db.bal("nerve.min", 0.05)), float(db.bal("nerve.max", 0.7)))
	return s


static func _add_stats(s: Dictionary, stats: Dictionary, mult: float) -> void:
	for k in ["might", "guard", "nerve", "luck"]:
		if stats.has(k):
			s[k] += roundi(float(stats[k]) * mult)
	if stats.has("hp"):
		s.max_hp += roundi(float(stats["hp"]) * mult)


static func display_name(db: ContentDB, hero: Dictionary) -> String:
	return "%s the %s" % [hero.get("name", "?"), db.get_row("classes", hero.get("class_id", "")).get("name", "?")]
