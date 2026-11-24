extends RefCounted


func test_local_storage_and_atomic_save(t: TestContext) -> void:
	var p := PlatformBackend.new()
	t.ok(p.init(), "local backend starts")
	var db := ContentDB.load_from()
	var st := Season.new_game(db, 77)
	var slot := "test_slot"
	SaveSystem.delete(p, slot)
	t.eq(SaveSystem.save(p, st, slot), OK, "first save")
	st.gold = 999
	t.eq(SaveSystem.save(p, st, slot), OK, "second save")
	t.ok(p.file_exists(slot + ".json.bak"), "previous save kept as backup")
	var loaded := SaveSystem.load_state(p, slot)
	t.eq(loaded.gold, 999, "loads latest")
	# Corrupt the main file: loading falls back to the backup.
	p.write_file(slot + ".json", "{not json".to_utf8_buffer())
	var recovered := SaveSystem.load_state(p, slot)
	t.ok(recovered != null, "recovers from backup")
	SaveSystem.delete(p, slot)
	t.ok(not SaveSystem.has_save(p, slot), "deleted")


func test_achievements_recorded_locally(t: TestContext) -> void:
	var p := PlatformBackend.new()
	p.init()
	p.unlock_achievement("test_ach", "")
	t.ok(p.is_achievement_unlocked("test_ach"), "unlocked")
	p._unlocked.erase("test_ach")
	p.write_file(PlatformBackend.LOCAL_ACHIEVEMENTS, JSON.stringify(p._unlocked).to_utf8_buffer())
