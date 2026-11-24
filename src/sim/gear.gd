class_name Gear
extends RefCounted
## Helpers for gear instances. A piece of gear is a plain Dictionary:
##   {uid, def, mods: [mod ids], durability, title,
##    history: {runs, kills, deepest, carriers: [names], kill_counts: {monster_id: n}}}
## `def` points at a row in items.json; everything else is this one item's story.


static func create(db: ContentDB, def_id: String, uid: String) -> Dictionary:
	var def := db.get_row("items", def_id)
	return {
		"uid": uid,
		"def": def_id,
		"mods": [],
		"durability": int(def.get("durability", 1)),
		"history": {"runs": 0, "kills": 0, "deepest": 0, "carriers": [], "kill_counts": {}},
		"title": "",
	}


static func def_of(db: ContentDB, gear: Dictionary) -> Dictionary:
	return db.get_row("items", gear.get("def", ""))


static func max_durability(db: ContentDB, gear: Dictionary) -> int:
	return int(def_of(db, gear).get("durability", 1))


static func free_sockets(db: ContentDB, gear: Dictionary) -> int:
	return int(def_of(db, gear).get("sockets", 0)) - gear.get("mods", []).size()


static func value(db: ContentDB, gear: Dictionary) -> int:
	var v := float(def_of(db, gear).get("value", 0))
	for mod_id in gear.get("mods", []):
		v += float(db.get_row("mods", mod_id).get("value", 0))
	if gear.get("title", "") != "":
		v *= 1.0 + float(gear.get("title_bonus", 0.0))
	var dur_ratio := float(gear.get("durability", 0)) / maxf(1.0, max_durability(db, gear))
	return roundi(v * lerpf(0.4, 1.0, dur_ratio))


static func display_name(db: ContentDB, gear: Dictionary) -> String:
	var base: String = def_of(db, gear).get("name", "?")
	if gear.get("title", "") != "":
		return "%s \"%s\"" % [base, gear.title]
	return base


## Records one run on this item. Returns the new title if one was earned.
static func record_run(db: ContentDB, gear: Dictionary, hero_name: String, result: Dictionary) -> String:
	if def_of(db, gear).get("slot", "") == "pack":
		return ""  # potions have no story
	var h: Dictionary = gear.history
	h.runs += 1
	h.kills += int(result.get("total_kills", 0))
	h.deepest = maxi(int(h.deepest), int(result.get("floor", 0)))
	if not h.carriers.has(hero_name):
		h.carriers.append(hero_name)
	var kc: Dictionary = result.get("kills", {})
	for m in kc:
		h.kill_counts[m] = int(h.kill_counts.get(m, 0)) + int(kc[m])
	gear.durability = maxi(0, int(gear.durability) - int(result.get("wear", 0)))
	return _check_title(db, gear)


static func _check_title(db: ContentDB, gear: Dictionary) -> String:
	if gear.get("title", "") != "":
		return ""
	for rule in db.bal("titles", []):
		if int(gear.history.get(rule.get("stat", ""), 0)) >= int(rule.get("at", 1 << 30)):
			var title: String = rule.get("title", "")
			if title.contains("{top_kill}"):
				title = title.replace("{top_kill}", _top_kill_name(db, gear))
			gear.title = title
			gear["title_bonus"] = float(rule.get("value_bonus", 0.0))
			return title
	return ""


static func _top_kill_name(db: ContentDB, gear: Dictionary) -> String:
	var best := ""
	var best_n := -1
	var kc: Dictionary = gear.history.get("kill_counts", {})
	for m in kc:
		if int(kc[m]) > best_n or (int(kc[m]) == best_n and str(m) < best):
			best_n = int(kc[m])
			best = m
	var monster_name: String = db.get_row("monsters", best).get("name", "Monster")
	return monster_name.split(" ")[-1]
