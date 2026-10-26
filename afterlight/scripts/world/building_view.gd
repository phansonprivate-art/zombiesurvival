class_name BuildingView
extends Node3D
## Darstellung eines Gebäudes. Liest nur den Zustand – verändert ihn nie.

const LAYER_SOLID := 2
const LAYER_PICK := 4
const LAYER_ENEMY_ONLY := 8

var id: int = 0
var def: Dictionary
var size_m := Vector2.ONE
var model: Node3D
var scaffold: Node3D
var status_label: Label3D
var outline: Node3D
var smoke: CPUParticles3D
var light: OmniLight3D
var _meshes: Array = []
var _faded := false
var _gate_open := 0.0
var _phase := ""


func setup(state: GameState, b: Dictionary) -> void:
	id = b.id
	name = "Building_%d" % id
	def = state.data.building(b.def)
	var cs := state.map.cell_size
	var fp := BuildingSystem.footprint(def, b.rot)
	size_m = Vector2(def.footprint) * cs
	var cells := BuildingSystem.cells_for(def, b.cell, b.rot)
	var hr := state.map.height_range(cells)
	position = Vector3((b.cell.x + fp.x * 0.5) * cs, hr.y, (b.cell.y + fp.y * 0.5) * cs)
	rotation.y = -b.rot * PI * 0.5
	# Fundament gleicht Gefälle aus
	var depth := hr.y - hr.x + 0.6
	ModelFactory.part(self, ModelFactory.box(Vector3(size_m.x - 0.15, depth, size_m.y - 0.15)), "stone_dark", Vector3(0, -depth * 0.5 + 0.04, 0))
	model = ModelFactory.building(def.model)
	add_child(model)
	_add_collision()
	_add_extras()
	status_label = Label3D.new()
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.font_size = 40
	status_label.pixel_size = 0.01
	status_label.outline_size = 10
	status_label.outline_modulate = Color(0, 0, 0, 0.8)
	status_label.no_depth_test = true
	status_label.position = Vector3(0, 4.2, 0)
	add_child(status_label)
	_meshes = ModelFactory.meshes_of(self)
	refresh(b)


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.set_meta("kind", "building")
	body.set_meta("id", id)
	body.set_meta("view", self)
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_m.x * 0.94, 3.0, size_m.y * 0.94)
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	body.add_child(cs)
	add_child(body)
	if def.passable_for_players:
		# Torflügel: nur für Gegner fest. Pfosten blockieren alle.
		body.collision_layer = LAYER_PICK | LAYER_ENEMY_ONLY
		var posts := StaticBody3D.new()
		posts.collision_layer = LAYER_SOLID
		posts.collision_mask = 0
		for x in [-1.85, 1.85]:
			var pc := CollisionShape3D.new()
			var ps := BoxShape3D.new()
			ps.size = Vector3(0.45, 3.0, 0.65)
			pc.shape = ps
			pc.position = Vector3(x, 1.5, 0)
			posts.add_child(pc)
		add_child(posts)
	else:
		body.collision_layer = LAYER_SOLID | LAYER_PICK


func _add_extras() -> void:
	match def.model:
		"hq":
			smoke = Fx.smoke()
			smoke.position = Vector3(1.4, 4.8, -1.4)
			add_child(smoke)
			light = OmniLight3D.new()
			light.light_color = Color("#ffb066")
			light.omni_range = 9.0
			light.position = Vector3(0.75, 2.4, 2.1)
			light.shadow_enabled = true
			add_child(light)
		"smelter":
			smoke = Fx.smoke()
			smoke.position = Vector3(-0.3, 4.9, -0.3)
			add_child(smoke)
			light = OmniLight3D.new()
			light.light_color = Color("#ff7a30")
			light.omni_range = 6.0
			light.position = Vector3(-0.3, 0.9, 1.3)
			add_child(light)
		"workshop":
			smoke = Fx.smoke()
			smoke.position = Vector3(1.3, 5.2, -1.0)
			add_child(smoke)
			light = OmniLight3D.new()
			light.light_color = Color("#ffc27a")
			light.omni_range = 6.0
			light.position = Vector3(2.4, 2.2, -0.3)
			add_child(light)


func refresh(b: Dictionary) -> void:
	var building: bool = b.phase == "construction"
	if building:
		var p: float = b.progress
		model.scale = Vector3(1.0, lerpf(0.15, 1.0, p), 1.0)
		if scaffold == null:
			scaffold = ModelFactory.scaffold(size_m * 0.98, 3.2)
			add_child(scaffold)
		status_label.text = "Im Bau %d %%" % int(p * 100.0)
		status_label.modulate = UiTheme.ACCENT
		status_label.visible = true
	else:
		model.scale = Vector3.ONE
		if scaffold != null:
			scaffold.queue_free()
			scaffold = null
		var text := ""
		var color := UiTheme.WARNING
		match String(b.status):
			"storage_full":
				text = "Lager voll"
			"no_source":
				text = "Keine Rohstoffe"
			"missing_input":
				text = "Wartet auf Rohstoffe"
		var hp_frac: float = b.hp / float(def.health)
		if hp_frac < 0.999:
			text = ("%s\n" % text if text != "" else "") + "Zustand %d %%" % int(hp_frac * 100.0)
			if hp_frac < 0.35:
				color = UiTheme.DANGER
		status_label.text = text
		status_label.modulate = color
		status_label.visible = text != ""
	var working: bool = not building and (def.production == null or b.status == "working")
	if smoke != null:
		smoke.emitting = working
	if light != null:
		light.visible = not building
	if _phase == "construction" and not building:
		Fx.burst(get_parent(), global_position + Vector3(0, 1.5, 0), Color(0.75, 0.68, 0.55), 24, 0.4)
	_phase = b.phase
	if _meshes.size() > 0:
		_meshes = ModelFactory.meshes_of(self)


func set_selected(on: bool) -> void:
	if on and outline == null:
		outline = Node3D.new()
		var hx := size_m.x * 0.5 + 0.15
		var hz := size_m.y * 0.5 + 0.15
		for e in [[Vector3(0, 0, -hz), Vector3(hx * 2.0, 0.08, 0.08)], [Vector3(0, 0, hz), Vector3(hx * 2.0, 0.08, 0.08)],
				[Vector3(-hx, 0, 0), Vector3(0.08, 0.08, hz * 2.0)], [Vector3(hx, 0, 0), Vector3(0.08, 0.08, hz * 2.0)]]:
			ModelFactory.part(outline, ModelFactory.box(e[1]), "accent", e[0] + Vector3(0, 0.12, 0))
		add_child(outline)
	elif not on and outline != null:
		outline.queue_free()
		outline = null


func set_faded(on: bool) -> void:
	if on == _faded:
		return
	_faded = on
	for m in _meshes:
		if is_instance_valid(m):
			m.transparency = 0.7 if on else 0.0


## Tor öffnet sich, wenn ein Spieler in der Nähe ist
func update_gate(player_pos: Vector3, delta: float) -> void:
	if not def.passable_for_players:
		return
	var near := global_position.distance_to(player_pos) < 4.0
	_gate_open = move_toward(_gate_open, 1.0 if near else 0.0, delta * 2.5)
	var l := model.get_node_or_null("HingeL")
	var r := model.get_node_or_null("HingeR")
	if l and r:
		l.rotation.y = -_gate_open * deg_to_rad(95)
		r.rotation.y = _gate_open * deg_to_rad(95)


func set_night(f: float) -> void:
	if light != null and def.model == "hq":
		light.light_energy = lerpf(0.0, 2.2, f)
