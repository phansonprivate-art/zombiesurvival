class_name NodeView
extends Node3D
## Darstellung eines Rohstoffknotens (Baum, Felsen, Erz, Wrack, Kiste).

var id: int = 0
var type: String = ""
var model: Node3D
var _meshes: Array = []
var _faded := false
var _max := 1


func setup(state: GameState, n: Dictionary) -> void:
	id = n.id
	type = n.type
	_max = maxi(1, int(n.max))
	name = "Node_%d" % id
	position = state.node_position(n)
	model = ModelFactory.resource_node(type, int(n.variant))
	model.rotation.y = n.rot
	model.scale = Vector3.ONE * float(n.scale)
	add_child(model)
	var nt: Dictionary = state.data.node_type(type)
	var body := StaticBody3D.new()
	body.set_meta("kind", "node")
	body.set_meta("id", id)
	body.set_meta("view", self)
	body.collision_layer = BuildingView.LAYER_SOLID | BuildingView.LAYER_PICK
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = float(nt.get("radius", 0.6)) * float(n.scale)
	shape.height = 4.0 if type == "tree" else 1.6
	cs.shape = shape
	cs.position = Vector3(0, shape.height * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_meshes = ModelFactory.meshes_of(model)
	refresh(n)


func refresh(n: Dictionary) -> void:
	# Felsen und Erz schrumpfen sichtbar beim Abbau
	if type == "rock" or type == "ore":
		var f := lerpf(0.55, 1.0, float(n.amount) / _max)
		model.scale = Vector3.ONE * float(n.scale) * f


## Kurzes Wackeln beim Sammeln
func hit() -> void:
	var tw := create_tween()
	var base := model.rotation
	tw.tween_property(model, "rotation", base + Vector3(0.08, 0, 0.05), 0.06)
	tw.tween_property(model, "rotation", base - Vector3(0.05, 0, 0.04), 0.08)
	tw.tween_property(model, "rotation", base, 0.1)


## Verschwinden: Bäume kippen um, andere versinken
func remove_animated() -> void:
	for c in get_children():
		if c is StaticBody3D:
			c.queue_free()
	var tw := create_tween()
	if type == "tree":
		tw.tween_property(model, "rotation:x", PI * 0.48, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(model, "position:y", -2.5, 0.8)
	else:
		tw.tween_property(model, "scale", Vector3.ONE * 0.05, 0.4)
	tw.tween_callback(queue_free)


func set_faded(on: bool) -> void:
	if on == _faded:
		return
	_faded = on
	for m in _meshes:
		m.transparency = 0.65 if on else 0.0
