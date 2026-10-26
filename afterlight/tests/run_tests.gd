extends SceneTree
## Testläufer: godot --headless --path . -s res://tests/run_tests.gd
## Führt alle tests/test_*.gd aus. Jede Testdatei hat Funktionen test_*(t).
## Exit-Code 0 = alles bestanden.

var failures := 0
var passed := 0
var current := ""


func _initialize() -> void:
	# Autoloads sind bei -s erst im ersten Frame verfügbar
	await process_frame
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var only := OS.get_environment("TEST_ONLY")
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			current = f
			check(false, "Testdatei lässt sich nicht laden (Parse-Fehler?)")
			continue
		var inst = script.new()
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not name.contains(only):
				continue
			current = "%s::%s" % [f, name]
			var before := failures
			await inst.call(name, self)
			if failures == before:
				passed += 1
				print("  ok   ", current)
		if inst is Node:
			inst.queue_free()
	print("\n%d bestanden, %d fehlgeschlagen" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures += 1
		printerr("  FAIL ", current, ": ", msg)
	return cond


func eq(a, b, msg: String) -> bool:
	return check(a == b, "%s (erwartet %s, erhalten %s)" % [msg, str(b), str(a)])
