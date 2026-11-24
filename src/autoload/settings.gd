extends Node
## Player settings, saved per machine in user://settings.cfg (not in the save
## game, so they survive starting a new season).
##
##   Settings.value("screen_shake")
##   Settings.set_value("music_volume", 0.5)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"ui_volume": 0.7,
	"fullscreen": false,
	"screen_shake": 1.0,     # 0 turns shake off (accessibility)
	"hit_stop": true,
	"flashes": true,
	"text_speed": 1.0,
	"playback_speed": 1.0,
}

var _values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputActions.register_defaults()
	_load()
	UiTheme.install()
	apply()


func value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	_values[key] = v
	apply()
	save()
	Events.settings_changed.emit()


func apply() -> void:
	Audio.set_bus_volume("Master", float(value("master_volume")))
	Audio.set_bus_volume("Music", float(value("music_volume")))
	Audio.set_bus_volume("SFX", float(value("sfx_volume")))
	Audio.set_bus_volume("UI", float(value("ui_volume")))
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func save() -> void:
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value("settings", k, _values[k])
	InputActions.save_bindings(cfg)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		_values[k] = cfg.get_value("settings", k, DEFAULTS[k])
	InputActions.load_bindings(cfg)
