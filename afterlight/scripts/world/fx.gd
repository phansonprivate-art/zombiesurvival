class_name Fx
extends RefCounted
## Kleine visuelle Effekte: Rauch, Staub, schwebender Text.

static var _smoke_mat: StandardMaterial3D
static var _dust_mat: StandardMaterial3D


static func _particle_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# weiche, runde Partikel statt Quadrate
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	m.albedo_texture = tex
	return m


## Dauerhafter Rauch (Schornstein)
static func smoke() -> CPUParticles3D:
	if _smoke_mat == null:
		_smoke_mat = _particle_mat(Color(0.55, 0.55, 0.58, 0.5))
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.6, 0.6)
	mesh.material = _smoke_mat
	p.mesh = mesh
	p.amount = 14
	p.lifetime = 4.5
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.25, 0.12, 0.05)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Einmaliger Staub- oder Splitterausstoß
static func burst(parent: Node, pos: Vector3, color: Color, amount := 14, size := 0.25) -> void:
	if _dust_mat == null:
		_dust_mat = _particle_mat(Color.WHITE)
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = _dust_mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -7.0, 0)
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Aufsteigender, verblassender Text (z. B. "+3 Holz")
static func float_text(parent: Node, pos: Vector3, text: String, color := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 44
	l.pixel_size = 0.01
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.6, 0), 1.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.3).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
