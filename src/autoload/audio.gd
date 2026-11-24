extends Node
## Sound with variety built in. Every call randomises pitch a little so repeated
## sounds never feel robotic.
##
##   Audio.play("click")                    # res://assets/audio/sfx/click.(ogg|wav|mp3)
##   Audio.play_step("coin", i)             # rising pitch for coin roll-ups
##   Audio.music("shop")                    # crossfades res://assets/audio/music/shop.*
##
## A missing file is a warning, not a crash, so code can call sounds before the
## audio pass (Day 24) adds them.

const BUSES: PackedStringArray = ["Music", "SFX", "UI"]
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]
const VOICES := 12

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _music_players: Array[AudioStreamPlayer] = []
var _music_index := 0
var _current_music := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		add_child(m)
		_music_players.append(m)


func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func play(sfx: String, pitch_jitter: float = 0.08, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var stream := _stream(SFX_DIR, sfx)
	if stream == null:
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func play_ui(sfx: String) -> void:
	play(sfx, 0.05, 0.0, 1.0, "UI")


## For sequences (coins into the purse, a counter rolling up): pitch climbs
## with each step, capped so it never squeals.
func play_step(sfx: String, step: int, pitch_per_step: float = 0.05, max_pitch: float = 1.8) -> void:
	play(sfx, 0.02, 0.0, minf(max_pitch, 1.0 + step * pitch_per_step))


func music(track: String, fade: float = 0.8) -> void:
	if track == _current_music:
		return
	_current_music = track
	var outgoing := _music_players[_music_index]
	_music_index = 1 - _music_index
	var incoming := _music_players[_music_index]
	if outgoing.playing:
		var out_tween := create_tween().set_ignore_time_scale()
		out_tween.tween_property(outgoing, "volume_db", -40.0, fade)
		out_tween.tween_callback(outgoing.stop)
	if track == "":
		return
	var stream := _stream(MUSIC_DIR, track)
	if stream == null:
		return
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	create_tween().set_ignore_time_scale().tween_property(incoming, "volume_db", 0.0, fade)


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


func _stream(dir: String, sfx: String) -> AudioStream:
	var key := dir + sfx
	if _cache.has(key):
		return _cache[key]
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [dir, sfx, ext]
		if ResourceLoader.exists(path):
			_cache[key] = load(path)
			return _cache[key]
	if not _warned.has(key):
		_warned[key] = true
		print_verbose("[audio] no sound yet for '%s'" % key)
	_cache[key] = null
	return null
