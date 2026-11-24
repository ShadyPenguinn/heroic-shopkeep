extends RefCounted


func test_data_loads_without_errors(t: TestContext) -> void:
	var db := ContentDB.load_from()
	t.empty(db.errors, "content errors:")
	t.ok(db.ids("classes").size() >= 8, "8 hero classes")
	t.ok(db.floor_count() == 5, "5 floors")


func test_validator_catches_bad_references(t: TestContext) -> void:
	var db := ContentDB.load_from()
	db.tables.floors.cellar.monsters["dragon"] = 1
	db.errors.clear()
	db._validate()
	t.ok(not db.is_valid(), "unknown monster should be an error")
