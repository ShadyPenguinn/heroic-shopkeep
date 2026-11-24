class_name SurvivalEstimator
extends RefCounted
## The Safe / Risky / Deadly read at the counter. Runs a batch of quick sims
## (no event log) and reports what fraction died. Honest but fuzzy: it is real
## sampling, and the reported range widens when the sample is small.


static func estimate(db: ContentDB, hero: Dictionary, gear: Array, floor_index: int, base_seed: int, samples: int = -1, opts: Dictionary = {}) -> Dictionary:
	var n := samples if samples > 0 else int(db.bal("estimate_sims", 200))
	var deaths := 0
	var retreats := 0
	var haul_value := 0.0
	var sim_opts := opts.duplicate()
	sim_opts["record_events"] = false
	for i in n:
		var r := RunSimulator.simulate(db, hero, gear, floor_index, Rng.derive(base_seed, ["estimate", i]), sim_opts)
		match r.outcome:
			"died":
				deaths += 1
			"retreated":
				retreats += 1
		var best := 0.0
		for c in r.haul:
			best = maxf(best, float(c.value))
		haul_value += best  # you only get to take one card
	var p := float(deaths) / n
	var margin := 1.96 * sqrt(maxf(p * (1.0 - p), 0.0001) / n)
	var bands: Dictionary = db.bal("survival_bands", {"safe": 0.1, "risky": 0.35})
	var band := "deadly"
	if p <= float(bands.safe):
		band = "safe"
	elif p <= float(bands.risky):
		band = "risky"
	return {
		"samples": n,
		"death_rate": p,
		"death_low": maxf(0.0, p - margin),
		"death_high": minf(1.0, p + margin),
		"retreat_rate": float(retreats) / n,
		"avg_best_card": haul_value / n,
		"band": band,
	}
