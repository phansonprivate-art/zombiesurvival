class_name ModelFactory
extends RefCounted
## Prozedurales, stilisiertes Art-Set: Gebäude, Vegetation, Felsen, Ruinen, Wracks, Figuren.
## Alle Modelle bestehen aus gemeinsam genutzten Meshes und Palette-Materialien.
## Gebäudemodelle sind um den Ursprung zentriert, Boden bei y = 0, Maße in Metern.

static var _meshes := {}


# ---------------------------------------------------------------- Mesh-Bausteine

static func box(size: Vector3) -> BoxMesh:
	var k := "b%s" % size
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = size
		_meshes[k] = m
	return _meshes[k]


static func cyl(top: float, bottom: float, h: float, segs := 10) -> CylinderMesh:
	var k := "c%.3f_%.3f_%.3f_%d" % [top, bottom, h, segs]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		_meshes[k] = m
	return _meshes[k]


static func sphere(r: float, segs := 10, rings := 6, h := -1.0) -> SphereMesh:
	var k := "s%.3f_%d_%d_%.3f" % [r, segs, rings, h]
	if not _meshes.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = h if h > 0.0 else r * 2.0
		m.radial_segments = segs
		m.rings = rings
		_meshes[k] = m
	return _meshes[k]


static func prism(size: Vector3) -> PrismMesh:
	var k := "p%s" % size
	if not _meshes.has(k):
		var m := PrismMesh.new()
		m.size = size
		_meshes[k] = m
	return _meshes[k]


static func torus(inner: float, outer: float) -> TorusMesh:
	var k := "t%.3f_%.3f" % [inner, outer]
	if not _meshes.has(k):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 6
		_meshes[k] = m
	return _meshes[k]


## Unregelmäßiger, flach schattierter Felsbrocken (deterministisch je Variante)
static func rock_mesh(variant: int, squash := 0.7) -> ArrayMesh:
	var k := "rock%d_%.2f" % [variant, squash]
	if _meshes.has(k):
		return _meshes[k]
	var src := SphereMesh.new()
	src.radius = 1.0
	src.height = 2.0
	src.radial_segments = 9
	src.rings = 6
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 1000 + variant * 31
	noise.frequency = 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx.size():
		var v := verts[idx[i]]
		var key := v.snapped(Vector3.ONE * 0.001)
		var d := 1.0 + noise.get_noise_3d(key.x * 2.0, key.y * 2.0, key.z * 2.0) * 0.45
		var p := key * d
		p.y = maxf(p.y * squash, -0.15)
		st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[k] = mesh
	return mesh


static func part(parent: Node3D, mesh: Mesh, mat_name: String, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Palette.mat(mat_name)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Liegender Baumstamm entlang X
static func log_x(parent: Node3D, length: float, r: float, pos: Vector3, mat_name := "wood") -> MeshInstance3D:
	return part(parent, cyl(r, r, length, 8), mat_name, pos, Vector3(0, 0, 90))


# ---------------------------------------------------------------- Vegetation und Rohstoffe

static func tree(variant: int) -> Node3D:
	var n := Node3D.new()
	match variant:
		0, 1:
			var tall := 1.0 if variant == 0 else 1.25
			part(n, cyl(0.12, 0.2, 1.6 * tall, 7), "bark", Vector3(0, 0.8 * tall, 0))
			var sizes := [[1.55, 1.9], [1.25, 1.7], [0.9, 1.5], [0.5, 1.2]]
			var y := 1.1 * tall
			for i in sizes.size():
				var s: Array = sizes[i]
				part(n, cyl(0.0, s[0], s[1] * tall, 8), "leaf_pine" if i % 2 == 0 else "leaf_pine2",
					Vector3(0, y + s[1] * tall * 0.5, 0), Vector3(0, i * 23.0, 0))
				y += s[1] * tall * 0.55
		_:
			part(n, cyl(0.13, 0.22, 2.0, 7), "bark", Vector3(0, 1.0, 0))
			part(n, cyl(0.05, 0.08, 1.1, 5), "bark", Vector3(0.35, 1.8, 0), Vector3(0, 0, -35))
			part(n, sphere(1.25, 8, 5), "leaf", Vector3(0, 2.9, 0), Vector3(0, 0, 0), Vector3(1, 0.85, 1))
			part(n, sphere(0.9, 8, 5), "leaf2", Vector3(0.75, 2.5, 0.35))
			part(n, sphere(0.85, 8, 5), "leaf2", Vector3(-0.6, 2.6, -0.45))
			part(n, sphere(0.7, 7, 5), "leaf", Vector3(0.1, 3.6, 0.2))
	return n


static func rock(variant: int) -> Node3D:
	var n := Node3D.new()
	part(n, rock_mesh(variant), "rock", Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	part(n, rock_mesh((variant + 1) % 3), "rock_dark", Vector3(0.6, 0.15, 0.4), Vector3(0, 40, 0), Vector3(0.45, 0.45, 0.45))
	return n


static func ore(variant: int) -> Node3D:
	var n := Node3D.new()
	part(n, rock_mesh(variant + 5, 0.6), "rock_dark", Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
	part(n, rock_mesh(variant + 6, 0.8), "ore", Vector3(0.45, 0.2, -0.3), Vector3(0, 70, 0), Vector3(0.5, 0.5, 0.5))
	for i in 4:
		var a := i * 1.7 + variant
		part(n, cyl(0.0, 0.11, 0.55, 5), "ore_crystal", Vector3(cos(a) * 0.45, 0.65, sin(a) * 0.4), Vector3(cos(a) * 25.0, 0, sin(a) * 25.0))
	return n


static func wreck(variant: int) -> Node3D:
	var n := Node3D.new()
	var paint: String = ["paint_blue", "paint_green", "paint_cream"][variant % 3]
	var body := Node3D.new()
	body.rotation_degrees = Vector3(0, 0, -4 if variant == 1 else 2)
	n.add_child(body)
	part(body, box(Vector3(1.75, 0.55, 4.0)), paint, Vector3(0, 0.55, 0))
	part(body, box(Vector3(1.6, 0.5, 2.0)), paint, Vector3(0, 1.08, -0.25))
	part(body, box(Vector3(1.62, 0.36, 1.86)), "glass_dark", Vector3(0, 1.1, -0.25))
	part(body, box(Vector3(1.8, 0.12, 0.3)), "metal_dark", Vector3(0, 0.4, 2.0))
	part(body, box(Vector3(1.8, 0.12, 0.3)), "metal_dark", Vector3(0, 0.4, -2.0))
	part(body, box(Vector3(0.5, 0.06, 0.6)), "rust", Vector3(0.4, 0.84, 1.2), Vector3(0, 20, 0))
	part(body, box(Vector3(0.35, 0.05, 0.9)), "rust", Vector3(-0.5, 1.34, -0.4))
	for w in [Vector3(0.85, 0.32, 1.25), Vector3(-0.85, 0.32, 1.25), Vector3(0.85, 0.32, -1.3), Vector3(-0.85, 0.32, -1.3)]:
		if variant == 2 and w.x > 0 and w.z > 0:
			continue
		part(n, cyl(0.32, 0.32, 0.22, 10), "rubber", w, Vector3(0, 0, 90))
	return n


static func crate(_variant: int) -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(1.1, 0.65, 0.75)), "olive", Vector3(0, 0.33, 0))
	part(n, box(Vector3(1.14, 0.08, 0.79)), "metal_dark", Vector3(0, 0.68, 0))
	for x in [-0.35, 0.35]:
		part(n, box(Vector3(0.08, 0.67, 0.79)), "metal_dark", Vector3(x, 0.33, 0))
	part(n, box(Vector3(0.3, 0.18, 0.02)), "canvas", Vector3(0, 0.4, 0.385))
	part(n, box(Vector3(0.6, 0.4, 0.5)), "olive", Vector3(0.75, 0.2, 0.35), Vector3(0, 25, 0))
	return n


static func resource_node(type: String, variant: int) -> Node3D:
	match type:
		"tree": return tree(variant)
		"rock": return rock(variant)
		"ore": return ore(variant)
		"wreck": return wreck(variant)
		"crate": return crate(variant)
	return rock(0)


# ---------------------------------------------------------------- Ruinen

## Zerfallene Gebäude. size in Metern (x, z)
static func ruin(kind: int, size: Vector2, seed: int) -> Node3D:
	var n := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mat_wall: String = ["concrete", "brick", "concrete_dark"][kind % 3]
	part(n, box(Vector3(size.x, 0.25, size.y)), "concrete_dark", Vector3(0, 0.12, 0))
	var hx := size.x * 0.5 - 0.15
	var hz := size.y * 0.5 - 0.15
	# vier Wände, jede in Segmenten mit unterschiedlicher Höhe (abgebrochene Kanten)
	var walls := [
		[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)],
		[Vector3(hx, 0, -hz), Vector3(hx, 0, hz)],
		[Vector3(hx, 0, hz), Vector3(-hx, 0, hz)],
		[Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz)],
	]
	for wi in walls.size():
		var a: Vector3 = walls[wi][0]
		var b: Vector3 = walls[wi][1]
		var length := a.distance_to(b)
		var segs := maxi(2, int(length / 1.2))
		var dir := (b - a) / length
		var missing_from := rng.randi_range(0, segs)
		for s in segs:
			if wi == 2 and s >= missing_from and s < missing_from + 2:
				continue  # eingestürzter Abschnitt
			var h := rng.randf_range(0.8, 3.0) if wi != 0 else rng.randf_range(2.2, 3.2)
			var seg_len := length / segs
			var center := a + dir * (seg_len * (s + 0.5))
			var window := s % 2 == 1 and h > 2.0
			var yaw := rad_to_deg(atan2(dir.x, dir.z)) + 90.0
			if window:
				part(n, box(Vector3(seg_len, 0.9, 0.3)), mat_wall, center + Vector3(0, 0.45, 0), Vector3(0, yaw, 0))
				part(n, box(Vector3(seg_len, h - 1.9, 0.3)), mat_wall, center + Vector3(0, 1.9 + (h - 1.9) * 0.5, 0), Vector3(0, yaw, 0))
				part(n, box(Vector3(0.15, 1.0, 0.3)), mat_wall, center + Vector3(0, 1.4, 0) - dir * seg_len * 0.42, Vector3(0, yaw, 0))
			else:
				part(n, box(Vector3(seg_len, h, 0.3)), mat_wall, center + Vector3(0, h * 0.5, 0), Vector3(0, yaw, rng.randf_range(-2, 2)))
			if rng.randf() < 0.3:
				part(n, cyl(0.02, 0.02, 0.8, 4), "rust", center + Vector3(0, h + 0.3, 0), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)))
	# Schutt
	for i in rng.randi_range(5, 9):
		var p := Vector3(rng.randf_range(-hx, hx), 0.15, rng.randf_range(-hz, hz))
		var s := rng.randf_range(0.25, 0.7)
		part(n, box(Vector3(s, s * 0.5, s * 0.8)), mat_wall, p, Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 180), rng.randf_range(-15, 15)))
	# eingestürzter Dachbalken
	part(n, box(Vector3(size.x * 0.9, 0.18, 0.25)), "wood_dark", Vector3(0, 0.9, 0), Vector3(0, 30, 18))
	return n


# ---------------------------------------------------------------- Gebäude

static func building(model: String) -> Node3D:
	match model:
		"hq": return _hq()
		"storage": return _storage()
		"lumber": return _lumber()
		"quarry": return _quarry()
		"mine": return _mine()
		"workshop": return _workshop()
		"smelter": return _smelter()
		"wall_wood": return _wall_wood()
		"wall_stone": return _wall_stone()
		"gate": return _gate()
	var n := Node3D.new()
	part(n, box(Vector3(1.5, 1.5, 1.5)), "accent", Vector3(0, 0.75, 0))
	return n


## Holzhaus mit Satteldach (Breite x entlang X, Tiefe z entlang Z)
static func _cabin(parent: Node3D, w: float, d: float, h: float, pos: Vector3, wall := "plank", roof := "roof") -> void:
	part(parent, box(Vector3(w, h, d)), wall, pos + Vector3(0, h * 0.5, 0))
	for cx in [-w * 0.5, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			part(parent, cyl(0.12, 0.12, h, 6), "wood_dark", pos + Vector3(cx, h * 0.5, cz))
	# PrismMesh: Dreieck in X, First entlang Z. Der First soll über die lange Seite laufen.
	if w > d:
		part(parent, prism(Vector3(d + 0.5, 1.3, w + 0.7)), roof, pos + Vector3(0, h + 0.65, 0), Vector3(0, 90, 0))
	else:
		part(parent, prism(Vector3(w + 0.7, 1.3, d + 0.5)), roof, pos + Vector3(0, h + 0.65, 0))
	part(parent, box(Vector3(w + 0.1, 0.15, d + 0.1)), "wood_dark", pos + Vector3(0, h, 0))


static func _window(parent: Node3D, pos: Vector3, yaw: float) -> void:
	part(parent, box(Vector3(0.7, 0.6, 0.06)), "window", pos, Vector3(0, yaw, 0))
	part(parent, box(Vector3(0.84, 0.08, 0.1)), "wood_dark", pos + Vector3(0, -0.33, 0), Vector3(0, yaw, 0))


static func _barrel(parent: Node3D, pos: Vector3, mat_name := "rust") -> void:
	part(parent, cyl(0.28, 0.28, 0.85, 10), mat_name, pos + Vector3(0, 0.43, 0))
	part(parent, torus(0.27, 0.31), "metal_dark", pos + Vector3(0, 0.2, 0))
	part(parent, torus(0.27, 0.31), "metal_dark", pos + Vector3(0, 0.66, 0))


static func _hq() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(5.6, 0.3, 5.2)), "stone", Vector3(0, 0.15, 0))
	_cabin(n, 4.4, 3.6, 2.6, Vector3(0, 0.3, -0.5))
	part(n, box(Vector3(0.9, 1.7, 0.08)), "wood_dark", Vector3(0, 1.15, 1.31))
	_window(n, Vector3(-1.3, 1.7, 1.32), 0)
	_window(n, Vector3(1.3, 1.7, 1.32), 0)
	_window(n, Vector3(2.22, 1.7, -0.5), 90)
	_window(n, Vector3(-2.22, 1.7, -0.5), 90)
	# Vordach
	for x in [-1.8, 1.8]:
		part(n, cyl(0.08, 0.08, 2.3, 6), "wood_dark", Vector3(x, 1.45, 2.3))
	part(n, box(Vector3(4.4, 0.1, 1.4)), "roof", Vector3(0, 2.6, 1.95), Vector3(-12, 0, 0))
	# Schornstein
	part(n, box(Vector3(0.6, 2.2, 0.6)), "stone_dark", Vector3(1.4, 3.6, -1.4))
	# Vorräte
	part(n, box(Vector3(0.7, 0.6, 0.7)), "wood_light", Vector3(-2.3, 0.6, 2.2), Vector3(0, 15, 0))
	part(n, box(Vector3(0.6, 0.5, 0.6)), "wood", Vector3(-2.2, 1.15, 2.1), Vector3(0, -10, 0))
	_barrel(n, Vector3(2.4, 0.3, 2.2))
	# Fahnenmast
	part(n, cyl(0.04, 0.05, 4.5, 6), "metal", Vector3(-2.6, 2.55, -2.4))
	part(n, box(Vector3(0.9, 0.55, 0.03)), "cloth_red", Vector3(-2.1, 4.4, -2.4))
	# Laterne am Eingang
	part(n, box(Vector3(0.18, 0.28, 0.18)), "lamp", Vector3(0.75, 2.1, 1.45))
	return n


static func _storage() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(3.8, 0.25, 3.8)), "stone", Vector3(0, 0.12, 0))
	for p in [Vector3(-1.7, 0, -1.7), Vector3(1.7, 0, -1.7), Vector3(-1.7, 0, 1.7), Vector3(1.7, 0, 1.7)]:
		var h := 3.0 if p.z < 0 else 2.4
		part(n, cyl(0.1, 0.12, h, 6), "wood_dark", p + Vector3(0, h * 0.5, 0))
	part(n, box(Vector3(4.2, 0.12, 4.3)), "roof_metal", Vector3(0, 2.85, 0), Vector3(-8.5, 0, 0))
	part(n, box(Vector3(3.4, 2.4, 0.12)), "plank", Vector3(0, 1.45, -1.72))
	# Ladung
	for i in 3:
		part(n, box(Vector3(0.75, 0.6, 0.75)), "wood_light", Vector3(-1.0 + i * 0.85, 0.55, -1.0), Vector3(0, i * 9.0, 0))
	part(n, box(Vector3(0.7, 0.55, 0.7)), "wood", Vector3(-0.6, 1.12, -1.0), Vector3(0, 20, 0))
	_barrel(n, Vector3(1.1, 0.25, 0.6), "metal")
	_barrel(n, Vector3(0.5, 0.25, 0.9), "rust")
	part(n, sphere(0.35, 8, 5), "canvas", Vector3(-1.0, 0.45, 0.6), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
	part(n, sphere(0.32, 8, 5), "canvas", Vector3(-0.4, 0.42, 0.8), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
	part(n, box(Vector3(1.6, 0.05, 1.2)), "tarp", Vector3(1.0, 1.25, -1.0), Vector3(0, 0, 8))
	return n


static func _lumber() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(3.8, 0.2, 3.8)), "wood_dark", Vector3(0, 0.1, 0))
	part(n, box(Vector3(2.0, 2.0, 1.8)), "plank", Vector3(-0.8, 1.2, -0.9))
	part(n, box(Vector3(2.4, 0.12, 2.3)), "roof", Vector3(-0.8, 2.35, -0.9), Vector3(10, 0, 0))
	part(n, box(Vector3(0.7, 1.4, 0.05)), "wood_dark", Vector3(-0.8, 0.95, 0.01))
	# Stammstapel
	for i in 3:
		log_x(n, 2.2, 0.2, Vector3(0.6, 0.35, 0.8 + i * 0.4), "bark")
	for i in 2:
		log_x(n, 2.2, 0.2, Vector3(0.6, 0.7, 1.0 + i * 0.4), "bark")
	# Hackklotz mit Axt
	part(n, cyl(0.3, 0.32, 0.5, 9), "wood_light", Vector3(1.2, 0.45, -0.9))
	part(n, cyl(0.03, 0.03, 0.8, 5), "wood_dark", Vector3(1.25, 0.95, -0.85), Vector3(0, 0, 30))
	part(n, box(Vector3(0.22, 0.12, 0.04)), "metal", Vector3(1.05, 1.3, -0.85), Vector3(0, 0, 30))
	# Sägebock
	part(n, box(Vector3(1.2, 0.08, 0.1)), "wood", Vector3(1.0, 0.75, 0.0))
	for x in [0.55, 1.45]:
		part(n, box(Vector3(0.06, 0.8, 0.06)), "wood", Vector3(x, 0.45, 0.1), Vector3(20, 0, 0))
		part(n, box(Vector3(0.06, 0.8, 0.06)), "wood", Vector3(x, 0.45, -0.1), Vector3(-20, 0, 0))
	return n


static func _quarry() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(3.8, 0.2, 3.8)), "stone_dark", Vector3(0, 0.1, 0))
	# A-Rahmen-Kran
	# Rotation um Z kippt die Spitze nach -X (positiver Winkel) – beide Beine treffen sich oben
	for z in [-1.2, 1.2]:
		part(n, cyl(0.08, 0.1, 3.6, 6), "wood", Vector3(-0.8, 1.62, z), Vector3(0, 0, -26))
		part(n, cyl(0.08, 0.1, 3.6, 6), "wood", Vector3(0.8, 1.62, z), Vector3(0, 0, 26))
	part(n, cyl(0.09, 0.09, 2.8, 6), "wood_dark", Vector3(0, 3.28, 0), Vector3(90, 0, 0))
	part(n, cyl(0.015, 0.015, 1.6, 4), "metal_dark", Vector3(0, 2.45, 0))
	part(n, rock_mesh(2), "stone", Vector3(0, 1.35, 0), Vector3.ZERO, Vector3(0.4, 0.4, 0.4))
	# Steinhaufen
	for i in 5:
		var a := i * 1.3
		part(n, rock_mesh(i % 3), "stone", Vector3(1.2 + cos(a) * 0.4, 0.3, -1.2 + sin(a) * 0.4), Vector3(0, i * 50.0, 0), Vector3(0.35, 0.35, 0.35))
	# Schubkarre
	part(n, box(Vector3(0.6, 0.3, 0.9)), "metal", Vector3(-1.1, 0.55, 1.1), Vector3(-8, 30, 0))
	part(n, cyl(0.18, 0.18, 0.08, 8), "rubber", Vector3(-1.3, 0.35, 1.5), Vector3(0, 30, 90))
	return n


static func _mine() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(3.8, 0.2, 3.8)), "stone_dark", Vector3(0, 0.1, 0))
	# Stollenmund im Erdhügel
	part(n, rock_mesh(4, 0.55), "rock_dark", Vector3(0, 0.3, -1.0), Vector3.ZERO, Vector3(1.9, 1.6, 1.2))
	part(n, box(Vector3(1.2, 1.4, 0.4)), "void", Vector3(0, 0.9, -0.05))
	for x in [-0.7, 0.7]:
		part(n, box(Vector3(0.16, 1.6, 0.16)), "wood_dark", Vector3(x, 1.0, 0.05))
	part(n, box(Vector3(1.6, 0.16, 0.2)), "wood_dark", Vector3(0, 1.8, 0.05))
	# Fördergerüst
	for p in [Vector3(1.0, 0, 0.6), Vector3(1.6, 0, 0.6), Vector3(1.0, 0, 1.4), Vector3(1.6, 0, 1.4)]:
		part(n, box(Vector3(0.1, 3.2, 0.1)), "wood", p + Vector3(0, 1.7, 0))
	part(n, box(Vector3(0.8, 0.1, 1.0)), "wood_dark", Vector3(1.3, 3.25, 1.0))
	part(n, cyl(0.45, 0.45, 0.08, 14), "metal_dark", Vector3(1.3, 3.55, 1.0), Vector3(90, 0, 0))
	# Gleise und Lore
	for x in [-0.3, 0.3]:
		part(n, box(Vector3(0.05, 0.05, 1.7)), "metal", Vector3(x, 0.24, 0.95))
	part(n, box(Vector3(0.75, 0.45, 0.6)), "rust", Vector3(0, 0.55, 1.3))
	part(n, rock_mesh(1), "ore", Vector3(0, 0.82, 1.3), Vector3.ZERO, Vector3(0.28, 0.2, 0.22))
	return n


static func _workshop() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(5.8, 0.25, 3.8)), "concrete", Vector3(0, 0.12, 0))
	part(n, box(Vector3(4.6, 2.7, 2.8)), "brick", Vector3(-0.4, 1.6, -0.3))
	part(n, prism(Vector3(5.2, 0.9, 3.3)), "roof_metal", Vector3(-0.4, 3.4, -0.3))
	part(n, box(Vector3(1.6, 2.0, 0.08)), "metal_dark", Vector3(-1.2, 1.25, 1.12))
	_window(n, Vector3(0.6, 1.9, 1.12), 0)
	_window(n, Vector3(1.4, 1.9, 1.12), 0)
	# Rohrschornstein
	part(n, cyl(0.15, 0.15, 2.0, 8), "metal", Vector3(1.3, 4.0, -1.0))
	part(n, cyl(0.22, 0.15, 0.2, 8), "metal_dark", Vector3(1.3, 5.05, -1.0))
	# Werkbank unter Vordach
	part(n, box(Vector3(1.1, 0.1, 2.2)), "roof", Vector3(2.4, 2.45, -0.3), Vector3(0, 0, -12))
	part(n, box(Vector3(0.7, 0.1, 1.6)), "wood_light", Vector3(2.4, 0.95, -0.3))
	for z in [-0.9, 0.3]:
		part(n, box(Vector3(0.6, 0.85, 0.08)), "wood_dark", Vector3(2.4, 0.5, z))
	part(n, box(Vector3(0.3, 0.2, 0.25)), "metal", Vector3(2.4, 1.1, -0.6))
	part(n, torus(0.12, 0.22), "metal_dark", Vector3(2.4, 1.05, 0.1), Vector3(90, 0, 0))
	_barrel(n, Vector3(2.5, 0.25, 1.3), "metal")
	return n


static func _smelter() -> Node3D:
	var n := Node3D.new()
	part(n, box(Vector3(3.8, 0.25, 3.8)), "stone_dark", Vector3(0, 0.12, 0))
	part(n, cyl(0.85, 1.25, 2.4, 10), "stone", Vector3(-0.3, 1.45, -0.3))
	part(n, cyl(0.35, 0.5, 2.2, 8), "stone_dark", Vector3(-0.3, 3.7, -0.3))
	part(n, box(Vector3(0.7, 0.55, 0.3)), "fire", Vector3(-0.3, 0.75, 0.75))
	part(n, box(Vector3(0.95, 0.12, 0.35)), "metal_dark", Vector3(-0.3, 1.1, 0.8))
	# Erz- und Kohlehaufen
	part(n, rock_mesh(0, 0.5), "ore", Vector3(1.2, 0.2, 1.1), Vector3.ZERO, Vector3(0.5, 0.5, 0.5))
	part(n, rock_mesh(2, 0.5), "metal_dark", Vector3(1.3, 0.2, -0.6), Vector3.ZERO, Vector3(0.45, 0.4, 0.45))
	# Barren
	for i in 3:
		part(n, box(Vector3(0.35, 0.1, 0.15)), "metal", Vector3(0.9, 0.3 + i * 0.1, 0.2), Vector3(0, i * 90.0, 0))
	return n


static func _wall_wood() -> Node3D:
	var n := Node3D.new()
	for i in 5:
		var x := -0.8 + i * 0.4
		var h := 2.3 + (0.15 if i % 2 == 0 else 0.0)
		part(n, cyl(0.19, 0.2, h, 7), "wood", Vector3(x, h * 0.5 - 0.2, 0))
		part(n, cyl(0.0, 0.19, 0.4, 7), "wood_light", Vector3(x, h, 0))
	part(n, box(Vector3(2.0, 0.16, 0.12)), "wood_dark", Vector3(0, 1.5, 0.2))
	part(n, box(Vector3(2.0, 0.16, 0.12)), "wood_dark", Vector3(0, 0.6, 0.2))
	return n


static func _wall_stone() -> Node3D:
	var n := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	part(n, box(Vector3(2.0, 0.3, 0.9)), "stone_dark", Vector3(0, 0.15, 0))
	for row in 4:
		var x := -1.0
		while x < 0.95:
			var w := minf(rng.randf_range(0.45, 0.75), 1.0 - x)
			part(n, box(Vector3(w - 0.04, 0.48, 0.75 - row * 0.04)), "stone" if rng.randf() < 0.7 else "rock", Vector3(x + w * 0.5, 0.55 + row * 0.5, 0), Vector3(0, rng.randf_range(-3, 3), 0))
			x += w
	part(n, box(Vector3(2.04, 0.15, 0.8)), "concrete_dark", Vector3(0, 2.38, 0))
	return n


static func _gate() -> Node3D:
	var n := Node3D.new()
	for x in [-1.85, 1.85]:
		part(n, box(Vector3(0.4, 2.8, 0.6)), "stone", Vector3(x, 1.4, 0))
		part(n, box(Vector3(0.5, 0.2, 0.7)), "stone_dark", Vector3(x, 2.9, 0))
	part(n, box(Vector3(4.1, 0.25, 0.3)), "wood_dark", Vector3(0, 2.75, 0))
	# Torflügel an Scharnier-Knoten, damit sie sich öffnen lassen
	for side in [-1, 1]:
		var hinge := Node3D.new()
		hinge.name = "HingeL" if side < 0 else "HingeR"
		hinge.position = Vector3(1.62 * side, 0, 0)
		n.add_child(hinge)
		for i in 4:
			var x: float = -side * (0.2 + i * 0.4)
			part(hinge, box(Vector3(0.37, 2.2, 0.12)), "plank", Vector3(x, 1.2, 0))
		part(hinge, box(Vector3(1.6, 0.15, 0.1)), "wood_dark", Vector3(-side * 0.8, 1.9, 0.08))
		part(hinge, box(Vector3(1.6, 0.15, 0.1)), "wood_dark", Vector3(-side * 0.8, 0.5, 0.08))
		part(hinge, box(Vector3(1.75, 0.1, 0.08)), "metal_dark", Vector3(-side * 0.8, 1.2, 0.09), Vector3(0, 0, side * 35.0))
	return n


## Gerüst für Baustellen (Maße in Metern)
static func scaffold(size: Vector2, h: float) -> Node3D:
	var n := Node3D.new()
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for p in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		part(n, cyl(0.05, 0.05, h, 5), "wood_light", Vector3(p.x, h * 0.5, p.y))
	for y in [h * 0.4, h * 0.85]:
		part(n, box(Vector3(size.x, 0.08, 0.08)), "wood_light", Vector3(0, y, -hz))
		part(n, box(Vector3(size.x, 0.08, 0.08)), "wood_light", Vector3(0, y, hz))
		part(n, box(Vector3(0.08, 0.08, size.y)), "wood_light", Vector3(-hx, y, 0))
		part(n, box(Vector3(0.08, 0.08, size.y)), "wood_light", Vector3(hx, y, 0))
	part(n, box(Vector3(size.x * 0.9, 0.05, 0.4)), "plank", Vector3(0, h * 0.4 + 0.06, -hz + 0.2))
	return n


# ---------------------------------------------------------------- Spielfigur

## Stilisierte Figur mit benannten Gliedern für die Laufanimation
static func survivor(jacket: Color) -> Node3D:
	var n := Node3D.new()
	var jm := Palette.color_mat(jacket)
	var body := _limb(n, "Body", cyl(0.24, 0.28, 0.75, 10), jm, Vector3(0, 1.15, 0))
	var head := _limb(n, "Head", sphere(0.2, 12, 8), Palette.mat("skin"), Vector3(0, 1.72, 0))
	var hood := MeshInstance3D.new()
	hood.mesh = sphere(0.215, 12, 8, 0.3)
	hood.material_override = Palette.mat("olive")
	hood.position = Vector3(0, 0.08, -0.02)
	head.add_child(hood)
	var pack := MeshInstance3D.new()
	pack.mesh = box(Vector3(0.38, 0.45, 0.2))
	pack.material_override = Palette.mat("backpack")
	pack.position = Vector3(0, 0.05, -0.27)
	body.add_child(pack)
	for side in [-1, 1]:
		var leg := _pivot(n, "LegL" if side < 0 else "LegR", Vector3(0.12 * side, 0.8, 0))
		_child(leg, cyl(0.09, 0.08, 0.7, 7), Palette.mat("pants"), Vector3(0, -0.36, 0))
		_child(leg, box(Vector3(0.16, 0.12, 0.26)), Palette.mat("boots"), Vector3(0, -0.74, 0.04))
		var arm := _pivot(n, "ArmL" if side < 0 else "ArmR", Vector3(0.33 * side, 1.45, 0))
		_child(arm, cyl(0.07, 0.065, 0.6, 7), jm, Vector3(0, -0.3, 0))
		_child(arm, sphere(0.075, 8, 5), Palette.mat("skin"), Vector3(0, -0.63, 0))
	# Werkzeug in der rechten Hand (Axt/Spitzhacke)
	var tool := _pivot(n.get_node("ArmR"), "Tool", Vector3(0, -0.62, 0.05))
	_child(tool, cyl(0.025, 0.025, 0.8, 5), Palette.mat("wood_dark"), Vector3(0, 0, 0.3), Vector3(90, 0, 0))
	_child(tool, box(Vector3(0.05, 0.22, 0.16)), Palette.mat("metal"), Vector3(0, 0.05, 0.66))
	return n


static func _limb(parent: Node3D, name: String, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	parent.add_child(p)
	return p


static func _child(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## Alle MeshInstance3D unterhalb eines Knotens (für Transparenz und Vorschau)
static func meshes_of(root: Node) -> Array:
	var out: Array = []
	if root is GeometryInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(meshes_of(c))
	return out
