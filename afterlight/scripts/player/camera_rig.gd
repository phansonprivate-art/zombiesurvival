class_name CameraRig
extends Node3D
## Schräge Vogelperspektive. Gehört genau einem lokalen Spieler und wird nie synchronisiert,
## damit Kameras verschiedener Spieler sich nicht beeinflussen.

const MIN_DIST := 9.0
const MAX_DIST := 70.0
const PAN_SPEED := 28.0
const ROT_SPEED := 1.8

var target: Node3D
var follow := true
var yaw := deg_to_rad(40.0)
var distance := 24.0
var _target_distance := 24.0
var focus := Vector3.ZERO
var bounds := Rect2(0, 0, 144, 144)
var map: WorldMap
var camera: Camera3D
var _drag_pan := false
var _drag_rot := false
var input_enabled := true


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.3
	camera.far = 500.0
	add_child(camera)
	camera.make_current()
	if target != null:
		focus = target.global_position
	_apply()


func pitch() -> float:
	# weiter weg = steiler von oben, damit die Basis gut überblickbar ist
	return deg_to_rad(lerpf(40.0, 62.0, (distance - MIN_DIST) / (MAX_DIST - MIN_DIST)))


func _process(delta: float) -> void:
	if input_enabled:
		var pan := Vector2(Input.get_axis("cam_pan_left", "cam_pan_right"), Input.get_axis("cam_pan_up", "cam_pan_down"))
		if pan != Vector2.ZERO:
			follow = false
			_pan(pan * PAN_SPEED * delta * (distance / 24.0))
		var rot := Input.get_axis("cam_rotate_left", "cam_rotate_right")
		yaw += rot * ROT_SPEED * delta
	if follow and target != null:
		focus = focus.lerp(target.global_position, 1.0 - exp(-8.0 * delta))
	distance = lerpf(distance, _target_distance, 1.0 - exp(-10.0 * delta))
	_apply()


func _pan(screen_delta: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	focus += right * screen_delta.x - forward * screen_delta.y


func _apply() -> void:
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	if map != null:
		focus.y = lerpf(focus.y, map.height_at(focus.x, focus.z), 0.2) if follow == false else focus.y
	var p := pitch()
	var offset := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * distance
	var pos := focus + offset
	# nie unter das Gelände tauchen
	if map != null:
		pos.y = maxf(pos.y, map.height_at(pos.x, pos.z) + 3.0)
	camera.global_position = pos
	camera.look_at(focus + Vector3(0, 1.0, 0), Vector3.UP)


func center_on_target() -> void:
	follow = true


func handle_input(event: InputEvent) -> bool:
	if not input_enabled:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance * 0.88, MIN_DIST, MAX_DIST)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance * 1.13, MIN_DIST, MAX_DIST)
			return true
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_pan = mb.pressed
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag_rot = mb.pressed
			return false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_pan:
			follow = false
			_pan(-mm.relative * 0.045 * (distance / 24.0))
			return true
		if _drag_rot:
			yaw -= mm.relative.x * 0.006
			return true
	elif event.is_action_pressed("cam_center"):
		center_on_target()
		return true
	return false


## Weltposition unter dem Mauszeiger (Schnitt mit dem Gelände)
func mouse_ray(screen_pos: Vector2, mask: int, exclude: Array = []) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)
