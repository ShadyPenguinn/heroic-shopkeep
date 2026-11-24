class_name SurvivalEstimator
extends RefCounted
## The Safe / Risky / Deadly read at the counter. Runs a batch of quick party
## sims (no event log) and reports how often each hero died. Honest but fuzzy:
## it is real sampling, and the reported range widens when the sample is small.


## One hero alone. Same shape as before the party existed.
static func estimate(db: ContentDB, hero: Dictionary, gear: Array, floor_index: int, base_seed: int, samples: int = -1, opts: Dictionary = {}) -> Dictionary:
	var est := estimate_party(db, [{"hero": hero, "gear": gear}], floor_index, base_seed, samples, opts)
	return est.heroes[hero.get("uid", "")]


## members: [{hero, gear}] in slot order. Returns
## {samples, wipe_rate, any_death_rate, band, heroes: {uid: {death_rate, death_low,
##  death_high, retreat_rate, avg_best_card, band, samples}}}
## band is the party's worst: one likely death makes the whole delve "deadly".
static func estimate_party(db: ContentDB, members: Array, floor_index: int, base_seed: int, samples: int = -1, opts: Dictionary = {}) -> Dictionary:
	var n := samples if samples > 0 else int(db.bal("estimate_sims", 200))
	var sim_opts := opts.duplicate()
	sim_opts["record_events"] = false
	var deaths := {}
	var retreats := {}
	var best_card := {}
	for m in members:
		var uid: String = m.hero.get("uid", "")
		deaths[uid] = 0
		retreats[uid] = 0
		best_card[uid] = 0.0
	var wipes := 0
	var any_death := 0
	for i in n:
		var r := RunSimulator.simulate_party(db, members, floor_index, Rng.derive(base_seed, ["estimate", i]), sim_opts)
		if r.outcome == "wiped":
			wipes += 1
		var died := false
		for h in r.heroes:
			match h.outcome:
				"died":
					deaths[h.hero_uid] += 1
					died = true
				"retreated":
					retreats[h.hero_uid] += 1
			var best := 0.0
			for c in h.haul:
				best = maxf(best, float(c.value))
			best_card[h.hero_uid] += best  # you only get to take one card
		if died:
			any_death += 1
	var per_hero := {}
	var worst := 0.0
	for uid in deaths:
		var p := float(deaths[uid]) / n
		worst = maxf(worst, p)
		var margin := 1.96 * sqrt(maxf(p * (1.0 - p), 0.0001) / n)
		per_hero[uid] = {
			"samples": n,
			"death_rate": p,
			"death_low": maxf(0.0, p - margin),
			"death_high": minf(1.0, p + margin),
			"retreat_rate": float(retreats[uid]) / n,
			"avg_best_card": best_card[uid] / n,
			"band": band_for(db, p),
		}
	return {
		"samples": n,
		"wipe_rate": float(wipes) / n,
		"any_death_rate": float(any_death) / n,
		"band": band_for(db, worst),
		"heroes": per_hero,
	}


static func band_for(db: ContentDB, death_rate: float) -> String:
	var bands: Dictionary = db.bal("survival_bands", {"safe": 0.1, "risky": 0.35})
	if death_rate <= float(bands.safe):
		return "safe"
	if death_rate <= float(bands.risky):
		return "risky"
	return "deadly"
