class_name SteamBackend
extends PlatformBackend
## Steam via the GodotSteam GDExtension (https://godotsteam.com), loaded at
## runtime so the project runs and exports fine without it installed.
##
## Saves stay in user://saves/ (inherited). Turn on Steam Auto-Cloud for that
## folder in Steamworks and cloud saves work with no code here.
##
## Setup when you go to Steam: install the GodotSteam GDExtension into addons/,
## set game/steam/app_id in Project Settings, and export with the "steam" feature
## tag (the "Windows (Steam)" preset already has it).

signal overlay_toggled(active: bool)

var _steam: Object
var _overlay := false


func init() -> bool:
	super.init()
	if not Engine.has_singleton("Steam"):
		push_warning("Steam build, but the GodotSteam extension is not installed.")
		return false
	_steam = Engine.get_singleton("Steam")
	var app_id := int(ProjectSettings.get_setting("game/steam/app_id", 480))
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))
	var res: Variant = _steam.call("steamInitEx")
	var ok := false
	if res is Dictionary:
		ok = int(res.get("status", 1)) == 0
	else:
		ok = bool(res)
	if not ok:
		push_warning("Steam failed to start: %s" % str(res))
		return false
	if _steam.has_signal("overlay_toggled"):
		_steam.connect("overlay_toggled", _on_overlay_toggled)
	return true


func tick() -> void:
	if _steam:
		_steam.call("run_callbacks")


func id() -> String:
	return "steam"


func display_name() -> String:
	return "Steam"


func user_name() -> String:
	return str(_steam.call("getPersonaName")) if _steam else ""


func unlock_achievement(local_id: String, store_id: String) -> void:
	super.unlock_achievement(local_id, store_id)
	if _steam and store_id != "":
		_steam.call("setAchievement", store_id)
		_steam.call("storeStats")


func set_stat(stat_name: String, value: int) -> void:
	if _steam:
		_steam.call("setStatInt", stat_name, value)
		_steam.call("storeStats")


func is_overlay_active() -> bool:
	return _overlay


func open_store_page() -> void:
	if _steam:
		_steam.call("activateGameOverlayToStore", int(ProjectSettings.get_setting("game/steam/app_id", 480)))


func _on_overlay_toggled(active: bool, _user_initiated: bool = false, _app_id: int = 0) -> void:
	_overlay = active
	overlay_toggled.emit(active)
