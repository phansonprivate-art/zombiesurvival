class_name InventoryPanel
extends PanelContainer
## Lagerübersicht: alle Rohstoffe der Siedlung mit Kapazität und Hinweisen.

var _grid: GridContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.96))
	custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiTheme.label("Lagerbestand der Siedlung", 21)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiTheme.label("I / Tab", 13, UiTheme.MUTED))
	v.add_child(UiTheme.label("Alle Spieler teilen sich dieses Lager.", 13, UiTheme.MUTED))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_grid)


func refresh() -> void:
	var state := Session.state
	if state == null or _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for rid in GameData.resource_order:
		var def: Dictionary = GameData.resources[rid]
		var name_l := UiTheme.label(String(def.name), 16, def.color if def.hud else UiTheme.MUTED)
		name_l.custom_minimum_size.x = 120
		_grid.add_child(name_l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(190, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = state.economy.capacity(rid)
		bar.value = state.economy.amount(rid)
		bar.add_theme_stylebox_override("fill", UiTheme.bar_style(UiTheme.DANGER if state.economy.is_full(rid) else Color(def.color).darkened(0.1)))
		_grid.add_child(bar)
		var text := "%d / %d %s" % [state.economy.amount(rid), state.economy.capacity(rid), def.unit]
		if not def.hud and def.note != "":
			text += "  ·  " + def.note
		_grid.add_child(UiTheme.label(text, 14, UiTheme.TEXT if def.hud else UiTheme.MUTED))
	reset_size()
