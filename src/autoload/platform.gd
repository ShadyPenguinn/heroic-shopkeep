extends Node
## Storefront services behind one facade. Game code calls Platform.unlock("id"),
## Platform.storage() and so on and never mentions Steam or itch directly.
##
## Which backend runs is decided by export feature tags, so one codebase builds
## for every store:
##   "steam" tag -> SteamBackend (falls back to local if Steam isn't running)
##   no tag      -> PlatformBackend (local files; what itch.io builds use)

var backend: PlatformBackend


func _ready() -> void:
	backend = _create_backend()
	if not backend.init():
		backend = PlatformBackend.new()
		backend.init()
	if backend.has_signal("overlay_toggled"):
		backend.connect("overlay_toggled", func(active: bool): Events.overlay_toggled.emit(active))
	print("[platform] %s" % backend.display_name())


func _create_backend() -> PlatformBackend:
	if OS.has_feature("steam"):
		return SteamBackend.new()
	return PlatformBackend.new()


func _process(_delta: float) -> void:
	backend.tick()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if backend:
			backend.shutdown()


func storage() -> PlatformBackend:
	return backend


func unlock(achievement_id: String) -> void:
	if backend.is_achievement_unlocked(achievement_id):
		return
	var row := Content.db.get_row("achievements", achievement_id)
	if row.is_empty():
		push_warning("Unknown achievement '%s'" % achievement_id)
		return
	var store_id: String = row.get("store_ids", {}).get(backend.id(), "")
	backend.unlock_achievement(achievement_id, store_id)
	Events.achievement_unlocked.emit(achievement_id)


func set_stat(stat_name: String, value: int) -> void:
	backend.set_stat(stat_name, value)


func is_overlay_active() -> bool:
	return backend.is_overlay_active()


func open_store_page() -> void:
	backend.open_store_page()
