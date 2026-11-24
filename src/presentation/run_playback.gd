class_name RunPlayback
extends Node2D
## Animates a party run's event log. It decides nothing: every hit, crit and
## death already happened in RunSimulator. That is why speed controls and skip
## are free, and why a save made mid-delve replays exactly.
##
## The party stands in a vertical stack on the left (slot 1 on top), monsters
## line up in the same rows on the right, and attackers lunge across the gap.
##
##   playback.play(run, heroes)   # heroes: hero dicts in slot order. async; emits `finished`
##   playback.speed = 2.0
##   playback.skip()

signal finished(run: Dictionary)
signal event_shown(event: Dictionary)

const HERO_X := -80.0
const MONSTER_X := 80.0
const ROW_TOP := -50.0
const ROW_H := 42.0
const BOSS_ROW := 1.5   # a lone boss stands mid-stack

## Base durations in seconds at 1x speed. Tune feel here.
const BEAT := {
	"room_enter": 0.55, "spawn": 0.35, "attack": 0.32, "hit": 0.32, "miss": 0.25,
	"dodge": 0.25, "block": 0.28, "status": 0.18, "status_tick": 0.22, "skip_turn": 0.2,
	"heal": 0.35, "potion": 0.2, "kill": 0.45, "drop": 0.12, "treasure": 0.5, "trap": 0.45,
	"retreat": 0.6, "death": 1.2, "run_end": 0.4,
}
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.5, 0.2), "frost": Color(0.55, 0.85, 1.0),
	"holy": Color(1.0, 0.95, 0.55), "shock": Color(0.75, 0.6, 1.0), "": Color.WHITE,
}
const END_TEXT := {"cleared": "Heading home", "retreated": "Limping home", "wiped": "Lost"}

var speed := 1.0
var playing := false

var _db: ContentDB
var _skip := false
var _heroes: Dictionary = {}     # "h0".. -> PlaybackActor
var _monsters: Dictionary = {}   # "m0".. -> PlaybackActor
var _room_label: Label


func _ready() -> void:
	_room_label = Label.new()
	_room_label.position = Vector2(-80, ROW_TOP - 46)
	_room_label.size = Vector2(160, 12)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_room_label)


func skip() -> void:
	_skip = true


static func row_y(slot: float) -> float:
	return ROW_TOP + slot * ROW_H


func play(run: Dictionary, heroes: Array, db: ContentDB = null) -> void:
	_db = db if db else Content.db
	_clear()
	_skip = false
	playing = true
	var events: Array = run.get("events", [])
	for ev in events:
		if _skip:
			_apply_silently(ev)
			continue
		event_shown.emit(ev)
		await _show(ev, heroes)
	Engine.time_scale = 1.0
	if _skip:
		_clear_monsters()
		_room_label.text = END_TEXT.get(run.get("outcome", ""), "")
	playing = false
	finished.emit(run)


func _show(ev: Dictionary, heroes: Array) -> void:
	var beat: float = BEAT.get(ev.type, 0.2)
	if ev.has("meters"):
		_update_meters(ev, beat)
	match ev.type:
		"run_start":
			_spawn_party(ev, heroes)
		"room_enter":
			_room_label.text = "Room %d: %s" % [int(ev.index) + 1, str(ev.kind).capitalize()]
			Juice.pop(_room_label, 0.25)
			_clear_monsters()
		"spawn":
			var n: int = ev.monsters.size()
			for i in n:
				var m: Dictionary = ev.monsters[i]
				var def := _db.get_row("monsters", m.id)
				var actor := PlaybackActor.new()
				add_child(actor)
				var boss: bool = def.get("boss", false)
				actor.setup(m.key, def.get("sprite", ""), def.get("name", "?"), int(m.hp), int(m.max_hp), true, Color(0.75, 0.5, 1.0) if boss else Color.WHITE)
				var slot := BOSS_ROW if boss and n == 1 else float(i)
				actor.set_home(Vector2(MONSTER_X + (i % 2) * 8.0, row_y(slot)))
				if boss:
					actor.scale = Vector2(1.5, 1.5)
				Juice.slide_in(actor, Vector2(30, 0), 0.25, i * 0.06)
				_monsters[m.key] = actor
			Audio.play("spawn")
		"attack":
			var attacker := _actor(ev.actor)
			var target := _actor(ev.target)
			if attacker:
				attacker.play_attack(beat / speed, target.position if target else null)
				if attacker.ranged and target:
					_projectile(attacker, target, ELEMENT_COLORS.get(ev.get("element", ""), Color.WHITE), beat * 0.35)
			await _wait(beat * 0.35)
			if target:
				target.play_hurt()
				target.set_hp(int(ev.hp))
				var col: Color = ELEMENT_COLORS.get(ev.get("element", ""), Color.WHITE)
				var text := str(ev.dmg) + ("!" if ev.crit else "")
				Juice.popup(self, target.position + Vector2(0, -30), text, col, ev.crit)
				if ev.eff == "weak":
					Juice.popup(self, target.position + Vector2(0, -44), "WEAK!", Color(1.0, 0.85, 0.3))
				elif ev.eff == "resist":
					Juice.popup(self, target.position + Vector2(0, -44), "RESIST", Color(0.6, 0.6, 0.65))
				Juice.hitstop(0.09 if ev.crit else 0.045)
				Juice.shake("medium" if ev.crit else "tiny")
				Audio.play("hit_crit" if ev.crit else "hit")
			await _wait(beat * 0.65)
			return
		"hit":
			var attacker := _actor(ev.actor)
			var victim := _actor(ev.target)
			if attacker:
				attacker.play_attack(beat / speed, victim.position if victim else null)
			await _wait(beat * 0.35)
			if victim:
				victim.play_hurt()
				victim.set_hp(int(ev.hp))
				Juice.popup(self, victim.position + Vector2(0, -30), str(ev.dmg), Color(1.0, 0.35, 0.35))
			Juice.hitstop(0.05)
			Juice.shake(clampf(float(ev.dmg) * 0.6, 2.0, 10.0))
			Audio.play("hurt")
			await _wait(beat * 0.65)
			return
		"miss":
			var a := _actor(ev.actor)
			var t := _actor(ev.target)
			if a:
				a.play_attack(beat / speed, t.position if t else null)
			if t:
				Juice.popup(self, t.position + Vector2(0, -30), "miss", Color(0.7, 0.7, 0.7))
			Audio.play("whiff")
		"dodge":
			var a := _actor(ev.actor)
			var t := _actor(ev.target)
			if a:
				a.play_attack(beat / speed, t.position if t else null)
			if t:
				t.play_dodge()
				Juice.popup(self, t.position + Vector2(0, -30), "DODGE", Color(0.7, 1.0, 0.8))
			Audio.play("whiff")
		"block":
			var a := _actor(ev.actor)
			var t := _actor(ev.target)
			if a:
				a.play_attack(beat / speed, t.position if t else null)
			await _wait(beat * 0.3)
			if t:
				t.play_block()
				Juice.popup(self, t.position + Vector2(0, -30), "BLOCK", Color(0.8, 0.85, 1.0))
			Juice.shake("tiny")
			Audio.play("block")
			await _wait(beat * 0.7)
			return
		"status":
			var st := _actor(ev.target)
			if st:
				Juice.popup(self, st.position + Vector2(0, -44), str(ev.status).to_upper(), Color(1.0, 0.7, 0.4))
		"status_tick":
			var tk := _actor(ev.target)
			if tk:
				tk.set_hp(int(ev.hp))
				tk.play_hurt()
				Juice.popup(self, tk.position + Vector2(0, -30), str(ev.dmg), Color(1.0, 0.55, 0.2))
		"skip_turn":
			var sk := _actor(ev.actor)
			if sk:
				Juice.shake_node(sk, 1.5, 0.2)
		"potion":
			var p := _actor(ev.actor)
			if p:
				Juice.popup(self, p.position + Vector2(0, -46), "GULP", Color(0.9, 0.5, 0.9))
		"heal":
			var h := _actor(ev.target)
			if h:
				h.set_hp(int(ev.hp))
				h.play_heal()
				Juice.popup(self, h.position + Vector2(0, -30), "+%d" % int(ev.amount), Color(0.45, 1.0, 0.5))
				if ev.source == "second_wind":
					Juice.popup(self, h.position + Vector2(0, -46), "SECOND WIND", Color(0.6, 1.0, 0.7), true)
					Juice.hitstop(0.15)
			if ev.source == "prayer":
				var priest := _actor(ev.get("actor", ""))
				if priest:
					Juice.pop(priest.body(), 0.15)
			Audio.play("heal")
		"kill":
			var k := _actor(ev.target)
			if k:
				k.play_death(beat / speed)
				Juice.shake("small")
			Audio.play("kill")
		"drop":
			var d := _actor(ev.get("actor", ""))
			var pos := d.position + Vector2(0, -46) if d else Vector2(0, -20)
			Juice.popup(self, pos, "+%d %s" % [int(ev.qty), _db.get_row("materials", ev.material).get("name", "")], Color(0.9, 0.8, 0.6))
		"treasure":
			var shares: Dictionary = ev.gold
			for key in shares:
				var h := _actor(key)
				if h:
					Juice.popup(self, h.position + Vector2(0, -30), "+%d gold" % int(shares[key]), Color(1.0, 0.85, 0.3))
			if ev.mod != "":
				Juice.popup(self, Vector2(0, row_y(0) - 20), _db.get_row("mods", ev.mod).get("name", "Mod"), Color(0.7, 0.9, 1.0), true)
			Audio.play("treasure")
		"trap":
			var t := _actor(ev.target)
			if t:
				if ev.dodged:
					t.play_dodge()
					Juice.popup(self, t.position + Vector2(0, -30), "TRAP DODGED", Color(0.7, 1.0, 0.8))
				else:
					t.play_hurt()
					t.set_hp(int(ev.hp))
					Juice.popup(self, t.position + Vector2(0, -30), str(ev.dmg), Color(1.0, 0.35, 0.35))
					Juice.shake("small")
					Audio.play("trap")
		"retreat":
			var r := _actor(ev.actor)
			if r:
				Juice.popup(self, r.position + Vector2(0, -40), "RETREAT!", Color(1.0, 0.9, 0.5), true)
				r.play_retreat(beat / speed)
			Audio.play("retreat")
		"death":
			# A hero falls: a beat of slow motion, then the fight goes on.
			var v := _actor(ev.target)
			Engine.time_scale = 0.35
			if v:
				v.play_death(beat / speed)
				Juice.popup(self, v.position + Vector2(0, -44), "FALLEN", Color(1.0, 0.3, 0.3), true)
			Juice.shake("big")
			Audio.play("death")
			await _wait(beat * 0.35)
			Engine.time_scale = 1.0
			await _wait(beat * 0.65)
			return
		"run_end":
			_room_label.text = END_TEXT.get(ev.outcome, "")
			Juice.pop(_room_label, 0.3)
	await _wait(beat)


func _spawn_party(ev: Dictionary, heroes: Array) -> void:
	var party: Array = ev.get("party", [])
	for i in party.size():
		var info: Dictionary = party[i]
		var hero: Dictionary = heroes[i] if i < heroes.size() else {}
		var cls := _db.get_row("classes", hero.get("class_id", ""))
		var tint_arr: Array = hero.get("tint", [1, 1, 1])
		var actor := PlaybackActor.new()
		add_child(actor)
		actor.setup(info.key, cls.get("sprite", ""), hero.get("name", "Hero"), int(info.hp), int(info.max_hp), false,
			Color(tint_arr[0], tint_arr[1], tint_arr[2]))
		actor.ranged = cls.get("role", "front") in ["ranged", "caster"]
		actor.set_home(Vector2(HERO_X - (i % 2) * 8.0, row_y(i)))
		Juice.slide_in(actor, Vector2(-30, 0), 0.3, i * 0.06)
		_heroes[info.key] = actor


## Skip: bring the stage to the run's end state without animating.
func _apply_silently(ev: Dictionary) -> void:
	match ev.type:
		"run_start":
			pass  # skipped before anything showed: nothing to update
		"attack", "hit", "status_tick", "heal", "trap":
			var a := _actor(ev.get("target", ""))
			if a and ev.has("hp"):
				a.set_hp(int(ev.hp))
		"death":
			var d := _actor(ev.target)
			if d:
				d.play_death(0.2)
		"retreat":
			var r := _actor(ev.actor)
			if r:
				r.play_retreat(0.2)


## A small bolt flies from a ranged attacker to its target.
func _projectile(from: PlaybackActor, to: PlaybackActor, color: Color, travel: float) -> void:
	var bolt := ColorRect.new()
	bolt.size = Vector2(6, 2)
	bolt.color = color
	bolt.position = from.position + Vector2(6, -14)
	add_child(bolt)
	var t := bolt.create_tween()
	t.tween_property(bolt, "position", to.position + Vector2(-6, -14), maxf(travel / maxf(speed, 0.01), 0.02))
	t.tween_callback(bolt.queue_free)


## The acting unit's bar fills to full, then drops to its leftover; the others
## slide to where they are now.
func _update_meters(ev: Dictionary, beat: float) -> void:
	var meters: Dictionary = ev.meters
	var acting := str(ev.get("actor", ""))
	for key in meters:
		var a := _actor(key)
		if a == null:
			continue
		if key == acting:
			a.meter = 100.0
			a.set_meter(float(meters[key]), beat * 0.4 / speed)
		else:
			a.set_meter(float(meters[key]), beat * 0.6 / speed)


func _actor(actor_key: String) -> PlaybackActor:
	if _heroes.has(actor_key):
		return _heroes[actor_key]
	return _monsters.get(actor_key)


func _wait(seconds: float) -> void:
	if _skip or seconds <= 0.0:
		return
	await get_tree().create_timer(seconds / maxf(speed, 0.01)).timeout


func _clear_monsters() -> void:
	for a in _monsters.values():
		a.queue_free()
	_monsters.clear()


func _clear() -> void:
	_clear_monsters()
	for a in _heroes.values():
		if is_instance_valid(a):
			a.queue_free()
	_heroes.clear()
