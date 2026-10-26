extends RefCounted
## Tests der Spiellogik ohne Szenen: Daten, Weltgenerierung, Bauen, Produktion, Sammeln, Zeit, Speichern.

const SEED := 4242


func _new_state(seed := SEED) -> GameState:
	var gd = load("res://scripts/core/game_data.gd").new()
	var s := GameState.create_new(gd, "Testwelt", seed)
	s.add_player(1, "Anna")
	s.events.clear()
	return s


## Freie, flache Stelle in der Nähe der Basis für ein Gebäude finden
func _find_spot(s: GameState, def_id: String, rot := 0) -> Vector2i:
	var start := s.map.start_cell
	for r in range(3, 12):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var c := start + Vector2i(x, y)
				if BuildingSystem.check(s, def_id, c, rot, false).ok:
					return c
	return Vector2i(-1, -1)


func _finish_construction(s: GameState) -> void:
	for i in 60 * 30:
		s.tick(1.0 / 60.0)


func test_data_valid(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	t.eq(gd.errors.size(), 0, "Datendefinitionen fehlerfrei: %s" % str(gd.errors))
	t.check(gd.resources.size() >= 8, "mindestens 8 Ressourcen")
	t.check(gd.buildings.size() >= 8, "mindestens 8 Gebäude")
	for id in gd.buildings:
		var b: Dictionary = gd.buildings[id]
		for key in ["name", "category", "model", "footprint", "cost", "build_time", "health", "repair_cost_factor", "placement", "power", "unlock"]:
			t.check(b.has(key), "%s hat Feld %s" % [id, key])


func test_world_is_reproducible(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	var t0 := Time.get_ticks_msec()
	var a := WorldGenerator.generate(SEED, gd)
	var ms := Time.get_ticks_msec() - t0
	var b := WorldGenerator.generate(SEED, gd)
	var c := WorldGenerator.generate(SEED + 1, gd)
	t.eq(a.checksum(), b.checksum(), "gleicher Seed -> gleiche Welt")
	t.check(a.checksum() != c.checksum(), "anderer Seed -> andere Welt")
	print("       Weltgenerierung: %d ms, %d Knoten, %d Ruinen" % [ms, a.node_spawns.size(), a.ruins.size()])
	var counts := {}
	for sp in a.node_spawns:
		counts[sp.type] = counts.get(sp.type, 0) + 1
	t.check(counts.get("tree", 0) > 150, "genug Bäume: %s" % str(counts))
	t.check(counts.get("rock", 0) > 15, "genug Felsen: %s" % str(counts))
	t.check(counts.get("ore", 0) >= 8, "genug Erz: %s" % str(counts))
	t.check(counts.get("wreck", 0) >= 3, "Wracks vorhanden: %s" % str(counts))
	t.check(counts.get("crate", 0) >= 3, "Kisten vorhanden: %s" % str(counts))
	t.check(a.ruins.size() >= 4, "Ruinen vorhanden")
	t.check(a.roads.size() == 2, "zwei Straßen")
	# Gelände ist nicht flach
	var lo := INF
	var hi := -INF
	for h in a.heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	t.check(hi - lo > 6.0, "Höhenunterschiede vorhanden (%.1f m)" % (hi - lo))


func test_start_state(t) -> void:
	var s := _new_state()
	t.eq(s.buildings.size(), 1, "zentrales Lager steht")
	var hq: Dictionary = s.buildings.values()[0]
	t.eq(hq.def, "hq", "erstes Gebäude ist das Lager")
	t.eq(hq.phase, "active", "Lager ist fertig")
	t.eq(s.economy.amount("wood"), 80, "Startholz")
	var near_trees := 0
	var center := s.map.center()
	for n in s.nodes.values():
		if n.type == "tree" and s.node_position(n).distance_to(center) < 26.0:
			near_trees += 1
	t.check(near_trees >= 10, "Bäume in Basisnähe: %d" % near_trees)


func test_build_place_and_complete(t) -> void:
	var s := _new_state()
	var spot := _find_spot(s, "storage")
	t.check(spot.x >= 0, "Bauplatz gefunden")
	var wood := s.economy.amount("wood")
	var r := s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot.x, spot.y], "rot": 0})
	t.check(r.ok, "Lager gebaut: " + String(r.reason))
	t.eq(s.economy.amount("wood"), wood - 40, "Kosten sofort abgezogen")
	var b: Dictionary = s.buildings[r.id]
	t.eq(b.phase, "construction", "zuerst im Bau")
	var cap_before := s.economy.capacity("wood")
	_finish_construction(s)
	t.eq(b.phase, "active", "nach Bauzeit fertig")
	t.eq(s.economy.capacity("wood"), cap_before + 200, "Lager erhöht Kapazität")
	# gleiche Stelle ist jetzt belegt
	var r2 := s.apply_action(1, {"type": "build", "def": "wall_wood", "cell": [spot.x, spot.y], "rot": 0})
	t.check(not r2.ok, "Überschneidung abgelehnt")
	t.eq(r2.reason, "Fläche belegt", "Grund für Ablehnung")


func test_build_rejections(t) -> void:
	var s := _new_state()
	var r := s.apply_action(1, {"type": "build", "def": "storage", "cell": [1, 1], "rot": 0})
	t.check(not r.ok, "außerhalb abgelehnt")
	var hq: Dictionary = s.buildings.values()[0]
	r = s.apply_action(1, {"type": "build", "def": "hq", "cell": [hq.cell.x + 5, hq.cell.y], "rot": 0})
	t.check(not r.ok, "Lager nicht baubar")
	var spot := _find_spot(s, "wall_stone")
	t.eq(spot, Vector2i(-1, -1), "Steinmauer gesperrt ohne Werkstatt")
	s.economy.stock["wood"] = 0
	spot = _find_spot(s, "wall_wood")
	r = s.apply_action(1, {"type": "build", "def": "wall_wood", "cell": [spot.x, spot.y], "rot": 0})
	t.check(not r.ok and String(r.reason).begins_with("Es fehlen"), "zu wenig Holz: " + String(r.reason))
	r = s.apply_action(1, {"type": "teleport"})
	t.check(not r.ok, "unbekannte Aktion abgelehnt")
	r = s.apply_action(99, {"type": "build", "def": "wall_wood", "cell": [spot.x, spot.y], "rot": 0})
	t.check(not r.ok, "unbekannter Spieler abgelehnt")


func test_rotation_footprint(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	var def: Dictionary = gd.building("workshop")
	t.eq(BuildingSystem.footprint(def, 0), Vector2i(3, 2), "Werkstatt 3x2")
	t.eq(BuildingSystem.footprint(def, 1), Vector2i(2, 3), "gedreht 2x3")
	t.eq(BuildingSystem.cells_for(def, Vector2i(10, 10), 1).size(), 6, "6 Kacheln")


func test_cancel_and_demolish_refund(t) -> void:
	var s := _new_state()
	var spot := _find_spot(s, "storage")
	var wood := s.economy.amount("wood")
	var r := s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot.x, spot.y], "rot": 0})
	var id: int = r.id
	r = s.apply_action(1, {"type": "cancel", "id": id})
	t.check(r.ok, "Bau abgebrochen")
	t.eq(s.economy.amount("wood"), wood, "volle Erstattung beim Abbruch")
	t.check(not s.occupancy.values().has("b:%d" % id), "Fläche wieder frei")
	r = s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot.x, spot.y], "rot": 0})
	id = r.id
	_finish_construction(s)
	r = s.apply_action(1, {"type": "demolish", "id": id})
	t.eq(s.economy.amount("wood"), wood - 40 + 20, "50 % Erstattung beim Abriss")
	var hq_id: int = s.buildings.keys()[0]
	r = s.apply_action(1, {"type": "demolish", "id": hq_id})
	t.check(not r.ok, "Zentrales Lager nicht abreißbar")


func test_repair(t) -> void:
	var s := _new_state()
	var spot := _find_spot(s, "storage")
	var r := s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot.x, spot.y], "rot": 0})
	_finish_construction(s)
	BuildingSystem.damage(s, r.id, 250.0)
	t.eq(s.buildings[r.id].hp, 250.0, "Schaden angekommen")
	var cost := BuildingSystem.repair_cost(s, s.buildings[r.id])
	t.eq(cost, {"wood": 8, "stone": 3}, "Reparaturkosten proportional zum Schaden")
	r = s.apply_action(1, {"type": "repair", "id": r.id})
	t.check(r.ok, "repariert")
	BuildingSystem.damage(s, s.buildings.keys()[1], 9999.0)
	t.eq(s.buildings.size(), 1, "zerstörtes Gebäude entfernt")
	t.eq(s.economy.capacity_bonus, 0, "zerstörtes Lager liefert keine Kapazität mehr")


func test_lumber_production_and_storage_full(t) -> void:
	var s := _new_state()
	# Holzfäller neben möglichst viele Bäume stellen
	var best := Vector2i(-1, -1)
	var best_n := 0
	for y in range(s.map.start_cell.y - 12, s.map.start_cell.y + 12):
		for x in range(s.map.start_cell.x - 12, s.map.start_cell.x + 12):
			var c := Vector2i(x, y)
			if not BuildingSystem.check(s, "lumber", c, 0).ok:
				continue
			var n := 0
			var center := Vector3((x + 1) * 2.0, 0, (y + 1) * 2.0)
			for node in s.nodes.values():
				var p := s.node_position(node)
				if node.type == "tree" and Vector2(p.x, p.z).distance_to(Vector2(center.x, center.z)) < 14.0:
					n += 1
			if n > best_n:
				best_n = n
				best = c
	t.check(best_n >= 2, "Holzfäller-Platz mit %d Bäumen" % best_n)
	var r := s.apply_action(1, {"type": "build", "def": "lumber", "cell": [best.x, best.y], "rot": 0})
	t.check(r.ok, "Holzfäller gebaut: " + String(r.reason))
	_finish_construction(s)
	var wood := s.economy.amount("wood")
	for i in 60 * 31:
		s.tick(1.0 / 60.0)
	t.check(s.economy.amount("wood") >= wood + 10, "Holz produziert (%d -> %d)" % [wood, s.economy.amount("wood")])
	t.eq(s.buildings[r.id].status, "working", "Status arbeitet")
	s.economy.stock["wood"] = s.economy.capacity("wood")
	for i in 60 * 8:
		s.tick(1.0 / 60.0)
	t.eq(s.buildings[r.id].status, "storage_full", "Lager voll pausiert Produktion")
	t.eq(s.economy.amount("wood"), s.economy.capacity("wood"), "nie über Kapazität")


func test_production_chain(t) -> void:
	var s := _new_state()
	s.economy.stock["metal"] = 20
	s.economy.stock["stone"] = 100
	var spot := _find_spot(s, "workshop")
	var r := s.apply_action(1, {"type": "build", "def": "workshop", "cell": [spot.x, spot.y], "rot": 0})
	t.check(r.ok, "Werkstatt gebaut: " + String(r.reason))
	_finish_construction(s)
	s.economy.stock["components"] = 0
	s.economy.stock["wood"] = 8
	s.economy.stock["metal"] = 1
	s.buildings[r.id].timer = 0.0
	for i in 60 * 11:
		s.tick(1.0 / 60.0)
	t.eq(s.economy.amount("components"), 2, "2 Bauteile hergestellt")
	t.eq(s.economy.amount("wood"), 4, "4 Holz verbraucht")
	for i in 60 * 11:
		s.tick(1.0 / 60.0)
	t.eq(s.buildings[r.id].status, "missing_input", "wartet ohne Metall")
	t.eq(s.economy.amount("components"), 2, "keine weitere Produktion")
	# jetzt ist die Steinmauer freigeschaltet
	t.eq(BuildingSystem.lock_reason(s, s.data.building("wall_stone")), "", "Steinmauer freigeschaltet")


func test_gather(t) -> void:
	var s := _new_state()
	var tree: Dictionary = {}
	for n in s.nodes.values():
		if n.type == "tree":
			tree = n
			break
	var far := s.apply_action(1, {"type": "gather", "node": tree.id})
	if s.node_position(tree).distance_to(s.players[1].pos) > 5.0:
		t.check(not far.ok and far.reason == "Zu weit entfernt", "Reichweite geprüft")
	s.set_player_position(1, s.node_position(tree) + Vector3(1.5, 0, 0))
	var wood := s.economy.amount("wood")
	var r := s.apply_action(1, {"type": "gather", "node": tree.id})
	t.check(r.ok, "gesammelt: " + String(r.reason))
	t.eq(s.economy.amount("wood"), wood + 3, "+3 Holz")
	r = s.apply_action(1, {"type": "gather", "node": tree.id})
	t.check(not r.ok and r.get("silent", false), "Abklingzeit greift")
	var rounds := 0
	while s.nodes.has(tree.id) and rounds < 20:
		s.tick(1.0)
		s.apply_action(1, {"type": "gather", "node": tree.id})
		rounds += 1
	t.check(not s.nodes.has(tree.id), "Baum verschwindet, wenn erschöpft")
	t.check(not s.occupancy.values().has("n:%d" % tree.id), "Kachel wieder frei")


func test_two_players_cannot_overspend(t) -> void:
	var s := _new_state()
	s.add_player(2, "Ben")
	s.set_player_position(2, s.map.center() + Vector3(-6, 0, -6))
	s.economy.stock["wood"] = 50
	s.economy.stock["stone"] = 50
	var spot_a := _find_spot(s, "storage")
	var r1 := s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot_a.x, spot_a.y], "rot": 0})
	var spot_b := _find_spot(s, "storage")
	var r2 := s.apply_action(2, {"type": "build", "def": "storage", "cell": [spot_b.x, spot_b.y], "rot": 0})
	t.check(r1.ok, "Spieler 1 baut")
	t.check(not r2.ok, "Spieler 2 scheitert am geteilten Bestand")
	t.eq(s.economy.amount("wood"), 10, "Holz nur einmal ausgegeben")
	var r3 := s.apply_action(2, {"type": "build", "def": "storage", "cell": [spot_a.x, spot_a.y], "rot": 0})
	t.check(not r3.ok, "gleiche Stelle doppelt abgelehnt")


func test_clock(t) -> void:
	var s := _new_state()
	t.eq(s.clock.day, 1, "Tag 1")
	t.check(not s.clock.is_night(), "Start am Tag")
	var to_night := s.clock.seconds_until_night()
	t.check(absf(to_night - 13.0 / 14.0 * 480.0) < 0.5, "Sekunden bis Nacht: %.1f" % to_night)
	var nights := 0
	var days := 0
	var step := 0.25
	var total := 0.0
	while total < 720.0 * 2.0 + to_night + 1.0:
		s.tick(step)
		total += step
		for ev in s.take_events():
			if ev.type == "night_started":
				nights += 1
			elif ev.type == "day_started":
				days += 1
	t.eq(nights, 3, "drei Nächte begonnen")
	t.eq(days, 2, "zwei neue Tage")
	t.eq(s.clock.day, 3, "jetzt Tag 3")
	t.check(s.clock.is_night(), "Nacht 3 läuft")


func test_save_roundtrip(t) -> void:
	var s := _new_state()
	var spot := _find_spot(s, "storage")
	s.apply_action(1, {"type": "build", "def": "storage", "cell": [spot.x, spot.y], "rot": 1})
	_finish_construction(s)
	var spot2 := _find_spot(s, "wall_wood")
	s.apply_action(1, {"type": "build", "def": "wall_wood", "cell": [spot2.x, spot2.y], "rot": 0})
	s.tick(1.0)
	var node_id: int = s.nodes.keys()[5]
	s.nodes[node_id].amount = 1
	s.remove_node(s.nodes.keys()[7])
	var json := JSON.stringify(s.to_dict())
	var loaded := GameState.from_dict(s.data, JSON.parse_string(json))
	t.check(loaded != null, "geladen")
	t.eq(JSON.stringify(loaded.to_dict()), json, "Zustand nach Laden identisch")
	t.eq(loaded.occupancy.size(), s.occupancy.size(), "Belegung identisch")
	t.eq(loaded.economy.capacity("wood"), s.economy.capacity("wood"), "Kapazität identisch")
	var bad: Dictionary = JSON.parse_string(json)
	bad.schema = 999
	t.check(GameState.from_dict(s.data, bad) == null, "falsche Schema-Version abgelehnt")
