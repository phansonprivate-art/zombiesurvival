extends Node
## Verwaltet die laufende Welt. In der Einzelspieler-Version ist diese Instanz der Host:
## Sie führt den GameState, simuliert die Zeit und verteilt Ereignisse an die Darstellung.
## Phase 5 (Koop): Clients rufen submit() per RPC auf dem Host auf; die Ereignisse aus
## take_events() werden an alle Peers verteilt. Darstellung und Logik bleiben unverändert.

signal world_started
signal world_closed
signal state_event(ev: Dictionary)

var state: GameState = null
var local_player_id: int = 1
var local_player_name: String = "Überlebender"


func is_running() -> bool:
	return state != null


func start_new_world(world_name: String, world_seed: int) -> void:
	state = GameState.create_new(GameData, world_name, world_seed)
	state.add_player(local_player_id, local_player_name)
	_flush()
	world_started.emit()


func close_world() -> void:
	state = null
	world_closed.emit()


## Spieleraktion an den (lokalen) Host senden. Ergebnis: {ok, reason, ...}
func submit(action: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Keine Welt geladen"}
	var result := state.apply_action(local_player_id, action)
	_flush()
	return result


func update_local_player(pos: Vector3) -> void:
	if state != null:
		state.set_player_position(local_player_id, pos)


func _physics_process(delta: float) -> void:
	if state == null:
		return
	state.tick(delta)
	_flush()


func _flush() -> void:
	for ev in state.take_events():
		state_event.emit(ev)
