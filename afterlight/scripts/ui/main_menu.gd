extends Node
## Hauptmenü mit lebendigem 3D-Hintergrund (Vorschauwelt).

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _ui: Control
var _menu: VBoxContainer
var _new_dialog: PanelContainer
var _settings: SettingsDialog
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _loading: Label


func _ready() -> void:
	get_tree().paused = false
	_spawn_background()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UiTheme.get_theme()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.05, 0.08, 0.92))
	g.set_color(1, Color(0.04, 0.05, 0.08, 0.0))
	grad.gradient = g
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(90, 150)
	_menu.custom_minimum_size.x = 360
	_menu.add_theme_constant_override("separation", 10)
	_ui.add_child(_menu)
	var title := UiTheme.label("AFTERLIGHT", 64, UiTheme.TEXT)
	title.add_theme_constant_override("outline_size", 0)
	_menu.add_child(title)
	_menu.add_child(UiTheme.label("Baut auf. Haltet stand. Gemeinsam.", 18, UiTheme.ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	_menu.add_child(gap)
	_menu.add_child(UiTheme.button("Neue Welt", _open_new_world))
	_menu.add_child(_todo_button("Fortsetzen", "Speichern & Laden folgt in Phase 4"))
	_menu.add_child(_todo_button("Gespeicherte Welten", "Folgt in Phase 4"))
	_menu.add_child(_todo_button("Koop-Spiel hosten", "Koop folgt in Phase 5"))
	_menu.add_child(_todo_button("Spiel beitreten", "Koop folgt in Phase 5"))
	_menu.add_child(UiTheme.button("Einstellungen", _open_settings))
	_menu.add_child(UiTheme.button("Beenden", func(): get_tree().quit()))
	var foot := UiTheme.label("Prototyp · Meilenstein 1 (Phase 0 + 1)", 13, UiTheme.MUTED)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	_ui.add_child(foot)

	_new_dialog = _build_new_dialog()
	_new_dialog.visible = false
	_settings = SettingsDialog.new()
	_settings.visible = false
	_settings.position = Vector2(90, 200)
	_settings.closed.connect(func(): _settings.visible = false; _menu.visible = true)
	_ui.add_child(_settings)
	_loading = UiTheme.label("Welt wird erzeugt …", 26, UiTheme.ACCENT)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.visible = false
	_ui.add_child(_loading)


func _todo_button(text: String, why: String) -> Button:
	var b := Button.new()
	b.text = "%s  ·  %s" % [text, why]
	b.disabled = true
	b.tooltip_text = why
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func _spawn_background() -> void:
	var seed := 1337
	var state := GameState.create_new(GameData, "Vorschau", seed)
	var world: Node3D = load(WORLD_SCENE).instantiate()
	world.preview_state = state
	add_child(world)


func _build_new_dialog() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(0.97))
	p.position = Vector2(90, 200)
	p.custom_minimum_size = Vector2(440, 0)
	_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UiTheme.label("Neue Welt", 26))
	v.add_child(UiTheme.label("Name der Siedlung", 13, UiTheme.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.text = "Neue Siedlung"
	_name_edit.max_length = 32
	v.add_child(_name_edit)
	v.add_child(UiTheme.label("Seed (gleicher Seed = gleiche Karte)", 13, UiTheme.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed_edit)
	row.add_child(UiTheme.button("Zufall", func(): _seed_edit.text = str(randi() % 1000000)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	var create := UiTheme.button("Welt erstellen", _create_world)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(create)
	var cancel := UiTheme.button("Abbrechen", func(): _new_dialog.visible = false; _menu.visible = true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel)
	return p


func _open_new_world() -> void:
	_seed_edit.text = str(randi() % 1000000)
	_menu.visible = false
	_new_dialog.visible = true
	_name_edit.grab_focus()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true


static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return t.to_int()
	return absi(hash(t)) % 100000000


func _create_world() -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		name = "Neue Siedlung"
	start_world(name, parse_seed(_seed_edit.text))


func start_world(world_name: String, world_seed: int) -> void:
	_new_dialog.visible = false
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	Session.local_player_name = Settings.player_name
	Session.start_new_world(world_name, world_seed)
	get_tree().change_scene_to_file(WORLD_SCENE)
