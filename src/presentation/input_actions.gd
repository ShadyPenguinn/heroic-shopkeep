class_name InputActions
extends RefCounted
## Input actions are defined here (not in project.godot) so players can remap
## them in Settings and the bindings save with the other settings.

const DEFAULTS := {
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"cancel": [KEY_ESCAPE],
	"skip": [KEY_SPACE],
	"speed_toggle": [KEY_TAB],
}


static func register_defaults() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for key in DEFAULTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


static func save_bindings(cfg: ConfigFile) -> void:
	for action in DEFAULTS:
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(ev.physical_keycode)
		cfg.set_value("input", action, keys)


static func load_bindings(cfg: ConfigFile) -> void:
	for action in DEFAULTS:
		var keys: Array = cfg.get_value("input", action, [])
		if keys.is_empty():
			continue
		InputMap.action_erase_events(action)
		for key in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(key)
			InputMap.action_add_event(action, ev)
