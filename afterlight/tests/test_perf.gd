extends RefCounted
## Performance-Ziel Meilenstein 1: Ein Simulationsschritt (Zeit, Bau, Produktion) mit
## ~40 Gebäuden kostet im Mittel weniger als 1 ms, damit bei 60 Hz genug Zeit für
## Darstellung, Physik und später Gegner bleibt.


func test_simulation_tick_budget(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	var s := GameState.create_new(gd, "Perf", 777)
	s.add_player(1, "P")
	for rid in s.economy.stock:
		s.economy.stock[rid] = 100000
	s.economy.capacity_bonus = 1000000
	var placed := 0
	var defs := ["lumber", "quarry", "mine", "workshop", "storage", "wall_wood", "gate"]
	var start := s.map.start_cell
	for r in range(2, 14):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if placed >= 40:
					break
				var d: String = defs[placed % defs.size()]
				var c := start + Vector2i(x, y)
				if BuildingSystem.check(s, d, c, 0).ok:
					s.apply_action(1, {"type": "build", "def": d, "cell": [c.x, c.y], "rot": 0})
					placed += 1
	t.check(placed >= 30, "genug Gebäude platziert (%d)" % placed)
	for i in 60 * 20:
		s.tick(1.0 / 60.0)
	s.take_events()
	var n := 3600
	var t0 := Time.get_ticks_usec()
	for i in n:
		s.tick(1.0 / 60.0)
		s.take_events()
	var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("       Simulation: %.3f ms pro Schritt bei %d Gebäuden" % [avg_ms, s.buildings.size()])
	t.check(avg_ms < 1.0, "Simulationsschritt unter 1 ms (%.3f ms)" % avg_ms)
	gd.free()
