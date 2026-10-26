extends Node
## Lädt alle Spieldefinitionen aus res://data/*.json und prüft sie.
## Einzige Quelle für Gebäude-, Ressourcen- und Weltwerte.

const RESOURCES_PATH := "res://data/resources.json"
const BUILDINGS_PATH := "res://data/buildings.json"
const WORLD_PATH := "res://data/world.json"

var resources: Dictionary = {}        ## id -> Definition
var resource_order: Array[String] = []
var buildings: Dictionary = {}        ## id -> Definition
var building_order: Array[String] = []
var categories: Array = []            ## [{id, name}]
var world: Dictionary = {}
var errors: PackedStringArray = []


func _init() -> void:
	reload()


func reload() -> void:
	errors.clear()
	resources.clear()
	resource_order.clear()
	buildings.clear()
	building_order.clear()
	var res_doc := _load_json(RESOURCES_PATH)
	for r in res_doc.get("resources", []):
		var id := String(r.get("id", ""))
		if id.is_empty() or resources.has(id):
			errors.append("Ressource ohne/mit doppelter ID: %s" % id)
			continue
		var def := {
			"id": id,
			"name": String(r.get("name", id)),
			"unit": String(r.get("unit", "")),
			"category": String(r.get("category", "raw")),
			"base_capacity": int(r.get("base_capacity", 100)),
			"start": int(r.get("start", 0)),
			"hud": bool(r.get("hud", true)),
			"color": Color.html(String(r.get("color", "#ffffff"))),
			"storage": String(r.get("storage", "general")),
			"transport": String(r.get("transport", "shared")),
			"note": String(r.get("note", "")),
		}
		resources[id] = def
		resource_order.append(id)

	var b_doc := _load_json(BUILDINGS_PATH)
	categories = b_doc.get("categories", [])
	var category_ids := categories.map(func(c): return String(c.get("id", "")))
	for b in b_doc.get("buildings", []):
		var def := _normalize_building(b)
		var id: String = def.id
		if id.is_empty() or buildings.has(id):
			errors.append("Gebäude ohne/mit doppelter ID: %s" % id)
			continue
		if not category_ids.has(def.category):
			errors.append("Gebäude %s: unbekannte Kategorie %s" % [id, def.category])
		for rid in def.cost:
			if not resources.has(rid):
				errors.append("Gebäude %s: unbekannte Ressource in Kosten: %s" % [id, rid])
		var prod = def.production
		if prod != null:
			for key in ["inputs", "outputs"]:
				for rid in prod.get(key, {}):
					if not resources.has(rid):
						errors.append("Gebäude %s: unbekannte Ressource in Produktion: %s" % [id, rid])
			if prod.get("type") == "harvest" and not resources.has(String(prod.get("resource", ""))):
				errors.append("Gebäude %s: unbekannte Ernte-Ressource" % id)
		buildings[id] = def
		building_order.append(id)
	for id in buildings:
		for req in buildings[id].unlock.get("buildings", []):
			if not buildings.has(req):
				errors.append("Gebäude %s: Freischaltung verweist auf unbekanntes Gebäude %s" % [id, req])

	world = _load_json(WORLD_PATH)
	for t in world.get("node_types", {}):
		var nt: Dictionary = world.node_types[t]
		var res_id := String(nt.get("resource", ""))
		if res_id != "loot" and not resources.has(res_id):
			errors.append("Knotentyp %s: unbekannte Ressource %s" % [t, res_id])
	for e in errors:
		push_error("GameData: " + e)


func _normalize_building(b: Dictionary) -> Dictionary:
	var fp: Array = b.get("footprint", [1, 1])
	var cost := {}
	for k in b.get("cost", {}):
		cost[String(k)] = int(b.cost[k])
	var prod = b.get("production")
	if prod != null:
		prod = prod.duplicate(true)
		for key in ["inputs", "outputs"]:
			if prod.has(key):
				var d := {}
				for k in prod[key]:
					d[String(k)] = int(prod[key][k])
				prod[key] = d
		prod["interval"] = float(prod.get("interval", 5.0))
		if prod.has("amount"):
			prod["amount"] = int(prod.amount)
		if prod.has("radius"):
			prod["radius"] = float(prod.radius)
	return {
		"id": String(b.get("id", "")),
		"name": String(b.get("name", "")),
		"category": String(b.get("category", "")),
		"description": String(b.get("description", "")),
		"model": String(b.get("model", b.get("id", ""))),
		"footprint": Vector2i(int(fp[0]), int(fp[1])),
		"cost": cost,
		"build_time": float(b.get("build_time", 5.0)),
		"health": int(b.get("health", 100)),
		"repair_cost_factor": float(b.get("repair_cost_factor", 0.5)),
		"placement": b.get("placement", {}),
		"storage": b.get("storage", {}),
		"capacity_bonus": int(b.get("storage", {}).get("capacity_bonus", 0)),
		"production": prod,
		"power": float(b.get("power", 0)),
		"passable_for_players": bool(b.get("passable_for_players", false)),
		"unlock": b.get("unlock", {}),
	}


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Datei fehlt: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("Ungültiges JSON: " + path)
		return {}
	return parsed


func building(id: String) -> Dictionary:
	return buildings.get(id, {})


func resource_name(id: String) -> String:
	return resources[id].name if resources.has(id) else id


func node_type(t: String) -> Dictionary:
	return world.get("node_types", {}).get(t, {})


func cell_size() -> float:
	return float(world.map.cell_size)


func map_cells() -> int:
	return int(world.map.size_cells)


func day_cycle() -> Dictionary:
	return world.day_cycle


func player_cfg() -> Dictionary:
	return world.player


## "12 Holz, 5 Stein"
func format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for rid in cost:
		parts.append("%d %s" % [cost[rid], resource_name(rid)])
	return ", ".join(parts) if parts.size() > 0 else "kostenlos"
