extends RefCounted
## Szenentests: Hauptmenü und Spielwelt laufen tatsächlich (headless), Spielfluss wird simuliert.


func _frames(t, n: int) -> void:
	for i in n:
		await t.physics_frame


func test_main_menu(t) -> void:
	var menu: Node = load("res://scenes/main/main_menu.tscn").instantiate()
	t.root.add_child(menu)
	await _frames(t, 5)
	var buttons := menu.find_children("*", "Button", true, false)
	var texts := buttons.map(func(b): return b.text)
	t.check(texts.has("Neue Welt"), "Button Neue Welt vorhanden")
	t.check(texts.has("Beenden"), "Button Beenden vorhanden")
	var disabled := buttons.filter(func(b): return b.disabled)
	for b in disabled:
		t.check(String(b.text).contains("Phase"), "deaktivierter Button ist gekennzeichnet: " + b.text)
	t.eq(menu.parse_seed("123"), 123, "Zahl als Seed")
	t.eq(menu.parse_seed("Wald"), menu.parse_seed("Wald"), "Text-Seed reproduzierbar")
	menu.queue_free()
	await _frames(t, 2)


func test_world_gameplay(t) -> void:
	Session.local_player_name = "Testspieler"
	Session.start_new_world("Szenentest", 31337)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	t.root.add_child(world)
	await _frames(t, 40)
	var state: GameState = Session.state
	var player: PlayerCharacter = world.player
	t.check(player != null, "Spieler erzeugt")
	var ground := state.map.height_at(player.global_position.x, player.global_position.z)
	t.check(absf(player.global_position.y - ground) < 0.6, "Spieler steht auf dem Gelände (%.2f vs %.2f)" % [player.global_position.y, ground])
	t.eq(world.node_views.size(), state.nodes.size(), "alle Rohstoffe dargestellt")
	t.eq(world.building_views.size(), 1, "Zentrales Lager dargestellt")

	# Laufen mit WASD
	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(t, 30)
	Input.action_release("move_forward")
	t.check(player.global_position.distance_to(start) > 1.5, "Spieler bewegt sich (%.2f m)" % player.global_position.distance_to(start))
	t.check(state.players[1].pos.distance_to(player.global_position) < 0.01, "Position an den Zustand gemeldet")

	# Kamera folgt und lässt sich zoomen
	var cam: CameraRig = world.cam_rig
	var d0 := cam.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	for i in 5:
		cam.handle_input(wheel)
	await _frames(t, 30)
	t.check(cam.distance > d0 + 5.0, "Herauszoomen (%.1f -> %.1f)" % [d0, cam.distance])
	t.check(cam.camera.global_position.y > state.map.height_at(cam.camera.global_position.x, cam.camera.global_position.z) + 2.0, "Kamera über dem Gelände")

	# Baum fällen: zum nächsten Baum laufen lassen
	var best := -1
	var best_d := INF
	for n in state.nodes.values():
		if n.type == "tree":
			var d := state.node_position(n).distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = n.id
	var tree_pos := state.node_position(state.nodes[best])
	player.global_position = tree_pos + (player.global_position - tree_pos).normalized() * 2.5 + Vector3(0, 0.5, 0)
	await _frames(t, 10)
	var wood := state.economy.amount("wood")
	player.set_gather_target(best)
	await _frames(t, 140)
	t.check(state.economy.amount("wood") > wood, "Holz durch Fällen erhalten (%d -> %d)" % [wood, state.economy.amount("wood")])

	# Bauen über den Platzierungsmodus
	state.economy.stock["wood"] = 200
	state.economy.stock["stone"] = 100
	var spot := Vector2i(-1, -1)
	for r in range(3, 10):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var c := state.map.start_cell + Vector2i(x, y)
				if spot.x < 0 and BuildingSystem.check(state, "storage", c, 1).ok:
					spot = c
	var build: BuildController = world.build
	world._on_building_chosen("storage")
	t.check(build.is_active(), "Platzierungsmodus aktiv")
	build.rotate_ghost()
	build.cell = spot
	build._try_place()
	await _frames(t, 2)
	var new_id := -1
	for b in state.buildings.values():
		if b.def == "storage":
			new_id = b.id
	t.check(new_id > 0, "Lager platziert")
	t.check(world.building_views.has(new_id), "Lager dargestellt")
	t.eq(state.buildings[new_id].rot, 1, "Drehung übernommen")
	build.cancel()
	t.check(not build.is_active(), "Platzierungsmodus beendet")

	# Auswahl und Infofenster
	world._select(new_id)
	await _frames(t, 2)
	t.check(world.hud.building_panel.visible, "Infofenster offen")
	t.check(world.hud.building_panel._title.text == "Ressourcenlager", "Titel stimmt")
	for i in 60 * 13:
		state.tick(1.0 / 60.0)
	Session._flush()
	await _frames(t, 2)
	t.eq(state.buildings[new_id].phase, "active", "Lager fertig")
	t.check(world.building_views[new_id].scaffold == null, "Gerüst entfernt")
	world.hud.building_panel._on_remove()
	await _frames(t, 2)
	t.check(not state.buildings.has(new_id), "über das Infofenster abgerissen")
	t.check(not world.building_views.has(new_id), "Darstellung entfernt")

	# Fenster
	world.hud.toggle_build_menu()
	await _frames(t, 2)
	t.check(world.hud.build_menu.visible, "Baumenü offen")
	var cards: Array = world.hud.build_menu.find_children("*", "Button", true, false)
	t.check(cards.size() >= 4, "Baumenü zeigt Karten (%d)" % cards.size())
	world.hud.toggle_inventory()
	world.hud.toggle_map()
	await _frames(t, 2)
	t.check(world.hud.map_overlay.visible and not world.hud.inventory.visible, "Karte ersetzt Lagerfenster")

	# Pause hält die Weltzeit an
	world.hud.set_paused(true)
	var hour := state.clock.hour
	await _frames(t, 20)
	t.eq(state.clock.hour, hour, "Weltzeit steht in der Pause")
	world.hud.set_paused(false)
	await _frames(t, 5)
	t.check(state.clock.hour > hour, "Weltzeit läuft weiter")

	# Nacht wird dunkel
	state.clock.hour = 23.0
	await _frames(t, 3)
	t.check(world.day_night.night_factor > 0.8, "Nachtbeleuchtung aktiv (%.2f)" % world.day_night.night_factor)
	t.check(player.lantern.light_energy > 1.0, "Laterne leuchtet nachts")

	world.queue_free()
	Session.close_world()
	await _frames(t, 3)
