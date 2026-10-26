extends Node3D
## Spielwelt-Szene. Baut die Darstellung aus dem GameState auf und hält sie über
## Session-Ereignisse aktuell. Enthält keine Spielregeln.

const MAIN_MENU := "res://scenes/main/main_menu.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Vorschau-Modus (Hauptmenü-Hintergrund): eigene Welt, kein Spieler, keine HUD
var preview_state: GameState = null

var state: GameState
var day_night: DayNight
var hud: Hud
var player: PlayerCharacter
var cam_rig: CameraRig
var build: BuildController
var node_views := {}
var building_views := {}
var gates: Array = []
var selected := -1
var map_colors: PackedColorArray
var _hover_timer := 0.0
var _occl_timer := 0.0
var _faded: Array = []
var _last_night := -1.0
var _orbit := 0.0


func is_preview() -> bool:
	return preview_state != null


func _ready() -> void:
	if is_preview():
		state = preview_state
	else:
		if Session.state == null:
			# Szene direkt gestartet (z. B. im Editor mit F6): Schnellstart-Welt anlegen
			Session.start_new_world("Schnellstart", randi() % 1000000)
		state = Session.state
	var t0 := Time.get_ticks_msec()
	day_night = DayNight.new()
	add_child(day_night)
	day_night.build(self)
	map_colors = TerrainBuilder.vertex_colors(state.map)
	add_child(TerrainBuilder.build(state.map, map_colors))
	add_child(TerrainBuilder.build_vegetation(state.map, map_colors, state.occupancy))
	_build_ruins()
	for n in state.nodes.values():
		_add_node_view(n)
	for b in state.buildings.values():
		_add_building_view(b)
	print("Welt aufgebaut in %d ms (%d Knoten, %d Gebäude)" % [Time.get_ticks_msec() - t0, node_views.size(), building_views.size()])
	if is_preview():
		cam_rig = CameraRig.new()
		cam_rig.map = state.map
		cam_rig.input_enabled = false
		cam_rig.focus = state.map.center()
		cam_rig.focus = state.map.center() + Vector3(10, 0, -6)
		cam_rig.distance = 46.0
		cam_rig.set("_target_distance", 46.0)
		add_child(cam_rig)
		return
	_spawn_player()
	build = BuildController.new()
	build.cam_rig = cam_rig
	add_child(build)
	hud = Hud.new()
	add_child(hud)
	hud.map_overlay.set_image(TerrainBuilder.map_image(state.map, map_colors))
	hud.building_chosen.connect(_on_building_chosen)
	hud.main_menu_requested.connect(_to_main_menu)
	hud.building_panel.closed.connect(_deselect)
	build.feedback.connect(func(text, ok): hud.set_build_hint(text, ok))
	build.mode_changed.connect(func(active): if not active: hud.set_build_hint("", true))
	build.placed.connect(func(_id): hud.build_menu.refresh())
	Session.state_event.connect(_on_event)
	hud.toast("Willkommen in %s. Sammle Holz und Stein und baue deine Siedlung aus (B)." % state.world_name, "info")


func _spawn_player() -> void:
	var p: Dictionary = state.players[Session.local_player_id]
	player = PLAYER_SCENE.instantiate()
	player.player_id = Session.local_player_id
	player.color = Color("#3f6f8f")
	var pos: Vector3 = p.pos
	player.position = Vector3(pos.x, state.map.height_at(pos.x, pos.z) + 0.3, pos.z)
	add_child(player)
	cam_rig = CameraRig.new()
	cam_rig.target = player
	cam_rig.map = state.map
	cam_rig.bounds = Rect2(4, 4, state.map.size_m() - 8, state.map.size_m() - 8)
	add_child(cam_rig)
	player.cam_rig = cam_rig
	player.message.connect(func(text, kind): hud.toast(text, kind))
	player.gathered.connect(_on_gathered)


func _build_ruins() -> void:
	var root := Node3D.new()
	root.name = "Ruins"
	add_child(root)
	var cs := state.map.cell_size
	var i := 0
	for r in state.map.ruins:
		i += 1
		var size := Vector2(r.size) * cs
		var cells: Array = []
		for y in r.size.y:
			for x in r.size.x:
				cells.append(r.cell + Vector2i(x, y))
		var hr := state.map.height_range(cells)
		var node := ModelFactory.ruin(int(r.kind), size, state.seed + i * 17)
		node.position = Vector3(r.cell.x * cs + size.x * 0.5, hr.x, r.cell.y * cs + size.y * 0.5)
		root.add_child(node)
		var body := StaticBody3D.new()
		body.collision_layer = BuildingView.LAYER_SOLID
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x * 0.95, 3.0, size.y * 0.95)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(0, 1.5, 0)
		body.add_child(col)
		node.add_child(body)


func _add_node_view(n: Dictionary) -> void:
	var v := NodeView.new()
	add_child(v)
	v.setup(state, n)
	node_views[n.id] = v


func _add_building_view(b: Dictionary) -> void:
	var v := BuildingView.new()
	add_child(v)
	v.setup(state, b)
	building_views[b.id] = v
	if v.def.passable_for_players:
		gates.append(v)
	_last_night = -1.0


# ---------------------------------------------------------------- Ereignisse aus dem Spielzustand

func _on_event(ev: Dictionary) -> void:
	match String(ev.type):
		"building_added":
			_add_building_view(state.buildings[ev.id])
		"building_changed":
			if building_views.has(ev.id) and state.buildings.has(ev.id):
				building_views[ev.id].refresh(state.buildings[ev.id])
			if ev.id == selected:
				hud.building_panel.refresh()
			if ev.get("completed", false):
				hud.build_menu.refresh()
		"building_removed":
			if building_views.has(ev.id):
				var v: BuildingView = building_views[ev.id]
				Fx.burst(self, v.global_position + Vector3(0, 1, 0), Color(0.6, 0.55, 0.5), 30, 0.5)
				gates.erase(v)
				_faded.erase(v)
				v.queue_free()
				building_views.erase(ev.id)
			if ev.id == selected:
				_deselect()
			hud.build_menu.refresh()
		"node_changed":
			if node_views.has(ev.id) and state.nodes.has(ev.id):
				node_views[ev.id].refresh(state.nodes[ev.id])
		"node_removed":
			if node_views.has(ev.id):
				var nv: NodeView = node_views[ev.id]
				_faded.erase(nv)
				nv.remove_animated()
				node_views.erase(ev.id)
		"stock_changed":
			hud.refresh_resources()
		"notify":
			hud.toast(String(ev.text), String(ev.kind))
		"produced":
			_show_production(ev)
		"night_started":
			hud.banner("NACHT %d" % ev.day, UiTheme.INFO)
		"day_started":
			hud.banner("TAG %d" % ev.day, UiTheme.ACCENT)


func _show_production(ev: Dictionary) -> void:
	if not building_views.has(ev.building):
		return
	var v: BuildingView = building_views[ev.building]
	if v.global_position.distance_to(cam_rig.focus) > 45.0:
		return
	var parts: PackedStringArray = []
	if ev.has("resource"):
		parts.append("+%d %s" % [ev.amount, GameData.resource_name(ev.resource)])
	for rid in ev.get("resources", {}):
		parts.append("+%d %s" % [ev.resources[rid], GameData.resource_name(rid)])
	Fx.float_text(self, v.global_position + Vector3(0, 3.6, 0), " ".join(parts), UiTheme.SUCCESS)


func _on_gathered(node_id: int, r: Dictionary) -> void:
	var pos: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	if node_views.has(node_id):
		var nv: NodeView = node_views[node_id]
		pos = nv.global_position + Vector3(0, 1.6, 0)
		nv.hit()
		var col := Color(0.62, 0.45, 0.28) if nv.type == "tree" else Color(0.6, 0.6, 0.6)
		Fx.burst(self, nv.global_position + Vector3(0, 1.0, 0), col, 10, 0.18)
	var parts: PackedStringArray = []
	for rid in r.get("gained", {}):
		parts.append("+%d %s" % [r.gained[rid], GameData.resource_name(rid)])
	if parts.size() > 0:
		Fx.float_text(self, pos, " ".join(parts), Color("#ffe39a"))


# ---------------------------------------------------------------- Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if is_preview() or hud.is_paused():
		return
	if cam_rig.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if build.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if build.is_active():
			build.cancel()
		else:
			hud.close_top_or_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu"):
		hud.toggle_build_menu()
		if not hud.build_menu.visible and build.is_active():
			build.cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		hud.toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		hud.toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_interact_nearest()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
		get_viewport().set_input_as_handled()


func _click(screen_pos: Vector2) -> void:
	var hit := cam_rig.mouse_ray(screen_pos, BuildingView.LAYER_PICK)
	if hit.is_empty():
		_deselect()
		return
	var col: Object = hit.collider
	match String(col.get_meta("kind", "")):
		"node":
			player.set_gather_target(int(col.get_meta("id")))
		"building":
			_select(int(col.get_meta("id")))


func _interact_nearest() -> void:
	var best := -1
	var best_d := 4.5
	for n in state.nodes.values():
		var d := state.node_position(n).distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n.id
	if best >= 0:
		player.set_gather_target(best)
	else:
		hud.toast("Nichts zum Sammeln in der Nähe", "info")


func _select(id: int) -> void:
	_deselect()
	selected = id
	if building_views.has(id):
		building_views[id].set_selected(true)
	hud.building_panel.show_building(id)


func _deselect() -> void:
	if selected >= 0 and building_views.has(selected):
		building_views[selected].set_selected(false)
	selected = -1
	if hud != null:
		hud.building_panel.visible = false


func _on_building_chosen(def_id: String) -> void:
	_deselect()
	build.begin(def_id)


func _to_main_menu() -> void:
	get_tree().paused = false
	Session.close_world()
	get_tree().change_scene_to_file(MAIN_MENU)


# ---------------------------------------------------------------- Laufende Aktualisierung

func _process(delta: float) -> void:
	var c := state.clock
	if is_preview():
		_orbit += delta * 0.04
		cam_rig.yaw = _orbit
		day_night.update(17.2, c.day_start, c.night_start)
		return
	day_night.update(c.hour, c.day_start, c.night_start)
	var nf := day_night.night_factor
	if absf(nf - _last_night) > 0.01:
		_last_night = nf
		player.set_night(nf)
		for v in building_views.values():
			v.set_night(nf)
	for g in gates:
		g.update_gate(player.global_position, delta)
	_hover_timer -= delta
	if _hover_timer <= 0.0:
		_hover_timer = 0.08
		_update_hover()
	_occl_timer -= delta
	if _occl_timer <= 0.0:
		_occl_timer = 0.15
		_update_occlusion()


func _update_hover() -> void:
	if build.is_active() or hud.is_paused():
		hud.set_hover("")
		return
	var mp := get_viewport().get_mouse_position()
	var hit := cam_rig.mouse_ray(mp, BuildingView.LAYER_PICK)
	if hit.is_empty():
		hud.set_hover("")
		return
	var col: Object = hit.collider
	var id := int(col.get_meta("id", -1))
	match String(col.get_meta("kind", "")):
		"node":
			if state.nodes.has(id):
				var n: Dictionary = state.nodes[id]
				var nt: Dictionary = GameData.node_type(n.type)
				if nt.resource == "loot":
					hud.set_hover("%s\nKlick: öffnen" % nt.name)
				else:
					hud.set_hover("%s · %d %s\nKlick: sammeln" % [nt.name, n.amount, GameData.resource_name(nt.resource)])
		"building":
			if state.buildings.has(id):
				var b: Dictionary = state.buildings[id]
				hud.set_hover("%s\nKlick: Details" % GameData.building(b.def).name)
		_:
			hud.set_hover("")


## Objekte zwischen Kamera und Spieler durchsichtig machen
func _update_occlusion() -> void:
	var from := cam_rig.camera.global_position
	var to := player.global_position + Vector3(0, 1.2, 0)
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var now: Array = []
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from, to, BuildingView.LAYER_SOLID | BuildingView.LAYER_PICK, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		exclude.append(hit.rid)
		var view = hit.collider.get_meta("view", null)
		if view != null and is_instance_valid(view):
			now.append(view)
	for v in _faded:
		if is_instance_valid(v) and not now.has(v):
			v.set_faded(false)
	for v in now:
		v.set_faded(true)
	_faded = now
