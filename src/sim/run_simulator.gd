class_name RunSimulator
extends RefCounted
## Resolves the party's delve, start to finish, the moment they leave the shop.
## The whole party (up to four heroes) walks one floor together and fights every
## room side by side.
##
## Pure and seeded: the same (content, party, floor, seed) always gives the same
## result. It never touches nodes, autoloads, time or the global RNG, so it runs
## headless, thousands of times a second, for estimates and balance tools.
##
## Output is a result Dictionary whose "events" array is the event log the
## playback layer animates. Playback never decides anything; it only shows what
## is in the log. See EVENT TYPES below.
##
## ACTORS: heroes are "h0".."h3" by party slot (slot 0 is the top of the stack
## and draws the most attacks); monsters are "m0".."mN" by row.
##
## EVENT TYPES (every event has "type")
##   run_start   {floor, rooms, party: [{key, uid, hp, max_hp, element, haste}]}
##   room_enter  {index, kind}                       kind: fight|treasure|trap|rest|boss
##   spawn       {monsters: [{key, id, hp, max_hp, haste}]}
##   attack      {actor, target, dmg, crit, eff, element, hp, tag}   a hero hits a monster. eff: weak|resist|""  tag: ""|cleave|riposte
##   miss        {actor, target}                      a hero misses
##   dodge       {actor, target}                      a hero dodged a monster
##   block       {actor, target}                      a hero blocked a monster
##   hit         {actor, target, dmg, hp}             a monster hurt a hero
##   status      {target, status}                     burn|chill|stagger|stun
##   status_tick {target, status, dmg, hp}
##   skip_turn   {actor, status}                      stunned: the full meter is spent doing nothing
##   heal        {actor, target, amount, hp, source}  source: rest|prayer|second_wind|potion
##   potion      {actor, item, uses_left}             a hero drinks a healing draught
##   kill        {actor, target, id}
##   drop        {actor, material, qty}               goes into the killer's haul
##   treasure    {gold: {hero key: amount}, mod, finder}
##   trap        {target, dmg, dodged, hp}
##   retreat     {actor, hp, reason}                  one hero heads home. reason: nerve|panic
##   death       {target, killer}                     one hero falls
##   run_end     {outcome}                            cleared|retreated|wiped
##
## Per-hero outcomes (in result.heroes) are survived|retreated|died, as before.

const SIM_VERSION := 3  # 3: the party delves together; 2: Haste action meters
const METER_FULL := 100
## Events where someone acts carry "tick" and a "meters" snapshot {actor key: 0..99}
## so playback can draw action bars that match the simulation.
const METER_EVENTS: PackedStringArray = ["attack", "hit", "miss", "dodge", "block", "skip_turn", "heal", "status_tick", "potion"]

var db: ContentDB
var rng: Rng
var record := true
var events: Array = []

var heroes: Array = []     # hero units, by slot
var monsters: Array = []
var floor_def: Dictionary
var boss_killed := false
var tick := -1   # combat tick, -1 outside fights


## A party of one. Returns that hero's result plus the run's events, so solo
## callers (sandbox, tests) read r.outcome, r.haul, r.events as before.
## opts: {record_events: bool = true, boss: monster_id = ""}
static func simulate(content: ContentDB, hero: Dictionary, gear: Array, floor_index: int, seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var party := simulate_party(content, [{"hero": hero, "gear": gear}], floor_index, seed_value, opts)
	var r: Dictionary = party.heroes[0]
	r["events"] = party.events
	r["party_outcome"] = party.outcome
	return r


## members: [{hero, gear}] in slot order (top of the stack first).
static func simulate_party(content: ContentDB, members: Array, floor_index: int, seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var sim := RunSimulator.new()
	return sim._run(content, members, floor_index, seed_value, opts)


func _run(content: ContentDB, members: Array, floor_index: int, seed_value: int, opts: Dictionary) -> Dictionary:
	db = content
	rng = Rng.new(seed_value)
	record = opts.get("record_events", true)
	var depth_bonus := 0
	for i in members.size():
		var s := Hero.combat_stats(db, members[i].hero, members[i].gear)
		depth_bonus = maxi(depth_bonus, int(s.depth_bonus))
		heroes.append({
			"key": "h%d" % i, "uid": members[i].hero.get("uid", ""), "slot": i, "s": s,
			"hp": int(s.max_hp), "meter": 0, "state": "in",
			"second_wind_used": false, "potions_used": 0, "prayed": false,
			"damage_taken": 0, "kills": {}, "total_kills": 0, "xp": 0.0,
			"loot": {"gold": 0, "materials": {}, "mods": []}, "killer": "", "rooms_cleared": 0,
		})

	var target := clampi(floor_index + depth_bonus, 1, maxi(1, db.floor_count()))
	floor_def = db.floor_by_index(target)
	var boss_id: String = opts.get("boss", "")
	var room_count := rng.range_arr(db.bal("rooms_per_run", [3, 6]))
	var party_info: Array = []
	for h in heroes:
		party_info.append({"key": h.key, "uid": h.uid, "hp": h.hp, "max_hp": h.s.max_hp, "element": h.s.element, "haste": h.s.haste})
	_emit("run_start", {"floor": target, "rooms": room_count, "party": party_info})

	for i in room_count:
		if _present().is_empty():
			break
		var last := i == room_count - 1
		var kind: String = "fight" if last else str(rng.weighted(db.bal("room_weights", {"fight": 1})))
		if last and boss_id != "":
			kind = "boss"
		_emit("room_enter", {"index": i, "kind": kind})
		match kind:
			"fight":
				_fight(_spawn_group())
			"boss":
				_fight([boss_id])
			"treasure":
				_treasure()
			"trap":
				_trap()
			"rest":
				_rest()
		for h in _present():
			h.rooms_cleared += 1
			h.xp += float(db.bal("xp.per_room", 2))
		# Between rooms, anyone whose nerve breaks heads home; the rest press on.
		if not last:
			for h in _present():
				if float(h.hp) / h.s.max_hp < h.s.nerve_threshold:
					h.state = "fled"
					_emit("retreat", {"actor": h.key, "hp": h.hp, "reason": "nerve"})

	var outcome := "wiped"
	for h in heroes:
		if h.state == "in":
			outcome = "cleared"
			break
		if h.state == "fled":
			outcome = "retreated"
	_emit("run_end", {"outcome": outcome})

	var results: Array = []
	for h in heroes:
		var hero_outcome: String = {"in": "survived", "fled": "retreated", "dead": "died"}[h.state]
		results.append({
			"sim_version": SIM_VERSION,
			"seed": seed_value,
			"hero_uid": h.uid,
			"slot": h.slot,
			"floor": target,
			"outcome": hero_outcome,
			"rooms": room_count,
			"rooms_cleared": h.rooms_cleared,
			"hp_left": maxi(h.hp, 0),
			"max_hp": h.s.max_hp,
			"damage_taken": h.damage_taken,
			"kills": h.kills,
			"total_kills": h.total_kills,
			"boss_killed": boss_killed,
			"killer": h.killer,
			"xp": 0 if hero_outcome == "died" else roundi(h.xp * float(h.s.xp_mult)),
			"potions_used": h.potions_used,
			"loot": h.loot,
			"haul": [] if hero_outcome == "died" else HaulGenerator.build(db, h.loot, h.s, floor_def, rng),
		})
	return {
		"sim_version": SIM_VERSION,
		"seed": seed_value,
		"floor": target,
		"rooms": room_count,
		"outcome": outcome,
		"boss_killed": boss_killed,
		"heroes": results,
		"events": events,
	}


# --- rooms -------------------------------------------------------------------

## Bigger parties meet bigger groups: each hero past the first adds
## combat.party_extra_monsters to the roll (fractions round randomly).
func _spawn_group() -> Array:
	var ids: Array = []
	var n := float(rng.range_arr(floor_def.get("group_size", [1, 1])))
	n += float(heroes.size() - 1) * float(db.bal("combat.party_extra_monsters", 0.6))
	var count := int(n)
	if rng.chance(n - count):
		count += 1
	count = clampi(count, 1, int(db.bal("combat.max_monsters", 4)))
	for i in count:
		ids.append(rng.weighted(floor_def.get("monsters", {})))
	return ids


func _fight(monster_ids: Array) -> void:
	monsters.clear()
	var scale := float(floor_def.get("monster_scale", 1.0))
	var spawn_info: Array = []
	for i in monster_ids.size():
		var def := db.get_row("monsters", monster_ids[i])
		var m_scale := scale
		var hp_scale := scale
		if def.get("boss", false):
			# A boss is tuned for one hero; it toughens up for each extra party member.
			m_scale = 1.0
			hp_scale = 1.0 + float(heroes.size() - 1) * float(db.bal("combat.boss_hp_per_hero", 0.6))
		var m := {
			"key": "m%d" % i,
			"id": monster_ids[i],
			"def": def,
			"hp": roundi(float(def.get("hp", 10)) * hp_scale),
			"might": float(def.get("might", 1)) * m_scale,
			"guard": int(def.get("guard", 0)),
			"haste": maxi(1, int(def.get("haste", 8))),
			"meter": 0,
			"status": {},
		}
		m["max_hp"] = m.hp
		monsters.append(m)
		spawn_info.append({"key": m.key, "id": m.id, "hp": m.hp, "max_hp": m.max_hp, "haste": m.haste})
	_emit("spawn", {"monsters": spawn_info})

	# Action meters, as in Ore Heroes: every tick each unit adds its Haste to
	# its meter and acts when the meter reaches 100 (overflow carries over).
	# Ranged heroes and casters start with a full meter, so they shoot first.
	for h in heroes:
		h.meter = METER_FULL if (h.s.role == "ranged" or h.s.role == "caster") else 0
		h.prayed = false
	var max_ticks := int(db.bal("combat.max_ticks", 3000))
	for t in max_ticks:
		tick = t
		if _first_alive().is_empty() or _present().is_empty():
			break
		# Heroes, top of the stack first
		for h in heroes:
			if h.state != "in":
				continue
			h.meter += int(h.s.haste)
			if h.meter < METER_FULL:
				continue
			h.meter -= METER_FULL
			_hero_turn(h)
			if _first_alive().is_empty():
				break
		if _first_alive().is_empty():
			break
		# Monsters, in row order
		for m in monsters:
			if m.hp <= 0:
				continue
			var haste: int = m.haste
			if m.status.has("chill"):
				haste = maxi(1, roundi(haste * float(db.bal("combat.chill_haste_mult", 0.5))))
			m.meter += haste
			if m.meter < METER_FULL:
				continue
			m.meter -= METER_FULL
			if not _monster_status_turn(m):
				continue
			var victim := _pick_victim()
			if victim.is_empty():
				break
			_monster_attack(m, victim)
			# Panic: badly hurt mid-fight, the hero bolts (taking one parting blow).
			if victim.state == "in" and float(victim.hp) / victim.s.max_hp < victim.s.nerve_threshold * float(db.bal("combat.panic_factor", 0.6)):
				_monster_attack(m, victim)
				if victim.state == "in":
					victim.state = "fled"
					_emit("retreat", {"actor": victim.key, "hp": victim.hp, "reason": "panic"})
			if _present().is_empty():
				break
	tick = -1


func _hero_turn(h: Dictionary) -> void:
	# A healer tends the worst-hurt ally once a fight before swinging.
	if h.s.role == "healer" and not h.prayed:
		var hurt := {}
		for o in _present():
			if float(o.hp) / o.s.max_hp < 0.5 and (hurt.is_empty() or float(o.hp) / o.s.max_hp < float(hurt.hp) / hurt.s.max_hp):
				hurt = o
		if not hurt.is_empty():
			h.prayed = true
			_heal(hurt, roundi(hurt.s.max_hp * float(db.bal("combat.healer_heal", 0.25))), "prayer", h.key)
	var target := _target_for(h)
	_hero_attack(h, target, 1.0, "")
	if h.s.actions.has("cleave"):
		var second := _first_alive(target)
		if not second.is_empty():
			_hero_attack(h, second, float(db.bal("combat.cleave_mult", 0.6)), "cleave")


## Each hero fights the monster in their own row, or the nearest one left.
func _target_for(h: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 999
	for i in monsters.size():
		if monsters[i].hp <= 0:
			continue
		var d := absi(i - int(h.slot))
		if d < best_d:
			best_d = d
			best = monsters[i]
	return best


## Monsters favour the top of the stack: weight by combat.aggro_by_slot.
func _pick_victim() -> Dictionary:
	var weights: Array = db.bal("combat.aggro_by_slot", [4, 3, 2, 2])
	var total := 0.0
	var present := _present()
	for h in present:
		total += float(weights[mini(h.slot, weights.size() - 1)])
	if present.is_empty():
		return {}
	var roll := rng.range_f(0.0, total)
	for h in present:
		roll -= float(weights[mini(h.slot, weights.size() - 1)])
		if roll <= 0.0:
			return h
	return present[-1]


func _hero_attack(h: Dictionary, m: Dictionary, mult: float, tag: String) -> void:
	if m.is_empty():
		return
	var s: Dictionary = h.s
	if rng.chance(float(db.bal("combat.monster_dodge", 0.05))):
		_emit("miss", {"actor": h.key, "target": m.key})
		return
	var armor: int = 0 if s.actions.has("pierce") else m.guard
	if m.status.has("stagger"):
		armor = maxi(0, armor - 2)
	var dmg := float(s.might) * rng.range_f(0.85, 1.15) * mult - armor
	var eff := ""
	if s.element != "":
		if m.def.get("weak", "") == s.element:
			eff = "weak"
			dmg *= float(db.bal("element_weak_mult", 1.5))
		elif m.def.get("resist", "") == s.element:
			eff = "resist"
			dmg *= float(db.bal("element_resist_mult", 0.5))
	var crit := rng.chance(s.crit)
	if crit:
		dmg *= float(db.bal("combat.crit_mult", 1.75))
	var dealt := maxi(1, roundi(dmg))
	m.hp -= dealt
	_emit("attack", {"actor": h.key, "target": m.key, "dmg": dealt, "crit": crit, "eff": eff, "element": s.element, "hp": maxi(m.hp, 0), "tag": tag})
	if m.hp <= 0:
		_kill(m, h)
		return
	if s.element != "" and eff != "resist" and rng.chance(float(db.bal("status_chance", 0.35))):
		var status: String = db.bal("element_status", {}).get(s.element, "")
		if status != "":
			m.status[status] = 2
			m["status_by"] = h.key
			_emit("status", {"target": m.key, "status": status})


## Returns false if the monster loses its turn.
func _monster_status_turn(m: Dictionary) -> bool:
	var st: Dictionary = m.status
	if st.has("burn"):
		var burn := maxi(1, roundi(m.max_hp * 0.08))
		m.hp -= burn
		_emit("status_tick", {"target": m.key, "status": "burn", "dmg": burn, "hp": maxi(m.hp, 0)})
		if m.hp <= 0:
			_kill(m, _unit(m.get("status_by", "")))
			return false
	var acts := true
	if st.has("stun"):
		acts = false
		_emit("skip_turn", {"actor": m.key, "status": "stun"})
	for k in st.keys():
		st[k] -= 1
		if st[k] <= 0:
			st.erase(k)
	return acts


func _monster_attack(m: Dictionary, h: Dictionary) -> void:
	var s: Dictionary = h.s
	if rng.chance(s.dodge):
		_emit("dodge", {"actor": m.key, "target": h.key})
		return
	if rng.chance(s.block):
		_emit("block", {"actor": m.key, "target": h.key})
		if s.actions.has("riposte"):
			_hero_attack(h, m, float(db.bal("combat.riposte_mult", 0.5)), "riposte")
		return
	var dmg := maxi(1, roundi(m.might * rng.range_f(0.85, 1.15)) - int(s.guard))
	h.hp -= dmg
	h.damage_taken += dmg
	_emit("hit", {"actor": m.key, "target": h.key, "dmg": dmg, "hp": maxi(h.hp, 0)})
	_after_damage(h, m.id)


## Potions, second wind, or death, after a hero loses HP.
func _after_damage(h: Dictionary, source_id: String) -> void:
	_maybe_drink(h)
	if h.hp > 0:
		return
	if h.s.actions.has("second_wind") and not h.second_wind_used:
		h.second_wind_used = true
		h.hp = 0
		_heal(h, roundi(h.s.max_hp * float(db.bal("combat.second_wind_heal", 0.35))), "second_wind", h.key)
		return
	h.hp = 0
	h.state = "dead"
	h.killer = source_id
	_emit("death", {"target": h.key, "killer": source_id})


func _kill(m: Dictionary, by: Dictionary) -> void:
	m.hp = 0
	if m.def.get("boss", false):
		boss_killed = true
	# Everyone still in the fight learns from it; the killer gets the trophy and the drops.
	for h in _present():
		h.xp += float(m.def.get("xp", 1))
	var actor := ""
	if not by.is_empty():
		actor = by.key
		by.kills[m.id] = int(by.kills.get(m.id, 0)) + 1
		by.total_kills += 1
	_emit("kill", {"actor": actor, "target": m.key, "id": m.id})
	var looter: Dictionary = by if not by.is_empty() and by.state == "in" else _first_present()
	if looter.is_empty():
		return
	for d in m.def.get("drops", []):
		if rng.chance(float(d.get("chance", 0.0))):
			var qty := maxi(1, roundi(rng.range_arr(d.get("qty", [1, 1])) * float(looter.s.material_mult)))
			var mat: String = d.get("material", "")
			looter.loot.materials[mat] = int(looter.loot.materials.get(mat, 0)) + qty
			_emit("drop", {"actor": looter.key, "material": mat, "qty": qty})


## A chest: the party splits it (a bigger party finds a little more in total,
## rooms.treasure_per_extra_hero), and the luckiest may find a mod.
func _treasure() -> void:
	var shares := {}
	var finder := {}
	var present := _present()
	var total := float(rng.range_arr(floor_def.get("gold", [1, 5])))
	total *= 1.0 + float(present.size() - 1) * float(db.bal("rooms.treasure_per_extra_hero", 0.5))
	for h in present:
		var gold := maxi(1, roundi(total / present.size() * float(h.s.gold_mult)))
		h.loot.gold += gold
		shares[h.key] = gold
		if finder.is_empty() or int(h.s.luck) > int(finder.s.luck):
			finder = h
	var mod := ""
	if not finder.is_empty() and rng.chance(float(floor_def.get("mod_chance", 0.0)) * float(finder.s.mod_find_mult)):
		mod = str(rng.pick(db.ids("mods")))
		finder.loot.mods.append(mod)
	_emit("treasure", {"gold": shares, "mod": mod, "finder": finder.get("key", "")})


## A trap springs on one hero (the top of the stack walks into it most often).
func _trap() -> void:
	var h := _pick_victim()
	if h.is_empty():
		return
	var dodge_chance: float = float(h.s.luck) * float(db.bal("rooms.trap_dodge_per_luck", 0.03))
	if rng.chance(dodge_chance):
		_emit("trap", {"target": h.key, "dmg": 0, "dodged": true, "hp": h.hp})
		return
	var range_arr: Array = db.bal("rooms.trap_damage", [0.08, 0.18])
	var frac := rng.range_f(float(range_arr[0]), float(range_arr[1]))
	var dmg := maxi(1, roundi(h.s.max_hp * frac * float(floor_def.get("monster_scale", 1.0))))
	h.hp -= dmg
	h.damage_taken += dmg
	_emit("trap", {"target": h.key, "dmg": dmg, "dodged": false, "hp": maxi(h.hp, 0)})
	_after_damage(h, "trap")


func _rest() -> void:
	for h in _present():
		_heal(h, roundi(h.s.max_hp * float(db.bal("rooms.rest_heal", 0.25))), "rest", h.key)


func _heal(h: Dictionary, amount: int, source: String, by: String) -> void:
	var before: int = h.hp
	h.hp = mini(h.s.max_hp, h.hp + amount)
	_emit("heal", {"actor": by, "target": h.key, "amount": h.hp - before, "hp": h.hp, "source": source})


## A hero carrying a healing draught drinks it when badly hurt (but still standing).
func _maybe_drink(h: Dictionary) -> void:
	var s: Dictionary = h.s
	if h.hp <= 0 or h.potions_used >= int(s.potion_heal_uses):
		return
	if float(h.hp) / s.max_hp >= float(s.potion_heal_below):
		return
	h.potions_used += 1
	_emit("potion", {"actor": h.key, "item": s.pack, "uses_left": int(s.potion_heal_uses) - h.potions_used})
	_heal(h, roundi(s.max_hp * float(s.potion_heal)), "potion", h.key)


func _present() -> Array:
	var out: Array = []
	for h in heroes:
		if h.state == "in":
			out.append(h)
	return out


func _first_present() -> Dictionary:
	for h in heroes:
		if h.state == "in":
			return h
	return {}


func _unit(key: String) -> Dictionary:
	for h in heroes:
		if h.key == key:
			return h
	return {}


func _first_alive(exclude: Dictionary = {}) -> Dictionary:
	for m in monsters:
		if m.hp > 0 and m != exclude:
			return m
	return {}


func _emit(type: String, data: Dictionary) -> void:
	if not record:
		return
	data["type"] = type
	if tick >= 0 and METER_EVENTS.has(type):
		data["tick"] = tick
		var meters := {}
		for h in heroes:
			if h.state == "in":
				meters[h.key] = h.meter
		for m in monsters:
			if m.hp > 0:
				meters[m.key] = m.meter
		data["meters"] = meters
	events.append(data)
