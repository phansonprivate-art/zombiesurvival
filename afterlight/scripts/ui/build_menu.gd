class_name BuildMenu
extends PanelContainer
## Baumenü: Kategorien als Reiter, Gebäude als Karten mit Kosten, Bauzeit und Sperrgrund.

signal building_chosen(def_id: String)

var _category := ""
var _tabs: HBoxContainer
var _cards: HBoxContainer
var _tab_buttons := {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.94))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	var title := UiTheme.label("BAUEN", 15, UiTheme.ACCENT)
	title.custom_minimum_size.x = 80
	head.add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	head.add_child(_tabs)
	for c in GameData.categories:
		var b := UiTheme.button(String(c.name), _select_category.bind(String(c.id)))
		b.toggle_mode = true
		_tabs.add_child(b)
		_tab_buttons[String(c.id)] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UiTheme.label("B schließen", 13, UiTheme.MUTED))
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	v.add_child(_cards)
	_select_category(String(GameData.categories[0].id))


func _select_category(cat: String) -> void:
	_category = cat
	for id in _tab_buttons:
		_tab_buttons[id].button_pressed = id == cat
	refresh()


func refresh() -> void:
	if not is_inside_tree() or Session.state == null:
		return
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var state := Session.state
	for id in GameData.building_order:
		var def: Dictionary = GameData.building(id)
		if def.category != _category or not bool(def.placement.get("buildable", true)):
			continue
		_cards.add_child(_card(state, def))
	reset_size()


func _card(state: GameState, def: Dictionary) -> Button:
	var lock := BuildingSystem.lock_reason(state, def)
	var affordable := state.economy.can_afford(def.cost)
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, 132)
	b.disabled = lock != ""
	b.tooltip_text = String(def.description)
	b.pressed.connect(func(): building_chosen.emit(String(def.id)))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var name_l := UiTheme.label(String(def.name), 16, UiTheme.TEXT if lock == "" else UiTheme.MUTED)
	v.add_child(name_l)
	var fp: Vector2i = def.footprint
	v.add_child(UiTheme.label("%d×%d · %.0f s Bauzeit" % [fp.x, fp.y, def.build_time], 12, UiTheme.MUTED))
	if lock != "":
		var l := UiTheme.label(lock, 13, UiTheme.WARNING)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(l)
	else:
		for rid in def.cost:
			var have := state.economy.amount(rid)
			var need := int(def.cost[rid])
			var col := UiTheme.TEXT if have >= need else UiTheme.DANGER
			var row := UiTheme.label("%d %s" % [need, GameData.resource_name(rid)], 13, col)
			v.add_child(row)
		if def.production != null:
			var p := UiTheme.label(_short_prod(def), 12, UiTheme.SUCCESS)
			v.add_child(p)
		elif int(def.capacity_bonus) > 0:
			v.add_child(UiTheme.label("+%d Lagerplatz" % def.capacity_bonus, 12, UiTheme.SUCCESS))
	if lock == "" and not affordable:
		b.modulate = Color(1, 1, 1, 0.75)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _short_prod(def: Dictionary) -> String:
	var prod: Dictionary = def.production
	if prod.type == "harvest":
		return "→ %s" % GameData.resource_name(prod.resource)
	var outs: PackedStringArray = []
	for rid in prod.outputs:
		outs.append(GameData.resource_name(rid))
	return "→ " + ", ".join(outs)
