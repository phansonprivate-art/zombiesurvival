class_name BuildingSystem
extends RefCounted
## Regeln für Platzieren, Bauen, Abreißen und Reparieren. Zustandslos (nur statische Funktionen).

const SETTLEMENT_RADIUS := 24.0  ## Meter um ein bestehendes Gebäude, in denen gebaut werden darf


static func footprint(def: Dictionary, rot: int) -> Vector2i:
	var fp: Vector2i = def.get("footprint", Vector2i.ONE)
	return Vector2i(fp.y, fp.x) if rot % 2 == 1 else fp


static func cells_for(def: Dictionary, origin: Vector2i, rot: int) -> Array:
	var fp := footprint(def, rot)
	var out: Array = []
	for y in fp.y:
		for x in fp.x:
			out.append(origin + Vector2i(x, y))
	return out


## Grund, warum ein Gebäude noch gesperrt ist ("" wenn freigeschaltet)
static func lock_reason(state, def: Dictionary) -> String:
	var missing: PackedStringArray = []
	for req in def.unlock.get("buildings", []):
		if state.count_active(req) == 0:
			missing.append(state.data.building(req).get("name", req))
	if missing.is_empty():
		return ""
	return "Benötigt: " + ", ".join(missing)


## Prüft eine Platzierung. Liefert {ok: bool, reason: String}
static func check(state, def_id: String, origin: Vector2i, rot: int, check_cost: bool = true) -> Dictionary:
	var def: Dictionary = state.data.building(def_id)
	if def.is_empty():
		return {"ok": false, "reason": "Unbekanntes Gebäude"}
	var placement: Dictionary = def.placement
	if not bool(placement.get("buildable", true)):
		return {"ok": false, "reason": "Kann nicht gebaut werden"}
	var lock := lock_reason(state, def)
	if lock != "":
		return {"ok": false, "reason": lock}
	if bool(placement.get("unique", false)) and state.buildings.values().any(func(b): return b.def == def_id):
		return {"ok": false, "reason": "Nur einmal erlaubt"}
	var cells := cells_for(def, origin, rot)
	for c in cells:
		if not state.map.in_bounds(c, 2):
			return {"ok": false, "reason": "Außerhalb der Karte"}
		if state.occupancy.has(c):
			var what: String = state.occupancy[c]
			if what.begins_with("n:"):
				return {"ok": false, "reason": "Rohstoffe im Weg – erst abbauen"}
			if what == "ruin":
				return {"ok": false, "reason": "Ruine im Weg"}
			return {"ok": false, "reason": "Fläche belegt"}
	var hr: Vector2 = state.map.height_range(cells)
	if hr.y - hr.x > float(placement.get("max_slope", 1.2)):
		return {"ok": false, "reason": "Gelände zu steil"}
	# Spieler nicht einmauern
	var fp := footprint(def, rot)
	var cs: float = state.map.cell_size
	var rect := Rect2(Vector2(origin) * cs, Vector2(fp) * cs).grow(0.45)
	for p in state.players.values():
		if rect.has_point(Vector2(p.pos.x, p.pos.z)):
			return {"ok": false, "reason": "Ein Spieler steht im Weg"}
	if not in_settlement(state, rect.get_center()):
		return {"ok": false, "reason": "Außerhalb des Siedlungsgebiets"}
	if check_cost and not state.economy.can_afford(def.cost):
		var parts: PackedStringArray = []
		var miss: Dictionary = state.economy.missing(def.cost)
		for rid in miss:
			parts.append("%d %s" % [miss[rid], state.data.resource_name(rid)])
		return {"ok": false, "reason": "Es fehlen " + ", ".join(parts)}
	return {"ok": true, "reason": ""}


static func in_settlement(state, p: Vector2) -> bool:
	for b in state.buildings.values():
		var c: Vector3 = state.building_center(b)
		if Vector2(c.x, c.z).distance_to(p) <= SETTLEMENT_RADIUS:
			return true
	return false


static func place(state, player_id: int, def_id: String, origin: Vector2i, rot: int) -> Dictionary:
	var res := check(state, def_id, origin, rot)
	if not res.ok:
		return res
	var def: Dictionary = state.data.building(def_id)
	state.economy.pay(def.cost)  # Kosten werden beim Baubeginn abgezogen
	var finished: bool = float(def.build_time) <= 0.0
	var b: Dictionary = state._create_building(def_id, origin, rot, finished)
	return {"ok": true, "reason": "", "id": b.id}


## Abbrechen (im Bau: volle Erstattung) oder Abreißen (fertig: 50 % je nach Zustand)
static func remove(state, player_id: int, id: int) -> Dictionary:
	if not state.buildings.has(id):
		return {"ok": false, "reason": "Gebäude existiert nicht"}
	var b: Dictionary = state.buildings[id]
	var def: Dictionary = state.data.building(b.def)
	if not bool(def.placement.get("buildable", true)):
		return {"ok": false, "reason": "%s kann nicht abgerissen werden" % def.name}
	var factor: float = 1.0 if b.phase == "construction" else 0.5 * (b.hp / float(def.health))
	var refunded := {}
	for rid in def.cost:
		var n := int(floor(def.cost[rid] * factor))
		var added: int = state.economy.add(rid, n)
		if added > 0:
			refunded[rid] = added
	state.buildings.erase(id)
	state.free_cells("b:%d" % id)
	if b.phase == "active":
		state.recalc_capacity()
	state.emit("building_removed", {"id": id})
	var verb := "abgebrochen" if b.phase == "construction" else "abgerissen"
	state.notify("%s %s. Zurück: %s" % [def.name, verb, state.data.format_cost(refunded) if refunded.size() > 0 else "nichts"], "info")
	return {"ok": true, "reason": "", "refund": refunded}


static func repair_cost(state, b: Dictionary) -> Dictionary:
	var def: Dictionary = state.data.building(b.def)
	var missing_frac: float = 1.0 - b.hp / float(def.health)
	if missing_frac <= 0.001:
		return {}
	var base: Dictionary = def.cost if def.cost.size() > 0 else {"wood": 30, "stone": 30}
	var cost := {}
	for rid in base:
		cost[rid] = maxi(1, int(ceil(base[rid] * def.repair_cost_factor * missing_frac)))
	return cost


static func repair(state, player_id: int, id: int) -> Dictionary:
	if not state.buildings.has(id):
		return {"ok": false, "reason": "Gebäude existiert nicht"}
	var b: Dictionary = state.buildings[id]
	if b.phase != "active":
		return {"ok": false, "reason": "Noch im Bau"}
	var cost := repair_cost(state, b)
	if cost.is_empty():
		return {"ok": false, "reason": "Nicht beschädigt"}
	if not state.economy.pay(cost):
		return {"ok": false, "reason": "Zu wenig Material für die Reparatur"}
	b.hp = float(state.data.building(b.def).health)
	state.emit("building_changed", {"id": id})
	return {"ok": true, "reason": "", "cost": cost}


## Schaden an einem Gebäude (für Phase 3 vorbereitet, schon testbar)
static func damage(state, id: int, amount: float) -> void:
	if not state.buildings.has(id):
		return
	var b: Dictionary = state.buildings[id]
	b.hp -= amount
	if b.hp <= 0.0:
		var def: Dictionary = state.data.building(b.def)
		state.buildings.erase(id)
		state.free_cells("b:%d" % id)
		if b.phase == "active":
			state.recalc_capacity()
		state.emit("building_removed", {"id": id, "destroyed": true})
		state.notify("%s wurde zerstört!" % def.name, "danger")
	else:
		state.emit("building_changed", {"id": id})


static func tick_construction(state, dt: float) -> void:
	for b in state.buildings.values():
		if b.phase != "construction":
			continue
		var def: Dictionary = state.data.building(b.def)
		var step: float = dt / maxf(0.01, float(def.build_time))
		b.progress = minf(1.0, b.progress + step)
		b.hp = minf(float(def.health), b.hp + def.health * 0.9 * step)
		if b.progress >= 1.0:
			b.phase = "active"
			b.hp = maxf(b.hp, def.health * 0.999)
			b.hp = float(def.health)
			b.timer = 0.0
			state.recalc_capacity()
			state.emit("building_changed", {"id": b.id, "completed": true})
			state.notify("%s fertiggestellt." % def.name, "success")
		elif int(b.progress * 20.0) != int((b.progress - step) * 20.0):
			state.emit("building_changed", {"id": b.id})
