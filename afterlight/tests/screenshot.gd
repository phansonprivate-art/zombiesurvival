extends SceneTree
## Erzeugt Screenshots zur Sichtprüfung (nicht headless ausführen):
## godot --path . -s res://tests/screenshot.gd -- <ausgabeordner>

var out_dir := "user://screenshots"
var session: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	session = root.get_node("Session")
	root.size = Vector2i(1600, 900)
	# Hauptmenü
	var menu: Node = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _settle(40)
	_shot("01_hauptmenue")
	menu.queue_free()
	await _settle(2)

	session.start_new_world("Screenshot", 31337)
	var state: GameState = session.state
	state.economy.stock["wood"] = 300
	state.economy.stock["stone"] = 300
	state.economy.stock["metal"] = 100
	state.economy.stock["components"] = 40
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await _settle(30)
	# eine kleine Basis bauen
	for def_id in ["storage", "lumber", "quarry", "workshop", "mine", "smelter"]:
		_place_near(state, def_id)
	for i in 60 * 20:
		state.tick(1.0 / 60.0)
	session._flush()
	_place_wall_line(state)
	for i in 60 * 7:
		state.tick(1.0 / 60.0)
	session._flush()
	_place_near(state, "storage")
	for i in 60 * 5:
		state.tick(1.0 / 60.0)
	session._flush()
	var cam: CameraRig = world.cam_rig
	state.clock.hour = 10.5
	cam.set("_target_distance", 40.0)
	await _settle(80)
	_shot("02_basis_tag")
	print("  Render-Statistik: %d Draw-Calls, %d Objekte, %d Primitive im Bild" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])

	cam.set("_target_distance", 14.0)
	await _settle(60)
	_shot("03_nah_tag")

	world.hud.toggle_build_menu()
	world._on_building_chosen("lumber")
	cam.set("_target_distance", 30.0)
	Input.warp_mouse(Vector2(1000, 420))
	await _settle(40)
	_shot("04_baumodus")
	world.build.cancel()
	world.hud.toggle_build_menu()

	state.clock.hour = 19.6
	cam.set("_target_distance", 34.0)
	await _settle(40)
	_shot("05_daemmerung")

	state.clock.hour = 23.0
	await _settle(40)
	_shot("06_nacht")

	state.clock.hour = 11.0
	world.hud.toggle_map()
	await _settle(20)
	_shot("07_karte")
	world.hud.toggle_map()
	world.hud.toggle_inventory()
	var hq_id: int = state.buildings.keys()[1]
	await _settle(10)
	_shot("08_lager")
	world.hud.toggle_inventory()
	world._select(hq_id)
	await _settle(10)
	_shot("09_gebaeudeinfo")
	print("Screenshots gespeichert in ", ProjectSettings.globalize_path(out_dir))
	quit()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("  ", name)


func _place_near(state: GameState, def_id: String) -> void:
	var start := state.map.start_cell
	for r in range(2, 12):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if absi(x) != r and absi(y) != r:
					continue
				var c := start + Vector2i(x, y)
				if BuildingSystem.check(state, def_id, c, 0).ok:
					session.submit({"type": "build", "def": def_id, "cell": [c.x, c.y], "rot": 0})
					return


func _place_wall_line(state: GameState) -> void:
	var start := state.map.start_cell + Vector2i(-7, 7)
	for i in 9:
		var c := start + Vector2i(i, 0)
		var def_id := "gate" if i == 4 else ("wall_stone" if i > 4 else "wall_wood")
		if def_id == "gate" or (i == 5):
			pass
		session.submit({"type": "build", "def": def_id, "cell": [c.x, c.y], "rot": 0})
