class_name PlaybackActor
extends Node2D
## One hero or monster on the delve stage. Plays pack animations when the
## sprite exists, otherwise a placeholder block with the same timing, so the
## playback code is identical before and after art lands.

const PLACEHOLDER_SIZE := Vector2(14, 22)
const LUNGE_REACH := 0.4   # fraction of the gap a melee attacker covers

var key := ""
var display_name := ""
var hp := 1
var max_hp := 1
var facing_left := false
var color := Color(0.6, 0.8, 1.0)
var dead := false
var gone := false   # walked off (retreated)
var ranged := false # shoots instead of lunging
var meter := 0.0   # action meter 0..100, drawn under the HP bar

var _sprite: AnimatedSprite2D
var _body: Node2D       # what flashes and squashes (sprite or placeholder)
var _home := Vector2.ZERO


func setup(actor_key: String, sprite_key: String, label: String, start_hp: int, start_max_hp: int, left: bool, tint: Color) -> void:
	key = actor_key
	display_name = label
	hp = start_hp
	max_hp = maxi(1, start_max_hp)
	facing_left = left
	color = tint
	var frames := CharacterSprites.frames_for(sprite_key)
	if frames:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = frames
		_sprite.flip_h = left
		_sprite.modulate = tint
		_sprite.position = Vector2(0, -20)  # pack characters stand near the cell's middle
		add_child(_sprite)
		_body = _sprite
		_play("idle")
	else:
		color = (Color(0.9, 0.42, 0.38) if left else Color(0.45, 0.7, 1.0)) * tint
		_body = Node2D.new()
		add_child(_body)
		_body.draw.connect(_draw_placeholder)
		_body.queue_redraw()
	queue_redraw()


func _ready() -> void:
	_home = position


func set_home(pos: Vector2) -> void:
	position = pos
	_home = pos


func set_hp(value: int) -> void:
	hp = maxi(0, value)
	queue_redraw()


## Slides the action bar to a new value. A drop means this unit just acted.
func set_meter(value: float, duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float):
		meter = v
		queue_redraw(), meter, clampf(value, 0.0, 100.0), duration)


func body() -> Node2D:
	return _body


## Lunges part of the way toward `target_pos` (a sibling position) and back.
## Ranged units only lean in a little; their projectile does the travelling.
func play_attack(duration: float, target_pos: Variant = null) -> void:
	_play("attack")
	var dir := -1.0 if facing_left else 1.0
	var offset := Vector2(10 * dir, 0)
	if target_pos is Vector2 and not ranged:
		offset = ((target_pos as Vector2) - _home) * LUNGE_REACH
	elif ranged:
		offset = Vector2(-4 * dir, 0)  # draw back the bow
	var t := create_tween()
	t.tween_property(self, "position", _home + offset, duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position", _home, duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func(): if not dead: _play("idle"))


## Turns tail and walks off the stage.
func play_retreat(duration: float) -> void:
	gone = true
	if _sprite:
		_sprite.flip_h = not facing_left
	_play("walk")
	var dir := 1.0 if facing_left else -1.0
	var t := create_tween()
	t.tween_property(self, "position", _home + Vector2(90 * dir, 0), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "modulate:a", 0.0, duration)
	queue_redraw()


func play_hurt() -> void:
	_play("hurt")
	Juice.flash(_body)
	var dir := 1.0 if facing_left else -1.0
	var t := create_tween()
	t.tween_property(self, "position", _home + Vector2(4 * dir, 0), 0.05)
	t.tween_property(self, "position", _home, 0.12)
	t.tween_callback(func(): if not dead: _play("idle"))


func play_block() -> void:
	_play("block")
	Juice.squash(_body, 0.15)


func play_dodge() -> void:
	var dir := 1.0 if facing_left else -1.0
	var t := create_tween()
	t.tween_property(self, "position", _home + Vector2(12 * dir, -4), 0.08)
	t.tween_property(self, "position", _home, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_heal() -> void:
	Juice.flash(_body, Color(1.2, 3.0, 1.4), 0.25)
	Juice.pop(_body, 0.12)


func play_death(duration: float) -> void:
	dead = true
	_play("death")
	var t := create_tween()
	t.tween_interval(duration * 0.6)
	t.tween_property(self, "modulate:a", 0.25, duration * 0.4)
	queue_redraw()


func _play(anim: String) -> void:
	if _sprite and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)


func _draw() -> void:
	# HP bar above the head
	if dead or gone:
		return
	var w := 20.0
	var y := -PLACEHOLDER_SIZE.y - 8.0
	draw_rect(Rect2(-w / 2, y, w, 3), Color(0.1, 0.05, 0.08))
	draw_rect(Rect2(-w / 2, y, w * float(hp) / max_hp, 3), Color(0.85, 0.25, 0.25) if facing_left else Color(0.35, 0.85, 0.4))
	# Action meter (Haste): fills, then empties when the unit acts.
	draw_rect(Rect2(-w / 2, y + 4, w, 2), Color(0.1, 0.05, 0.08))
	draw_rect(Rect2(-w / 2, y + 4, w * meter / 100.0, 2), Color(0.95, 0.8, 0.35))


func _draw_placeholder() -> void:
	var r := Rect2(-PLACEHOLDER_SIZE.x / 2, -PLACEHOLDER_SIZE.y, PLACEHOLDER_SIZE.x, PLACEHOLDER_SIZE.y)
	_body.draw_rect(r, color)
	_body.draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
	var eye_x := -3.0 if facing_left else 3.0
	_body.draw_rect(Rect2(eye_x - 1, -PLACEHOLDER_SIZE.y + 5, 2, 2), Color(0.1, 0.05, 0.08))
