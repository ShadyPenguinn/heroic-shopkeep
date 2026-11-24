class_name ContentDB
extends RefCounted
## All game content, loaded from res://data/*.json.
##
## Designers edit the JSON (or a spreadsheet exported to it); code never hard-codes
## a hero, item, monster or number. Each table is an array of rows with a unique
## "id". Rows keep the file's order, which matters for deterministic iteration.
##
## Pure data: no autoload or scene access, so headless tools and tests can build
## their own instance with ContentDB.load_from().

const TABLES: PackedStringArray = [
	"classes", "traits", "items", "mods", "materials", "monsters", "floors", "achievements",
]

var tables: Dictionary = {}      # table name -> {id: row}
var balance: Dictionary = {}
var names: Dictionary = {}
var errors: PackedStringArray = []
var _floors_by_index: Dictionary = {}


static func load_from(dir: String = "res://data") -> ContentDB:
	var db := ContentDB.new()
	db._load(dir)
	return db


func is_valid() -> bool:
	return errors.is_empty()


func get_row(table: String, id: String) -> Dictionary:
	var t: Dictionary = tables.get(table, {})
	return t.get(id, {})


func has_row(table: String, id: String) -> bool:
	return tables.get(table, {}).has(id)


func rows(table: String) -> Array:
	return tables.get(table, {}).values()


func ids(table: String) -> Array:
	return tables.get(table, {}).keys()


func floor_by_index(index: int) -> Dictionary:
	return _floors_by_index.get(index, {})


func floor_count() -> int:
	return _floors_by_index.size()


func bal(path: String, default: Variant = null) -> Variant:
	## Reads a balance value by dotted path, e.g. bal("combat.crit_mult").
	var node: Variant = balance
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default
	return node


# --- loading -----------------------------------------------------------------

func _load(dir: String) -> void:
	for t in TABLES:
		var by_id := {}
		var data: Variant = _read_json("%s/%s.json" % [dir, t])
		if data is Array:
			for row in data:
				if not (row is Dictionary) or not row.has("id"):
					errors.append("%s: row without an id: %s" % [t, str(row)])
					continue
				var id := str(row["id"])
				if by_id.has(id):
					errors.append("%s: duplicate id '%s'" % [t, id])
				by_id[id] = row
		elif data != null:
			errors.append("%s.json must be an array of rows" % t)
		tables[t] = by_id
	var b: Variant = _read_json(dir + "/balance.json")
	balance = b if b is Dictionary else {}
	var n: Variant = _read_json(dir + "/names.json")
	names = n if n is Dictionary else {}
	for f in rows("floors"):
		_floors_by_index[int(f.get("index", 0))] = f
	_validate()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing data file: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


# --- validation: catch typos in data before they become weird bugs -----------

func _validate() -> void:
	var elements: Array = bal("elements", [])
	for c in rows("classes"):
		_need(c, ["name", "sprite", "role", "weapons", "hp", "might", "guard", "nerve", "luck", "haste"], "classes")
	for it in rows("items"):
		_need(it, ["name", "slot", "tier", "stats", "sockets", "value"], "items")
		if not ["weapon", "armor", "charm", "pack"].has(it.get("slot")):
			errors.append("items.%s: bad slot '%s'" % [it.id, it.get("slot")])
		if it.get("slot") == "weapon" and not it.has("kind"):
			errors.append("items.%s: weapons need a 'kind'" % it.id)
	for t in rows("traits"):
		if not ["common", "uncommon", "rare"].has(t.get("rarity", "")):
			errors.append("traits.%s: rarity must be common, uncommon or rare" % t.id)
	for m in rows("mods"):
		_need(m, ["name", "kind", "value", "cost"], "mods")
		if m.get("kind") == "element" and not elements.has(m.get("element")):
			errors.append("mods.%s: unknown element '%s'" % [m.id, m.get("element")])
		for mat in m.get("cost", {}):
			if not has_row("materials", mat):
				errors.append("mods.%s: cost uses unknown material '%s'" % [m.id, mat])
	for mo in rows("monsters"):
		_need(mo, ["name", "sprite", "hp", "might", "guard", "haste", "xp"], "monsters")
		for key in ["weak", "resist"]:
			if mo.has(key) and not elements.has(mo[key]):
				errors.append("monsters.%s: unknown %s element '%s'" % [mo.id, key, mo[key]])
		for d in mo.get("drops", []):
			if not has_row("materials", d.get("material", "")):
				errors.append("monsters.%s: drops unknown material '%s'" % [mo.id, d.get("material")])
	for f in rows("floors"):
		_need(f, ["index", "name", "monster_scale", "group_size", "gold", "monsters"], "floors")
		for mid in f.get("monsters", {}):
			if not has_row("monsters", mid):
				errors.append("floors.%s: unknown monster '%s'" % [f.id, mid])
	for item_id in bal("start_inventory", []):
		if not has_row("items", item_id):
			errors.append("balance.start_inventory: unknown item '%s'" % item_id)
	var boss_id: String = bal("boss.monster", "")
	if boss_id != "" and not has_row("monsters", boss_id):
		errors.append("balance.boss.monster: unknown monster '%s'" % boss_id)
	for i in range(1, floor_count() + 1):
		if not _floors_by_index.has(i):
			errors.append("floors: indexes must run 1..N without gaps (missing %d)" % i)


func _need(row: Dictionary, keys: Array, table: String) -> void:
	for k in keys:
		if not row.has(k):
			errors.append("%s.%s: missing '%s'" % [table, row.get("id", "?"), k])
