class_name GameState
extends RefCounted
## The single object that is the saved game. Everything needed to resume a
## season lives here and nowhere else; scenes read it and call Season to change it.
##
## Save format: to_dict() -> JSON. When the shape changes, bump SAVE_VERSION and
## add a step to _migrate() so older saves keep loading.

const SAVE_VERSION := 1

enum Phase { MORNING, OUTFIT, DELVE, DUSK, WON, LOST }

var run_seed := 0
var difficulty := "normal"
var day := 1
var phase: Phase = Phase.MORNING
var gold := 0
var next_uid := 1

var inventory: Array = []       # gear on the racks (gear dicts)
var materials: Dictionary = {}  # material id -> qty
var mod_stock: Dictionary = {}  # mod id -> qty, mods waiting to be socketed
var roster: Dictionary = {}     # hero uid -> hero dict, everyone met this season
var counter: Array = []         # hero uids at the counter today
var loans: Array = []           # [{hero, gear: [gear dicts], floor}] gear is off the racks while lent
var results: Array = []         # run results for today's delves (kept so a mid-delve save replays)
var picks_left: Dictionary = {} # hero uid -> cards the player may still take at dusk
var merchant_stock: Array = []  # [{gear, price}] today's wandering merchant offers (empty when not in town)
var memorial: Array = []        # [{hero, class_id, day, floor, killer, gear: [gear dicts]}]
var upgrades: Dictionary = {}   # upgrade id -> level
var stats: Dictionary = {}      # lifetime counters for this season (loans, deaths, gold_earned ...)
var flags: Dictionary = {}      # one-off story / tutorial flags


func new_uid(prefix: String) -> String:
	var id := "%s%d" % [prefix, next_uid]
	next_uid += 1
	return id


func bump_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func find_gear(uid: String) -> Dictionary:
	for g in inventory:
		if g.uid == uid:
			return g
	return {}


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"run_seed": run_seed,
		"difficulty": difficulty,
		"day": day,
		"phase": Phase.keys()[phase],
		"gold": gold,
		"next_uid": next_uid,
		"inventory": inventory,
		"materials": materials,
		"mod_stock": mod_stock,
		"roster": roster,
		"counter": counter,
		"loans": loans,
		"results": results,
		"picks_left": picks_left,
		"merchant_stock": merchant_stock,
		"memorial": memorial,
		"upgrades": upgrades,
		"stats": stats,
		"flags": flags,
	}


static func from_dict(d: Dictionary) -> GameState:
	d = _migrate(d.duplicate(true))
	var s := GameState.new()
	s.run_seed = int(d.get("run_seed", 0))
	s.difficulty = str(d.get("difficulty", "normal"))
	s.day = int(d.get("day", 1))
	s.phase = Phase.get(str(d.get("phase", "MORNING")), Phase.MORNING)
	s.gold = int(d.get("gold", 0))
	s.next_uid = int(d.get("next_uid", 1))
	s.inventory = d.get("inventory", [])
	s.materials = d.get("materials", {})
	s.mod_stock = d.get("mod_stock", {})
	s.roster = d.get("roster", {})
	s.counter = d.get("counter", [])
	s.loans = d.get("loans", [])
	s.results = d.get("results", [])
	s.picks_left = d.get("picks_left", {})
	s.merchant_stock = d.get("merchant_stock", [])
	s.memorial = d.get("memorial", [])
	s.upgrades = d.get("upgrades", {})
	s.stats = d.get("stats", {})
	s.flags = d.get("flags", {})
	_fix_json_numbers(s)
	return s


## JSON has no ints, so counts come back as floats. Normalise the ones that
## matter so `==` comparisons and string formatting behave.
static func _fix_json_numbers(s: GameState) -> void:
	for k in s.materials.keys():
		s.materials[k] = int(s.materials[k])
	for k in s.mod_stock.keys():
		s.mod_stock[k] = int(s.mod_stock[k])
	for k in s.picks_left.keys():
		s.picks_left[k] = int(s.picks_left[k])
	for k in s.stats.keys():
		s.stats[k] = int(s.stats[k])
	for k in s.upgrades.keys():
		s.upgrades[k] = int(s.upgrades[k])
	for h in s.roster.values():
		for key in ["level", "xp", "bond", "runs", "kills", "day_met"]:
			if h.has(key):
				h[key] = int(h[key])
	for offer in s.merchant_stock:
		offer.price = int(offer.price)
	var all_gear: Array = s.inventory.duplicate()
	for offer in s.merchant_stock:
		all_gear.append(offer.gear)
	for loan in s.loans:
		all_gear.append_array(loan.get("gear", []))
	for g in all_gear:
		g.durability = int(g.get("durability", 0))
		var h: Dictionary = g.get("history", {})
		for key in ["runs", "kills", "deepest"]:
			h[key] = int(h.get(key, 0))
		var kc: Dictionary = h.get("kill_counts", {})
		for m in kc.keys():
			kc[m] = int(kc[m])
	for loan in s.loans:
		loan.floor = int(loan.get("floor", 1))


static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("save_version", 1))
	# Example for the future:
	# if v < 2:
	#     d["new_field"] = default
	#     v = 2
	d["save_version"] = v
	return d
