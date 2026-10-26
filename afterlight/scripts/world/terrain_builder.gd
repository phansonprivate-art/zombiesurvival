class_name TerrainBuilder
extends RefCounted
## Baut Gelände-Mesh, Kollision, Straßenmarkierungen, Gras und Büsche aus einer WorldMap.

const COL_GRASS_A := Color("#4a6133")
const COL_GRASS_B := Color("#3a5129")
const COL_DRY := Color("#6d6a3e")
const COL_DIRT := Color("#665540")
const COL_BASE := Color("#5c4e39")
const COL_ROAD := Color("#3a3c3e")
const COL_ROAD_EDGE := Color("#55503f")
const COL_ROCK := Color("#6c665b")

const LAYER_TERRAIN := 1


## Farbe des Geländes an jedem Höhenpunkt (auch für die Übersichtskarte genutzt)
static func vertex_colors(m: WorldMap) -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize(m.res * m.res)
	var patch := FastNoiseLite.new()
	patch.seed = m.seed + 3
	patch.frequency = 0.045
	var fine := FastNoiseLite.new()
	fine.seed = m.seed + 4
	fine.frequency = 0.22
	var center := Vector2(m.cell_center(m.start_cell).x, m.cell_center(m.start_cell).z)
	var ruin_cells := {}
	for r in m.ruins:
		for y in range(-1, r.size.y + 1):
			for x in range(-1, r.size.x + 1):
				ruin_cells[r.cell + Vector2i(x, y)] = true
	for iz in m.res:
		for ix in m.res:
			var h := m.heights[iz * m.res + ix]
			var hx := m.heights[iz * m.res + mini(ix + 1, m.res - 1)] - m.heights[iz * m.res + maxi(ix - 1, 0)]
			var hz := m.heights[mini(iz + 1, m.res - 1) * m.res + ix] - m.heights[maxi(iz - 1, 0) * m.res + ix]
			var slope := Vector2(hx, hz).length() * 0.5
			var p := Vector2(ix, iz)
			var c := COL_GRASS_A.lerp(COL_GRASS_B, clampf(patch.get_noise_2d(ix, iz) * 1.4 + 0.5, 0.0, 1.0))
			var dryness := clampf(patch.get_noise_2d(ix + 300, iz - 120) * 2.0 - 0.2, 0.0, 0.7)
			c = c.lerp(COL_DRY, dryness)
			c = c.lerp(COL_ROCK, smoothstep(0.45, 1.0, slope))
			var d := p.distance_to(center)
			var base_w := (1.0 - smoothstep(7.0, 15.0, d)) * clampf(0.75 + fine.get_noise_2d(ix, iz) * 0.6, 0.0, 1.0)
			c = c.lerp(COL_BASE, base_w)
			var cell := Vector2i(floori(ix / m.cell_size), floori(iz / m.cell_size))
			if ruin_cells.has(cell):
				c = c.lerp(COL_DIRT, 0.7)
			var rd := WorldGenerator.road_distance(m, p)
			if rd < 4.6:
				c = c.lerp(COL_ROAD_EDGE, 1.0 - smoothstep(3.2, 4.6, rd))
				c = c.lerp(COL_ROAD, 1.0 - smoothstep(2.3, 3.0, rd))
			c = c.darkened(fine.get_noise_2d(ix * 2.0, iz * 2.0) * 0.06 + 0.02)
			c = c.lightened(clampf((h - 4.0) * 0.015, 0.0, 0.08))
			cols[iz * m.res + ix] = c
	return cols


static func build(m: WorldMap, colors: PackedColorArray) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	root.add_child(_mesh(m, colors))
	root.add_child(_collision(m))
	root.add_child(_road_marks(m))
	return root


static func _mesh(m: WorldMap, colors: PackedColorArray) -> MeshInstance3D:
	var n := m.res
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(ix, m.heights[i], iz)
			var hl := m.heights[iz * n + maxi(ix - 1, 0)]
			var hr := m.heights[iz * n + mini(ix + 1, n - 1)]
			var hd := m.heights[maxi(iz - 1, 0) * n + ix]
			var hu := m.heights[mini(iz + 1, n - 1) * n + ix]
			normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
			uvs[i] = Vector2(ix, iz) * 0.25
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.97
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.86, 0.86))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


static func _collision(m: WorldMap) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = LAYER_TERRAIN
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = m.res
	shape.map_depth = m.res
	shape.map_data = m.heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# HeightMapShape3D ist um den Ursprung zentriert, 1 m Abstand
	body.position = Vector3((m.res - 1) * 0.5, 0, (m.res - 1) * 0.5)
	return body


static func _road_marks(m: WorldMap) -> Node3D:
	var root := Node3D.new()
	root.name = "RoadMarks"
	var mesh := ModelFactory.box(Vector3(0.18, 0.04, 1.6))
	for road in m.roads:
		for i in range(0, road.size() - 1):
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var mid := (a + b) * 0.5
			if mid.x < 3 or mid.y < 3 or mid.x > m.size_m() - 3 or mid.y > m.size_m() - 3:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = Palette.mat("asphalt_line")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(mid.x, m.height_at(mid.x, mid.y) + 0.04, mid.y)
			mi.rotation.y = atan2(b.x - a.x, b.y - a.y)
			root.add_child(mi)
	return root


## Grasbüschel und Büsche als MultiMesh (sehr viele Instanzen, wenige Draw-Calls)
static func build_vegetation(m: WorldMap, colors: PackedColorArray, blocked: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Vegetation"
	var rng := RandomNumberGenerator.new()
	rng.seed = m.seed + 55
	var grass_t: Array[Transform3D] = []
	var grass_dry: Array[float] = []
	var bush_t: Array[Transform3D] = []
	var size := m.size_m()
	var center := Vector2(m.cell_center(m.start_cell).x, m.cell_center(m.start_cell).z)
	for i in 26000:
		var x := rng.randf_range(1.0, size - 1.0)
		var z := rng.randf_range(1.0, size - 1.0)
		var col := colors[int(z) * m.res + int(x)]
		var cell := Vector2i(floori(x / m.cell_size), floori(z / m.cell_size))
		if blocked.has(cell) or m.road_cells.has(cell):
			continue
		# nur auf grünem Boden (nicht Straße, Fels, Lagerplatz)
		if col.g < col.r * 1.05 or col.g < 0.27:
			continue
		var dc := Vector2(x, z).distance_to(center)
		if dc < 9.0:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), Vector3(x, m.height_at(x, z) - 0.03, z))
		if rng.randf() < 0.025 and dc > 16.0:
			bush_t.append(t.scaled_local(Vector3(1.0, rng.randf_range(0.6, 0.9), 1.0)))
		else:
			grass_t.append(t)
			grass_dry.append(clampf((col.r - 0.25) * 3.0, 0.0, 1.0))
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.use_custom_data = true
	grass.mesh = _grass_mesh()
	grass.instance_count = grass_t.size()
	for i in grass_t.size():
		grass.set_instance_transform(i, grass_t[i])
		grass.set_instance_custom_data(i, Color(grass_dry[i], 0, 0, 0))
	var gmi := MultiMeshInstance3D.new()
	gmi.name = "Grass"
	gmi.multimesh = grass
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/grass.gdshader")
	gmi.material_override = gmat
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gmi)

	var bushes := MultiMesh.new()
	bushes.transform_format = MultiMesh.TRANSFORM_3D
	bushes.mesh = ModelFactory.sphere(0.6, 8, 5)
	bushes.instance_count = bush_t.size()
	for i in bush_t.size():
		bushes.set_instance_transform(i, bush_t[i].translated_local(Vector3(0, 0.25, 0)))
	var bmi := MultiMeshInstance3D.new()
	bmi.name = "Bushes"
	bmi.multimesh = bushes
	bmi.material_override = Palette.mat("leaf2")
	root.add_child(bmi)
	return root


static func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 6
	for i in blades:
		var a := TAU * i / blades + 0.4 * i
		var off := Vector3(cos(a), 0, sin(a)) * 0.08 * (i % 3)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var h := 0.32 + 0.1 * ((i * 7) % 3)
		var lean := Vector3(cos(a), 0, sin(a)) * 0.12
		st.set_uv(Vector2(0, 0))
		st.add_vertex(off - side)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(off + side)
		st.set_uv(Vector2(0.5, 1))
		st.add_vertex(off + lean + Vector3(0, h, 0))
	st.generate_normals()
	return st.commit()


## Bild für die Übersichtskarte (1 Pixel pro Meter)
static func map_image(m: WorldMap, colors: PackedColorArray) -> Image:
	var img := Image.create(m.res, m.res, false, Image.FORMAT_RGB8)
	for iz in m.res:
		for ix in m.res:
			var c := colors[iz * m.res + ix]
			var shade := clampf(0.85 + (m.height_at(ix, iz) - m.height_at(ix - 1, iz - 1)) * 0.25, 0.6, 1.2)
			img.set_pixel(ix, iz, Color(c.r * shade, c.g * shade, c.b * shade))
	return img
