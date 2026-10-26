class_name PlayerCharacter
extends CharacterBody3D
## Lokal gesteuerte Spielfigur. Bewegung ist lokal; alle Spielaktionen (Sammeln)
## gehen als Aktion an die Session, die sie prüft.

signal message(text: String, kind: String)
signal gathered(node_id: int, result: Dictionary)

const SPEED := 6.0
const SPRINT := 9.5
const GRAVITY := 22.0

var player_id: int = 1
var color := Color("#3f6f8f")
var cam_rig: CameraRig
var model: Node3D
var lantern: OmniLight3D
var gather_target: int = -1
var _gather_cd := 0.0
var _swing := 0.0
var _walk_phase := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var input_enabled := true


func _ready() -> void:
	collision_layer = 0
	collision_mask = TerrainBuilder.LAYER_TERRAIN | BuildingView.LAYER_SOLID
	floor_snap_length = 0.6
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = ModelFactory.survivor(color)
	add_child(model)
	lantern = OmniLight3D.new()
	lantern.light_color = Color("#ffcf8a")
	lantern.omni_range = 9.0
	lantern.light_energy = 0.0
	lantern.shadow_enabled = false
	lantern.position = Vector3(0, 2.0, 0.4)
	add_child(lantern)
	_last_pos = global_position


func set_gather_target(node_id: int) -> void:
	gather_target = node_id
	_stuck_timer = 0.0


func _physics_process(delta: float) -> void:
	var state := Session.state
	if state == null:
		return
	var dir := Vector3.ZERO
	if input_enabled:
		var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if inp != Vector2.ZERO:
			gather_target = -1
			var yaw := cam_rig.yaw if cam_rig != null else 0.0
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var back := Vector3(sin(yaw), 0, cos(yaw))
			dir = (right * inp.x + back * inp.y).normalized()
	_gather_cd -= delta
	var face := Vector3.ZERO
	if gather_target >= 0:
		if not state.nodes.has(gather_target):
			gather_target = -1
		else:
			var n: Dictionary = state.nodes[gather_target]
			var npos := state.node_position(n)
			var to := Vector3(npos.x - global_position.x, 0, npos.z - global_position.z)
			var reach: float = float(GameData.player_cfg().reach) + float(GameData.node_type(n.type).get("radius", 0.5))
			face = to
			if to.length() > reach:
				dir = to.normalized()
				_check_stuck(delta)
			elif _gather_cd <= 0.0:
				_do_gather()
	var speed := SPRINT if Input.is_action_pressed("sprint") and input_enabled else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Nicht aus der Karte fallen
	if global_position.y < state.map.height_at(global_position.x, global_position.z) - 2.0:
		global_position.y = state.map.height_at(global_position.x, global_position.z) + 0.5
	Session.update_local_player(global_position)
	if dir != Vector3.ZERO:
		face = dir
	if face.length() > 0.01:
		var target_yaw := atan2(face.x, face.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
	_animate(delta, Vector2(velocity.x, velocity.z).length())


func _do_gather() -> void:
	var cfg: Dictionary = GameData.player_cfg()
	_gather_cd = float(cfg.gather_cooldown)
	_swing = 1.0
	var node_id := gather_target
	var r := Session.submit({"type": "gather", "node": node_id})
	if r.ok:
		gathered.emit(node_id, r)
		if r.get("depleted", false):
			gather_target = -1
	elif not r.get("silent", false):
		message.emit(String(r.reason), "warning")
		gather_target = -1


func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer > 1.0:
		if global_position.distance_to(_last_pos) < 0.4:
			message.emit("Weg blockiert", "warning")
			gather_target = -1
		_last_pos = global_position
		_stuck_timer = 0.0


func _animate(delta: float, speed: float) -> void:
	var moving := speed > 0.3
	_walk_phase += delta * speed * 1.6 if moving else 0.0
	var swing := sin(_walk_phase) * (0.65 if moving else 0.0)
	var legl := model.get_node("LegL")
	var legr := model.get_node("LegR")
	var arml := model.get_node("ArmL")
	var armr := model.get_node("ArmR")
	legl.rotation.x = lerpf(legl.rotation.x, swing, 0.3)
	legr.rotation.x = lerpf(legr.rotation.x, -swing, 0.3)
	arml.rotation.x = lerpf(arml.rotation.x, -swing * 0.8, 0.3)
	var body := model.get_node("Body")
	body.position.y = 1.15 + absf(sin(_walk_phase)) * 0.05
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta * 3.0)
		armr.rotation.x = -sin(_swing * PI) * 2.0
	else:
		armr.rotation.x = lerpf(armr.rotation.x, swing * 0.8, 0.3)


func set_night(f: float) -> void:
	lantern.light_energy = lerpf(0.0, 1.6, f)
