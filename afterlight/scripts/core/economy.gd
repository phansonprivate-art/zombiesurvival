class_name Economy
extends RefCounted
## Gemeinsames Ressourcenlager der Siedlung. Bestände sind ganzzahlig und nie negativ.
## Kapazität = Grundkapazität der Ressource + Bonus aller fertigen Lagergebäude.

var data
var stock: Dictionary = {}
var capacity_bonus: int = 0
var dirty := false


func _init(game_data) -> void:
	data = game_data
	for id in data.resource_order:
		stock[id] = 0


func amount(id: String) -> int:
	return int(stock.get(id, 0))


func capacity(id: String) -> int:
	if not data.resources.has(id):
		return 0
	return int(data.resources[id].base_capacity) + capacity_bonus


func space(id: String) -> int:
	return maxi(0, capacity(id) - amount(id))


func is_full(id: String) -> bool:
	return amount(id) >= capacity(id)


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if amount(id) < int(cost[id]):
			return false
	return true


## Ressourcen, die für die Kosten fehlen: {id: fehlende Menge}
func missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for id in cost:
		var m := int(cost[id]) - amount(id)
		if m > 0:
			out[id] = m
	return out


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		stock[id] = amount(id) - int(cost[id])
	dirty = true
	return true


## Fügt bis zur Kapazitätsgrenze hinzu und gibt die tatsächlich gelagerte Menge zurück
func add(id: String, n: int) -> int:
	if n <= 0 or not stock.has(id):
		return 0
	var added := mini(n, space(id))
	if added > 0:
		stock[id] = amount(id) + added
		dirty = true
	return added


func can_store_all(outputs: Dictionary) -> bool:
	for id in outputs:
		if space(id) < int(outputs[id]):
			return false
	return true


func to_dict() -> Dictionary:
	return stock.duplicate()


func load_dict(d: Dictionary) -> void:
	for id in stock:
		stock[id] = maxi(0, int(d.get(id, 0)))
	dirty = true
