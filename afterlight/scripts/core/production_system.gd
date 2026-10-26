class_name ProductionSystem
extends RefCounted
## Produktionsgebäude: "harvest" (baut Rohstoffknoten im Umkreis ab) und
## "convert" (wandelt Eingangs- in Ausgangsressourcen um). Bei vollem Lager
## oder fehlenden Rohstoffen pausiert die Produktion mit passendem Status.

const RETRY := 1.0

const STATUS_TEXT := {
	"idle": "Bereit",
	"working": "Arbeitet",
	"storage_full": "Lager voll – Produktion pausiert",
	"no_source": "Keine Rohstoffe in Reichweite",
	"missing_input": "Wartet auf Rohstoffe",
	"construction": "Im Bau",
}


static func tick(state, dt: float) -> void:
	for b in state.buildings.values():
		if b.phase != "active":
			continue
		var def: Dictionary = state.data.building(b.def)
		var prod = def.production
		if prod == null:
			continue
		b.timer += dt
		if b.timer < float(prod.interval):
			continue
		var status := _run_cycle(state, b, prod)
		if status == "working":
			b.timer -= float(prod.interval)
		else:
			b.timer = float(prod.interval) - RETRY
		if status != b.status:
			b.status = status
			state.emit("building_changed", {"id": b.id})


static func _run_cycle(state, b: Dictionary, prod: Dictionary) -> String:
	match String(prod.type):
		"harvest":
			var rid := String(prod.resource)
			if state.economy.is_full(rid):
				return "storage_full"
			var node := find_source(state, b, prod)
			if node.is_empty():
				return "no_source"
			var take := mini(int(prod.amount), int(node.amount))
			var added: int = state.economy.add(rid, take)
			node.amount -= added
			if node.amount <= 0:
				state.remove_node(node.id)
			else:
				state.emit("node_changed", {"id": node.id})
			state.emit("produced", {"building": b.id, "resource": rid, "amount": added})
			return "working"
		"convert":
			var inputs: Dictionary = prod.inputs
			var outputs: Dictionary = prod.outputs
			if not state.economy.can_store_all(outputs):
				return "storage_full"
			if not state.economy.can_afford(inputs):
				return "missing_input"
			state.economy.pay(inputs)
			for rid in outputs:
				state.economy.add(rid, int(outputs[rid]))
			state.emit("produced", {"building": b.id, "resources": outputs})
			return "working"
	return "idle"


## Nächster passender Rohstoffknoten im Umkreis (über das Belegungsraster, nicht über alle Knoten)
static func find_source(state, b: Dictionary, prod: Dictionary) -> Dictionary:
	var center: Vector3 = state.building_center(b)
	var radius := float(prod.radius)
	var cs: float = state.map.cell_size
	var cc := Vector2i(floori(center.x / cs), floori(center.z / cs))
	var r_cells := int(ceil(radius / cs))
	var types: Array = prod.node_types
	var best: Dictionary = {}
	var best_d := INF
	for y in range(-r_cells, r_cells + 1):
		for x in range(-r_cells, r_cells + 1):
			var key = state.occupancy.get(cc + Vector2i(x, y))
			if key == null or not String(key).begins_with("n:"):
				continue
			var n: Dictionary = state.nodes.get(String(key).substr(2).to_int(), {})
			if n.is_empty() or not types.has(n.type) or n.amount <= 0:
				continue
			var d: float = state.node_position(n).distance_to(center)
			if d <= radius and d < best_d:
				best_d = d
				best = n
	return best


## Kurze Beschreibung der Produktion für die Oberfläche
static func describe(state, def: Dictionary) -> String:
	var prod = def.production
	if prod == null:
		return ""
	var per_min := 60.0 / float(prod.interval)
	if prod.type == "harvest":
		return "%.0f %s/min aus %s im Umkreis von %.0f m" % [
			per_min * int(prod.amount), state.data.resource_name(prod.resource),
			", ".join(prod.node_types.map(func(t): return state.data.node_type(t).get("name", t))), float(prod.radius)]
	var ins: PackedStringArray = []
	for rid in prod.inputs:
		ins.append("%d %s" % [prod.inputs[rid], state.data.resource_name(rid)])
	var outs: PackedStringArray = []
	for rid in prod.outputs:
		outs.append("%d %s" % [prod.outputs[rid], state.data.resource_name(rid)])
	return "%s → %s alle %.0f s" % [" + ".join(ins), " + ".join(outs), float(prod.interval)]
