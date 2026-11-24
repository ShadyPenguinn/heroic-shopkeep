class_name SaveSystem
extends RefCounted
## Reads and writes GameState through a PlatformBackend's storage, so the same
## code saves to disk on itch, to Steam's cloud folder on Steam, and wherever a
## future store wants.
##
## Writes are crash-safe: write a temp file, keep the previous save as .bak,
## then swap. Loading falls back to .bak if the main file is damaged.

const DEFAULT_SLOT := "season"


static func save(storage: PlatformBackend, state: GameState, slot: String = DEFAULT_SLOT) -> Error:
	var payload := {
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": state.to_dict(),
	}
	# sort_keys = false keeps insertion order, so iteration order (and therefore
	# the seeded season) is identical after a reload.
	var bytes := JSON.stringify(payload, "\t", false).to_utf8_buffer()
	var name := slot + ".json"
	var err := storage.write_file(name + ".tmp", bytes)
	if err != OK:
		return err
	if storage.file_exists(name):
		storage.remove_file(name + ".bak")
		storage.rename_file(name, name + ".bak")
	return storage.rename_file(name + ".tmp", name)


static func load_state(storage: PlatformBackend, slot: String = DEFAULT_SLOT) -> GameState:
	for name in [slot + ".json", slot + ".json.bak"]:
		if not storage.file_exists(name):
			continue
		var data: Variant = JSON.parse_string(storage.read_file(name).get_string_from_utf8())
		if data is Dictionary and data.has("state"):
			return GameState.from_dict(data.state)
		push_warning("Save file %s is damaged, trying the backup." % name)
	return null


static func has_save(storage: PlatformBackend, slot: String = DEFAULT_SLOT) -> bool:
	return storage.file_exists(slot + ".json") or storage.file_exists(slot + ".json.bak")


static func delete(storage: PlatformBackend, slot: String = DEFAULT_SLOT) -> void:
	for suffix in [".json", ".json.bak", ".json.tmp"]:
		storage.remove_file(slot + suffix)
