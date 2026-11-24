extends SceneTree
## Death-rate table: every class x gear tier x floor, many seeded runs each.
##   godot --headless --path . -s res://tools/balance_sim.gd -- --runs 500 --level 1
## Writes build/balance.csv as well as printing a table.


func _initialize() -> void:
	var args := _args()
	var runs := int(args.get("runs", "300"))
	var level := int(args.get("level", "1"))
	var db := ContentDB.load_from()
	if not db.is_valid():
		printerr("\n".join(db.errors))
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var csv := PackedStringArray(["class,tier,floor,death_rate,retreat_rate,avg_best_card"])
	print("Death rate by class / gear tier / floor  (%d runs each, hero level %d)\n" % [runs, level])
	print("%-10s %-5s %s" % ["class", "tier", "   F1    F2    F3    F4    F5"])
	var total := 0
	for class_id in db.ids("classes"):
		var hero := Hero.create(db, Rng.new(1), "bal")
		hero.class_id = class_id
		hero.traits = []
		hero.level = level
		for tier in [1, 2, 3]:
			var gear := _kit(db, class_id, tier)
			var line := "%-10s %-5d" % [class_id, tier]
			for f in range(1, db.floor_count() + 1):
				var est := SurvivalEstimator.estimate(db, hero, gear, f, Rng.derive(99, [class_id, tier, f]), runs)
				total += runs
				line += " %4d%%" % roundi(est.death_rate * 100)
				csv.append("%s,%d,%d,%.3f,%.3f,%.1f" % [class_id, tier, f, est.death_rate, est.retreat_rate, est.avg_best_card])
			print(line)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("\n%d simulated runs in %.1fs (%.0f runs/s)" % [total, secs, total / maxf(secs, 0.001)])
	DirAccess.make_dir_recursive_absolute("res://build")
	var f := FileAccess.open("res://build/balance.csv", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(csv) + "\n")
		print("Wrote build/balance.csv")
	quit(0)


static func _kit(db: ContentDB, class_id: String, tier: int) -> Array:
	var kinds: Array = db.get_row("classes", class_id).get("weapons", [])
	var picks := {}
	for it in db.rows("items"):
		if int(it.tier) != tier or picks.has(it.slot):
			continue
		if it.slot == "weapon" and not kinds.has(it.get("kind")):
			continue
		picks[it.slot] = it.id
	var gear: Array = []
	for slot in picks:
		gear.append(Gear.create(db, picks[slot], "k_" + slot))
	return gear


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out
