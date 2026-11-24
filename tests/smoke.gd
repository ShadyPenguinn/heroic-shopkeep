extends Node
## Scene smoke test with the real autoloads: boots each scene, plays a delve
## at high speed, drives the placeholder shop through two full days.
##   godot --headless --path . res://tests/smoke.tscn
## Exit code 0 = everything ran. Watch the output for SCRIPT ERROR lines.


func _ready() -> void:
	var ok := true
	print("[smoke] sandbox")
	var sandbox: Node = load("res://scenes/dev/sim_sandbox.tscn").instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	sandbox.playback.speed = 20.0
	await sandbox._delve()
	sandbox._estimate()
	print("[smoke]   ", sandbox._estimate_label.text.replace("\n", " "))
	sandbox.queue_free()

	print("[smoke] title")
	var title: Node = load("res://scenes/title/title.tscn").instantiate()
	add_child(title)
	await get_tree().create_timer(0.2).timeout
	title.queue_free()

	print("[smoke] shop, two days")
	Game.new_game(1234)
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop.playback.speed = 20.0
	var steps := 0
	while Game.state.day <= 2 and not Game.state.is_over() and steps < 20:
		await shop._on_advance()
		steps += 1
	print("[smoke]   reached day %d, gold %d, phase %s" % [Game.state.day, Game.state.gold, GameState.Phase.keys()[Game.state.phase]])
	ok = ok and Game.state.day >= 2
	print("[smoke]   save exists: ", Game.has_save())
	ok = ok and Game.has_save()
	shop.queue_free()
	print("[smoke] %s" % ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
