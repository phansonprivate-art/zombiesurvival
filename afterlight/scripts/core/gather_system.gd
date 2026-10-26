class_name GatherSystem
extends RefCounted
## Manuelles Sammeln durch Spieler. Reichweite und Abklingzeit werden mit der
## Spielerposition im Zustand geprüft – nicht mit Angaben des Clients.


static func gather(state, player_id: int, node_id: int) -> Dictionary:
	var p: Dictionary = state.players[player_id]
	if p.hp <= 0.0:
		return {"ok": false, "reason": "Du bist außer Gefecht"}
	if not state.nodes.has(node_id):
		return {"ok": false, "reason": "Nichts mehr da"}
	var n: Dictionary = state.nodes[node_id]
	var nt: Dictionary = state.data.node_type(n.type)
	var cfg: Dictionary = state.data.player_cfg()
	var npos: Vector3 = state.node_position(n)
	var dist := Vector2(p.pos.x, p.pos.z).distance_to(Vector2(npos.x, npos.z))
	if dist > float(cfg.reach) + float(nt.get("radius", 0.5)) + 0.5:
		return {"ok": false, "reason": "Zu weit entfernt"}
	if state.clock.elapsed - float(p.last_gather) < float(cfg.gather_cooldown) * 0.8:
		return {"ok": false, "reason": "cooldown", "silent": true}
	p.last_gather = state.clock.elapsed

	var gained := {}
	if nt.get("resource") == "loot":
		var loot: Dictionary = nt.get("loot", {})
		for rid in loot:
			var r: Array = loot[rid]
			var amount: int = state.rng.randi_range(int(r[0]), int(r[1]))
			var added: int = state.economy.add(rid, amount)
			if added > 0:
				gained[rid] = added
		state.remove_node(node_id)
		state.notify("Versorgungskiste geöffnet: " + (state.data.format_cost(gained) if gained.size() > 0 else "leer"), "success")
		return {"ok": true, "reason": "", "gained": gained, "depleted": true}

	var rid := String(nt.resource)
	if state.economy.is_full(rid):
		return {"ok": false, "reason": "%s-Lager ist voll" % state.data.resource_name(rid)}
	var take := mini(int(nt.per_gather), int(n.amount))
	var added: int = state.economy.add(rid, take)
	n.amount -= added
	gained[rid] = added
	var bonus: Dictionary = nt.get("bonus", {})
	if not bonus.is_empty() and state.rng.randf() < float(bonus.chance):
		var b_added: int = state.economy.add(String(bonus.resource), int(bonus.amount))
		if b_added > 0:
			gained[String(bonus.resource)] = b_added
	var depleted: bool = n.amount <= 0
	if depleted:
		state.remove_node(node_id)
	else:
		state.emit("node_changed", {"id": node_id})
	return {"ok": true, "reason": "", "gained": gained, "depleted": depleted}
