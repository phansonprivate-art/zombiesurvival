class_name BuildingPanel
extends PanelContainer
## Informationen zum ausgewählten Gebäude: Zustand, Status, Produktion, Lager, Reparatur, Abriss.

signal closed
signal action_result(result: Dictionary)

var building_id: int = -1
var _title: Label
var _cat: Label
var _hp: ProgressBar
var _hp_label: Label
var _progress: ProgressBar
var _status: Label
var _prod: Label
var _extra: Label
var _power: Label
var _repair: Button
var _remove: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.95))
	custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiTheme.label("", 21)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiTheme.button("✕", func(): closed.emit())
	x.custom_minimum_size = Vector2(36, 32)
	head.add_child(x)
	_cat = UiTheme.label("", 13, UiTheme.MUTED)
	v.add_child(_cat)
	_hp_label = UiTheme.label("", 13, UiTheme.MUTED)
	v.add_child(_hp_label)
	_hp = ProgressBar.new()
	_hp.custom_minimum_size.y = 12
	_hp.show_percentage = false
	v.add_child(_hp)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 18
	_progress.add_theme_stylebox_override("fill", UiTheme.bar_style(UiTheme.ACCENT))
	v.add_child(_progress)
	_status = UiTheme.label("", 16)
	v.add_child(_status)
	_prod = UiTheme.label("", 14, UiTheme.TEXT)
	_prod.autowrap_mode = TextServer.AUTOWRAP_WORD
	_prod.custom_minimum_size.x = 300
	v.add_child(_prod)
	_extra = UiTheme.label("", 14, UiTheme.MUTED)
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD
	_extra.custom_minimum_size.x = 300
	v.add_child(_extra)
	_power = UiTheme.label("Strom: wird in Phase 2 eingeführt", 12, UiTheme.MUTED)
	v.add_child(_power)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_repair = UiTheme.button("Reparieren", _on_repair)
	_repair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_repair)
	_remove = UiTheme.button("Abreißen", _on_remove)
	_remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_remove)


func show_building(id: int) -> void:
	building_id = id
	visible = true
	refresh()


func refresh() -> void:
	var state := Session.state
	if state == null or not state.buildings.has(building_id):
		visible = false
		return
	var b: Dictionary = state.buildings[building_id]
	var def: Dictionary = GameData.building(b.def)
	_title.text = String(def.name)
	var cat_name := ""
	for c in GameData.categories:
		if c.id == def.category:
			cat_name = c.name
	_cat.text = "%s · %s" % [cat_name, def.description]
	_cat.autowrap_mode = TextServer.AUTOWRAP_WORD
	_cat.custom_minimum_size.x = 300
	_hp.max_value = float(def.health)
	_hp.value = float(b.hp)
	var hp_frac: float = b.hp / float(def.health)
	_hp.add_theme_stylebox_override("fill", UiTheme.bar_style(UiTheme.SUCCESS if hp_frac > 0.5 else (UiTheme.WARNING if hp_frac > 0.25 else UiTheme.DANGER)))
	_hp_label.text = "Zustand %d / %d" % [int(b.hp), int(def.health)]
	var constructing: bool = b.phase == "construction"
	_progress.visible = constructing
	_progress.value = b.progress * 100.0
	if constructing:
		_status.text = "Im Bau – noch %.0f s" % ((1.0 - b.progress) * float(def.build_time))
		_status.add_theme_color_override("font_color", UiTheme.ACCENT)
	elif def.production != null:
		_status.text = ProductionSystem.STATUS_TEXT.get(String(b.status), String(b.status))
		var ok: bool = b.status == "working" or b.status == "idle"
		_status.add_theme_color_override("font_color", UiTheme.SUCCESS if ok else UiTheme.WARNING)
	else:
		_status.text = "Einsatzbereit"
		_status.add_theme_color_override("font_color", UiTheme.SUCCESS)
	_prod.text = ProductionSystem.describe(state, def)
	_prod.visible = _prod.text != ""
	var extra: PackedStringArray = []
	if int(def.capacity_bonus) > 0:
		extra.append("+%d Lagerkapazität je Rohstoff" % def.capacity_bonus)
	if def.id == "hq":
		extra.append("Grundlager der Siedlung. Bauen ist im Umkreis von %.0f m um Gebäude möglich." % BuildingSystem.SETTLEMENT_RADIUS)
	if def.passable_for_players:
		extra.append("Öffnet sich für Spieler automatisch.")
	_extra.text = "\n".join(extra)
	_extra.visible = extra.size() > 0
	var cost := BuildingSystem.repair_cost(state, b)
	_repair.disabled = constructing or cost.is_empty()
	_repair.text = "Reparieren" if cost.is_empty() else "Reparieren (%s)" % GameData.format_cost(cost)
	var removable := bool(def.placement.get("buildable", true))
	_remove.visible = removable
	_remove.text = "Bau abbrechen" if constructing else "Abreißen"
	reset_size()


func _on_repair() -> void:
	action_result.emit(Session.submit({"type": "repair", "id": building_id}))
	refresh()


func _on_remove() -> void:
	var r := Session.submit({"type": "demolish", "id": building_id})
	action_result.emit(r)
	if r.ok:
		closed.emit()
