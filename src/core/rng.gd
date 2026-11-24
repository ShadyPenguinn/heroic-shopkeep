class_name Rng
extends RefCounted
## Deterministic random source. Every random choice in the simulation and the
## season rules goes through one of these, so a seed always replays the same run.
##
## Never call randf()/randi() (the global ones) from game logic: they are not seeded.

var _r := RandomNumberGenerator.new()
var _seed := 0


func _init(seed_value: int = 0) -> void:
	_seed = seed_value
	_r.seed = seed_value


## Builds a stable child seed from a base seed and labels, e.g.
## Rng.derive(state.run_seed, ["counter", day]). Same inputs give the same seed
## on every platform (32-bit FNV-1a, no engine hash involved).
static func derive(base: int, parts: Array = []) -> int:
	var s := str(base)
	for p in parts:
		s += "|" + str(p)
	return fnv1a(s)


static func fnv1a(s: String) -> int:
	var h := 2166136261
	for b in s.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


func fork(label: Variant) -> Rng:
	return Rng.new(derive(_seed, [label]))


func chance(p: float) -> bool:
	return _r.randf() < p


func range_i(lo: int, hi: int) -> int:
	return _r.randi_range(lo, hi)


func range_f(lo: float, hi: float) -> float:
	return _r.randf_range(lo, hi)


## Inclusive int range from a two-element array like [1, 3].
func range_arr(pair: Array) -> int:
	return _r.randi_range(int(pair[0]), int(pair[1]))


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_r.randi_range(0, arr.size() - 1)]


## Picks a key from {key: weight}. Iteration order is the data file's order,
## which keeps it deterministic.
func weighted(weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return null
	var roll := _r.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll < 0.0:
			return k
	return weights.keys().back()


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _r.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
