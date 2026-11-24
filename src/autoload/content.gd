extends Node
## Loads res://data once at startup and exposes it as `Content.db`.
## Headless tools build their own ContentDB instead of using this.

var db: ContentDB


func _ready() -> void:
	db = ContentDB.load_from("res://data")
	for e in db.errors:
		push_error("[data] " + e)
	if not db.is_valid():
		push_error("[data] %d content error(s). Fix data/*.json." % db.errors.size())


func reload() -> void:
	_ready()
