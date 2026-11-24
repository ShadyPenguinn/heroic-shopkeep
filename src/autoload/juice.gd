extends Node
## The juice library. The rule for this project: juice is a one-line call, so
## it actually gets added. Every helper respects the player's settings
## (screen shake strength, hit-stop and flashes can be turned down or off).
##
##   Juice.shake("medium")                    # camera shake: tiny/small/medium/big/huge or pixels
##   Juice.hitstop(0.06)                      # freeze-frame on impact
##   Juice.pop(node)                          # quick scale punch
##   Juice.squash(node)                       # squash and stretch
##   Juice.flash(node)                        # white flash on hurt
##   Juice.popup(parent, pos, "12", Color.RED, true)  # floating damage number
##   Juice.roll_number(label, 10, 250)        # counter rolls up instead of jumping
##   Juice.slide_in(control, Vector2(0, 20))  # entrance
##   Juice.bind_button(button)                # hover lift, press squash, click sound
##
## UI tweens ignore time scale so menus never freeze during hit-stop.

const SHAKE := {"tiny": 1.5, "small": 3.0, "medium": 6.0, "big": 10.0, "huge": 16.0}
const SHAKE_DECAY_PER_SEC := 30.0
const POPUP_POOL_SIZE := 32

var _camera: Camera2D
var _shake_px := 0.0
var _last_usec := 0
var _hitstop_until_usec := 0
var _hitstop_active := false
var _popup_pool: Array[Label] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	# Real time, so shake keeps moving and hit-stop ends while time is scaled.
	var now := Time.get_ticks_usec()
	var real_dt := (now - _last_usec) / 1_000_000.0
	_last_usec = now
	if _hitstop_active and now >= _hitstop_until_usec:
		_hitstop_active = false
		Engine.time_scale = 1.0
	if is_instance_valid(_camera):
		if _shake_px > 0.0:
			var o := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_px
			_camera.offset = o.round()  # whole pixels keep pixel art crisp
			_shake_px = move_toward(_shake_px, 0.0, SHAKE_DECAY_PER_SEC * real_dt)
		elif _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO


# --- camera ------------------------------------------------------------------------

func register_camera(cam: Camera2D) -> void:
	_camera = cam


## strength: a SHAKE name or a number of pixels.
func shake(strength: Variant = "small") -> void:
	var px: float = SHAKE.get(strength, 3.0) if strength is String else float(strength)
	px *= float(Settings.value("screen_shake"))
	_shake_px = maxf(_shake_px, px)


## Freezes (or nearly freezes) game time for a moment. Overlapping calls extend
## the freeze rather than stacking.
func hitstop(seconds: float = 0.06, time_scale: float = 0.02) -> void:
	if not Settings.value("hit_stop") or seconds <= 0.0:
		return
	var until := Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	_hitstop_until_usec = maxi(_hitstop_until_usec, until)
	_hitstop_active = true
	Engine.time_scale = time_scale


# --- tweens --------------------------------------------------------------------------

func pop(node: CanvasItem, amount: float = 0.15, duration: float = 0.25) -> Tween:
	_center_pivot(node)
	var base := _base_scale(node)
	var t := node.create_tween().set_ignore_time_scale()
	node.set("scale", base * (1.0 + amount))
	t.tween_property(node, "scale", base, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


func squash(node: CanvasItem, amount: float = 0.2, duration: float = 0.18) -> Tween:
	_center_pivot(node)
	var base := _base_scale(node)
	var t := node.create_tween().set_ignore_time_scale()
	t.tween_property(node, "scale", base * Vector2(1.0 + amount, 1.0 - amount), duration * 0.3)
	t.tween_property(node, "scale", base * Vector2(1.0 - amount * 0.5, 1.0 + amount * 0.5), duration * 0.3)
	t.tween_property(node, "scale", base, duration * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## Bright flash then back to normal. Uses over-bright modulate, which reads as
## a white flash on pixel sprites without needing a shader.
func flash(node: CanvasItem, color: Color = Color(4, 4, 4), duration: float = 0.12) -> Tween:
	if not Settings.value("flashes"):
		color = color.lerp(Color.WHITE, 0.75)
	var original: Color = node.get_meta("juice_modulate", node.modulate)
	node.set_meta("juice_modulate", original)
	node.modulate = color
	var t := node.create_tween()
	t.tween_property(node, "modulate", original, duration)
	return t


func shake_node(node: CanvasItem, px: float = 3.0, duration: float = 0.2) -> Tween:
	var origin: Vector2 = node.get_meta("juice_origin", node.get("position"))
	node.set_meta("juice_origin", origin)
	var t := node.create_tween().set_ignore_time_scale()
	var steps := 6
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		t.tween_property(node, "position", origin + Vector2(randf_range(-px, px), randf_range(-px, px)).round() * falloff, duration / steps)
	t.tween_property(node, "position", origin, duration / steps)
	return t


func slide_in(node: CanvasItem, from_offset: Vector2 = Vector2(0, 16), duration: float = 0.3, delay: float = 0.0) -> Tween:
	var target: Vector2 = node.get("position")
	node.set("position", target + from_offset)
	node.modulate.a = 0.0
	var t := node.create_tween().set_parallel().set_ignore_time_scale()
	t.tween_property(node, "position", target, duration).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, duration * 0.6).set_delay(delay)
	return t


func fade(node: CanvasItem, to_alpha: float, duration: float = 0.25) -> Tween:
	var t := node.create_tween().set_ignore_time_scale()
	t.tween_property(node, "modulate:a", to_alpha, duration)
	return t


## Rolls a number shown in a Label from `from` to `to`. Optional tick sound
## climbs in pitch as it counts.
func roll_number(label: Label, from: int, to: int, duration: float = 0.6, fmt: String = "%d", tick_sfx: String = "") -> Tween:
	var state := {"last": from, "step": 0}
	var t := label.create_tween().set_ignore_time_scale()
	t.tween_method(func(v: float):
		var n := roundi(v)
		label.text = fmt % n
		if tick_sfx != "" and n != state.last:
			state.step += 1
			if state.step % 2 == 0:
				Audio.play_step(tick_sfx, state.step / 2)
		state.last = n
	, float(from), float(to), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t


# --- floating text -----------------------------------------------------------------

## Pops a number or word that arcs up and fades. Pooled, so spamming is cheap.
func popup(parent: Node, pos: Vector2, text: String, color: Color = Color.WHITE, big: bool = false) -> void:
	var label := _take_popup()
	if label.get_parent():
		label.get_parent().remove_child(label)
	parent.add_child(label)
	label.text = text
	label.modulate = color
	label.z_index = 100
	label.add_theme_font_size_override("font_size", 16 if big else 10)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = (pos - label.size / 2.0).round()
	label.scale = Vector2.ONE * (1.6 if big else 1.3)
	label.visible = true
	var drift := randf_range(-10.0, 10.0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", label.position.y - (22.0 if big else 16.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:x", label.position.x + drift, 0.6)
	t.tween_property(label, "modulate:a", 0.0, 0.25).set_delay(0.45)
	t.chain().tween_callback(func(): _return_popup(label))


func _take_popup() -> Label:
	if not _popup_pool.is_empty():
		return _popup_pool.pop_back()
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.1))
	return l


func _return_popup(label: Label) -> void:
	label.visible = false
	if _popup_pool.size() < POPUP_POOL_SIZE:
		_popup_pool.append(label)
	else:
		label.queue_free()


# --- buttons ---------------------------------------------------------------------------

## Makes any button answer the player: lift on hover, squash on press,
## overshoot on release, and a click with pitch variation.
func bind_button(button: BaseButton, click_sfx: String = "click", hover_sfx: String = "hover") -> void:
	button.resized.connect(func(): button.pivot_offset = button.size / 2.0)
	button.pivot_offset = button.size / 2.0
	button.mouse_entered.connect(func():
		if button.disabled:
			return
		Audio.play_ui(hover_sfx)
		var t := button.create_tween().set_ignore_time_scale()
		t.tween_property(button, "scale", Vector2(1.04, 1.04), 0.08))
	button.mouse_exited.connect(func():
		var t := button.create_tween().set_ignore_time_scale()
		t.tween_property(button, "scale", Vector2.ONE, 0.1))
	button.button_down.connect(func():
		var t := button.create_tween().set_ignore_time_scale()
		t.tween_property(button, "scale", Vector2(1.08, 0.9), 0.05))
	button.button_up.connect(func():
		var t := button.create_tween().set_ignore_time_scale()
		t.tween_property(button, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	button.pressed.connect(func(): Audio.play_ui(click_sfx))


# --- helpers -----------------------------------------------------------------------------

func _center_pivot(node: CanvasItem) -> void:
	if node is Control:
		node.pivot_offset = node.size / 2.0


func _base_scale(node: CanvasItem) -> Vector2:
	if not node.has_meta("juice_scale"):
		node.set_meta("juice_scale", node.get("scale"))
	return node.get_meta("juice_scale")
