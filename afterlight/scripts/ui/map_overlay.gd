class_name MapOverlay
extends PanelContainer
## Übersichtskarte (M): Gelände, Straßen, Gebäude, besondere Fundorte und Spieler.

var _canvas: Control
var _tex: ImageTexture
var _map_px := 620.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.96))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiTheme.label("Karte", 21)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiTheme.label("M schließen", 13, UiTheme.MUTED))
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(_map_px, _map_px)
	_canvas.draw.connect(_draw_map)
	v.add_child(_canvas)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	v.add_child(legend)
	for item in [["Gebäude", UiTheme.ACCENT], ["Erz", Color("#e08a3c")], ["Wrack", Color("#8fa3b3")], ["Kiste", Color("#d6d36a")], ["Ruine", Color("#b8b2a8")], ["Spieler", Color("#7fd0ff")]]:
		legend.add_child(UiTheme.label("● " + item[0], 13, item[1]))


func set_image(img: Image) -> void:
	_tex = ImageTexture.create_from_image(img)


func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_map() -> void:
	var state := Session.state
	if state == null or _tex == null:
		return
	var s := _map_px / state.map.size_m()
	_canvas.draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(_map_px, _map_px)), false)
	var cs := state.map.cell_size
	for r in state.map.ruins:
		_canvas.draw_rect(Rect2(Vector2(r.cell) * cs * s, Vector2(r.size) * cs * s), Color("#b8b2a8"), true)
	for n in state.nodes.values():
		var col := Color.TRANSPARENT
		match n.type:
			"ore": col = Color("#e08a3c")
			"wreck": col = Color("#8fa3b3")
			"crate": col = Color("#d6d36a")
		if col.a > 0:
			var p := state.node_position(n)
			_canvas.draw_circle(Vector2(p.x, p.z) * s, 3.0, col)
	for b in state.buildings.values():
		var def: Dictionary = GameData.building(b.def)
		var fp := BuildingSystem.footprint(def, b.rot)
		_canvas.draw_rect(Rect2(Vector2(b.cell) * cs * s, Vector2(fp) * cs * s), UiTheme.ACCENT if b.phase == "active" else UiTheme.ACCENT.darkened(0.4), true)
	for p in state.players.values():
		_canvas.draw_circle(Vector2(p.pos.x, p.pos.z) * s, 6.0, Color("#0c1018"))
		_canvas.draw_circle(Vector2(p.pos.x, p.pos.z) * s, 4.5, Color("#7fd0ff"))
	var c := state.map.center()
	_canvas.draw_arc(Vector2(c.x, c.z) * s, BuildingSystem.SETTLEMENT_RADIUS * s, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.5)
