class_name Hud
extends CanvasLayer
## Spieloberfläche. Liest den Zustand aus der Session; Aktionen laufen über Session.submit().

signal building_chosen(def_id: String)
signal pause_toggled(paused: bool)
signal main_menu_requested

var root: Control
var build_menu: BuildMenu
var building_panel: BuildingPanel
var inventory: InventoryPanel
var map_overlay: MapOverlay
var pause_menu: PauseMenu
var _res_box: HBoxContainer
var _res_labels := {}
var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _hp_bar: ProgressBar
var _name_label: Label
var _hover: Label
var _build_hint: Label
var _toasts: VBoxContainer
var _banner: Label
var _clock_timer := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_bar()
	_build_player_card()
	_build_center_texts()
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_toasts.position = Vector2(-376, 120)
	_toasts.custom_minimum_size.x = 360
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_toasts)

	build_menu = BuildMenu.new()
	build_menu.visible = false
	build_menu.building_chosen.connect(func(id): building_chosen.emit(id))
	_anchor(build_menu, Control.PRESET_CENTER_BOTTOM, Vector2(0, -16))
	building_panel = BuildingPanel.new()
	building_panel.visible = false
	_anchor(building_panel, Control.PRESET_CENTER_RIGHT, Vector2(-16, 0))
	building_panel.action_result.connect(_on_action_result)
	inventory = InventoryPanel.new()
	inventory.visible = false
	_anchor(inventory, Control.PRESET_CENTER, Vector2.ZERO)
	map_overlay = MapOverlay.new()
	map_overlay.visible = false
	_anchor(map_overlay, Control.PRESET_CENTER, Vector2.ZERO)
	pause_menu = PauseMenu.new()
	pause_menu.visible = false
	pause_menu.resume_requested.connect(func(): set_paused(false))
	pause_menu.main_menu_requested.connect(func(): main_menu_requested.emit())
	root.add_child(pause_menu)
	refresh_resources()


## Fügt ein Panel hinzu und hält es an der gewünschten Bildschirmkante
func _anchor(c: Control, preset: int, offset: Vector2) -> void:
	root.add_child(c)
	c.set_meta("preset", preset)
	c.set_meta("offset", offset)
	c.resized.connect(_place.bind(c))
	c.visibility_changed.connect(_place.bind(c))
	_place(c)


func _place(c: Control) -> void:
	var vp := root.get_viewport_rect().size if root.is_inside_tree() else Vector2(1600, 900)
	var s := c.size
	var off: Vector2 = c.get_meta("offset")
	match int(c.get_meta("preset")):
		Control.PRESET_CENTER_BOTTOM:
			c.position = Vector2((vp.x - s.x) * 0.5, vp.y - s.y) + off
		Control.PRESET_CENTER_RIGHT:
			c.position = Vector2(vp.x - s.x, (vp.y - s.y) * 0.5) + off
		_:
			c.position = (vp - s) * 0.5 + off


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.panel(0.88))
	bar.position = Vector2(16, 16)
	root.add_child(bar)
	_res_box = HBoxContainer.new()
	_res_box.add_theme_constant_override("separation", 18)
	bar.add_child(_res_box)
	for rid in GameData.resource_order:
		var def: Dictionary = GameData.resources[rid]
		if not def.hud:
			continue
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.tooltip_text = "%s (%s)" % [def.name, def.unit]
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		var n := UiTheme.label(String(def.name).to_upper(), 11, def.color)
		v.add_child(n)
		var amount := UiTheme.label("0", 19)
		v.add_child(amount)
		_res_box.add_child(v)
		_res_labels[rid] = amount

	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", UiTheme.panel(0.88))
	clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(clock)
	var cv := VBoxContainer.new()
	cv.custom_minimum_size.x = 230
	cv.add_theme_constant_override("separation", 0)
	clock.add_child(cv)
	var row := HBoxContainer.new()
	cv.add_child(row)
	_day_label = UiTheme.label("TAG 1", 24, UiTheme.ACCENT)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_day_label)
	_time_label = UiTheme.label("07:00", 24)
	row.add_child(_time_label)
	_phase_label = UiTheme.label("", 14, UiTheme.MUTED)
	cv.add_child(_phase_label)


func _build_player_card() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel(0.88))
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(card)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 260
	card.add_child(v)
	_name_label = UiTheme.label(Session.local_player_name, 17)
	v.add_child(_name_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size.y = 14
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 100
	_hp_bar.add_theme_stylebox_override("fill", UiTheme.bar_style(UiTheme.DANGER))
	v.add_child(_hp_bar)
	var keys := UiTheme.label("WASD laufen · Klick sammeln · B bauen\nI Lager · M Karte · Q/E drehen · Leertaste zentrieren", 12, UiTheme.MUTED)
	v.add_child(keys)


func _build_center_texts() -> void:
	_hover = UiTheme.label("", 15)
	_hover.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hover.add_theme_constant_override("outline_size", 6)
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hover)
	_build_hint = UiTheme.label("", 16)
	_build_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_build_hint.add_theme_constant_override("outline_size", 6)
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_build_hint.position.y = 110
	_build_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_build_hint)
	_banner = UiTheme.label("", 40, UiTheme.ACCENT)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position.y = 170
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)


func _process(delta: float) -> void:
	var state := Session.state
	if state == null:
		return
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = 0.2
		_update_clock(state)
		var p: Dictionary = state.players.get(Session.local_player_id, {})
		if not p.is_empty():
			_hp_bar.value = p.hp
		if building_panel.visible:
			building_panel.refresh()
		if map_overlay.visible:
			map_overlay.refresh()
	_hover.position = root.get_viewport().get_mouse_position() + Vector2(18, 14)
	# Banner auf Bildschirmmitte halten
	_banner.position.x = (root.get_viewport_rect().size.x - _banner.size.x) * 0.5
	_build_hint.position.x = (root.get_viewport_rect().size.x - _build_hint.size.x) * 0.5


func _update_clock(state: GameState) -> void:
	var c := state.clock
	_day_label.text = "TAG %d" % c.day
	_time_label.text = c.time_text()
	if c.is_night():
		var s := c.seconds_until_day()
		_phase_label.text = "Nacht %d · Morgen in %d:%02d" % [c.day, int(s) / 60, int(s) % 60]
		_phase_label.add_theme_color_override("font_color", UiTheme.INFO)
	else:
		var s := c.seconds_until_night()
		_phase_label.text = "Tag · Nacht in %d:%02d" % [int(s) / 60, int(s) % 60]
		_phase_label.add_theme_color_override("font_color", UiTheme.WARNING if s < 60.0 else UiTheme.MUTED)


func refresh_resources() -> void:
	var state := Session.state
	if state == null:
		return
	for rid in _res_labels:
		var l: Label = _res_labels[rid]
		var amount := state.economy.amount(rid)
		var cap := state.economy.capacity(rid)
		l.text = "%d" % amount
		l.tooltip_text = "%d / %d" % [amount, cap]
		var col := UiTheme.TEXT
		if amount >= cap:
			col = UiTheme.DANGER
		elif amount >= cap * 0.9:
			col = UiTheme.WARNING
		l.add_theme_color_override("font_color", col)
	if build_menu.visible:
		build_menu.refresh()
	if inventory.visible:
		inventory.refresh()


func set_hover(text: String) -> void:
	_hover.text = text
	_hover.visible = text != ""


func set_build_hint(text: String, ok: bool) -> void:
	_build_hint.text = text
	_build_hint.add_theme_color_override("font_color", UiTheme.SUCCESS if ok else UiTheme.DANGER)
	_build_hint.visible = text != ""


func toast(text: String, kind := "info") -> void:
	var col: Color = {"info": UiTheme.TEXT, "success": UiTheme.SUCCESS, "warning": UiTheme.WARNING, "danger": UiTheme.DANGER}.get(kind, UiTheme.TEXT)
	var p := PanelContainer.new()
	var sb := UiTheme.panel(0.9)
	sb.border_color = col.darkened(0.2)
	sb.border_width_left = 4
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(text, 15, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 320
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	var tw := _banner.create_tween()
	_banner.modulate.a = 0.0
	tw.tween_property(_banner, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.5)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.0)


func _on_action_result(r: Dictionary) -> void:
	if not r.ok:
		toast(String(r.reason), "warning")


func toggle_build_menu() -> void:
	build_menu.visible = not build_menu.visible
	if build_menu.visible:
		build_menu.refresh()


func toggle_inventory() -> void:
	inventory.visible = not inventory.visible
	if inventory.visible:
		map_overlay.visible = false
		inventory.refresh()


func toggle_map() -> void:
	map_overlay.visible = not map_overlay.visible
	if map_overlay.visible:
		inventory.visible = false
		map_overlay.refresh()


func is_paused() -> bool:
	return pause_menu.visible


func set_paused(on: bool) -> void:
	pause_menu.visible = on
	get_tree().paused = on
	pause_toggled.emit(on)


## ESC: zuerst offene Fenster schließen, dann pausieren
func close_top_or_pause() -> void:
	if pause_menu.visible:
		set_paused(false)
	elif inventory.visible or map_overlay.visible:
		inventory.visible = false
		map_overlay.visible = false
	elif building_panel.visible:
		building_panel.visible = false
		building_panel.closed.emit()
	elif build_menu.visible:
		build_menu.visible = false
	else:
		set_paused(true)
