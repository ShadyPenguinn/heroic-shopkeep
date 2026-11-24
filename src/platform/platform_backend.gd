class_name PlatformBackend
extends RefCounted
## The one interface the game uses for anything a storefront provides:
## achievements, stats, file storage, overlay, store page, user name.
##
## Game code calls the Platform autoload, which holds one backend. To support a
## new store (GOG Galaxy, Epic, consoles ...), subclass this, override what the
## store offers, and add it to Platform._create_backend(). Nothing else changes.
##
## The base class is a complete, working offline backend: files under
## user://saves/, achievements remembered in a local file. itch.io uses it as is.

const SAVE_DIR := "user://saves/"
const LOCAL_ACHIEVEMENTS := "achievements.json"

var _unlocked: Dictionary = {}


## Called once at startup. Return false if the store cannot start (for example
## Steam is not running); Platform then falls back to the local backend.
func init() -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if file_exists(LOCAL_ACHIEVEMENTS):
		var data: Variant = JSON.parse_string(read_file(LOCAL_ACHIEVEMENTS).get_string_from_utf8())
		if data is Dictionary:
			_unlocked = data
	return true


## Called every frame.
func tick() -> void:
	pass


func shutdown() -> void:
	pass


## Short id used in logs and for store-specific data, e.g. achievement ids.
func id() -> String:
	return "local"


func display_name() -> String:
	return "itch.io"


func user_name() -> String:
	return ""


# --- achievements & stats ------------------------------------------------------

## `store_id` is the id this store uses (from achievements.json "store_ids"),
## `local_id` is the game's own id. The base class only records locally.
func unlock_achievement(local_id: String, _store_id: String) -> void:
	if _unlocked.has(local_id):
		return
	_unlocked[local_id] = int(Time.get_unix_time_from_system())
	write_file(LOCAL_ACHIEVEMENTS, JSON.stringify(_unlocked).to_utf8_buffer())


func is_achievement_unlocked(local_id: String) -> bool:
	return _unlocked.has(local_id)


func set_stat(_name: String, _value: int) -> void:
	pass


# --- storage (all paths are file names relative to the save folder) ---------------

func write_file(file_name: String, bytes: PackedByteArray) -> Error:
	var f := FileAccess.open(SAVE_DIR + file_name, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return OK


func read_file(file_name: String) -> PackedByteArray:
	if not file_exists(file_name):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(SAVE_DIR + file_name)


func file_exists(file_name: String) -> bool:
	return FileAccess.file_exists(SAVE_DIR + file_name)


func remove_file(file_name: String) -> Error:
	if not file_exists(file_name):
		return OK
	return DirAccess.remove_absolute(SAVE_DIR + file_name)


func rename_file(from_name: String, to_name: String) -> Error:
	return DirAccess.rename_absolute(SAVE_DIR + from_name, SAVE_DIR + to_name)


# --- store UI --------------------------------------------------------------------

func is_overlay_active() -> bool:
	return false


func open_store_page() -> void:
	var url := str(ProjectSettings.get_setting("game/store/itch_url", ""))
	if url != "":
		OS.shell_open(url)
