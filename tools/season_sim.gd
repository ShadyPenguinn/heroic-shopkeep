extends SceneTree
## Plays whole seasons with the AutoPlayer bot and reports how the economy
## holds up: win rate, the day seasons are lost, gold curve, deaths.
##   godot --headless --path . -s res://tools/season_sim.gd -- --seasons 200 --samples 30
## Run it overnight with a big --seasons number after balance changes.
## Writes build/season_sim.csv (one row per season).


func _initialize() -> void:
	var args := _args()
	var seasons := int(args.get("seasons", "50"))
	var samples := int(args.get("samples", "30"))
	var base_seed := int(args.get("seed", "1"))
	var db := ContentDB.load_from()
	if not db.is_valid():
		printerr("\n".join(db.errors))
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var wins := 0
	var lost_days := {}
	var gold_by_day: Array = []
	var deaths_total := 0
	var csv := PackedStringArray(["seed,won,last_day,gold,deaths,gear_lost,loans,gold_earned"])
	for i in seasons:
		var st := Season.new_game(db, base_seed + i)
		var bot := AutoPlayer.new()
		bot.estimate_samples = samples
		while not st.is_over():
			while gold_by_day.size() < st.day:
				gold_by_day.append([])
			gold_by_day[st.day - 1].append(st.gold)  # gold at dawn
			bot.play_day(db, st)
		var won := st.phase == GameState.Phase.WON
		if won:
			wins += 1
		else:
			lost_days[st.day] = int(lost_days.get(st.day, 0)) + 1
		deaths_total += int(st.stats.get("deaths", 0))
		csv.append("%d,%s,%d,%d,%d,%d,%d,%d" % [base_seed + i, won, st.day, st.gold, int(st.stats.get("deaths", 0)),
			int(st.stats.get("gear_lost", 0)), int(st.stats.get("loans", 0)), int(st.stats.get("gold_earned", 0))])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("Seasons: %d   Won: %d (%d%%)   Avg deaths per season: %.1f   (%.1fs)" % [
		seasons, wins, roundi(100.0 * wins / seasons), float(deaths_total) / seasons, secs])
	var keys := lost_days.keys()
	keys.sort()
	var lines: Array = []
	for k in keys:
		lines.append("day %d: %d" % [k, lost_days[k]])
	print("Seasons lost on: " + (", ".join(lines) if not lines.is_empty() else "none"))
	var curve: Array = []
	for d in range(0, gold_by_day.size(), 7):
		var vals: Array = gold_by_day[d]
		var sum := 0
		for v in vals:
			sum += int(v)
		curve.append("d%d=%d" % [d + 1, sum / maxi(1, vals.size())])
	print("Average gold: " + "  ".join(curve))
	DirAccess.make_dir_recursive_absolute("res://build")
	var f := FileAccess.open("res://build/season_sim.csv", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(csv) + "\n")
	quit(0)


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out
