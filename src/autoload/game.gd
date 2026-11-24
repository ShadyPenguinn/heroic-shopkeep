extends Node
## The running season. Holds the one GameState, calls Season for the rules,
## then announces what happened on the Events bus, unlocks achievements, and
## autosaves at every dawn.
##
## Scenes call these methods; they never edit Game.state directly.

var state: GameState
var db: ContentDB:
	get:
		return Content.db


func has_save() -> bool:
	return SaveSystem.has_save(Platform.storage())


func new_game(seed_value: int = -1, difficulty: String = "normal") -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	state = Season.new_game(db, seed_value, difficulty)
	save()
	Events.state_loaded.emit()


func continue_game() -> bool:
	state = SaveSystem.load_state(Platform.storage())
	if state == null:
		return false
	Events.state_loaded.emit()
	return true


func save() -> void:
	if state == null:
		return
	var err := SaveSystem.save(Platform.storage(), state)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))


# --- the day ------------------------------------------------------------------------

func start_day() -> void:
	Season.start_day(db, state)
	Events.day_started.emit(state.day)


func lend(hero_uid: String, gear_uids: Array, floor_index: int) -> String:
	var err := Season.lend(db, state, hero_uid, gear_uids, floor_index)
	if err == "":
		Platform.unlock("first_loan")
		Events.gear_lent.emit(hero_uid)
	return err


func turn_away(hero_uid: String) -> void:
	Season.turn_away(state, hero_uid)


func estimate(hero_uid: String, gear: Array, floor_index: int) -> Dictionary:
	return Season.estimate_loan(db, state, hero_uid, gear, floor_index)


func send_delves() -> void:
	Season.send_delves(db, state)
	save()  # a quit mid-delve resumes with the same results
	Events.delves_sent.emit(state.results)


func begin_dusk() -> Array:
	var report := Season.begin_dusk(db, state)
	for entry in report:
		if not entry.lost_gear.is_empty():
			Platform.unlock("first_loss")
		for t in entry.titles:
			Platform.unlock("titled_gear")
			Events.title_earned.emit(t.gear, t.title)
	Events.dusk_report.emit(report)
	return report


func take_card(hero_uid: String, card_index: int) -> String:
	var err := Season.take_card(db, state, hero_uid, card_index)
	if err == "":
		var r := Season.result_for(state, hero_uid)
		Events.card_taken.emit(hero_uid, r.haul[card_index])
	return err


func end_day() -> Dictionary:
	var day := state.day
	var out := Season.end_day(db, state)
	if out.rent > 0:
		if out.paid:
			Platform.unlock("rent_paid")
		Events.rent_collected.emit(out.rent, out.paid)
	Events.day_ended.emit(day)
	if out.won:
		Platform.unlock("season_won")
	if state.is_over():
		Events.season_over.emit(out.won)
	save()  # autosave at dawn
	return out
