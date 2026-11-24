extends Node
## Saves screenshots of the dev scenes to build/ (needs a display; on a server
## use xvfb-run). Handy for devlogs and for checking pixel scale.
##   godot --path . res://tools/capture.tscn


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://build")
	var sandbox: Node = load("res://scenes/dev/sim_sandbox.tscn").instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	sandbox._floor_spin.value = 2
	sandbox._element_opt.select(3)
	sandbox._refresh_hero()
	sandbox._estimate()
	sandbox._delve()
	for wait in [1.3, 1.6, 2.2]:
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		var path := "res://build/sandbox_%d.png" % roundi(wait * 10)
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()
