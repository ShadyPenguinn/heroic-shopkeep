extends Node
## Screenshots of the shop screens to build/shop_*.png (needs a display; use xvfb-run).
##   godot --path . res://tools/capture_shop.tscn


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://build")
	Game.new_game(77)
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await _wait(0.4)
	await _snap("shop_1_day1")
	await _wait(3.2)
	# Hold a sword and hand it to the first walk-in.
	var sword := ""
	for g in Game.state.inventory:
		if g.def == "iron_sword":
			sword = g.uid
	shop._pick_up(sword)
	await _wait(0.3)
	await _snap("shop_2_holding")
	shop._auto_outfit()
	await _wait(1.0)
	await _snap("shop_3_outfitted")
	shop.playback.speed = 2.0
	shop._send()
	await _wait(4.0)
	await _snap("shop_4_delve")
	shop.playback.skip()
	await _wait(2.0)
	await _snap("shop_5_dusk")
	# Jump to merchant day.
	shop.auto_bot.pick_cards(Game.db, Game.state)
	shop._close_day()
	shop._close_overlay(false)
	Game.state.day = 3
	Game.state.phase = GameState.Phase.DUSK
	Game.state.results = []
	shop._close_day()
	await _wait(3.5)
	shop._open_merchant()
	await _wait(0.4)
	await _snap("shop_6_merchant")
	Game.state.mod_stock["holy_rune"] = 1
	Game.state.materials["bone_dust"] = 4
	shop._bench_mod = "holy_rune"
	shop._open_workbench()
	await _wait(0.4)
	await _snap("shop_7_workbench")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/%s.png" % name)
	print("saved ", name)
