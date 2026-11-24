class_name RunSimulator
extends RefCounted
## Resolves one hero's delve, start to finish, the moment they leave the shop.
##
## Pure and seeded: the same (content, hero, gear, floor, seed) always gives the
## same result. It never touches nodes, autoloads, time or the global RNG, so it
## runs headless, thousands of times a second, for estimates and balance tools.
##
## Output is a result Dictionary whose "events" array is the event log the
## playback layer animates. Playback never decides anything; it only shows what
## is in the log. See EVENT TYPES below and docs in README.md.
##
## EVENT TYPES (every event has "type"; actors are "hero" or a monster key "m0".."mN")
##   run_start   {hero, floor, hp, max_hp, rooms, element, haste}
##   room_enter  {index, kind}                       kind: fight|treasure|trap|rest|boss
##   spawn       {monsters: [{key, id, hp, max_hp, haste}]}
##   attack      {actor, target, dmg, crit, eff, element, hp, tag}   eff: weak|resist|""  tag: ""|cleave|riposte
##   miss        {actor, target}
##   dodge       {actor, target}                      the hero dodged a monster
##   block       {actor, target}                      the hero blocked a monster
##   hit         {actor, target, dmg, hp}             a monster hurt the hero
##   status      {target, status}                     burn|chill|stagger|stun
##   status_tick {target, status, dmg, hp}
##   skip_turn   {actor, status}                      stunned: the full meter is spent doing nothing
##   heal        {target, amount, hp, source}         source: rest|prayer|second_wind|potion
##   potion      {item, uses_left}                    the hero drinks a healing draught
##   kill        {target, id}
##   drop        {material, qty}
##   treasure    {gold, mod}
##   trap        {dmg, dodged, hp}
##   retreat     {hp, reason}                         reason: nerve|panic
##   death       {hp, killer}
##   run_end     {outcome}                            outcome: survived|retreated|died

const SIM_VERSION := 2  # 2: action meters driven by Haste replaced fixed rounds
const METER_FULL := 100
## Events where someone acts carry "tick" and a "meters" snapshot {actor key: 0..99}
## so playback can draw action bars that match the simulation.
const METER_EVENTS: PackedStringArray = ["attack", "hit", "miss", "dodge", "block", "skip_turn", "heal", "status_tick", "potion"]

var db: ContentDB
var rng: Rng
var record := true
var events: Array = []

var s: Dictionary          # hero combat stats
var hp := 0
var second_wind_used := false
var damage_taken := 0
var hits_taken := 0
var kills: Dictionary = {}
var total_kills := 0
var xp := 0.0
var loot := {"gold": 0, "materials": {}, "mods": []}
var monsters: Array = []
var floor_def: Dictionary
var killer := ""
var boss_killed := false
var hero_meter := 0
var potions_used := 0
var tick := -1   # combat tick, -1 outside fights


## opts: {record_events: bool = true, boss: monster_id = ""}
static func simulate(content: ContentDB, hero: Dictionary, gear: Array, floor_index: int, seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var sim := RunSimulator.new()
	return sim._run(content, hero, gear, floor_index, seed_value, opts)


func _run(content: ContentDB, hero: Dictionary, gear: Array, floor_index: int, seed_value: int, opts: Dictionary) -> Dictionary:
	db = content
	rng = Rng.new(seed_value)
	record = opts.get("record_events", true)
	s = Hero.combat_stats(db, hero, gear)
	hp = s.max_hp

	var target := clampi(floor_index + int(s.depth_bonus), 1, maxi(1, db.floor_count()))
	floor_def = db.floor_by_index(target)
	var boss_id: String = opts.get("boss", "")
	var room_count := rng.range_arr(db.bal("rooms_per_run", [3, 6]))
	_emit("run_start", {"hero": hero.get("uid", ""), "floor": target, "hp": hp, "max_hp": s.max_hp, "rooms": room_count, "element": s.element, "haste": s.haste})

	var outcome := "survived"
	var rooms_cleared := 0
	for i in room_count:
		var last := i == room_count - 1
		var kind: String = "fight" if last else str(rng.weighted(db.bal("room_weights", {"fight": 1})))
		if last and boss_id != "":
			kind = "boss"
		_emit("room_enter", {"index": i, "kind": kind})
		var room_outcome := ""
		match kind:
			"fight":
				room_outcome = _fight(_spawn_group())
			"boss":
				room_outcome = _fight([boss_id])
			"treasure":
				_treasure()
			"trap":
				_trap()
			"rest":
				_rest()
		if hp <= 0:
			outcome = "died"
			_emit("death", {"hp": 0, "killer": killer})
			break
		if room_outcome == "fled":
			outcome = "retreated"
			break
		rooms_cleared += 1
		xp += float(db.bal("xp.per_room", 2))
		if not last and _nerve_breaks():
			outcome = "retreated"
			_emit("retreat", {"hp": hp, "reason": "nerve"})
			break

	_emit("run_end", {"outcome": outcome})
	var wear := 0.0
	if outcome != "died":
		wear = (rooms_cleared * float(db.bal("wear.per_room", 2)) + hits_taken * float(db.bal("wear.per_hit_taken", 1))) * float(s.wear_mult)
	var result := {
		"sim_version": SIM_VERSION,
		"seed": seed_value,
		"hero_uid": hero.get("uid", ""),
		"floor": target,
		"outcome": outcome,
		"rooms": room_count,
		"rooms_cleared": rooms_cleared,
		"hp_left": maxi(hp, 0),
		"max_hp": s.max_hp,
		"damage_taken": damage_taken,
		"kills": kills,
		"total_kills": total_kills,
		"boss_killed": boss_killed,
		"xp": 0 if outcome == "died" else roundi(xp * float(s.xp_mult)),
		"wear": roundi(wear),
		"potions_used": potions_used,
		"loot": loot,
		"haul": [] if outcome == "died" else HaulGenerator.build(db, loot, s, floor_def, rng),
		"events": events,
	}
	return result


# --- rooms -------------------------------------------------------------------

func _spawn_group() -> Array:
	var ids: Array = []
	var n := rng.range_arr(floor_def.get("group_size", [1, 1]))
	for i in n:
		ids.append(rng.weighted(floor_def.get("monsters", {})))
	return ids


func _fight(monster_ids: Array) -> String:
	monsters.clear()
	var scale := float(floor_def.get("monster_scale", 1.0))
	var spawn_info: Array = []
	for i in monster_ids.size():
		var def := db.get_row("monsters", monster_ids[i])
		var m_scale := 1.0 if def.get("boss", false) else scale
		var m := {
			"key": "m%d" % i,
			"id": monster_ids[i],
			"def": def,
			"hp": roundi(float(def.get("hp", 10)) * m_scale),
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
	hero_meter = METER_FULL if (s.role == "ranged" or s.role == "caster") else 0
	var max_ticks := int(db.bal("combat.max_ticks", 3000))
	var prayed := false
	var outcome := "cleared"
	for t in max_ticks:
		tick = t
		if _first_alive().is_empty():
			break
		# Hero
		hero_meter += int(s.haste)
		if hero_meter >= METER_FULL:
			hero_meter -= METER_FULL
			var target := _first_alive()
			_hero_attack(target, 1.0, "")
			if s.actions.has("cleave"):
				var second := _first_alive(target)
				if not second.is_empty():
					_hero_attack(second, float(db.bal("combat.cleave_mult", 0.6)), "cleave")
			if s.role == "healer" and not prayed and hp < s.max_hp * 0.5:
				prayed = true
				_heal(roundi(s.max_hp * float(db.bal("combat.healer_heal", 0.25))), "prayer")
			if _first_alive().is_empty():
				break
		# Monsters, in line order
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
			_monster_attack(m)
			if hp <= 0:
				outcome = "dead"
				break
			# Panic: badly hurt mid-fight, the hero bolts (taking one parting blow).
			if float(hp) / s.max_hp < s.nerve_threshold * float(db.bal("combat.panic_factor", 0.6)):
				_monster_attack(_first_alive())
				if hp <= 0:
					outcome = "dead"
					break
				_emit("retreat", {"hp": hp, "reason": "panic"})
				outcome = "fled"
				break
		if outcome != "cleared":
			break
	tick = -1
	return outcome


func _hero_attack(m: Dictionary, mult: float, tag: String) -> void:
	if m.is_empty():
		return
	if rng.chance(float(db.bal("combat.monster_dodge", 0.05))):
		_emit("miss", {"actor": "hero", "target": m.key})
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
	_emit("attack", {"actor": "hero", "target": m.key, "dmg": dealt, "crit": crit, "eff": eff, "element": s.element, "hp": maxi(m.hp, 0), "tag": tag})
	if m.hp <= 0:
		_kill(m)
		return
	if s.element != "" and eff != "resist" and rng.chance(float(db.bal("status_chance", 0.35))):
		var status: String = db.bal("element_status", {}).get(s.element, "")
		if status != "":
			m.status[status] = 2
			_emit("status", {"target": m.key, "status": status})


## Returns false if the monster loses its turn.
func _monster_status_turn(m: Dictionary) -> bool:
	var st: Dictionary = m.status
	if st.has("burn"):
		var burn := maxi(1, roundi(m.max_hp * 0.08))
		m.hp -= burn
		_emit("status_tick", {"target": m.key, "status": "burn", "dmg": burn, "hp": maxi(m.hp, 0)})
		if m.hp <= 0:
			_kill(m)
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


func _monster_attack(m: Dictionary) -> void:
	if rng.chance(s.dodge):
		_emit("dodge", {"actor": m.key, "target": "hero"})
		return
	if rng.chance(s.block):
		_emit("block", {"actor": m.key, "target": "hero"})
		if s.actions.has("riposte"):
			_hero_attack(m, float(db.bal("combat.riposte_mult", 0.5)), "riposte")
		return
	var dmg := maxi(1, roundi(m.might * rng.range_f(0.85, 1.15)) - int(s.guard))
	hp -= dmg
	damage_taken += dmg
	hits_taken += 1
	_emit("hit", {"actor": m.key, "target": "hero", "dmg": dmg, "hp": maxi(hp, 0)})
	_maybe_drink()
	if hp <= 0:
		killer = m.id
		if s.actions.has("second_wind") and not second_wind_used:
			second_wind_used = true
			hp = 0
			_heal(roundi(s.max_hp * float(db.bal("combat.second_wind_heal", 0.35))), "second_wind")


func _kill(m: Dictionary) -> void:
	m.hp = 0
	kills[m.id] = int(kills.get(m.id, 0)) + 1
	total_kills += 1
	xp += float(m.def.get("xp", 1))
	if m.def.get("boss", false):
		boss_killed = true
	_emit("kill", {"target": m.key, "id": m.id})
	for d in m.def.get("drops", []):
		if rng.chance(float(d.get("chance", 0.0))):
			var qty := maxi(1, roundi(rng.range_arr(d.get("qty", [1, 1])) * float(s.material_mult)))
			var mat: String = d.get("material", "")
			loot.materials[mat] = int(loot.materials.get(mat, 0)) + qty
			_emit("drop", {"material": mat, "qty": qty})


func _treasure() -> void:
	var gold := roundi(rng.range_arr(floor_def.get("gold", [1, 5])) * float(s.gold_mult))
	var mod := ""
	if rng.chance(float(floor_def.get("mod_chance", 0.0)) * float(s.mod_find_mult)):
		mod = str(rng.pick(db.ids("mods")))
		loot.mods.append(mod)
	loot.gold += gold
	_emit("treasure", {"gold": gold, "mod": mod})


func _trap() -> void:
	var dodge_chance: float = float(s.luck) * float(db.bal("rooms.trap_dodge_per_luck", 0.03))
	if rng.chance(dodge_chance):
		_emit("trap", {"dmg": 0, "dodged": true, "hp": hp})
		return
	var frac := rng.range_f(float(db.bal("rooms.trap_damage", [0.08, 0.18])[0]), float(db.bal("rooms.trap_damage", [0.08, 0.18])[1]))
	var dmg := maxi(1, roundi(s.max_hp * frac * float(floor_def.get("monster_scale", 1.0))))
	hp -= dmg
	damage_taken += dmg
	_emit("trap", {"dmg": dmg, "dodged": false, "hp": maxi(hp, 0)})
	_maybe_drink()
	if hp <= 0:
		killer = "trap"


func _rest() -> void:
	_heal(roundi(s.max_hp * float(db.bal("rooms.rest_heal", 0.25))), "rest")


func _heal(amount: int, source: String) -> void:
	var before := hp
	hp = mini(s.max_hp, hp + amount)
	_emit("heal", {"target": "hero", "amount": hp - before, "hp": hp, "source": source})


## A hero carrying a healing draught drinks it when badly hurt (but still standing).
func _maybe_drink() -> void:
	if hp <= 0 or potions_used >= int(s.potion_heal_uses):
		return
	if float(hp) / s.max_hp >= float(s.potion_heal_below):
		return
	potions_used += 1
	_emit("potion", {"item": s.pack, "uses_left": int(s.potion_heal_uses) - potions_used})
	_heal(roundi(s.max_hp * float(s.potion_heal)), "potion")


func _nerve_breaks() -> bool:
	return float(hp) / s.max_hp < s.nerve_threshold


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
		var meters := {"hero": hero_meter}
		for m in monsters:
			if m.hp > 0:
				meters[m.key] = m.meter
		data["meters"] = meters
	events.append(data)
