class_name RunPlayback
extends Node2D
## Animates a run result's event log. It decides nothing: every hit, crit and
## death already happened in RunSimulator. That is why speed controls and skip
## are free, and why a save made mid-delve replays exactly.
##
##   playback.play(result, hero_dict)      # async; emits `finished`
##   playback.speed = 2.0
##   playback.skip()

signal finished(result: Dictionary)
signal event_shown(event: Dictionary)

const HERO_POS := Vector2(-70, 30)
const MONSTER_POS := Vector2(50, 30)
const MONSTER_SPACING := 26.0

## Base durations in seconds at 1x speed. Tune feel here.
const BEAT := {
	"room_enter": 0.55, "spawn": 0.35, "attack": 0.32, "hit": 0.32, "miss": 0.25,
	"dodge": 0.25, "block": 0.28, "status": 0.18, "status_tick": 0.22, "skip_turn": 0.2,
	"heal": 0.35, "kill": 0.45, "drop": 0.12, "treasure": 0.5, "trap": 0.45,
	"retreat": 0.6, "death": 1.4, "run_end": 0.4,
}
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.5, 0.2), "frost": Color(0.55, 0.85, 1.0),
	"holy": Color(1.0, 0.95, 0.55), "shock": Color(0.75, 0.6, 1.0), "": Color.WHITE,
}

var speed := 1.0
var playing := false

var _db: ContentDB
var _skip := false
var _hero: PlaybackActor
var _monsters: Dictionary = {}   # key -> PlaybackActor
var _room_label: Label


func _ready() -> void:
	_room_label = Label.new()
	_room_label.position = Vector2(-60, -60)
	_room_label.size = Vector2(120, 12)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_room_label)


func skip() -> void:
	_skip = true


func play(result: Dictionary, hero: Dictionary, db: ContentDB = null) -> void:
	_db = db if db else Content.db
	_clear()
	_skip = false
	playing = true
	var cls := _db.get_row("classes", hero.get("class_id", ""))
	var tint_arr: Array = hero.get("tint", [1, 1, 1])
	_hero = PlaybackActor.new()
	add_child(_hero)
	_hero.setup("hero", cls.get("sprite", ""), hero.get("name", "Hero"), int(result.max_hp), int(result.max_hp), false,
		Color(tint_arr[0], tint_arr[1], tint_arr[2]))
	_hero.set_home(HERO_POS)
	Juice.slide_in(_hero, Vector2(-30, 0), 0.3)

	for ev in result.get("events", []):
		if _skip:
			break
		event_shown.emit(ev)
		await _show(ev)
	if _skip:
		_jump_to_end(result)
	playing = false
	finished.emit(result)


func _show(ev: Dictionary) -> void:
	var beat: float = BEAT.get(ev.type, 0.2)
	if ev.has("meters"):
		_update_meters(ev, beat)
	match ev.type:
		"room_enter":
			_room_label.text = "Room %d: %s" % [int(ev.index) + 1, str(ev.kind).capitalize()]
			Juice.pop(_room_label, 0.25)
			_clear_monsters()
		"spawn":
			var i := 0
			for m in ev.monsters:
				var def := _db.get_row("monsters", m.id)
				var actor := PlaybackActor.new()
				add_child(actor)
				actor.setup(m.key, def.get("sprite", ""), def.get("name", "?"), int(m.hp), int(m.max_hp), true, Color(0.75, 0.5, 1.0) if def.get("boss", false) else Color.WHITE)
				actor.set_home(MONSTER_POS + Vector2(i * MONSTER_SPACING, (i % 2) * 6))
				Juice.slide_in(actor, Vector2(30, 0), 0.25, i * 0.06)
				_monsters[m.key] = actor
				i += 1
			Audio.play("spawn")
		"attack":
			var target := _actor(ev.target)
			_hero.play_attack(beat / speed)
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
			if attacker:
				attacker.play_attack(beat / speed)
			await _wait(beat * 0.35)
			_hero.play_hurt()
			_hero.set_hp(int(ev.hp))
			Juice.popup(self, _hero.position + Vector2(0, -30), str(ev.dmg), Color(1.0, 0.35, 0.35))
			Juice.hitstop(0.05)
			Juice.shake(clampf(float(ev.dmg) * 0.6, 2.0, 10.0))
			Audio.play("hurt")
			await _wait(beat * 0.65)
			return
		"miss":
			_hero.play_attack(beat / speed)
			var t := _actor(ev.target)
			if t:
				Juice.popup(self, t.position + Vector2(0, -30), "miss", Color(0.7, 0.7, 0.7))
			Audio.play("whiff")
		"dodge":
			var a := _actor(ev.actor)
			if a:
				a.play_attack(beat / speed)
			_hero.play_dodge()
			Juice.popup(self, _hero.position + Vector2(0, -30), "DODGE", Color(0.7, 1.0, 0.8))
			Audio.play("whiff")
		"block":
			var a2 := _actor(ev.actor)
			if a2:
				a2.play_attack(beat / speed)
			await _wait(beat * 0.3)
			_hero.play_block()
			Juice.popup(self, _hero.position + Vector2(0, -30), "BLOCK", Color(0.8, 0.85, 1.0))
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
		"heal":
			_hero.set_hp(int(ev.hp))
			_hero.play_heal()
			Juice.popup(self, _hero.position + Vector2(0, -30), "+%d" % int(ev.amount), Color(0.45, 1.0, 0.5))
			if ev.source == "second_wind":
				Juice.popup(self, _hero.position + Vector2(0, -46), "SECOND WIND", Color(0.6, 1.0, 0.7), true)
				Juice.hitstop(0.15)
			Audio.play("heal")
		"kill":
			var k := _actor(ev.target)
			if k:
				k.play_death(beat / speed)
				Juice.shake("small")
			Audio.play("kill")
		"drop":
			Juice.popup(self, Vector2(0, -20), "+%d %s" % [int(ev.qty), _db.get_row("materials", ev.material).get("name", "")], Color(0.9, 0.8, 0.6))
		"treasure":
			Juice.popup(self, Vector2(0, -10), "+%d gold" % int(ev.gold), Color(1.0, 0.85, 0.3), true)
			if ev.mod != "":
				Juice.popup(self, Vector2(0, -28), _db.get_row("mods", ev.mod).get("name", "Mod"), Color(0.7, 0.9, 1.0), true)
			Audio.play("treasure")
		"trap":
			if ev.dodged:
				_hero.play_dodge()
				Juice.popup(self, _hero.position + Vector2(0, -30), "TRAP DODGED", Color(0.7, 1.0, 0.8))
			else:
				_hero.play_hurt()
				_hero.set_hp(int(ev.hp))
				Juice.popup(self, _hero.position + Vector2(0, -30), str(ev.dmg), Color(1.0, 0.35, 0.35))
				Juice.shake("small")
				Audio.play("trap")
		"retreat":
			Juice.popup(self, _hero.position + Vector2(0, -40), "RETREAT!", Color(1.0, 0.9, 0.5), true)
			var t2 := _hero.create_tween()
			t2.tween_property(_hero, "position", _hero.position + Vector2(-80, 0), beat / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			Audio.play("retreat")
		"death":
			# The big one: slow motion on the killing blow, then hold.
			Engine.time_scale = 0.35
			_hero.play_death(beat / speed)
			Juice.shake("big")
			Audio.play("death")
			await _wait(beat * 0.35)
			Engine.time_scale = 1.0
			await _wait(beat * 0.65)
			return
		"run_end":
			_room_label.text = {"survived": "Heading home", "retreated": "Limping home", "died": "Lost"}.get(ev.outcome, "")
			Juice.pop(_room_label, 0.3)
	await _wait(beat)


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


func _jump_to_end(result: Dictionary) -> void:
	Engine.time_scale = 1.0
	_clear_monsters()
	_hero.set_hp(int(result.hp_left))
	if result.outcome == "died":
		_hero.play_death(0.2)
	_room_label.text = {"survived": "Heading home", "retreated": "Limping home", "died": "Lost"}.get(result.outcome, "")


func _actor(actor_key: String) -> PlaybackActor:
	if actor_key == "hero":
		return _hero
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
	if is_instance_valid(_hero):
		_hero.queue_free()
	_hero = null
