class_name WorldGenerator
extends RefCounted
## Erzeugt eine kompakte, reproduzierbare Karte aus einem Seed:
## flaches Basisplateau, Hügel am Rand, Straßen, Ruinen, Wälder, Felsen, Erz, Wracks, Kisten.
## Gleiche Reihenfolge der Zufallsaufrufe = gleiche Welt für gleichen Seed.


static func generate(seed: int, data) -> WorldMap:
	var m := WorldMap.new()
	m.seed = seed
	m.cells = int(data.world.map.size_cells)
	m.cell_size = float(data.world.map.cell_size)
	m.base_radius = float(data.world.map.base_radius)
	var sc: Array = data.world.map.start_cell
	m.start_cell = Vector2i(int(sc[0]), int(sc[1]))
	m.res = int(m.cells * m.cell_size) + 1

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_make_roads(m, rng)
	_make_heights(m, seed)
	_mark_road_cells(m)

	var occupied := {}
	# Platz für das zentrale Lager (3x3) und einen freien Hof drumherum
	var reserve := int(ceil(9.0 / m.cell_size))
	for y in range(-reserve, reserve + 1):
		for x in range(-reserve, reserve + 1):
			occupied[m.start_cell + Vector2i(x, y)] = "base"

	_place_ruins(m, rng, occupied)
	_place_wrecks(m, rng, occupied)
	_place_nature(m, rng, occupied, seed)
	_guarantee_start_resources(m, rng, occupied)
	return m


static func _make_roads(m: WorldMap, rng: RandomNumberGenerator) -> void:
	var size := m.size_m()
	var c := size * 0.5
	# Straße 1: von West nach Ost, südlich oder nördlich an der Basis vorbei
	var off_a := rng.randf_range(24.0, 30.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var phase := rng.randf() * TAU
	var road_a := PackedVector2Array()
	for i in range(0, int(size) + 4, 4):
		road_a.append(Vector2(i, c + off_a + sin(i * 0.035 + phase) * 6.0))
	m.roads.append(road_a)
	# Straße 2: von Nord nach Süd, leicht schräg, immer auf einer Seite der Basis
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var x0 := c + side * rng.randf_range(26.0, 36.0)
	var x1 := c + side * rng.randf_range(24.0, 40.0)
	var road_b := PackedVector2Array()
	for i in range(0, int(size) + 4, 4):
		var t := float(i) / size
		road_b.append(Vector2(lerpf(x0, x1, t) + sin(i * 0.05 + phase) * 4.0, i))
	m.roads.append(road_b)


static func road_distance(m: WorldMap, p: Vector2) -> float:
	var best := INF
	for road in m.roads:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


static func _make_heights(m: WorldMap, seed: int) -> void:
	var hills := FastNoiseLite.new()
	hills.seed = seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 4
	hills.frequency = 0.016
	var detail := FastNoiseLite.new()
	detail.seed = seed + 1
	detail.frequency = 0.09
	var size := m.size_m()
	var center := Vector2((m.start_cell.x + 0.5) * m.cell_size, (m.start_cell.y + 0.5) * m.cell_size)
	m.heights.resize(m.res * m.res)
	for iz in m.res:
		for ix in m.res:
			var p := Vector2(ix, iz)
			var h := hills.get_noise_2d(ix, iz) * 7.0 + 2.0
			h += detail.get_noise_2d(ix, iz) * 0.35
			var d := p.distance_to(center)
			var f := smoothstep(m.base_radius * 0.55, m.base_radius * 1.6, d)
			h = lerpf(1.0 + detail.get_noise_2d(ix, iz) * 0.15, h, f)
			var edge := minf(minf(ix, iz), minf(size - ix, size - iz))
			h += (1.0 - smoothstep(0.0, 20.0, edge)) * 8.0
			var rd := road_distance(m, p)
			var w := 1.0 - smoothstep(3.0, 8.0, rd)
			h = lerpf(h, h * 0.55 + 0.4, w)
			m.heights[iz * m.res + ix] = h


static func _mark_road_cells(m: WorldMap) -> void:
	for y in m.cells:
		for x in m.cells:
			var p := Vector2((x + 0.5) * m.cell_size, (y + 0.5) * m.cell_size)
			if road_distance(m, p) < 3.2:
				m.road_cells[Vector2i(x, y)] = true


static func _free(m: WorldMap, occupied: Dictionary, cell: Vector2i, margin: int = 2) -> bool:
	return m.in_bounds(cell, margin) and not occupied.has(cell) and not m.road_cells.has(cell)


static func _place_ruins(m: WorldMap, rng: RandomNumberGenerator, occupied: Dictionary) -> void:
	var center := Vector2((m.start_cell.x + 0.5) * m.cell_size, (m.start_cell.y + 0.5) * m.cell_size)
	var wanted := rng.randi_range(5, 7)
	var tries := 0
	while m.ruins.size() < wanted and tries < 400:
		tries += 1
		var road: PackedVector2Array = m.roads[rng.randi() % m.roads.size()]
		var i := rng.randi_range(1, road.size() - 2)
		var dir := (road[i + 1] - road[i - 1]).normalized()
		var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p := road[i] + side * rng.randf_range(7.0, 10.0)
		var dist := p.distance_to(center)
		if dist < 30.0 or dist > 64.0:
			continue
		var size := Vector2i(rng.randi_range(2, 4), rng.randi_range(2, 3))
		var origin := Vector2i(floori(p.x / m.cell_size), floori(p.y / m.cell_size))
		var ok := true
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				if not _free(m, occupied, origin + Vector2i(x, y), 3):
					ok = false
		if not ok:
			continue
		for y in size.y:
			for x in size.x:
				occupied[origin + Vector2i(x, y)] = "ruin"
		var ruin := {"cell": origin, "size": size, "kind": rng.randi_range(0, 2), "rot": 0.0}
		m.ruins.append(ruin)
		# Versorgungskisten neben der Ruine
		for k in rng.randi_range(1, 2):
			var c := origin + Vector2i(rng.randi_range(-1, size.x), [-1, size.y][rng.randi() % 2])
			if _free(m, occupied, c, 2):
				_add_node(m, rng, occupied, "crate", c)


static func _place_wrecks(m: WorldMap, rng: RandomNumberGenerator, occupied: Dictionary) -> void:
	for road in m.roads:
		for i in range(2, road.size() - 2, 4):
			if rng.randf() > 0.45:
				continue
			var dir: Vector2 = (road[i + 1] - road[i - 1]).normalized()
			var side := Vector2(-dir.y, dir.x) * rng.randf_range(-2.5, 2.5)
			var p: Vector2 = road[i] + side
			var c := Vector2i(floori(p.x / m.cell_size), floori(p.y / m.cell_size))
			if not m.in_bounds(c, 3) or occupied.has(c):
				continue
			var spawn := _add_node(m, rng, occupied, "wreck", c)
			spawn.rot = atan2(dir.x, dir.y) + rng.randf_range(-0.6, 0.6)


static func _place_nature(m: WorldMap, rng: RandomNumberGenerator, occupied: Dictionary, seed: int) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = seed + 7
	forest.frequency = 0.03
	var rocks := FastNoiseLite.new()
	rocks.seed = seed + 11
	rocks.frequency = 0.06
	var center := Vector2(m.start_cell.x + 0.5, m.start_cell.y + 0.5) * m.cell_size
	# Erzadern als Cluster, eine davon nah an der Basis
	var ore_centers: Array[Vector2] = []
	for k in 6:
		var a := rng.randf() * TAU
		var d := rng.randf_range(24.0, 30.0) if k == 0 else rng.randf_range(32.0, 62.0)
		ore_centers.append(center + Vector2(cos(a), sin(a)) * d)
	for oc in ore_centers:
		for k in rng.randi_range(3, 5):
			var p: Vector2 = oc + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			var c := Vector2i(floori(p.x / m.cell_size), floori(p.y / m.cell_size))
			if _free(m, occupied, c):
				_add_node(m, rng, occupied, "ore", c)
	for y in m.cells:
		for x in m.cells:
			var c := Vector2i(x, y)
			if not _free(m, occupied, c, 1):
				continue
			var p := Vector2(x + 0.5, y + 0.5) * m.cell_size
			if p.distance_to(center) < 16.0:
				continue
			var f := forest.get_noise_2d(x, y)
			var r := rocks.get_noise_2d(x, y)
			var roll := rng.randf()
			if r > 0.42 and roll < 0.35:
				_add_node(m, rng, occupied, "rock", c)
			elif f > 0.12 and roll < 0.55:
				_add_node(m, rng, occupied, "tree", c)
			elif f > -0.12 and roll < 0.07:
				_add_node(m, rng, occupied, "tree", c)
			elif roll < 0.012:
				_add_node(m, rng, occupied, "tree", c)
			elif roll > 0.994:
				_add_node(m, rng, occupied, "rock", c)


static func _guarantee_start_resources(m: WorldMap, rng: RandomNumberGenerator, occupied: Dictionary) -> void:
	var center := Vector2(m.start_cell.x + 0.5, m.start_cell.y + 0.5) * m.cell_size
	var need := {"tree": 10, "rock": 4}
	for t in need:
		var have := 0
		for s in m.node_spawns:
			var p := Vector2(s.cell.x + 0.5, s.cell.y + 0.5) * m.cell_size
			if s.type == t and p.distance_to(center) < 26.0:
				have += 1
		var tries := 0
		while have < need[t] and tries < 300:
			tries += 1
			var a := rng.randf() * TAU
			var d := rng.randf_range(13.0, 24.0)
			var p := center + Vector2(cos(a), sin(a)) * d
			var c := Vector2i(floori(p.x / m.cell_size), floori(p.y / m.cell_size))
			if _free(m, occupied, c):
				_add_node(m, rng, occupied, t, c)
				have += 1


static func _add_node(m: WorldMap, rng: RandomNumberGenerator, occupied: Dictionary, type: String, cell: Vector2i) -> Dictionary:
	var spawn := {
		"type": type,
		"cell": cell,
		"offset": Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)),
		"scale": rng.randf_range(0.85, 1.25),
		"rot": rng.randf() * TAU,
		"variant": rng.randi_range(0, 2),
	}
	occupied[cell] = type
	m.node_spawns.append(spawn)
	return spawn
