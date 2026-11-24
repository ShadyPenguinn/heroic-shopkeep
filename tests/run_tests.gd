extends SceneTree
## Headless test runner. No addons needed.
##   godot --headless --path . -s res://tests/run_tests.gd
## Runs every test_*() method in tests/test_*.gd. Exit code 0 = all passed.


func _initialize() -> void:
	var failed := 0
	var passed := 0
	var dir := DirAccess.open("res://tests")
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: Object = script.new()
		for m in suite.get_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			var t := TestContext.new()
			var t0 := Time.get_ticks_msec()
			suite.call(mname, t)
			var ms := Time.get_ticks_msec() - t0
			if t.failures.is_empty():
				passed += 1
				print("  PASS  %s.%s (%d ms)" % [f.get_basename(), mname, ms])
			else:
				failed += 1
				print("  FAIL  %s.%s" % [f.get_basename(), mname])
				for msg in t.failures:
					print("        - " + msg)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
