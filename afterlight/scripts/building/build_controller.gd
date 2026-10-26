class_name BuildController
extends Node3D
## Platzierungsmodus: Vorschau am Mauszeiger, Rastereinrasten, Drehen, Gültigkeitsprüfung.
## Die Prüfung nutzt dieselbe Regel wie der Host (BuildingSystem.check); gebaut wird per Aktion.

signal mode_changed(active: bool)
signal placed(def_id: String)
signal feedback(text: String, ok: bool)

var cam_rig: CameraRig
var def_id: String = ""
var rot: int = 0
var cell := Vector2i(-999, -999)
var valid := false
var reason := ""
var _ghost: Node3D
var _footprint: MeshInstance3D
var _range_ring: MeshInstance3D
var _ghost_meshes: Array = []
var _recheck := 0.0


func is_active() -> bool:
	return def_id != ""


func begin(id: String) -> void:
	cancel(false)
	def_id = id
	rot = 0
	cell = Vector2i(-999, -999)
	var def: Dictionary = GameData.building(id)
	_ghost = Node3D.new()
	_ghost.add_child(ModelFactory.building(def.model))
	add_child(_ghost)
	_ghost_meshes = ModelFactory.meshes_of(_ghost)
	for m in _ghost_meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_footprint = MeshInstance3D.new()
	var fp: Vector2i = def.footprint
	_footprint.mesh = ModelFactory.box(Vector3(fp.x * 2.0, 0.08, fp.y * 2.0))
	_ghost.add_child(_footprint)
	var prod = def.production
	if prod != null and prod.get("type") == "harvest":
		var r: float = float(prod.radius)
		_range_ring = MeshInstance3D.new()
		_range_ring.mesh = ModelFactory.torus(r - 0.12, r)
		_range_ring.material_override = Palette.mat("accent")
		_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(_range_ring)
	mode_changed.emit(true)


func cancel(emit := true) -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_range_ring = null
	def_id = ""
	if emit:
		mode_changed.emit(false)


func rotate_ghost() -> void:
	rot = (rot + 1) % 4
	cell = Vector2i(-999, -999)


func _process(delta: float) -> void:
	if not is_active() or Session.state == null:
		return
	var state := Session.state
	var hit := cam_rig.mouse_ray(get_viewport().get_mouse_position(), TerrainBuilder.LAYER_TERRAIN)
	if hit.is_empty():
		_ghost.visible = false
		return
	_ghost.visible = true
	var def: Dictionary = GameData.building(def_id)
	var fp := BuildingSystem.footprint(def, rot)
	var cs := state.map.cell_size
	var p: Vector3 = hit.position
	var new_cell := Vector2i(roundi(p.x / cs - fp.x * 0.5), roundi(p.z / cs - fp.y * 0.5))
	_recheck -= delta
	if new_cell != cell or _recheck <= 0.0:
		cell = new_cell
		_recheck = 0.25
		var res := BuildingSystem.check(state, def_id, cell, rot)
		valid = res.ok
		reason = res.reason
		var hr := state.map.height_range(BuildingSystem.cells_for(def, cell, rot))
		_ghost.position = Vector3((cell.x + fp.x * 0.5) * cs, hr.y, (cell.y + fp.y * 0.5) * cs)
		_ghost.rotation.y = -rot * PI * 0.5
		var m := Palette.ghost(valid)
		for mi in _ghost_meshes:
			mi.material_override = m
		_footprint.material_override = m
		var info := reason
		if valid:
			info = "Linksklick: bauen · R: drehen · Rechtsklick: abbrechen"
			var prod = def.production
			if prod != null and prod.get("type") == "harvest":
				var n := _count_sources(state, def, prod)
				info = "%d %s in Reichweite · %s" % [n, "Quellen" if n != 1 else "Quelle", info]
		feedback.emit(info, valid)


func _count_sources(state: GameState, def: Dictionary, prod: Dictionary) -> int:
	var fake := {"def": def.id, "cell": cell, "rot": rot}
	var center := state.building_center(fake)
	var n := 0
	for node in state.nodes.values():
		if prod.node_types.has(node.type) and state.node_position(node).distance_to(center) <= float(prod.radius):
			n += 1
	return n


## Rückgabe true, wenn das Ereignis verarbeitet wurde
func handle_input(event: InputEvent) -> bool:
	if not is_active():
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	if event.is_action_pressed("build_rotate"):
		rotate_ghost()
		return true
	return false


func _try_place() -> void:
	if cell.x < -100:
		return
	var r := Session.submit({"type": "build", "def": def_id, "cell": [cell.x, cell.y], "rot": rot})
	if r.ok:
		placed.emit(def_id)
		cell = Vector2i(-999, -999)  # neu prüfen (Kosten, Belegung)
	else:
		feedback.emit(String(r.reason), false)
