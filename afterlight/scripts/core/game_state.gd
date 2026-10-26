class_name GameState
extends RefCounted
## Der komplette, autoritative Spielzustand einer Welt – ohne Szenenknoten.
## Alle Änderungen laufen über apply_action() (Spieleraktionen) und tick() (Zeit).
## Jede Änderung erzeugt ein Ereignis in `events`, das die Session an die
## Darstellung (und später an die Clients) weitergibt.

const SCHEMA_VERSION := 1

var data
var map: WorldMap
var world_name: String = ""
var seed: int = 0
var created_unix: int = 0
var play_time: float = 0.0
var clock := WorldClock.new()
var economy: Economy
var rng := RandomNumberGenerator.new()

var buildings: Dictionary = {}   ## id -> {id, def, cell, rot, hp, phase, progress, timer, status}
var nodes: Dictionary = {}       ## id -> {id, type, cell, amount, max, offset, scale, rot, variant}
var players: Dictionary = {}     ## id -> {id, name, pos, hp, last_gather}
var occupancy: Dictionary = {}   ## Vector2i -> "b:<id>" | "n:<id>" | "ruin"
var next_id: int = 1
var events: Array = []


static func create_new(game_data, name: String, world_seed: int) -> GameState:
	var s := GameState.new()
	s.data = game_data
	s.world_name = name
	s.seed = world_seed
	s.created_unix = int(Time.get_unix_time_from_system())
	s._setup_world()
	s.clock.configure(game_data.day_cycle())
	for id in game_data.resource_order:
		s.economy.stock[id] = int(game_data.resources[id].start)
	s.rng.seed = world_seed + 12345
	# Zentrales Lager mittig auf dem Plateau
	var hq_cell: Vector2i = s.map.start_cell - Vector2i(1, 1)
	s._create_building("hq", hq_cell, 0, true)
	s.events.clear()
	return s


func _setup_world() -> void:
	economy = Economy.new(data)
	map = WorldGenerator.generate(seed, data)
	for r in map.ruins:
		for y in r.size.y:
			for x in r.size.x:
				occupancy[r.cell + Vector2i(x, y)] = "ruin"
	var amount_rng := RandomNumberGenerator.new()
	amount_rng.seed = seed + 99
	var i := 0
	for sp in map.node_spawns:
		i += 1
		var nt: Dictionary = data.node_type(sp.type)
		var rng_range: Array = nt.get("amount", [10, 10])
		var amount := amount_rng.randi_range(int(rng_range[0]), int(rng_range[1]))
		nodes[i] = {
			"id": i, "type": sp.type, "cell": sp.cell, "amount": amount, "max": amount,
			"offset": sp.offset, "scale": sp.scale, "rot": sp.rot, "variant": sp.variant,
		}
		occupancy[sp.cell] = "n:%d" % i


# ---------------------------------------------------------------- Ereignisse

func emit(type: String, payload: Dictionary = {}) -> void:
	var ev := payload.duplicate()
	ev["type"] = type
	events.append(ev)


func notify(text: String, kind: String = "info") -> void:
	emit("notify", {"text": text, "kind": kind})


func take_events() -> Array:
	if economy.dirty:
		economy.dirty = false
		emit("stock_changed")
	var out := events
	events = []
	return out


# ---------------------------------------------------------------- Spieler

func add_player(id: int, name: String) -> Dictionary:
	var p := {
		"id": id, "name": name, "pos": map.center() + Vector3(0, 0, 5.0),
		"hp": float(data.player_cfg().health), "last_gather": -100.0,
	}
	if players.has(id):
		p = players[id]
		p.name = name
	players[id] = p
	emit("player_joined", {"id": id})
	return p


func remove_player(id: int) -> void:
	if players.erase(id):
		emit("player_left", {"id": id})


func set_player_position(id: int, pos: Vector3) -> void:
	if players.has(id):
		players[id].pos = pos


# ---------------------------------------------------------------- Aktionen

## Einziger Weg, mit dem Spieler den Zustand verändern. Liefert {ok, reason, ...}.
func apply_action(player_id: int, action: Dictionary) -> Dictionary:
	if not players.has(player_id):
		return {"ok": false, "reason": "Unbekannter Spieler"}
	match String(action.get("type", "")):
		"build":
			var c = action.get("cell", [0, 0])
			return BuildingSystem.place(self, player_id, String(action.get("def", "")), Vector2i(int(c[0]), int(c[1])), int(action.get("rot", 0)))
		"cancel", "demolish":
			return BuildingSystem.remove(self, player_id, int(action.get("id", -1)))
		"repair":
			return BuildingSystem.repair(self, player_id, int(action.get("id", -1)))
		"gather":
			return GatherSystem.gather(self, player_id, int(action.get("node", -1)))
	return {"ok": false, "reason": "Unbekannte Aktion"}


# ---------------------------------------------------------------- Zeit

func tick(dt: float) -> void:
	play_time += dt
	for ev in clock.advance(dt):
		events.append(ev)
		if ev.type == "night_started":
			notify("Die Nacht bricht herein (Nacht %d)." % ev.day, "warning")
		else:
			notify("Tag %d beginnt." % ev.day, "info")
	BuildingSystem.tick_construction(self, dt)
	ProductionSystem.tick(self, dt)


# ---------------------------------------------------------------- Hilfen

func _create_building(def_id: String, cell: Vector2i, rot: int, finished: bool) -> Dictionary:
	var def: Dictionary = data.building(def_id)
	var id := next_id
	next_id += 1
	var b := {
		"id": id, "def": def_id, "cell": cell, "rot": rot % 4,
		"hp": float(def.health) if finished else maxf(1.0, def.health * 0.1),
		"phase": "active" if finished else "construction",
		"progress": 1.0 if finished else 0.0,
		"timer": 0.0,
		"status": "idle",
	}
	buildings[id] = b
	for c in BuildingSystem.cells_for(def, cell, rot):
		occupancy[c] = "b:%d" % id
	if finished:
		recalc_capacity()
	emit("building_added", {"id": id})
	return b


func free_cells(key: String) -> void:
	for c in occupancy.keys():
		if occupancy[c] == key:
			occupancy.erase(c)


func recalc_capacity() -> void:
	var bonus := 0
	for b in buildings.values():
		if b.phase == "active":
			bonus += int(data.building(b.def).capacity_bonus)
	economy.capacity_bonus = bonus
	economy.dirty = true


func building_center(b: Dictionary) -> Vector3:
	var def: Dictionary = data.building(b.def)
	var fp := BuildingSystem.footprint(def, b.rot)
	var x: float = (b.cell.x + fp.x * 0.5) * map.cell_size
	var z: float = (b.cell.y + fp.y * 0.5) * map.cell_size
	return Vector3(x, map.height_at(x, z), z)


func node_position(n: Dictionary) -> Vector3:
	var x: float = (n.cell.x + 0.5) * map.cell_size + n.offset.x
	var z: float = (n.cell.y + 0.5) * map.cell_size + n.offset.y
	return Vector3(x, map.height_at(x, z), z)


func count_active(def_id: String) -> int:
	var n := 0
	for b in buildings.values():
		if b.def == def_id and b.phase == "active":
			n += 1
	return n


func remove_node(id: int) -> void:
	if nodes.has(id):
		nodes[id].amount = 0
		free_cells("n:%d" % id)
		nodes.erase(id)
		emit("node_removed", {"id": id})


# ---------------------------------------------------------------- Speichern

func to_dict() -> Dictionary:
	var b_list: Array = []
	for b in buildings.values():
		b_list.append({
			"id": b.id, "def": b.def, "cell": [b.cell.x, b.cell.y], "rot": b.rot,
			"hp": b.hp, "phase": b.phase, "progress": b.progress, "timer": b.timer, "status": b.status,
		})
	var amounts: Array = []
	for i in range(1, map.node_spawns.size() + 1):
		amounts.append(int(nodes[i].amount) if nodes.has(i) else 0)
	var p_list: Array = []
	for p in players.values():
		p_list.append({"id": p.id, "name": p.name, "pos": [p.pos.x, p.pos.y, p.pos.z], "hp": p.hp})
	return {
		"schema": SCHEMA_VERSION,
		"world_name": world_name,
		"seed": seed,
		"created_unix": created_unix,
		"play_time": play_time,
		"clock": clock.to_dict(),
		"stock": economy.to_dict(),
		"next_id": next_id,
		"rng_state": str(rng.state),
		"buildings": b_list,
		"node_amounts": amounts,
		"players": p_list,
	}


static func from_dict(game_data, d: Dictionary) -> GameState:
	if int(d.get("schema", -1)) != SCHEMA_VERSION:
		push_error("Spielstand hat Schema %s, erwartet %d" % [d.get("schema"), SCHEMA_VERSION])
		return null
	var s := GameState.new()
	s.data = game_data
	s.world_name = String(d.get("world_name", "Welt"))
	s.seed = int(d.get("seed", 0))
	s.created_unix = int(d.get("created_unix", 0))
	s.play_time = float(d.get("play_time", 0.0))
	s._setup_world()
	s.clock.configure(game_data.day_cycle())
	s.clock.load_dict(d.get("clock", {}))
	s.economy.load_dict(d.get("stock", {}))
	s.rng.seed = s.seed + 12345
	if d.has("rng_state"):
		s.rng.state = String(d.rng_state).to_int()
	var amounts: Array = d.get("node_amounts", [])
	for i in amounts.size():
		var id := i + 1
		if not s.nodes.has(id):
			continue
		var a := int(amounts[i])
		if a <= 0:
			s.free_cells("n:%d" % id)
			s.nodes.erase(id)
		else:
			s.nodes[id].amount = a
	for bd in d.get("buildings", []):
		var def_id := String(bd.get("def", ""))
		if game_data.building(def_id).is_empty():
			push_warning("Unbekanntes Gebäude im Spielstand übersprungen: " + def_id)
			continue
		var id := int(bd.id)
		var b := {
			"id": id, "def": def_id, "cell": Vector2i(int(bd.cell[0]), int(bd.cell[1])), "rot": int(bd.rot),
			"hp": float(bd.hp), "phase": String(bd.phase), "progress": float(bd.progress),
			"timer": float(bd.get("timer", 0.0)), "status": String(bd.get("status", "idle")),
		}
		s.buildings[id] = b
		for c in BuildingSystem.cells_for(game_data.building(def_id), b.cell, b.rot):
			s.occupancy[c] = "b:%d" % id
	s.next_id = int(d.get("next_id", 1))
	for pd in d.get("players", []):
		s.players[int(pd.id)] = {
			"id": int(pd.id), "name": String(pd.name),
			"pos": Vector3(float(pd.pos[0]), float(pd.pos[1]), float(pd.pos[2])),
			"hp": float(pd.hp), "last_gather": -100.0,
		}
	s.recalc_capacity()
	s.events.clear()
	s.economy.dirty = false
	return s
